"""Úpravy obrázků postavy v2 (volá je tools/build_hero.py). Všechno pracuje s 64px buňkami sheetu.

- vlasy: oddělí se od těla (vrstva skrytá přilbou),
- sjednocení barev vlasů a šortek nových snímků s původním tělem,
- doplnění vybavení do buněk, kde ho zdrojový sheet nemá (barvy věci se přenesou na pózu těla; hlava se přenese z klidové pózy).
Vybavení se tedy "dokresluje" přebarvením těla v pásmech (torso/legs/feet) a přenosem hlavy, ne ručním kreslením detailů."""
import numpy as np
from scipy import ndimage

CELL = 64
OUTLINE_LUM = 0.2          # tmavší = obrys
LIT_LUM = 0.45             # světlejší = kůže/oblečení
HAIR_SAT, HAIR_VAL = 0.7, 0.82
HAIR_CROWN_ROWS = 8        # vlasová oblast musí sahat do tolika řádků od temene
BANDS = {"torso": (28, 46), "legs": (46, 58), "feet": (54, 62), "hands": (0, 64)}  # kde v 4směrových buňkách hledat barvy věci
TORSO_START = 0.45         # kde (podíl výšky těla) končí hlava a začíná trup
HEAD_TOP_ROWS, HEAD_DEPTH = 8, 24
ARM_X, HAND_ROWS = 8, 4      # paže = trup dál než ARM_X px od osy těla; ruka = spodních HAND_ROWS řádků paže
EIGHT = np.ones((3, 3), bool)


def hsv(a: np.ndarray):
    """(h ve stupních, s, v) pro RGBA pole."""
    rgb = a[..., :3].astype(float) / 255
    mx, mn = rgb.max(-1), rgb.min(-1)
    d = mx - mn
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    with np.errstate(divide="ignore", invalid="ignore"):
        h = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) * 60
    h = np.where(d == 0, 0, h)
    s = np.where(mx == 0, 0, d / np.where(mx == 0, 1, mx))
    return h, s, mx


def lum(a: np.ndarray) -> np.ndarray:
    return (0.3 * a[..., 0] + 0.59 * a[..., 1] + 0.11 * a[..., 2]) / 255


def cell(sheet: np.ndarray, row: int, col: int) -> np.ndarray:
    return sheet[row * CELL:(row + 1) * CELL, col * CELL:(col + 1) * CELL]


def _rows(mask: np.ndarray):
    ys = np.nonzero(mask.any(1))[0]
    return (ys.min(), ys.max()) if len(ys) else (0, 0)


# --- vlasy a šortky -----------------------------------------------------------------------------
def hair_masks(c: np.ndarray):
    """(vlasy, jejich obrys) v buňce. Vlas = sytě oranžovohnědé pixely spojené s temenem; obrys = tmavé pixely u vlasů bez sousední kůže."""
    op = c[..., 3] > 0
    if not op.any():
        return np.zeros_like(op), np.zeros_like(op)
    h, s, v = hsv(c)
    cand = op & (h >= 4) & (h <= 42) & (s > HAIR_SAT) & (v < HAIR_VAL)
    lab, n = ndimage.label(cand, EIGHT)
    top = _rows(op)[0]
    keep = [i for i in range(1, n + 1) if np.nonzero((lab == i).any(1))[0].min() < top + HAIR_CROWN_ROWS]
    hair = np.isin(lab, keep)
    dark = op & (lum(c) < OUTLINE_LUM)
    skin = op & ~hair & ~dark & ~cand
    outline = dark & ndimage.binary_dilation(hair, EIGHT) & ~ndimage.binary_dilation(skin, EIGHT)
    return hair, outline


def shorts_mask(c: np.ndarray) -> np.ndarray:
    """Šortky: bílé (původní tělo) nebo šedomodré (nové diagonály), jen ve spodní polovině těla."""
    op = c[..., 3] > 0
    if not op.any():
        return op
    h, s, v = hsv(c)
    white = (s < 0.2) & (v > 0.6)
    grey = (h > 180) & (h < 245) & (s < 0.35)
    y0, y1 = _rows(op)
    low = np.arange(CELL)[:, None] > y0 + 0.55 * (y1 - y0)
    return op & (white | grey) & low


