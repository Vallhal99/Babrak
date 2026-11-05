"""Osm směrů pohybu a zvedání ze země pro postavu v2 (volá ho tools/build_hero.py).

Zdroj `tools/source_hero/Animace_doplnek/`: diagonální chůze (80px snímky) a zvedání ze země (3 směry).
Tělo se jen vycentruje do 64px buňky. Vybavení pro diagonály nikdo nenakreslil, proto se PŘEFITUJE z hotových vrstev:
  head  = výřez hlavy z vrstvy (svislý směr) posunutý na hlavu nového těla,
  torso/legs/feet = pixely kůže v daném pásmu těla se přebarví barvami věci (přiřazení podle světlosti, okraj = obrys věci).
Zvedání ze země je zatím jen tělo (experiment)."""
import colorsys
import re
from pathlib import Path

import numpy as np
from PIL import Image

DIRS = ("north-west", "north-east", "south-west", "south-east")  # = AnimCatalog.Dir UP_LEFT, UP_RIGHT, DOWN_LEFT, DOWN_RIGHT
PICK_DIRS = {"west": 1, "south": 2, "east": 3}                      # řádek = Dir (UP=0 se zkopíruje z jihu)
WALK_FRAMES, PICK_FRAMES = 6, 5
FEET_Y = 61                 # patky postavy v 64px buňce (ORIGIN v CharacterVisual)
# pásma těla v kreslené buňce 64px (barvy věci se berou z hotových 4směrových snímků)
BANDS = {"torso": (28, 46), "legs": (46, 58), "feet": (54, 62)}
HEAD_TOP_ROWS = 8           # počet řádků od temene, podle kterých se odhadne střed hlavy
HEAD_DEPTH = 24             # kolik řádků pod temenem hlavy se přenáší z vrstvy (kapuce/přilba)
OUTLINE_LUM = 0.2
LIT_LUM = 0.45             # světlost, od které je pixel těla kůže/oblečení (tmavší = obrys, vlasy)


def _read(path) -> np.ndarray:
    return np.array(Image.open(path).convert("RGBA"))


def _lum(p) -> float:
    return (0.3 * float(p[0]) + 0.59 * float(p[1]) + 0.11 * float(p[2])) / 255


def _hsv(p):
    return colorsys.rgb_to_hsv(*(float(x) / 255 for x in p[:3]))


def _is_shorts(p) -> bool:
    h, s, _ = _hsv(p)
    return p[3] > 0 and 0.5 < h < 0.68 and s < 0.35


def _crop(frames: list[np.ndarray], bottom: int) -> list[np.ndarray]:
    """80px snímky -> 64px buňka: střed x, nejnižší bod animace na FEET_Y."""
    top = bottom - FEET_Y
    return [np.ascontiguousarray(f[top:top + 64, 8:72]) for f in frames]


def _lowest(frames: list[np.ndarray]) -> int:
    return max(int(np.nonzero(f[..., 3])[0].max()) for f in frames)


class Diagonals:
    def __init__(self, folder: Path, rows: dict[str, int], size: tuple[int, int]):
        """rows = řádky v sheetu (walk_diag, pickup), size = (výška, šířka) plátna."""
        self.rows, self.size = rows, size
        anim = folder / "animations"
        walk = {d: [_read(anim / "Walking" / d / f"frame_{i:03d}.png") for i in range(WALK_FRAMES)] for d in DIRS}
        pick = {d: [_read(anim / "Picking_Up" / d / f"frame_{i:03d}.png") for i in range(PICK_FRAMES)] for d in PICK_DIRS}
        bw = max(_lowest(f) for f in walk.values())
        bp = max(_lowest(f) for f in pick.values())
        self.walk = {d: _crop(f, bw) for d, f in walk.items()}
        self.pick = {d: _crop(f, bp) for d, f in pick.items()}

    def _canvas(self) -> np.ndarray:
        return np.zeros((*self.size, 4), np.uint8)

    def _put(self, canvas, row: int, col: int, cell: np.ndarray) -> None:
        canvas[row * 64:(row + 1) * 64, col * 64:(col + 1) * 64] = cell

    def body(self) -> np.ndarray:
        """Řádky diagonální chůze + zvedání v plátně celého sheetu."""
        out = self._canvas()
        for k, d in enumerate(DIRS):
            for i, cell in enumerate(self.walk[d]):
                self._put(out, self.rows["walk_diag"] + k, i, cell)
        for d, k in PICK_DIRS.items():
            for i, cell in enumerate(self.pick[d]):
                self._put(out, self.rows["pickup"] + k, i, cell)
                if d == "south":
                    self._put(out, self.rows["pickup"], i, cell)
        return out

    def fit(self, layer: np.ndarray, modes: tuple[str, ...], body_ref: np.ndarray, walk_row: int) -> np.ndarray:
        """Vrstva věci pro diagonální chůzi. layer = hotová 4směrová vrstva, body_ref = 4směrové tělo, walk_row = řádek 'walk'."""
        out = self._canvas()
        pal = {m: _palette(layer, walk_row, *BANDS[m]) for m in modes if m in BANDS}
        for k, d in enumerate(DIRS):
            for i, cell in enumerate(self.walk[d]):
                parts = [_recolor(cell, _masks(cell)[m], pal[m]) for m in pal]
                if "head" in modes:
                    parts.append(_head(cell, layer, body_ref, walk_row + (0 if d.startswith("north") else 2), i))
                self._put(out, self.rows["walk_diag"] + k, i, _stack(parts))
        return out


