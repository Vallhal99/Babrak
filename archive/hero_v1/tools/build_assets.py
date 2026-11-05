"""Rozdělí full_sheet_with_sword.png na tělo + vrstvu meče a vyrobí ikony.
Spuštění z kořene projektu:  python3 tools/build_assets.py
Layout sheetu: viz scripts/character/anim_catalog.gd (64px snímky, dole 128px 'oversize')."""
import colorsys
import numpy as np
from PIL import Image

SRC = "tools/reference/full_sheet_with_sword.png"
SWORD = {(97, 72, 44), (46, 37, 51), (253, 208, 130), (131, 99, 50), (175, 138, 53), (253, 245, 204)}
UP_H = 3456  # výška části s 64px snímky

im = np.array(Image.open(SRC).convert("RGBA"))
rgb = im[..., :3]
vis = im[..., 3] > 0
is_sword = np.zeros(vis.shape, bool)
for c in SWORD:
    is_sword |= (rgb == np.array(c)).all(-1)
is_sword &= vis

# Paleta těla = barvy horní části mimo meč. V oversize části je zbraň vše, co není v paletě těla.
body_pal = {tuple(p) for p in im[:UP_H][vis[:UP_H] & ~is_sword[:UP_H]].reshape(-1, 4)}
weapon = np.zeros_like(is_sword)
weapon[:UP_H] = is_sword[:UP_H]
bot = im[UP_H:]
weapon[UP_H:] = [[vis[UP_H + y, x] and tuple(bot[y, x]) not in body_pal for x in range(im.shape[1])] for y in range(bot.shape[0])]

body = im.copy()
body[weapon] = 0
body = body[:UP_H, :832]  # oversize tělo nepotřebujeme, kreslí se 64px tělo

# Zalátání děr po meči (ruka), 2 průchody: průhledný pixel s >=3 sousedy -> nejčastější barva
hole = np.zeros(body.shape[:2], bool); hole[:UP_H] = is_sword[:UP_H, :832]
for _ in range(2):
    for y, x in zip(*np.nonzero(hole & (body[..., 3] == 0))):
        n = [tuple(body[y + dy, x + dx]) for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1))
             if 0 < y + dy < UP_H - 1 and 0 < x + dx < 831 and body[y + dy, x + dx, 3] == 255 and not hole[y + dy, x + dx]]
        if len(n) >= 3:
            body[y, x] = max(set(n), key=n.count)

w = im.copy(); w[~weapon] = 0
Image.fromarray(body).save("assets/characters/hero/body/hero_base.png")
Image.fromarray(w).save("assets/characters/hero/weapons/sword_wood.png")

# Ocelová varianta meče (posun odstínu + desaturace) – test výměny zbraně
def steel(px):
    r, g, b, a = px
    h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
    r, g, b = colorsys.hsv_to_rgb(0.58, s * 0.25, min(1, v * 1.05))
    return (int(r * 255), int(g * 255), int(b * 255), a)
ws = w.copy()
ys, xs = np.nonzero(ws[..., 3] > 0)
for y, x in zip(ys, xs):
    ws[y, x] = steel(tuple(ws[y, x]))
Image.fromarray(ws).save("assets/characters/hero/weapons/sword_steel.png")

# Ikony: ořez předmětu z idle snímku (řádek 24 = dolů, sloupec 0; meč řádek 23 = vlevo), x4 nearest
def icon(sheet_path, row, name, pad=1, scale=3):
    a = np.array(Image.open(sheet_path).convert("RGBA"))[row * 64:(row + 1) * 64, :64]
    ys, xs = np.nonzero(a[..., 3] > 0)
    c = Image.fromarray(a[ys.min():ys.max() + 1, xs.min():xs.max() + 1])
    s = max(c.size); o = Image.new("RGBA", (s + 2 * pad, s + 2 * pad))
    o.paste(c, ((s - c.width) // 2 + pad, (s - c.height) // 2 + pad))
    o.resize((o.width * scale, o.height * scale), Image.NEAREST).save(f"assets/icons/{name}.png")
E = "assets/characters/hero/equipment/"
icon(E + "boots_armour_silver.png", 24, "boots_armour_silver"); icon(E + "boots_sandals_maroon.png", 24, "boots_sandals_maroon")
icon(E + "helm_mail_silver.png", 24, "helm_mail_silver"); icon(E + "helm_armet_steel.png", 24, "helm_armet_steel")
icon(E + "helm_hood_slate.png", 24, "helm_hood_slate")
icon("assets/characters/hero/weapons/sword_wood.png", 23, "sword_wood"); icon("assets/characters/hero/weapons/sword_steel.png", 23, "sword_steel")

# Diagnostika: zarovnání (nohy) a rekompozice oversize
feet = np.nonzero(im[24 * 64:25 * 64, :64, 3].any(1))[0]
print("idle-down y-rozsah", feet.min(), feet.max(), "| zbraň px:", int(weapon.sum()), "| tělo px:", int((body[..., 3] > 0).sum()))