def split_hair(sheet: np.ndarray, cells) -> tuple[np.ndarray, np.ndarray]:
    """Tělo bez vlasů a samotné vlasy (stejný layout). cells = [(řádek, sloupec)]."""
    body, hair_sheet = sheet.copy(), np.zeros_like(sheet)
    for r, c in cells:
        src, dst, out = cell(sheet, r, c), cell(body, r, c), cell(hair_sheet, r, c)
        hair, outline = hair_masks(src)
        m = hair | outline
        out[m] = src[m]
        dst[m] = 0
    return body, hair_sheet


def _match(px: np.ndarray, palette: np.ndarray) -> np.ndarray:
    """Barvy px přiřadí z palette podle pořadí světlosti (histogramové přiřazení)."""
    order = np.argsort(lum(px))
    pal = palette[np.argsort(lum(palette))]
    out = np.zeros_like(px)
    out[order] = pal[((np.arange(len(px)) + .5) / len(px) * len(pal)).astype(int)]
    out[:, 3] = 255
    return out


def unify_palette(cells_new: list[np.ndarray], reference: list[np.ndarray]) -> None:
    """Vlasy a šortky nových buněk dostanou barvy referenčního (původního) těla. Mění buňky na místě."""
    ref_hair = np.concatenate([c[hair_masks(c)[0]] for c in reference])
    ref_shorts = np.concatenate([c[shorts_mask(c)] for c in reference])
    for c in cells_new:
        for m, pal in ((hair_masks(c)[0], ref_hair), (shorts_mask(c), ref_shorts)):
            if m.any() and len(pal):
                c[m] = _match(c[m], pal)


# --- vybavení: přebarvení těla a přenos hlavy -----------------------------------------------------
def body_masks(c: np.ndarray) -> dict[str, np.ndarray]:
    """Pásma těla: torso (od brady po šortky vč. paží), legs (šortky a nohy), feet (spodních 5 řádků)."""
    op = c[..., 3] > 0
    y0, y1 = _rows(op)
    hair, outline = hair_masks(c)
    lit = op & (lum(c) >= LIT_LUM) & ~hair & ~outline
    shorts = shorts_mask(c)
    sy = np.nonzero(shorts.sum(1) >= 6)[0]  # řádky s alespoň 6 pixely šortek (světlé body na břiše nestačí)
    h = y1 - y0 + 1
    s0, s1 = (sy.min(), sy.max()) if len(sy) >= 3 else (y0 + int(.66 * h), y0 + int(.8 * h))
    y = np.arange(CELL)[:, None]
    feet = lit & (y > y1 - 5)
    trunk = lit & ~shorts & (y >= y0 + int(TORSO_START * h)) & (y <= s1)
    xs = np.nonzero(op[y0:y0 + HEAD_TOP_ROWS].any(0))[0]
    x = np.arange(CELL)[None, :]
    hands = np.zeros_like(op)
    for side in (x < xs.mean() - ARM_X, x > xs.mean() + ARM_X):
        arm = trunk & side
        if arm.any():
            hands |= arm & (y > _rows(arm)[1] - HAND_ROWS)
    return {"hands": hands,
            "torso": lit & (y >= y0 + int(TORSO_START * h)) & (y < s0),
            "legs": ((lit & (y > s1)) | shorts) & ~feet,
            "feet": feet}


