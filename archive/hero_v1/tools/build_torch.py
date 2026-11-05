"""Dokreslí pózu 'držení pochodně' (zvednutá ruka) pro tělo + vrstvu plamene.
Výstup (layout 'extra': 8 snímků x 4 směry po 64px, viz AnimCatalog torch_idle):
  body/hero_torch_pose.png, equipment/torch_flame.png, icons/torch.png
Spuštění z kořene projektu: python3 tools/build_torch.py"""
import collections, math, random
import numpy as np
from PIL import Image, ImageDraw

body = np.array(Image.open("assets/characters/hero/body/hero_base.png").convert("RGBA"))
IDLE = 22
def frame(d, c): return body[(IDLE + d) * 64:(IDLE + d + 1) * 64, c * 64:(c + 1) * 64].copy()

def common(a, box, pred=lambda p: True):
    x0, y0, x1, y1 = box
    px = [tuple(p) for p in a[y0:y1, x0:x1].reshape(-1, 4) if p[3] == 255 and pred(p)]
    return collections.Counter(px).most_common(1)[0][0]

f = frame(2, 0)
SKIN = common(f, (26, 28, 38, 34), lambda p: p[0] > 200 and p[1] > 140)
SHIRT = common(f, (24, 38, 38, 46), lambda p: p[0] > 200 and p[1] > 200)
OUT = common(f, (14, 10, 50, 40), lambda p: int(p[0]) + int(p[1]) + int(p[2]) < 160)
SHADE = tuple(int(v * .82) for v in SKIN[:3]) + (255,)
print("skin", SKIN, "shirt", SHIRT, "outline", OUT)

# (rameno, loket, ruka), box starého ramene k vymazání (jen čelo/záda; z boku se zvedá vzdálená ruka za tělem)
CFG = {0: dict(path=[(45, 38), (49, 35), (49, 24)], erase=(45, 40, 52, 54)),
       2: dict(path=[(45, 38), (49, 35), (49, 24)], erase=(45, 40, 52, 54)),
       1: dict(path=[(39, 38), (44, 35), (46, 24)], erase=None),
       3: dict(path=[(24, 38), (19, 35), (17, 24)], erase=None)}

def raised_arm(a, d):
    c = CFG[d]
    if c["erase"]:
        x0, y0, x1, y1 = c["erase"]; a[y0:y1, x0:x1] = 0
    m = Image.new("L", (64, 64), 0); dr = ImageDraw.Draw(m)
    dr.line(c["path"], fill=255, width=3)
    hx, hy = c["path"][-1]; dr.rectangle([hx - 2, hy - 3, hx + 2, hy + 1], fill=255)
    mk = np.array(m) > 0
    out = np.zeros_like(mk)
    out[1:] |= mk[:-1]; out[:-1] |= mk[1:]; out[:, 1:] |= mk[:, :-1]; out[:, :-1] |= mk[:, 1:]
    out &= ~mk
    arm = np.zeros((64, 64, 4), np.uint8)
    sx, sy = c["path"][0]
    for y, x in zip(*np.nonzero(mk)):
        near = math.hypot(x - sx, y - sy) < 6
        arm[y, x] = SHIRT if near else (SHADE if (x + y) % 5 == 0 and y > hy + 2 else SKIN)
    arm[out] = OUT
    if d in (1, 3):   # z boku: ruka je ZA tělem
        under = a[..., 3] == 0
        a[under] = arm[under]
    else:             # zepředu/zezadu: ruka je přes pozadí těla, rukáv přes tělo
        a[:] = np.where((arm[..., 3:] > 0), arm, a)
    return a

pose = np.zeros((256, 512, 4), np.uint8)
flame = np.zeros((256, 512, 4), np.uint8)
rnd = random.Random(7)
FL = [(214, 70, 20, 255), (250, 140, 30, 255), (255, 214, 80, 255), (255, 244, 200, 255)]

def draw_flame(img, cx, ytop, n):
    h = 9 + (n % 3)  # výška plamene mírně kolísá
    sway = [0, 1, 0, -1, 0, 1, -1, 0][n]
    for r in range(h):
        t = (r + 1) / h
        w = max(1, round(3.2 * math.sin(math.pi * min(1, t * 0.95 + 0.12))))
        off = round(sway * (1 - t))
        for layer, col in enumerate(FL):
            ww = w - layer
            if ww < 0 or (layer == 3 and r < h * .55): continue
            for x in range(cx - ww + off, cx + ww + 1 + off):
                img[ytop + r, x] = col

for d in range(4):
    for n in range(8):
        a = raised_arm(frame(d, n // 4), d)
        pose[d * 64:(d + 1) * 64, n * 64:(n + 1) * 64] = a
        hx, hy = CFG[d]["path"][-1]
        fl = np.zeros((64, 64, 4), np.uint8)
        fl[hy - 10:hy + 4, hx:hx + 2] = (131, 99, 50, 255)      # rukojeť
        fl[hy - 10:hy + 4, hx - 1] = (97, 72, 44, 255)
        fl[hy - 11:hy - 9, hx - 1:hx + 2] = (46, 37, 51, 255)   # hlavice
        draw_flame(fl, hx, hy - 21, n)
        flame[d * 64:(d + 1) * 64, n * 64:(n + 1) * 64] = fl
Image.fromarray(pose).save("assets/characters/hero/body/hero_torch_pose.png")
Image.fromarray(flame).save("assets/characters/hero/equipment/torch_flame.png")
ic = Image.fromarray(flame[128:192, 0:64]).crop((40, 0, 56, 36)); 
o = Image.new("RGBA", (36, 36)); o.paste(ic, (10, 0)); o.resize((108, 108), Image.NEAREST).save("assets/icons/torch.png")

# náhled pro kontrolu
prev = Image.new("RGBA", (4 * 128, 128), (110, 150, 110, 255))
for d in range(4):
    c = Image.fromarray(pose[d * 64:(d + 1) * 64, 0:64]); c.alpha_composite(Image.fromarray(flame[d * 64:(d + 1) * 64, 0:64]))
    prev.alpha_composite(c.resize((128, 128), Image.NEAREST), (d * 128, 0))
prev.resize((prev.width * 2, prev.height * 2), Image.NEAREST).save("/tmp/claude-0/torch_preview.png")
