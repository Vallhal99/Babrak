#!/usr/bin/env python3
"""Dočasné obrázky truhly (zavřená / otevřená), pixel-art. Oficiální obrázky stačí uložit pod stejnými názvy:
assets/props/chest_closed.png a chest_open.png (cca 48x40 px, patou/spodkem dole uprostřed)."""
from PIL import Image, ImageDraw
from pathlib import Path
W, H = 48, 40
WOOD, WOOD_D, WOOD_L = (122, 78, 42), (84, 52, 28), (156, 104, 58)
METAL, METAL_D, GOLD = (150, 156, 166), (96, 102, 114), (240, 200, 70)
OUT = (28, 18, 12)

def body(d):
    d.rectangle([4, 18, 43, 37], fill=WOOD, outline=OUT)
    for x in (12, 21, 30, 38):
        d.line([x, 19, x, 36], fill=WOOD_D)
    d.rectangle([4, 18, 43, 21], fill=WOOD_L, outline=OUT)
    for x in (8, 38):
        d.rectangle([x, 18, x + 3, 37], fill=METAL, outline=OUT)
        d.line([x + 1, 19, x + 1, 36], fill=METAL_D)

def closed():
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    d.ellipse([2, 33, 45, 39], fill=(0, 0, 0, 70))
    body(d)
    d.rounded_rectangle([4, 7, 43, 19], radius=6, fill=WOOD, outline=OUT)
    d.arc([4, 3, 43, 22], 180, 360, fill=WOOD_L)
    for x in (8, 38):
        d.rectangle([x, 8, x + 3, 19], fill=METAL, outline=OUT)
    d.rectangle([20, 15, 27, 24], fill=GOLD, outline=OUT)   # zámek
    d.rectangle([22, 18, 25, 21], fill=OUT)
    return im

def opened():
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    d.ellipse([2, 33, 45, 39], fill=(0, 0, 0, 70))
    d.polygon([(6, 17), (41, 17), (39, 3), (8, 3)], fill=WOOD_D, outline=OUT)   # víko vzadu
    d.rectangle([8, 5, 39, 7], fill=WOOD)
    body(d)
    d.rectangle([6, 15, 41, 21], fill=(36, 22, 14), outline=OUT)                # vnitřek
    for x, y in ((14, 14), (22, 12), (30, 14), (36, 13), (19, 15)):
        d.ellipse([x, y, x + 4, y + 3], fill=GOLD, outline=(160, 120, 30))
    return im

if __name__ == "__main__":
    out = Path(__file__).resolve().parent.parent / "assets" / "props"
    out.mkdir(parents=True, exist_ok=True)
    closed().save(out / "chest_closed.png"); opened().save(out / "chest_open.png")
    print("uloženo", out)