def palette(layer: np.ndarray, rows: range, y0: int, y1: int):
    """Barvy věci v pásmu těla ze snímků chůze: (barvy bez obrysu, barva obrysu) nebo None."""
    px = np.concatenate([cell(layer, r, c)[y0:y1].reshape(-1, 4) for r in rows for c in range(9)])
    px = px[px[:, 3] > 0]
    body = px[lum(px) >= OUTLINE_LUM] if len(px) else px
    if len(body) == 0:
        return None
    outline = px[lum(px) < OUTLINE_LUM]
    return body, (outline[len(outline) // 2] if len(outline) else body[0])


def recolor(c: np.ndarray, mask: np.ndarray, pal) -> np.ndarray:
    out = np.zeros_like(c)
    if not mask.any() or pal is None:
        return out
    colors, outline = pal
    out[mask] = _match(c[mask], colors)
    a = np.pad(c[..., 3] > 0, 1)
    edge = ~(a[:-2, 1:-1] & a[2:, 1:-1] & a[1:-1, :-2] & a[1:-1, 2:])
    out[mask & edge] = outline
    return out


def _head_box(c: np.ndarray):
    ys, xs = np.nonzero(c[..., 3])
    top = ys.min()
    return top, xs[ys < top + HEAD_TOP_ROWS].mean()


def transfer_head(body_cell, ref_layer, ref_body) -> np.ndarray:
    """Hlava věci z klidové pózy (ref_*) posunutá na hlavu body_cell."""
    out = np.zeros_like(body_cell)
    (t0, x0), (t1, x1) = _head_box(ref_body), _head_box(body_cell)
    dy, dx = int(round(t1 - t0)), int(round(x1 - x0))
    ys, xs = np.nonzero(ref_layer[..., 3])
    keep = ys < t0 + HEAD_DEPTH
    ys, xs = ys[keep], xs[keep]
    ty, tx = ys + dy, xs + dx
    ok = (ty >= 0) & (ty < CELL) & (tx >= 0) & (tx < CELL)
    out[ty[ok], tx[ok]] = ref_layer[ys[ok], xs[ok]]
    return out


def _over(top: np.ndarray, under: np.ndarray) -> np.ndarray:
    out = under.copy()
    m = top[..., 3] > 0
    out[m] = top[m]
    return out


def complete(layer, body, anims, modes, walk_rows, idle_row, force=False):
    """Doplní do vrstvy buňky, kde tělo je a věc ne (force: dokreslí i do existujících, stávající pixely mají přednost).

    anims = [(řádek, snímků, směrů, funkce směr->svislý/boční směr klidové pózy pro hlavu)]; modes = ("head", "torso", "legs", "feet").
    Vrací (nová vrstva, počet doplněných buněk)."""
    out, added = layer.copy(), 0
    pal = {m: palette(layer, walk_rows, *BANDS[m]) for m in modes if m in BANDS}
    for row, frames, dirs, ref_dir in anims:
        for d in range(dirs):
            for f in range(frames):
                b = cell(body, row + d, f)
                existing = cell(out, row + d, f)
                if not b[..., 3].any() or (existing[..., 3].any() and not force):
                    continue
                masks = body_masks(b)
                parts = [recolor(b, masks[m], p) for m, p in pal.items() if p is not None]
                if "head" in modes:
                    ref_layer, ref_body = cell(layer, idle_row + ref_dir(d), 0), cell(body, idle_row + ref_dir(d), 0)
                    if ref_layer[..., 3].any() and ref_body[..., 3].any():
                        parts.append(transfer_head(b, ref_layer, ref_body))
                fitted = np.zeros_like(b)
                for p in parts:
                    fitted = _over(p, fitted)
                existing[:] = _over(existing, fitted)
                added += 1
    return out, added


# --- zbraň v ruce ve všech pózách -------------------------------------------------------------------
def _shift(c: np.ndarray, dy: int, dx: int) -> np.ndarray:
    out = np.zeros_like(c)
    ys, xs = np.nonzero(c[..., 3])
    ty, tx = ys + dy, xs + dx
    ok = (ty >= 0) & (ty < CELL) & (tx >= 0) & (tx < CELL)
    out[ty[ok], tx[ok]] = c[ys[ok], xs[ok]]
    return out


def carry(weapon: np.ndarray, body: np.ndarray, anims, fill, ref_order) -> int:
    """Zbraň ve zdrojových animacích často chybí (stání, běh...). Do animací `fill` bez jediného pixelu zbraně přenese
    zbraň z referenční pózy (první snímek první animace z `ref_order`, která ji má) posunutou za hlavou těla.

    anims = {název: (řádek, snímků, směrů)}; fill = [(název, ref_směr_funkce)]. Mění `weapon` na místě, vrací počet buněk."""
    def has(name, d):
        row, frames, _ = anims[name]
        return any(cell(weapon, row + d, f)[..., 3].any() for f in range(frames))
    added = 0
    for name, ref_dir in fill:
        row, frames, dirs = anims[name]
        if any(has(name, d) for d in range(dirs)):
            continue
        for d in range(dirs):
            rd = ref_dir(d)
            ref = next(((anims[r][0] + rd, cell(weapon, anims[r][0] + rd, 0)) for r in ref_order
                        if cell(weapon, anims[r][0] + rd, 0)[..., 3].any()), None)
            if ref is None:
                continue
            ref_body = cell(body, ref[0], 0)
            t0, x0 = _head_box(ref_body)
            for f in range(frames):
                b = cell(body, row + d, f)
                if not b[..., 3].any():
                    continue
                t1, x1 = _head_box(b)
                cell(weapon, row + d, f)[:] = _shift(ref[1], int(round(t1 - t0)), int(round(x1 - x0)))
                added += 1
    return added
