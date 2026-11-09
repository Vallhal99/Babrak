#!/usr/bin/env python3
"""Dočasné obrázky surovin (ikony 96x96) a rekvizit (pixel-art) pro craft, vaření, spánek a hrobku.
Finální obrázky stačí uložit pod stejnými názvy do assets/icons a assets/props."""
from PIL import Image, ImageDraw
from pathlib import Path
R = Path(__file__).resolve().parent.parent / "assets"
OUT = (28, 18, 12)

def icon(name, draw):
    im = Image.new("RGBA", (96, 96), (0, 0, 0, 0)); d = ImageDraw.Draw(im); draw(d)
    im.save(R / "icons" / f"{name}.png")

def iron(d):
    for i, (x, y) in enumerate(((14, 54), (46, 54), (30, 30))):
        d.polygon([(x, y + 22), (x + 12, y), (x + 50, y), (x + 36, y + 22)], fill=(150, 158, 170), outline=OUT)
        d.polygon([(x + 12, y), (x + 50, y), (x + 44, y + 6), (x + 14, y + 6)], fill=(205, 212, 222))
def wood(d):
    for y in (26, 46, 66):
        d.rounded_rectangle([12, y, 84, y + 16], radius=7, fill=(138, 92, 50), outline=OUT)
        d.ellipse([70, y + 1, 84, y + 15], fill=(214, 170, 110), outline=OUT)
def meat(d):
    d.ellipse([16, 28, 76, 72], fill=(200, 70, 60), outline=OUT); d.ellipse([28, 38, 52, 56], fill=(240, 150, 140))
    d.rectangle([66, 44, 86, 54], fill=(235, 226, 205), outline=OUT); d.ellipse([80, 38, 92, 60], fill=(235, 226, 205), outline=OUT)
def herb(d):
    for dx, c in ((0, (70, 160, 70)), (-18, (50, 130, 60)), (18, (90, 180, 80))):
        d.polygon([(48 + dx, 80), (40 + dx, 40), (48 + dx, 14), (56 + dx, 40)], fill=c, outline=OUT)
def mushroom(d):
    d.rounded_rectangle([40, 48, 58, 80], radius=5, fill=(235, 226, 205), outline=OUT)
    d.pieslice([18, 18, 80, 70], 180, 360, fill=(190, 80, 60), outline=OUT)
    for x, y in ((32, 40), (48, 32), (60, 44)): d.ellipse([x, y, x + 8, y + 8], fill=(250, 240, 220))
def key(d):
    d.ellipse([14, 14, 46, 46], outline=OUT, fill=None, width=7); d.ellipse([14, 14, 46, 46], outline=(240, 200, 70), width=4)
    d.rectangle([40, 38, 84, 48], fill=(240, 200, 70), outline=OUT); d.rectangle([70, 48, 78, 62], fill=(240, 200, 70), outline=OUT); d.rectangle([56, 48, 62, 58], fill=(240, 200, 70), outline=OUT)

def prop(name, size, draw):
    im = Image.new("RGBA", size, (0, 0, 0, 0)); d = ImageDraw.Draw(im); draw(d, size); im.save(R / "props" / f"{name}.png")

def workbench(d, s):
    d.ellipse([2, s[1] - 10, s[0] - 2, s[1] - 1], fill=(0, 0, 0, 70))
    d.rectangle([4, 16, s[0] - 5, 26], fill=(150, 104, 58), outline=OUT)
    for x in (8, s[0] - 14):
        d.rectangle([x, 26, x + 6, s[1] - 6], fill=(110, 72, 40), outline=OUT)
    d.polygon([(14, 16), (30, 16), (34, 10), (42, 10), (42, 5), (22, 5), (22, 10), (10, 10)], fill=(90, 94, 104), outline=OUT)  # kovadlina
    d.rectangle([46, 10, 50, 16], fill=(120, 80, 40), outline=OUT); d.rectangle([44, 6, 56, 11], fill=(150, 156, 166), outline=OUT)  # kladivo
def campfire(d, s):
    d.ellipse([4, s[1] - 14, s[0] - 4, s[1] - 2], fill=(0, 0, 0, 70))
    for i in range(7):
        x = 6 + i * (s[0] - 18) / 6; d.ellipse([x, s[1] - 18, x + 10, s[1] - 8], fill=(120, 120, 126), outline=OUT)
    d.line([10, s[1] - 14, s[0] - 10, s[1] - 24], fill=(110, 72, 40), width=5); d.line([s[0] - 10, s[1] - 14, 10, s[1] - 24], fill=(120, 80, 44), width=5)
    cx = s[0] // 2; d.polygon([(cx - 12, s[1] - 18), (cx - 6, s[1] - 38), (cx, s[1] - 30), (cx + 4, s[1] - 46), (cx + 12, s[1] - 18)], fill=(255, 150, 30), outline=(170, 60, 10))
    d.polygon([(cx - 6, s[1] - 18), (cx, s[1] - 32), (cx + 6, s[1] - 18)], fill=(255, 230, 110))
    d.line([cx - 22, s[1] - 28, cx + 22, s[1] - 28], fill=OUT, width=2); d.arc([cx - 18, s[1] - 24, cx + 18, s[1] - 8], 0, 180, fill=OUT, width=2)  # kotlík
