"""Generuje barevné LUT (16 řezů, pásek 256x16) pro nálady oblastí: python3 tools/make_luts.py → data/lut/*.png
Každá nálada je jednoduchá úprava: posun stínů/světel, saturace, kontrast. Hra je míchá podle polohy hrdiny."""
import os
import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "data", "lut")
# název: (stíny RGB, světla RGB, saturace, kontrast, jas)
MOODS = {
    "neutral": ((1, 1, 1), (1, 1, 1), 1.0, 1.0, 0.0),
    "forest": ((0.82, 1.0, 0.92), (1.0, 1.03, 0.86), 1.06, 1.06, -0.02),      # zelenavé stíny, žlutozelená světla
    "village": ((0.98, 0.92, 0.88), (1.08, 1.0, 0.86), 1.05, 1.02, 0.015),     # teplé, útulné
    "graveyard": ((0.8, 0.86, 1.05), (0.92, 0.98, 1.02), 0.72, 1.12, -0.03),   # studené, odbarvené
    "mountain": ((0.9, 0.96, 1.06), (1.0, 0.99, 0.97), 0.9, 1.08, 0.0),        # chladné, ostré
    "water": ((0.85, 0.97, 1.05), (0.97, 1.02, 1.04), 1.04, 1.0, 0.0),
}


def make(shadow, light, sat, con, bright):
    g = np.linspace(0, 1, 16)
    b, gg, r = np.meshgrid(g, g, g, indexing="ij")           # [b][g][r]
    c = np.stack([r, gg, b], -1)
    lum = (c * [0.299, 0.587, 0.114]).sum(-1, keepdims=True)
    t = np.clip((lum - 0.1) / 0.7, 0, 1); t = t * t * (3 - 2 * t)
    c = c * (np.array(shadow) * (1 - t) + np.array(light) * t)
    lum = (c * [0.299, 0.587, 0.114]).sum(-1, keepdims=True)
    c = lum + (c - lum) * sat
    c = (c - 0.5) * con + 0.5 + bright
    c = np.clip(c, 0, 1)
    strip = np.zeros((16, 256, 3))
    for bi in range(16):
        strip[:, bi * 16:(bi + 1) * 16] = c[bi].transpose(0, 1, 2)   # řádek = g, sloupec = r
    return Image.fromarray((strip * 255 + .5).astype(np.uint8))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for n, a in MOODS.items():
        make(*a).save(os.path.join(OUT, n + ".png"))
    print("LUT:", ", ".join(MOODS))