def _stack(parts: list[np.ndarray]) -> np.ndarray:
    out = np.zeros_like(parts[0])
    for p in parts:
        m = p[..., 3] > 0
        out[m] = p[m]
    return out


def _palette(layer: np.ndarray, walk_row: int, y0: int, y1: int):
    """Barvy věci v pásmu těla ze snímků chůze: (barvy bez obrysu, barva obrysu) nebo None."""
    px = np.concatenate([layer[r * 64 + y0:r * 64 + y1, c * 64:(c + 1) * 64].reshape(-1, 4) for r in range(walk_row, walk_row + 4) for c in range(9)])
    px = px[px[:, 3] > 0]
    if len(px) == 0:
        return None
    lum = np.array([_lum(p) for p in px])
    body = px[lum >= OUTLINE_LUM]
    if len(body) == 0:
        return None
    outline = px[lum < OUTLINE_LUM]
    return body[np.argsort([_lum(p) for p in body])], (outline[len(outline) // 2] if len(outline) else body[0])


def _masks(f: np.ndarray) -> dict[str, np.ndarray]:
    """Pásma těla: torso (od brady po šortky, vč. paží), legs (šortky a nohy), feet (spodních 5 řádků). Obrys a vlasy se nepřebarvují."""
    opaque = f[..., 3] > 0
    ys = np.nonzero(opaque.any(1))[0]
    y0, y1 = ys.min(), ys.max()
    h = y1 - y0 + 1
    lit = np.array([[_lum(p) >= LIT_LUM for p in row] for row in f]) & opaque  # světlé pixely = kůže/šortky, ne obrys a vlasy
    shorts = np.array([[_is_shorts(p) for p in row] for row in f])
    sy = np.nonzero(shorts.sum(1) >= 2)[0]
    s0, s1 = (sy.min(), sy.max()) if len(sy) >= 3 else (y0 + int(.66 * h), y0 + int(.8 * h))
    y = np.arange(f.shape[0])[:, None]
    feet = lit & (y > y1 - 5)
    return {"torso": lit & ~shorts & (y >= y0 + int(.40 * h)) & (y < s0),
            "legs": ((lit & (y > s1)) | shorts) & ~feet,
            "feet": feet}


def _recolor(f: np.ndarray, mask: np.ndarray, pal) -> np.ndarray:
    out = np.zeros_like(f)
    ys, xs = np.nonzero(mask)
    if len(ys) == 0 or pal is None:
        return out
    colors, outline = pal
    order = np.argsort([_lum(p) for p in f[ys, xs]])
    q = (np.arange(len(order)) + .5) / len(order)
    new = np.zeros((len(ys), 4), np.uint8)
    new[order] = colors[(q * len(colors)).astype(int)]
    new[:, 3] = 255
    out[ys, xs] = new
    # okraj masky u průhledna = obrys věci
    alpha = np.pad(f[..., 3] > 0, 1)
    edge = ~(alpha[:-2, 1:-1] & alpha[2:, 1:-1] & alpha[1:-1, :-2] & alpha[1:-1, 2:])
    e = edge[ys, xs]
    out[ys[e], xs[e]] = outline
    return out


def _head_box(cell: np.ndarray):
    """Temeno a střed hlavy (x) podle horních řádků siluety."""
    ys, xs = np.nonzero(cell[..., 3])
    top = ys.min()
    band = xs[ys < top + HEAD_TOP_ROWS]
    return top, band.mean()


def _head(cell: np.ndarray, layer: np.ndarray, body_ref: np.ndarray, row: int, i: int) -> np.ndarray:
    """Hlava věci ze svislého směru, posunutá na hlavu nového těla."""
    c = i % 9
    src_body = body_ref[row * 64:(row + 1) * 64, c * 64:(c + 1) * 64]
    src_layer = layer[row * 64:(row + 1) * 64, c * 64:(c + 1) * 64]
    (t0, cx0), (t1, cx1) = _head_box(src_body), _head_box(cell)
    dy, dx = int(round(t1 - t0)), int(round(cx1 - cx0))
    out = np.zeros_like(cell)
    ys, xs = np.nonzero(src_layer[..., 3])
    keep = ys < t0 + HEAD_DEPTH
    ys, xs = ys[keep], xs[keep]
    ty, tx = ys + dy, xs + dx
    ok = (ty >= 0) & (ty < 64) & (tx >= 0) & (tx < 64)
    out[ty[ok], tx[ok]] = src_layer[ys[ok], xs[ok]]
    return out
