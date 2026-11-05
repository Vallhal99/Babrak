"""Postava v2: z balíčku tools/source_hero/ vyrobí tělo, vrstvy vybavení, ikony a data/items/*.tres.

Zdroj jsou KOMPLETNÍ renderované postavy (tělo + věc). Vrstva věci = pixely, kterými se kompletní sheet liší od holého těla.
Layout výstupu: 64px snímky v řádcích podle scripts/character/anim_catalog.gd, pod nimi 128px "oversize" oblast (jen meč).
Spuštění z kořene projektu:  python3 tools/build_hero.py   (vypíše i chybějící animace u každé věci)"""
import re
from pathlib import Path

import numpy as np
from PIL import Image

SRC = Path("tools/source_hero")
OUT = Path("assets/characters/hero")
CATALOG = Path("scripts/character/anim_catalog.gd").read_text()

BIG, BIG_Y = 128, int(re.search(r"const BIG_Y := (\d+)", CATALOG).group(1))
BIG_ROWS, W, W_BIG = 12, 832, 1664
# animace katalogu, které mají zdroj v balíčku (torch_* se kreslí zvlášť); soubor se jmenuje jinak než animace jen u těchto:
STEM = {"backslash": "1h_backslash", "halfslash": "1h_halfslash", "slash_1h": "1h_slash"}
ROWS = {n: int(r) for n, r in re.findall(r'&"(\w+)": \{"row": (\d+)', CATALOG) if not n.startswith("torch")}
BIG_FILES = {"slash": ("slash_128", 0), "backslash": ("backslash_128", 4), "halfslash": ("halfslash_128", 8)}  # složka Nahy_boj


def read(path) -> np.ndarray:
    return np.array(Image.open(path).convert("RGBA"))


def canvas(h=BIG_Y, w=W) -> np.ndarray:
    return np.zeros((h, w, 4), np.uint8)


def from_dir(folder: Path) -> np.ndarray:
    """64px část z jednotlivých souborů po animacích."""
    out = canvas()
    for anim, row in ROWS.items():
        f = folder / f"{STEM.get(anim, anim)}.png"
        if f.exists():
            img = read(f)
            out[row * 64:row * 64 + img.shape[0], :img.shape[1]] = img
    return out


def from_sheet(path: Path) -> np.ndarray:
    """64px část z celého sheetu (nové animace 1h_slash/watering v něm nejsou)."""
    out = canvas()
    img = read(path)[:3456, :W]
    out[:3456] = img
    return out


def fill_empty(base: np.ndarray, extra: np.ndarray) -> np.ndarray:
    """Do prázdných pixelů base doplní extra."""
    out = base.copy()
    m = (out[..., 3] == 0) & (extra[..., 3] > 0)
    out[m] = extra[m]
    return out


def diff(comp: np.ndarray, base: np.ndarray) -> np.ndarray:
    """Vrstva = pixely kompletu, které se liší od základu."""
    out = comp.copy()
    out[(comp == base).all(-1) | (comp[..., 3] == 0)] = 0
    return out


def missing_anims(comp: np.ndarray) -> list[str]:
    """Animace, které v kompletním sheetu vůbec nejsou (postava v nich zůstane bez věci)."""
    out = []
    for anim, row in ROWS.items():
        if comp.shape[0] >= (row + 1) * 64 and not comp[row * 64:(row + 4) * 64, :, 3].any():
            out.append(anim)
    return out


def body_big() -> np.ndarray:
    out = canvas(BIG_ROWS * BIG, W_BIG)
    for stem, row in BIG_FILES.values():
        img = read(SRC / "Nahy_boj" / f"{stem}.png")
        out[row * BIG:row * BIG + img.shape[0], :img.shape[1]] = img
    return out


