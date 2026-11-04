"""Rozrezani RPG Maker tilesetu na samostatne spritey pro svet (bez pecenych stinu, kotva = pata objektu)
a vytvoreni proceduralnich detailu (travnate chomace, kvetiny, kaminky).
Pouziti: python3 tools/build_world_assets.py   (cte tools/source_tilesets, zapisuje assets/world)"""
import json, random, os
import numpy as np
from PIL import Image, ImageDraw
SRC, OUT = "tools/source_tilesets", "assets/world"
os.makedirs(OUT, exist_ok=True)
ld = lambda n: Image.open(f"{SRC}/{n}.png").convert("RGBA")
a2, market, trees = ld("a2"), ld("market"), ld("trees1")
meta = {}

def strip_shadow(im):
    """Odstrani pecene cerne stiny (temer cerna pixely s ruznou pruhlednosti)."""
    a = np.array(im)
    dark = (a[:, :, :3].max(2) < 45)
    a[dark, 3] = 0
    return Image.fromarray(a)

def save_prop(name, img, strip=True):
    if strip: img = strip_shadow(img)
    bb = img.getbbox(); img = img.crop(bb)
    a = np.array(img)[:, :, 3]
    rows = np.where(a.max(1) > 60)[0]; base_y = rows.max()
    xs = np.where(a[max(0, base_y - 5):base_y + 1].max(0) > 60)[0]
    ax = int(xs.mean()) if len(xs) else img.width // 2
    half = max(ax, img.width - ax)
    canvas = Image.new("RGBA", (half * 2, img.height))
    canvas.paste(img, (half - ax, 0))                    # kotva (pata) = stred spodniho okraje
    canvas.save(f"{OUT}/{name}.png"); meta[name] = [canvas.width, canvas.height]

# stromy (trees1) - souradnice z obrazku tilesetu
for n, b in {"tree_oak": (0,5,290,193), "tree_pine": (286,0,387,146), "tree_a": (382,7,530,140),
             "tree_b": (526,5,627,145), "tree_spruce": (628,20,768,275), "tree_tall": (98,208,290,380),
             "tree_c": (623,382,722,481), "tree_d": (530,383,623,481), "tree_round": (385,390,530,479),
             "tree_conifer": (719,381,768,482), "tree_e": (578,625,675,768), "tree_f": (676,625,768,768)}.items():
    save_prop(n, trees.crop(b))
# tabor (market)
for n, b, st in [("tent", (384,480,528,624), False), ("campfire_ring", (144,480,192,528), False),
                 ("campfire_logs", (192,480,240,528), False), ("log", (192,576,240,624), False),
                 ("barrel", (240,432,288,480), False), ("stump", (192,528,240,576), False)]:
    save_prop(n, market.crop(b), st)
# seamless textury zeme (plne dlazdice autotilu)
a2.crop((24, 72, 72, 120)).convert("RGB").save(f"{OUT}/grass_tile.png")
a2.crop((96 + 24, 72, 96 + 72, 120)).convert("RGB").save(f"{OUT}/dirt_tile.png")

# --- proceduralni detaily (kresleno 4x, zmenseno) ---
random.seed(3); S = 4
def new(w, h): return Image.new("RGBA", (w * S, h * S))
def fin(im, name, w, h):
    im.resize((w, h), Image.LANCZOS).save(f"{OUT}/{name}.png"); meta[name] = [w, h]
def blade(d, x, y, h, lean, col, w):
    pts = [(x - w, y), (x + lean * .4 - w * .3, y - h * .55), (x + lean, y - h), (x + lean * .4 + w * .3, y - h * .55), (x + w, y)]
    d.polygon([(px * S, py * S) for px, py in pts], fill=col)
for i in range(5):                                       # travnate chomace
    W_, H_ = 36, 26; im = new(W_, H_); d = ImageDraw.Draw(im)
    for _ in range(random.randint(6, 10)):
        v = random.uniform(-25, 30)
        blade(d, W_ / 2 + random.uniform(-7, 7), H_ - 2, random.uniform(10, 22), random.uniform(-7, 7),
              (int(70 + v * .5), int(135 + v), int(40 + v * .3), 255), 1.2)
    fin(im, f"tuft_{i}", W_, H_)
for i, col in enumerate([(250, 250, 240), (250, 225, 90), (200, 150, 230), (240, 130, 150)]):  # kvetiny
    W_, H_ = 30, 24; im = new(W_, H_); d = ImageDraw.Draw(im)
    for _ in range(random.randint(2, 3)):
        px = W_ / 2 + random.uniform(-8, 8); py = H_ - 2; hh = random.uniform(7, 12)
        d.line([(px * S, py * S), (px * S, (py - hh) * S)], fill=(70, 125, 45, 255), width=S)
        r = random.uniform(1.8, 2.6); d.ellipse([(px - r) * S, (py - hh - r) * S, (px + r) * S, (py - hh + r) * S], fill=col + (255,))
        d.ellipse([(px - .7) * S, (py - hh - .7) * S, (px + .7) * S, (py - hh + .7) * S], fill=(250, 200, 60, 255))
    fin(im, f"flower_{i}", W_, H_)
for i in range(3):                                       # kaminky
    W_, H_ = 14, 9; im = new(W_, H_); d = ImageDraw.Draw(im)
    r = random.uniform(3, 5); s = random.uniform(-15, 15); c = (int(150 + s), int(135 + s), int(110 + s), 255)
    d.ellipse([(7 - r + .8) * S, 1.5 * S, (7 + r + .8) * S, 8.5 * S], fill=(60, 40, 20, 110))
    d.ellipse([(7 - r) * S, 1 * S, (7 + r) * S, 7 * S], fill=c)
    d.ellipse([(7 - r * .6) * S, 1.4 * S, (7 + r * .1) * S, 4 * S], fill=(c[0] + 30, c[1] + 28, c[2] + 24, 255))
    fin(im, f"pebble_{i}", W_, H_)
json.dump(meta, open(f"{OUT}/_sizes.json", "w"), indent=1)
print("OK", len(meta))