def hay(d, s):
    d.ellipse([2, s[1] - 12, s[0] - 2, s[1] - 1], fill=(0, 0, 0, 70))
    d.ellipse([4, 8, s[0] - 4, s[1] - 6], fill=(214, 182, 84), outline=(130, 100, 40))
    for i in range(14):
        x = 8 + i * 4; d.line([x, 14 + (i % 4) * 4, x + 8, 30 + (i % 3) * 3], fill=(240, 212, 120), width=1)
def vein(d, s):
    d.ellipse([2, s[1] - 10, s[0] - 2, s[1] - 1], fill=(0, 0, 0, 70))
    d.polygon([(4, s[1] - 6), (10, 14), (24, 4), (38, 12), (s[0] - 4, s[1] - 6)], fill=(104, 106, 114), outline=OUT)
    for x, y in ((16, 20), (26, 14), (30, 28), (20, 32)): d.polygon([(x, y), (x + 8, y - 4), (x + 12, y + 4), (x + 4, y + 8)], fill=(210, 150, 80), outline=(120, 70, 30))
def bush(d, s):
    d.ellipse([2, s[1] - 9, s[0] - 2, s[1] - 1], fill=(0, 0, 0, 70))
    for x, y, r in ((12, 24, 12), (28, 20, 14), (22, 30, 12)): d.ellipse([x - r, y - r, x + r, y + r], fill=(60, 130, 60), outline=OUT)
    for x, y in ((14, 22), (30, 16), (24, 30)): d.ellipse([x, y, x + 5, y + 5], fill=(240, 120, 150))
def shrooms(d, s):
    d.ellipse([2, s[1] - 9, s[0] - 2, s[1] - 1], fill=(0, 0, 0, 70))
    for x, y, w in ((8, 20, 14), (24, 14, 18), (18, 26, 10)):
        d.rectangle([x + w // 2 - 2, y + 8, x + w // 2 + 2, y + 16], fill=(235, 226, 205), outline=OUT); d.pieslice([x, y, x + w, y + 14], 180, 360, fill=(190, 80, 60), outline=OUT)
def logs(d, s):
    d.ellipse([2, s[1] - 9, s[0] - 2, s[1] - 1], fill=(0, 0, 0, 70))
    for y in (s[1] - 20, s[1] - 12, s[1] - 28):
        d.rounded_rectangle([6, y, s[0] - 6, y + 9], radius=4, fill=(138, 92, 50), outline=OUT); d.ellipse([s[0] - 14, y, s[0] - 6, y + 9], fill=(214, 170, 110), outline=OUT)
def tomb(d, s):
    w, h = s
    d.ellipse([4, h - 14, w - 4, h - 2], fill=(0, 0, 0, 80))
    d.rectangle([8, 24, w - 9, h - 8], fill=(88, 90, 100), outline=OUT)
    d.pieslice([8, 6, w - 9, 60], 180, 360, fill=(88, 90, 100), outline=OUT)
    d.rectangle([w // 2 - 18, 38, w // 2 + 18, h - 8], fill=(10, 10, 16), outline=OUT); d.pieslice([w // 2 - 18, 26, w // 2 + 18, 52], 180, 360, fill=(10, 10, 16))
    for x in (14, w - 26): d.rectangle([x, 28, x + 12, h - 8], fill=(120, 122, 134), outline=OUT)
    for y in range(16, h - 12, 14): d.line([8, y, w - 9, y], fill=(66, 68, 78))
    d.ellipse([w // 2 - 6, 12, w // 2 + 6, 24], fill=(60, 220, 210), outline=OUT)

if __name__ == "__main__":
    (R / "icons").mkdir(exist_ok=True); (R / "props").mkdir(exist_ok=True)
    for n, f in (("iron", iron), ("wood", wood), ("meat", meat), ("herb", herb), ("mushroom", mushroom), ("archive_key", key)): icon(n, f)
    for n, s, f in (("workbench", (64, 48), workbench), ("campfire", (56, 56), campfire), ("hay", (64, 36), hay), ("iron_vein", (56, 44), vein),
                    ("herb_bush", (44, 40), bush), ("mushrooms", (40, 34), shrooms), ("logs", (56, 40), logs), ("tomb_entrance", (96, 96), tomb)):
        prop(n, s, f)
    print("hotovo")