# --- základ těla ---------------------------------------------------------------------------------
plain = fill_empty(from_sheet(SRC / "Nahy.png"), from_dir(SRC / "Nahy_standard"))  # holé tělo bez meče u pasu
armed = fill_empty(from_dir(SRC / "Nahy_standard"), plain)                         # tělo s mečem u pasu (= Nahy_zbran)
armed_big = read(SRC / "Nahy_zbran.png")[3456:]
sword_main, sword_big = diff(armed, plain), diff(armed_big, body_big())

# --- vybavení: id, název, popis, slot, zdroj, základ, staty ---------------------------------------
# zdroj: ("dir", složka s animacemi) | ("sheet", soubor); základ, od kterého se kompletní postava odečítá:
# "armed" (tělo s mečem u pasu) | "plain" (holé) | "shirt" (tělo + tričko, u bot) | "none" (sheet už obsahuje jen věc)
shirt_comp = from_dir(SRC / "Telo/standard")
S = {"WEAPON": 1, "HEAD": 2, "FEET": 3, "TORSO": 5, "HANDS": 6}
ITEMS = [
    # hlava
    dict(id="hood", name="Kápě", desc="Látková kápě.", slot="HEAD", src=("dir", "Hlava/standard"), base="armed", defense=1, price=25),
    dict(id="mail_coif", name="Kroužková kapuce", desc="Ocelová kroužková kapuce.", slot="HEAD", src=("sheet", "Hlava/125 mail__steel_.png"), base="none", defense=2, price=60),
    dict(id="close_helm", name="Uzavřená přilba", desc="Keramická uzavřená přilba.", slot="HEAD", src=("sheet", "Hlava/130 close_helm__ceramic_.png"), base="none", defense=4, price=120),
    dict(id="wizard_hat", name="Čarodějův klobouk", desc="Bílý nebeský klobouk.", slot="HEAD", src=("sheet", "Hlava/130 celestial_wizard_hat__white_.png"), base="none", defense=1, max_mana=5, price=80),
    # tělo
    dict(id="shirt", name="Tričko", desc="Obyčejné tričko.", slot="TORSO", src=("dir", "Telo/standard"), base="armed", price=10),
    dict(id="chainmail", name="Kroužková košile", desc="Železná kroužková košile.", slot="TORSO", src=("sheet", "Telo/050 chainmail__iron_.png"), base="none", defense=3, price=100),
    dict(id="frock_coat", name="Zelený kabát", desc="Elegantní zelený kabát.", slot="TORSO", src=("sheet", "Telo/055 frock_coat__green_.png"), base="none", defense=1, max_mana=3, price=70),
    dict(id="plate", name="Plátová zbroj", desc="Ocelový plátový krunýř.", slot="TORSO", src=("sheet", "Telo/060 plate__steel_.png"), base="none", defense=6, max_hp=4, price=250),
    # boty a rukavice (komplety obsahují i tričko -> základ "shirt")
    dict(id="boots", name="Boty", desc="Pevné boty.", slot="FEET", src=("sheet", "Boty/Boty.png"), base="shirt", defense=1, price=30),
    dict(id="gloves", name="Rukavice", desc="Kožené rukavice.", slot="HANDS", src=("sheet", "Rukavice/rukavice.png"), base="armed", defense=1, price=20),
    # zbraně
    dict(id="sword", name="Meč", desc="Vyvážená čepel, široký sek.", slot="WEAPON", src=("sword", ""), attack="backslash", damage=3, price=60),
    dict(id="longsword", name="Dlouhý meč", desc="Dlouhá čepel pro dva údery.", slot="WEAPON", src=("dir", "Zbrane/Longsword"), base="plain", attack="slash", damage=5, price=120),
    dict(id="dagger", name="Dýka", desc="Rychlá a lehká.", slot="WEAPON", src=("dir", "Zbrane/Dagger"), base="plain", attack="halfslash", damage=2, price=40),
    dict(id="axe", name="Sekera", desc="Těžká sekera.", slot="WEAPON", src=("dir", "Zbrane/Axe"), base="plain", attack="slash", damage=4, price=90),
    dict(id="blunt", name="Palcát", desc="Drtí zbroj.", slot="WEAPON", src=("dir", "Zbrane/Blunt"), base="plain", attack="slash", damage=4, price=80),
    dict(id="staff", name="Hůl", desc="Dřevěná hůl.", slot="WEAPON", src=("dir", "Zbrane/Staff"), base="plain", attack="thrust", damage=2, max_mana=5, price=50),
    dict(id="bow", name="Luk", desc="Střelná zbraň (střelba zatím není).", slot="WEAPON", src=("dir", "Zbrane/Bow"), base="plain", attack="shoot", damage=3, price=100),
    dict(id="crossbow", name="Kuše", desc="Střelná zbraň (střelba zatím není).", slot="WEAPON", src=("dir", "Zbrane/Crossbow"), base="plain", attack="shoot", damage=4, price=140),
]
# "shirt" = tělo + tričko (základ pro boty); kde tričko chybí, zůstane holé tělo
BASES = {"armed": armed, "plain": plain, "shirt": np.where(shirt_comp[..., 3:] > 0, shirt_comp, armed)}


