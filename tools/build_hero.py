"""Postava v2: z balíčku tools/source_hero/ vyrobí tělo, vlasy, vrstvy vybavení, ikony a data/items/*.tres.

Zdroj jsou KOMPLETNÍ renderované postavy (tělo + věc). Vrstva věci = pixely, kterými se kompletní sheet liší od holého těla;
brnění a přilby jsou ve zdroji už samostatné vrstvy. Chybějící animace vybavení doplňuje tools/hero_fit.py.
Layout výstupu: 64px snímky v řádcích podle scripts/character/anim_catalog.gd, pod nimi (od BIG_Y) 192px oversize efekty zbraní.
Spuštění z kořene projektu:  python3 tools/build_hero.py   (vypíše buňky, které vybavení stále chybí)"""
import re
from pathlib import Path

import numpy as np
from PIL import Image

import hero_diag
import hero_fit as fit

SRC = Path("tools/source_hero")
OUT = Path("assets/characters/hero")
CATALOG = Path("scripts/character/anim_catalog.gd").read_text()

BIG, BIG_Y = 192, int(re.search(r"const BIG_Y := (\d+)", CATALOG).group(1))
BIG_ROWS, W, W_BIG = 16, 832, 13 * 192
SRC_BIG, SRC_BIG_Y = 128, 3456  # 128px oversize oblast v Nahy_zbran.png / Nahy_boj
# katalog: název -> (řádek, snímků, směrů, big_row); soubor animace se jmenuje jinak jen u těchto:
STEM = {"backslash": "1h_backslash", "halfslash": "1h_halfslash"}
ANIMS = {n: (int(r), int(f), int(d or 4), int(b) if b else None)
         for n, r, f, d, b in re.findall(r'&"(\w+)": \{"row": (\d+), "frames": (\d+)(?:, [^}]*?"dirs": (\d+))?(?:[^}]*?"big_row": (\d+))?', CATALOG)}
SPECIAL = {"walk_diag", "run_diag", "pickup"}  # nemají zdroj po animacích (viz hero_diag)
CARDINAL = {n: a for n, a in ANIMS.items() if n not in SPECIAL}
WALK, IDLE = ANIMS["walk"][0], ANIMS["idle"][0]
WALK_DIAG, PICKUP = ANIMS["walk_diag"][0], ANIMS["pickup"][0]


def read(path) -> np.ndarray:
    return np.array(Image.open(path).convert("RGBA"))


def canvas(h=BIG_Y, w=W) -> np.ndarray:
    return np.zeros((h, w, 4), np.uint8)


def from_dir(folder: Path) -> np.ndarray:
    """64px část z jednotlivých souborů po animacích (jen animace katalogu)."""
    out = canvas()
    for anim, (row, *_) in CARDINAL.items():
        f = folder / f"{STEM.get(anim, anim)}.png"
        if f.exists():
            img = read(f)
            out[row * 64:row * 64 + img.shape[0], :img.shape[1]] = img
    return out


def from_sheet(path: Path) -> np.ndarray:
    """64px část z celého sheetu (jen animace katalogu)."""
    out, img = canvas(), read(path)
    for row, _, dirs, _ in CARDINAL.values():
        out[row * 64:(row + dirs) * 64] = img[row * 64:(row + dirs) * 64, :W]
    return out


def diff(comp: np.ndarray, base: np.ndarray) -> np.ndarray:
    """Vrstva = pixely kompletu, které se liší od základu."""
    out = comp.copy()
    out[(comp == base).all(-1) | (comp[..., 3] == 0)] = 0
    return out


def place_big(dst: np.ndarray, anim: str, src: np.ndarray, src_cell: int, frames: int) -> None:
    """Vloží oversize snímky animace (4 řádky směrů) ze zdroje do 192px buněk dst, vystředěné."""
    big_row = ANIMS[anim][3]
    off = (BIG - src_cell) // 2
    for d in range(4):
        for f in range(frames):
            c = src[d * src_cell:(d + 1) * src_cell, f * src_cell:(f + 1) * src_cell]
            dst[(big_row + d) * BIG + off:(big_row + d) * BIG + off + src_cell, f * BIG + off:f * BIG + off + src_cell] = c


