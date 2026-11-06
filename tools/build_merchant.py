"""Obchodník z obrázku tools/source_merchant/caba64.jpg (pixel art 55x55 "pixelů", stojí čelem).
Sprite se vloží do všech buněk sheetu (všechny animace i směry), takže stojí a hledí na hráče.
Spouštět z kořene projektu: python3 tools/build_merchant.py"""
import re
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

GRID, CELL, FEET_Y = 55, 64, 61
catalog = Path("scripts/character/anim_catalog.gd").read_text()
big_y = int(re.search(r"const BIG_Y := (\d+)", catalog).group(1))
anims = [(int(r), int(f), int(d or 4)) for r, f, d in re.findall(r'"row": (\d+), "frames": (\d+)(?:[^}]*?"dirs": (\d+))?', catalog)]

img = Image.open("tools/source_merchant/caba64.jpg").convert("RGB").resize((GRID, GRID), Image.BOX)
px = np.array(img)
white = (px.min(-1) > 225)
lab, _ = ndimage.label(white)
border = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
bg = np.isin(lab, list(border))
rgba = np.dstack([px, np.where(bg, 0, 255).astype(np.uint8)])
ys, xs = np.nonzero(~bg)
sprite = rgba[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
h, w = sprite.shape[:2]
cell = np.zeros((CELL, CELL, 4), np.uint8)
y0, x0 = FEET_Y + 1 - h, (CELL - w) // 2
cell[y0:y0 + h, x0:x0 + w] = sprite

sheet = np.zeros((big_y, 13 * CELL, 4), np.uint8)
for row, frames, dirs in anims:
    for d in range(dirs):
        for f in range(frames):
            sheet[(row + d) * CELL:(row + d + 1) * CELL, f * CELL:(f + 1) * CELL] = cell
Image.fromarray(sheet).save("assets/characters/merchant/merchant.png")
print("obchodník:", w, "x", h, "px")