def trim(a: np.ndarray) -> np.ndarray:
    a = a.copy()
    a[a[..., 3] == 0] = 0
    return a


def icon(layer: np.ndarray, weapon: bool, pad=1, scale=3) -> Image.Image:
    """Ikona = ořez věci z nejvhodnějšího snímku (zbraň: pohled doleva, ostatní: dolů; snímek s nejvíce pixely), x3 nearest."""
    d = 1 if weapon else 2
    cands = [(ROWS[a] + d, c) for a in ("combat", "idle", "walk", "shoot") for c in range(13)]
    row, col = max(cands, key=lambda rc: int((layer[rc[0] * 64:(rc[0] + 1) * 64, rc[1] * 64:(rc[1] + 1) * 64, 3] > 0).sum()))
    cell = layer[row * 64:(row + 1) * 64, col * 64:(col + 1) * 64]
    ys, xs = np.nonzero(cell[..., 3] > 0)
    crop = Image.fromarray(cell[ys.min():ys.max() + 1, xs.min():xs.max() + 1])
    side = max(crop.size)
    img = Image.new("RGBA", (side + 2 * pad, side + 2 * pad))
    img.paste(crop, ((side - crop.width) // 2 + pad, (side - crop.height) // 2 + pad))
    return img.resize((img.width * scale, img.height * scale), Image.NEAREST)


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
Image.fromarray(trim(plain)).save(OUT / "body/body.png")
print(f"tělo: chybí animace {missing_anims(plain)}")

for it in ITEMS:
    kind, rel = it["src"]
    big = None
    if kind == "sword":
        main, big, comp = sword_main, sword_big, armed
    else:
        comp = from_dir(SRC / rel) if kind == "dir" else from_sheet(SRC / rel)
        main = comp if it["base"] == "none" else diff(comp, BASES[it["base"]])
    weapon = it["slot"] == "WEAPON"
    sheet = canvas(BIG_Y + (BIG_ROWS * BIG if big is not None else 0), W_BIG if big is not None else W)
    sheet[:BIG_Y, :W] = main
    if big is not None:
        sheet[BIG_Y:] = big
    path = OUT / ("weapons" if weapon else "equipment") / f"{it['id']}.png"
    Image.fromarray(trim(sheet)).save(path)
    icon(main, weapon).save(f"assets/icons/{it['id']}.png")
    text = TRES.format(sheet=path.as_posix(), slot=S[it["slot"]], **{k: it[k] for k in ("id", "name", "desc")})
    text += f'attack_anim = &"{it["attack"]}"\n' if weapon else ""
    text += "".join(f"{k} = {it[k]}\n" for k in STAT_KEYS if it.get(k))
    Path(f"data/items/{it['id']}.tres").write_text(text)
    print(f"{it['id']:11s} chybí animace: {missing_anims(comp) or '-'}")