def centered_body(plain: np.ndarray, anim: str) -> np.ndarray:
    """Holé tělo animace v 192px buňkách (základ pro rozdíl proti oversize zdrojům)."""
    row, frames, _, _ = ANIMS[anim]
    out = np.zeros((4 * BIG, frames * BIG, 4), np.uint8)
    off = (BIG - 64) // 2
    for d in range(4):
        for f in range(frames):
            out[d * BIG + off:d * BIG + off + 64, f * BIG + off:f * BIG + off + 64] = fit.cell(plain, row + d, f)
    return out


# --- tělo ----------------------------------------------------------------------------------------
plain = from_sheet(SRC / "Nahy.png")                    # holé tělo, bez zbraně
armed = from_dir(SRC / "Nahy_standard")                 # tělo s mečem u pasu / v ruce
walk_cells, pick_cells = hero_diag.load(SRC / "Animace_doplnek")
reference = [fit.cell(plain, WALK + d, c) for d in range(4) for c in range(9)]
for cells in (*walk_cells.values(), *pick_cells.values()):
    fit.unify_palette(cells, reference)                 # vlasy a šortky diagonál stejné jako u 4 směrů
for k, d in enumerate(hero_diag.DIRS):
    for i, c in enumerate(walk_cells[d]):
        fit.cell(plain, WALK_DIAG + k, i)[:] = c
for d, k in hero_diag.PICK_DIRS.items():
    for i, c in enumerate(pick_cells[d]):
        fit.cell(plain, PICKUP + k, i)[:] = c
        if d == "south":
            fit.cell(plain, PICKUP, i)[:] = c

body_cells = [(row + d, f) for name, (row, frames, dirs, _) in ANIMS.items() if name != "run_diag"
              for d in range(dirs) for f in range(frames) if fit.cell(plain, row + d, f)[..., 3].any()]
body, hair = fit.split_hair(plain, body_cells)

