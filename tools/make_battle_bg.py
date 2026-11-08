#!/usr/bin/env python3
"""Dočasné pozadí tahového souboje (les) – vykreslí se procedurálně, než bude hotový finální obrázek.

Použití:  python3 tools/make_battle_bg.py [výstup.png] [--seed N]
Výchozí výstup: assets/battle/bg_forest.png (1280x960, poměr 4:3 jako okno hry).

Finální obrázek stačí uložit pod stejným názvem (nebo bg_<nálada>.png pro jiné oblasti:
forest, village, graveyard, mountain, water, neutral) – hra si ho najde sama, žádný kód se nemění.
Kompozice: horizont ~42 % výšky, hráč stojí vpravo, nepřátelé vlevo na 54–68 % výšky (tam má být zem).
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

W, H = 1280, 960
HORIZON = int(H * 0.42)


def vnoise(w, h, cells_x, cells_y, rng):
    grid = rng.random((cells_y + 1, cells_x + 1)).astype(np.float32)
    im = Image.fromarray((grid * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
    return np.asarray(im, dtype=np.float32) / 255.0


def fbm(w, h, base, rng, octaves=4):
    total = np.zeros((h, w), np.float32)
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        total += amp * vnoise(w, h, base * 2 ** o, max(2, int(base * 2 ** o * h / w)), rng)
        norm += amp
        amp *= 0.5
    return total / norm


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def layer():
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    return im, ImageDraw.Draw(im)


def bark(im, rng, strength=0.5):
    """Svislé žíhání kůry: násobí barvu tam, kde je vrstva neprůhledná."""
    a = np.asarray(im, dtype=np.float32).copy()
    streak = vnoise(W, H, 90, 3, rng)
    a[..., :3] *= (1.0 - strength / 2 + strength * streak)[..., None]
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")


def trunk(d, x, base_y, top_y, w_base, w_top, color, lean):
    d.polygon([(x - w_base / 2, base_y), (x + w_base / 2, base_y),
               (x + lean + w_top / 2, top_y), (x + lean - w_top / 2, top_y)], fill=color)
    # náběh kořenů
    d.polygon([(x - w_base * 0.9, base_y + 6), (x - w_base * 0.35, base_y - w_base * 0.8),
               (x + w_base * 0.35, base_y - w_base * 0.8), (x + w_base * 0.9, base_y + 6)], fill=color)


def make(seed=7):
    rng = np.random.default_rng(seed)
    py_rng = np.random.default_rng(seed + 1)

    # --- obloha / dálka: svítivá zeleno-zlatá mlha za stromy
    y = np.linspace(0, 1, H, dtype=np.float32)[:, None]
    top, mid, haze = np.array([22, 48, 44]), np.array([88, 128, 84]), np.array([206, 214, 150])
    t = np.clip(y / (HORIZON / H), 0, 1)
    sky = top + (mid - top) * (t ** 1.4)[..., None]
    glow = np.exp(-(((np.arange(W)[None, :] - W * 0.62) / (W * 0.30)) ** 2) - (((y * H - HORIZON * 0.55) / (H * 0.30)) ** 2))
    sky = sky + (haze - sky) * (glow * 0.85)[..., None]
    img = Image.fromarray(np.clip(sky, 0, 255).astype(np.uint8)).convert("RGBA")

    # --- koruny stromů nahoře (tmavé, rozmazané) + světlé škvíry
    crown, d = layer()
    for _ in range(260):
        cx, cy = py_rng.uniform(-50, W + 50), py_rng.uniform(-60, H * 0.30)
        rx, ry = py_rng.uniform(60, 190), py_rng.uniform(40, 120)
        shade = py_rng.uniform(0, 1)
        d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=lerp((14, 40, 30), (42, 82, 46), shade) + (int(py_rng.uniform(140, 230)),))
    crown = crown.filter(ImageFilter.GaussianBlur(9))
    leaks, d = layer()
    for _ in range(70):
        cx, cy = py_rng.uniform(W * 0.25, W * 0.95), py_rng.uniform(0, H * 0.22)
        r = py_rng.uniform(10, 38)
        d.ellipse([cx - r, cy - r * 0.7, cx + r, cy + r * 0.7], fill=(235, 238, 170, int(py_rng.uniform(70, 170))))
    leaks = leaks.filter(ImageFilter.GaussianBlur(11))
    img = Image.alpha_composite(img, leaks)
    img = Image.alpha_composite(img, crown)

    # --- tři vrstvy kmenů s hloubkovou neostrostí (dálka světlejší a modřejší)
    specs = [  # (počet, šířka od-do, barva, rozmazání, základna y, průhlednost)
        (16, (16, 30), (86, 118, 92), 5.5, HORIZON + 8, 235),
        (9, (34, 62), (44, 74, 54), 2.6, HORIZON + 40, 245),
    ]
    for count, (w0, w1), color, blur, base, alpha in specs:
        lay, d = layer()
        for _ in range(count):
            x = py_rng.uniform(-20, W + 20)
            w = py_rng.uniform(w0, w1)
            trunk(d, x, base + py_rng.uniform(-8, 14), -40, w * 1.15, w * 0.8, color + (alpha,), py_rng.uniform(-18, 18))
        lay = bark(lay, rng, 0.45).filter(ImageFilter.GaussianBlur(blur))
        img = Image.alpha_composite(img, lay)
        # mlha mezi vrstvami
        mist = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        md = ImageDraw.Draw(mist)
        md.rectangle([0, HORIZON - 60, W, HORIZON + 70], fill=(205, 215, 160, 70))
        img = Image.alpha_composite(img, mist.filter(ImageFilter.GaussianBlur(40)))

    # --- podlaha: tráva s cestou, tmavne směrem k divákovi
    gy = np.arange(H, dtype=np.float32)[:, None]
    gt = np.clip((gy - HORIZON) / (H - HORIZON), 0, 1)
    g_far, g_near = np.array([128, 156, 92]), np.array([30, 58, 34])
    ground = g_far + (g_near - g_far) * (gt ** 0.8)[..., None]
    ground = ground * np.ones((1, W, 1), np.float32)
    n = fbm(W, H, 10, rng)
    # textura se s hloubkou zjemňuje (blíž = větší skvrny)
    ground *= (0.82 + 0.36 * n)[..., None]
    # cesta: klikatý pás hlíny
    path = Image.new("L", (W, H), 0)
    pd = ImageDraw.Draw(path)
    pts_l, pts_r = [], []
    for i in range(0, 41):
        v = i / 40.0
        yy = HORIZON + (H - HORIZON) * v
        cx = W * (0.50 + 0.14 * np.sin(v * 3.1 + 0.4)) - 40 * v
        half = 28 + 380 * (v ** 1.35)
        pts_l.append((cx - half, yy))
        pts_r.append((cx + half, yy))
    pd.polygon(pts_l + pts_r[::-1], fill=255)
    path = path.filter(ImageFilter.GaussianBlur(14))
    pm = (np.asarray(path, dtype=np.float32) / 255.0)[..., None]
    dirt_far, dirt_near = np.array([188, 166, 112]), np.array([84, 64, 40])
    dirt = dirt_far + (dirt_near - dirt_far) * (gt ** 0.8)[..., None]
    dirt = dirt * (0.85 + 0.3 * fbm(W, H, 18, rng))[..., None]
    ground = ground * (1 - pm * 0.92) + dirt * (pm * 0.92)
    gimg = Image.fromarray(np.clip(ground, 0, 255).astype(np.uint8)).convert("RGBA")
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).rectangle([0, HORIZON, W, H], fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(5))
    img = Image.composite(gimg, img, mask)

    # --- trsy trávy a kamínky (větší dole)
    tufts, d = layer()
    for _ in range(2600):
        yy = HORIZON + (H - HORIZON) * py_rng.uniform(0, 1) ** 0.7
        s = 0.25 + 1.6 * (yy - HORIZON) / (H - HORIZON)
        x = py_rng.uniform(0, W)
        shade = py_rng.uniform(0, 1)
        col = lerp((40, 76, 38), (150, 184, 96), shade) + (int(py_rng.uniform(110, 220)),)
        for k in range(py_rng.integers(2, 5)):
            dx = (k - 1.5) * 3 * s
            d.line([(x + dx, yy), (x + dx + py_rng.uniform(-4, 4) * s, yy - py_rng.uniform(6, 15) * s)], fill=col, width=max(1, int(s * 1.4)))
    img = Image.alpha_composite(img, tufts)

    # --- světelné paprsky z pravého horního rohu
    shafts, d = layer()
    for i in range(7):
        x0 = W * (0.42 + 0.10 * i) + py_rng.uniform(-30, 30)
        wdt = py_rng.uniform(40, 110)
        d.polygon([(x0, -20), (x0 + wdt, -20), (x0 - 380 + wdt * 1.6, H * 0.92), (x0 - 380 - wdt * 0.4, H * 0.92)],
                  fill=(255, 244, 186, int(py_rng.uniform(26, 58))))
    img = Image.alpha_composite(img, shafts.filter(ImageFilter.GaussianBlur(22)))

    # --- popředí: rámující kmeny a keře po stranách (nejtmavší, ostré)
    fg, d = layer()
    for x, w in [(-30, 220), (W * 0.045, 120), (W * 0.965, 190), (W * 1.04, 240)]:
        trunk(d, x, H + 40, -40, w, w * 0.7, (16, 28, 20, 255), (60 if x < W / 2 else -60) * 0.3)
    fg = bark(fg, rng, 0.35)
    bush, bd = layer()
    for _ in range(90):
        side = py_rng.choice([0, 1])
        cx = py_rng.uniform(-30, W * 0.2) if side == 0 else py_rng.uniform(W * 0.8, W + 30)
        cy = py_rng.uniform(H * 0.72, H + 20)
        r = py_rng.uniform(30, 90)
        bd.ellipse([cx - r, cy - r * 0.7, cx + r, cy + r * 0.7], fill=lerp((10, 26, 16), (34, 62, 34), py_rng.uniform(0, 1)) + (235,))
    img = Image.alpha_composite(img, bush.filter(ImageFilter.GaussianBlur(1.2)))
    img = Image.alpha_composite(img, fg.filter(ImageFilter.GaussianBlur(0.8)))

    # --- tonální korekce: vinětace, zrno, teplé světlo
    a = np.asarray(img.convert("RGB"), dtype=np.float32)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    r = np.sqrt(((xx - W * 0.55) / (W * 0.75)) ** 2 + ((yy - H * 0.45) / (H * 0.8)) ** 2)
    a *= (1.0 - 0.55 * np.clip(r - 0.35, 0, 1) ** 1.5)[..., None]
    a *= np.array([1.04, 1.0, 0.92], np.float32)
    a += rng.normal(0, 2.2, (H, W, 1)).astype(np.float32)
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    seed = 7
    if "--seed" in sys.argv:
        seed = int(sys.argv[sys.argv.index("--seed") + 1])
        args = [a for a in args if a != str(seed)]
    root = Path(__file__).resolve().parent.parent
    out = Path(args[0]) if args else root / "assets" / "battle" / "bg_forest.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    make(seed).save(out, optimize=True)
    print("uloženo:", out)