# --- vybavení: id, název, popis, slot, zdroj, základ, staty --------------------------------------
# zdroj: ("dir", složka s animacemi) | ("sheet", soubor) | ("sword", ""); základ, od kterého se kompletní postava odečítá:
# "armed" (tělo s mečem) | "plain" (holé) | "shirt" (tělo + tričko, u bot) | "none" (sheet už obsahuje jen věc)
# fit = čím se doplní chybějící animace (viz hero_fit); big = oversize zdroje {animace: (soubor, snímků)}
shirt_comp = from_dir(SRC / "Telo/standard")
S = {"WEAPON": 1, "HEAD": 2, "FEET": 3, "TORSO": 5, "HANDS": 6}
ITEMS = [
    # hlava
    dict(id="hood", name="Kápě", desc="Látková kápě.", slot="HEAD", src=("dir", "Hlava/standard"), base="armed", fit=("head",), hides_hair=True, defense=1, price=25),
    dict(id="mail_coif", name="Kroužková kapuce", desc="Ocelová kroužková kapuce.", slot="HEAD", src=("sheet", "Hlava/125 mail__steel_.png"), base="none", fit=("head",), hides_hair=True, defense=2, price=60),
    dict(id="close_helm", name="Uzavřená přilba", desc="Keramická uzavřená přilba.", slot="HEAD", src=("sheet", "Hlava/130 close_helm__ceramic_.png"), base="none", fit=("head",), hides_hair=True, defense=4, price=120),
    dict(id="wizard_hat", name="Čarodějův klobouk", desc="Bílý nebeský klobouk.", slot="HEAD", src=("sheet", "Hlava/130 celestial_wizard_hat__white_.png"), base="none", fit=("head",), defense=1, max_mana=5, price=80),
    # tělo
    dict(id="shirt", name="Tričko", desc="Obyčejné tričko.", slot="TORSO", src=("dir", "Telo/standard"), base="armed", fit=("torso", "legs"), price=10),
    dict(id="chainmail", name="Kroužková košile", desc="Železná kroužková košile.", slot="TORSO", src=("sheet", "Telo/050 chainmail__iron_.png"), base="none", fit=("torso",), defense=3, price=100),
    dict(id="frock_coat", name="Zelený kabát", desc="Elegantní zelený kabát.", slot="TORSO", src=("sheet", "Telo/055 frock_coat__green_.png"), base="none", fit=("torso",), force=True, defense=1, max_mana=3, price=70),
    dict(id="plate", name="Plátová zbroj", desc="Ocelový plátový krunýř.", slot="TORSO", src=("sheet", "Telo/060 plate__steel_.png"), base="none", fit=("torso",), defense=6, max_hp=4, price=250),
    # boty a rukavice (komplety obsahují i tričko -> základ "shirt")
    dict(id="boots", name="Boty", desc="Pevné boty.", slot="FEET", src=("sheet", "Boty/Boty.png"), base="shirt", fit=("feet",), defense=1, price=30),
    dict(id="gloves", name="Rukavice", desc="Kožené rukavice.", slot="HANDS", src=("sheet", "Rukavice/rukavice.png"), base="armed", fit=("hands",), defense=1, price=20),
    # zbraně (sekera: zdrojová animace tool_axe zatím nemá tělo -> není ve hře)
    dict(id="sword", name="Meč", desc="Vyvážená čepel, široký sek.", slot="WEAPON", src=("sword", ""), attack="backslash", damage=3, price=60),
    dict(id="longsword", name="Dlouhý meč", desc="Dlouhá čepel pro dva údery.", slot="WEAPON", src=("dir", "Zbrane/Longsword"), base="plain", attack="slash",
         big={"slash": ("slash_oversize", 6), "thrust": ("thrust_oversize", 8)}, damage=5, price=120),
    dict(id="dagger", name="Dýka", desc="Rychlá a lehká.", slot="WEAPON", src=("dir", "Zbrane/Dagger"), base="plain", attack="slash", damage=2, price=40),
    dict(id="blunt", name="Palcát", desc="Drtí zbroj.", slot="WEAPON", src=("dir", "Zbrane/Blunt"), base="plain", attack="slash", big={"slash": ("slash_oversize", 6)}, damage=4, price=80),
    dict(id="staff", name="Hůl", desc="Dřevěná hůl.", slot="WEAPON", src=("dir", "Zbrane/Staff"), base="plain", attack="thrust", damage=2, max_mana=5, price=50),
    dict(id="bow", name="Luk", desc="Střelná zbraň.", slot="WEAPON", src=("dir", "Zbrane/Bow"), base="plain", attack="shoot", ranged=True, damage=3, price=100),
    dict(id="crossbow", name="Kuše", desc="Střelná zbraň.", slot="WEAPON", src=("dir", "Zbrane/Crossbow"), base="plain", attack="thrust", ranged=True, damage=4, price=140),
]
BASES = {"armed": armed, "plain": plain, "shirt": np.where(shirt_comp[..., 3:] > 0, shirt_comp, armed)}
# anims pro doplňování: (řádek, snímků, směrů, funkce směr -> směr klidové pózy hlavy); pickup je jen tělo (experiment)
FILL = [(row, frames, dirs, (lambda d: d) if dirs == 4 else (lambda d: 2)) for name, (row, frames, dirs, _) in CARDINAL.items()]
FILL.append((WALK_DIAG, ANIMS["walk_diag"][1], 4, lambda d: 0 if d < 2 else 2))


def trim(a: np.ndarray) -> np.ndarray:
    a = a.copy()
    a[a[..., 3] == 0] = 0
    return a


def icon(layer: np.ndarray, weapon: bool, pad=1, scale=3) -> Image.Image:
    """Ikona = ořez věci z nejvhodnějšího snímku (zbraň: pohled doleva, ostatní: dolů; snímek s nejvíce pixely), x3 nearest."""
    d = 1 if weapon else 2
    cands = [(CARDINAL[a][0] + d, c) for a in ("combat", "idle", "walk", "shoot") for c in range(13)]
    row, col = max(cands, key=lambda rc: int((fit.cell(layer, *rc)[..., 3] > 0).sum()))
    cell = fit.cell(layer, row, col)
    ys, xs = np.nonzero(cell[..., 3] > 0)
    crop = Image.fromarray(cell[ys.min():ys.max() + 1, xs.min():xs.max() + 1])
    side = max(crop.size)
    img = Image.new("RGBA", (side + 2 * pad, side + 2 * pad))
    img.paste(crop, ((side - crop.width) // 2 + pad, (side - crop.height) // 2 + pad))
    return img.resize((img.width * scale, img.height * scale), Image.NEAREST)


def missing_cells(layer: np.ndarray) -> dict[str, int]:
    """Kolik buněk animace tělo má a vrstva ne."""
    out = {}
    for name, (row, frames, dirs, _) in ANIMS.items():
        if name in ("run_diag", "pickup"):
            continue
        n = sum(1 for d in range(dirs) for f in range(frames)
                if fit.cell(plain, row + d, f)[..., 3].any() and not fit.cell(layer, row + d, f)[..., 3].any())
        if n:
            out[name] = n
    return out


def big_region(it: dict) -> tuple[np.ndarray, list[str]]:
    """192px oversize efekty zbraně a seznam animací, které je mají."""
    big, anims = np.zeros((BIG_ROWS * BIG, W_BIG, 4), np.uint8), []
    if it["src"][0] == "sword":  # meč: 128px zdroj (Nahy_boj už obsahuje meč, proto rozdíl proti holému tělu z hlavního sheetu)
        comp = read(SRC / "Nahy_zbran.png")[SRC_BIG_Y:]
        for anim in ("slash", "backslash", "halfslash"):
            row, frames, _, big_row = ANIMS[anim]
            raw = np.zeros_like(big)
            place_big(raw, anim, comp[big_row * SRC_BIG:(big_row + 4) * SRC_BIG], SRC_BIG, frames)
            region = raw[big_row * BIG:(big_row + 4) * BIG, :frames * BIG]
            big[big_row * BIG:(big_row + 4) * BIG, :frames * BIG] = diff(region, centered_body(plain, anim))
            anims.append(anim)
    for anim, (stem, frames) in it.get("big", {}).items():
        comp = read(SRC / it["src"][1] / f"{stem}.png")
        place_big(big, anim, diff(comp, centered_body(plain, anim)[:, :comp.shape[1]]), BIG, frames)
        anims.append(anim)
    return big, anims


TRES = """[gd_resource type="Resource" script_class="ItemData" load_steps=4 format=3]

[ext_resource type="Script" path="res://scripts/data/item_data.gd" id="1"]
[ext_resource type="Texture2D" path="res://assets/icons/{id}.png" id="2"]
[ext_resource type="Texture2D" path="res://{sheet}" id="3"]

[resource]
script = ExtResource("1")
id = &"{id}"
display_name = "{name}"
description = "{desc}"
icon = ExtResource("2")
slot = {slot}
layer_sheet = ExtResource("3")
"""
STAT_KEYS = ("damage", "defense", "max_hp", "max_mana", "price")

for p in (OUT / "body", OUT / "equipment", OUT / "weapons", Path("assets/icons"), Path("data/items")):
    p.mkdir(parents=True, exist_ok=True)
Image.fromarray(trim(body)).save(OUT / "body/body.png")
Image.fromarray(trim(hair)).save(OUT / "body/hair.png")

for it in ITEMS:
    kind, rel = it["src"]
    weapon = it["slot"] == "WEAPON"
    if kind == "sword":
        main = diff(armed, plain)
    else:
        comp = from_dir(SRC / rel) if kind == "dir" else from_sheet(SRC / rel)
        main = comp if it["base"] == "none" else diff(comp, BASES[it["base"]])
    if it.get("fit"):
        main, _ = fit.complete(main, plain, FILL, it["fit"], range(WALK, WALK + 4), IDLE, it.get("force", False))
    big, big_anims = big_region(it) if weapon else (None, [])
    sheet = canvas(BIG_Y + (BIG_ROWS * BIG if big_anims else 0), W_BIG if big_anims else W)
    sheet[:BIG_Y, :W] = main
    if big_anims:
        sheet[BIG_Y:] = big
    path = OUT / ("weapons" if weapon else "equipment") / f"{it['id']}.png"
    Image.fromarray(trim(sheet)).save(path)
    icon(main, weapon).save(f"assets/icons/{it['id']}.png")
    text = TRES.format(sheet=path.as_posix(), slot=S[it["slot"]], **{k: it[k] for k in ("id", "name", "desc")})
    if weapon:
        text += f'attack_anim = &"{it["attack"]}"\n'
        text += "ranged = true\n" if it.get("ranged") else ""
        text += f'big_anims = Array[StringName]([{", ".join(f"&{chr(34)}{a}{chr(34)}" for a in big_anims)}])\n' if big_anims else ""
    text += "hides_hair = true\n" if it.get("hides_hair") else ""
    text += "".join(f"{k} = {it[k]}\n" for k in STAT_KEYS if it.get(k))
    Path(f"data/items/{it['id']}.tres").write_text(text)
    print(f"{it['id']:11s} {'oversize: ' + ','.join(big_anims) + '  ' if big_anims else ''}chybí buňky: {missing_cells(main) if not weapon else '(zbraň – ukazuje se jen tam, kde ji zdroj kreslí)'}")
