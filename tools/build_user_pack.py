#!/usr/bin/env python3
"""Sestavi balicek pro Tiled (tiled_pack/) z uzivatelovych sheetu (tools/source_tilesets/user/images):
  * paleta terenu (ploche dlazdice s vlastnosti terrain) + textury terenu pro Godot (assets/world/terrain, data/world/terrains.json)
  * atlasy 'zem' (24 px) pro rucni kresleni zdi, utesu, mostu...
  * kolekce objektu automaticky vyriznute z 'okoli', 'doplnky', stromu (kolize, stin, vitr predvyplneny)
  * ukazkova mapa mapy/start.tmj
Pouziti z korene projektu: python3 tools/build_user_pack.py"""
import json, math, os, random, shutil, sys
import numpy as np
from PIL import Image
from scipy import ndimage as ndi
sys.path.insert(0, os.path.dirname(__file__))
from terrains_user import TERRAINS
from tiled_map import TiledMap, prop_list

SRC = "tools/source_tilesets/user/images"; R = "tiled_pack"; G = 24
random.seed(5)
shutil.rmtree(R, ignore_errors=True)
for d in ("tilesety/obrazky", "tilesety/objekty", "mapy"): os.makedirs(f"{R}/{d}")
P = lambda n, t, v: {"name": n, "type": t, "value": v}
tilesets = []            # (jmeno, tsj dict, tilecount)

# ---------- 1) paleta terenu ----------
os.makedirs("assets/world/terrain", exist_ok=True)
cols = 8; rows = math.ceil(len(TERRAINS) / cols)
pal = Image.new("RGBA", (cols * G, rows * G)); tiles = []
for i, (name, sh, x, y) in enumerate(TERRAINS):
    tex = Image.open(f"{SRC}/{sh}.png").convert("RGBA").crop((x, y, x + 48, y + 48))
    tex.convert("RGB").save(f"assets/world/terrain/{name}.png")
    pal.paste(tex.crop((12, 12, 12 + G, 12 + G)), ((i % cols) * G, (i // cols) * G))
    tiles.append({"id": i, "properties": [P("terrain", "string", name)]})
pal.save(f"{R}/tilesety/terrain.png")
tilesets.append(("terrain", {"type": "tileset", "version": "1.10", "name": "terrain", "image": "terrain.png", "imagewidth": cols * G, "imageheight": rows * G,
                             "tilewidth": G, "tileheight": G, "columns": cols, "tilecount": len(TERRAINS) if False else cols * rows, "margin": 0, "spacing": 0, "tiles": tiles}))
json.dump({"terrains": [{"name": n, "texture": f"res://assets/world/terrain/{n}.png"} for n, *_ in TERRAINS]}, open("data/world/terrains.json", "w"), indent=1)

# ---------- 2) atlasy zemi ----------
for key, sh in (("zem1", "titleset_zem"), ("zem2", "tileset_zem2"), ("zem3", "titleset_zem3")):
    shutil.copy(f"{SRC}/{sh}.png", f"{R}/tilesety/obrazky/{sh}.png"); im = Image.open(f"{SRC}/{sh}.png")
    c, r = im.width // G, im.height // G
    tilesets.append((key, {"type": "tileset", "version": "1.10", "name": key, "image": f"obrazky/{sh}.png", "imagewidth": im.width, "imageheight": im.height,
                           "tilewidth": G, "tileheight": G, "columns": c, "tilecount": c * r, "margin": 0, "spacing": 0}))

# ---------- 3) kolekce objektu ----------
def classify(img):
    a = np.array(img); op = a[:, :, 3] > 200; w, h = img.size
    r, g, b = (a[:, :, i][op].astype(float) for i in range(3))
    leafy = float(np.mean((g > b * 1.25) & (g > r * 0.85))) if len(r) else 0
    if h >= 70 and w >= 36 and leafy > 0.35: kind = "tree"
    elif h >= 70 and w < 36 and leafy > 0.35: kind = "tree"
    elif h >= 90 and w >= 90: kind = "building"
    elif leafy > 0.35 and h >= 24: kind = "bush"
    elif leafy > 0.35: kind = "plant"
    elif h >= 26: kind = "prop"
    else: kind = "deco"
    return kind

import sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import object_catalog
CAT = object_catalog.load()

def props_for(name, kind, w, h):
    e = CAT.get(name)
    if e: kind = e["kind"]
    if kind == "tree": col, sw, sh, ss = str(max(8, min(14, int(w * .09)))), True, True, (w * .3, max(8, w * .07))
    elif kind == "bush": col, sw, sh, ss = str(max(6, min(24, int(w * .3)))), True, True, (w * .42, max(5, h * .18))
    elif kind == "prop": col, sw, sh, ss = str(max(6, min(24, int(w * .35)))), False, True, (w * .42, max(5, h * .16))
    elif kind == "building": col, sw, sh, ss = f"{int(w * .7)},26", False, True, (w * .45, 14)
    elif kind == "plant": col, sw, sh, ss = "none", True, False, (0, 0)
    else: col, sw, sh, ss = "none", False, False, (0, 0)
    pr = [P("id", "string", name), P("kind", "string", kind), P("collision", "string", col), P("sway", "bool", sw), P("shadow", "bool", sh)]
    if e: pr += [P("tags", "string", ",".join(e["tags"])), P("label", "string", e["name"])]
    if sh: pr.append(P("shadow_size", "string", f"{ss[0]:.0f},{ss[1]:.0f}"))
    return pr

def extract(sheet, key):
    out = f"{R}/tilesety/objekty/{key}"; os.makedirs(out)
    a = np.array(Image.open(f"{SRC}/{sheet}.png").convert("RGBA"))
    a[(a[:, :, :3].max(2) < 60) & (a[:, :, 3] < 235)] = 0               # peceny stin (pulprusvitna cerna)
    alpha = a[:, :, 3] > 24
    lab, n = ndi.label(ndi.binary_dilation(alpha, iterations=2))
    boxes = []
    for i, sl in enumerate(ndi.find_objects(lab), 1):
        m = (lab[sl] == i) & alpha[sl]
        if m.sum() < 40: continue
        boxes.append((sl, m))
    boxes.sort(key=lambda b: ((b[0][0].start + b[0][0].stop) // 2 // 64, b[0][1].start))
    tl = []
    for idx, (sl, m) in enumerate(boxes):
        crop = a[sl].copy(); crop[~m] = 0
        img = Image.fromarray(crop); bb = img.getbbox(); img = img.crop(bb)
        arr = np.array(img)[:, :, 3]; base = np.where(arr.max(1) > 60)[0].max()
        xs = np.where(arr[max(0, base - 5):base + 1].max(0) > 60)[0]; ax = int(xs.mean()) if len(xs) else img.width // 2
        half = max(ax, img.width - ax); canvas = Image.new("RGBA", (half * 2, img.height)); canvas.paste(img, (half - ax, 0))
        name = f"{key}_{idx:03d}"; canvas.save(f"{out}/{name}.png"); kind = classify(canvas)
        tl.append({"id": idx, "image": f"objekty/{key}/{name}.png", "imagewidth": canvas.width, "imageheight": canvas.height,
                   "properties": props_for(name, kind, canvas.width, canvas.height)})
    return {"type": "tileset", "version": "1.10", "name": key, "tilewidth": max(t["imagewidth"] for t in tl), "tileheight": max(t["imageheight"] for t in tl),
            "columns": 0, "tilecount": len(tl), "margin": 0, "spacing": 0, "objectalignment": "bottom", "tiles": tl}

for sheet, key in (("tileset_okoli", "okoli1"), ("tileset_okoli2", "okoli2"), ("tileset_okoli3", "okoli3"), ("tileset_doplnky", "doplnky"),
                   ("Trees02", "stromy02"), ("Trees01", "rm_stromy01"), ("trees", "rm_stromy")):
    ts = extract(sheet, key); tilesets.append((key, ts)); print(f"  {key}: {ts['tilecount']} objektu")

# ---------- 4) zapis tilesetu + gidy ----------
first, refs = 1, {}
for name, ts in tilesets:
    json.dump(ts, open(f"{R}/tilesety/{name}.tsj", "w"), indent=0 if ts.get("tiles") else 1)
    refs[name] = (first, ts); first += ts["tilecount"]
json.dump({"folders": ["."]}, open(f"{R}/svet.tiled-project", "w"))

# ---------- 5) ukazkova mapa ----------
def tl_layer(i, name, props=None):
    return {"id": i, "name": name, "type": "tilelayer", "visible": True, "opacity": 1, "x": 0, "y": 0, "width": 0, "height": 0, "startx": 0, "starty": 0, "chunks": [], "properties": props or []}
m = TiledMap({"type": "map", "version": "1.10", "infinite": True, "orientation": "orthogonal", "renderorder": "right-down", "width": 100, "height": 76,
              "tilewidth": G, "tileheight": G, "nextlayerid": 10, "nextobjectid": 1,
              "tilesets": [{"firstgid": refs[n][0], "source": f"../tilesety/{n}.tsj"} for n, _ in tilesets],
              "layers": [tl_layer(1, "ground", [P("hd", "bool", True)]), tl_layer(2, "walls"), tl_layer(3, "above", [P("above", "bool", True)]),
                         {"id": 4, "name": "objects", "type": "objectgroup", "visible": True, "opacity": 1, "x": 0, "y": 0, "draworder": "topdown", "objects": []}]})
tid = {n: i + 1 for i, (n, *_ ) in enumerate(TERRAINS)}
X0, Y0, X1, Y1 = -50, -38, 50, 38
for y in range(Y0, Y1):
    for x in range(X0, X1): m.set("ground", x, y, tid["grass"])
def blob(cx, cy, r, t):
    for y in range(int(cy - r - 3), int(cy + r + 4)):
        for x in range(int(cx - r - 3), int(cx + r + 4)):
            rr = r * (1 + 0.18 * math.sin(x * .45 + y * .31) + 0.1 * math.cos(y * .7 - x * .2))
            if X0 <= x < X1 and Y0 <= y < Y1 and (x + .5 - cx) ** 2 + (y + .5 - cy) ** 2 <= rr * rr: m.set("ground", x, y, tid[t])
for cx, cy, r, t in [(-25, -15, 12, "grass_meadow"), (22, -18, 10, "flowers"), (-30, 15, 9, "dry_grass"), (28, 14, 8, "grass_dark"), (0, -26, 7, "leaf_grass"),
                     (-10, 24, 7, "grass_meadow"), (38, -2, 6, "flowers")]: blob(cx, cy, r, t)
for y in range(Y0, Y1):                                    # lesni podrost kolem okraje
    for x in range(X0, X1):
        if math.hypot((x - 0) / 48, (y - 0) / 36) > 0.78: m.set("ground", x, y, tid["forest_floor"])
blob(0, 2, 9, "dirt"); blob(0, 2, 5, "dirt_rock"); blob(-8, 3, 2.5, "cobble")
blob(30, 28 - 38 + 38, 7, "sand") if False else blob(26, 22, 7, "sand")
m.stroke("ground", [(-50, 6), (-30, 3), (-12, 4), (0, 2), (15, 6), (32, 3), (50, 5)], 1.8, tid["dirt"])
m.stroke("ground", [(0, 2), (2, 20), (-3, 32), (0, 38)], 1.6, tid["dirt"])
blob(-26, 22, 5, "stone_dark"); blob(-26, 22, 3, "cobble")
# objekty
def tile_of(key): return refs[key][0], refs[key][1]["tiles"]
def pick(kinds, keys):
    out = []
    for k in keys:
        f, tl = tile_of(k)
        for t in tl:
            kind = next(p["value"] for p in t["properties"] if p["name"] == "kind")
            if kind in kinds: out.append((f + t["id"], t))
    return out
def named(key, nums):
    f, tl = tile_of(key); return [(f + t["id"], t) for t in tl if t["id"] in nums]
trees = [x for x in pick({"tree"}, ["stromy02"]) if x[1]["imageheight"] >= 90] + named("okoli2", {7, 19, 26, 32, 33, 34}) + named("okoli3", {1, 3, 37, 41})
bushes = named("okoli2", {25, 27, 29, 31}) + named("okoli3", {0, 43})
rocks = named("okoli2", {35, 36, 37, 39}) + named("okoli3", {8, 9, 10, 12})
plants = [x for x in pick({"plant", "deco"}, ["okoli1"]) if x[1]["imageheight"] <= 60] + named("okoli2", set(range(0, 25))) + named("okoli3", {13, 14, 15, 16, 19, 20, 21, 33, 39, 40, 42})
print("  vyber: stromy", len(trees), "keře", len(bushes), "kameny", len(rocks), "rostliny", len(plants))
def place(item, px, py):
    gid, t = item; w, h = t["imagewidth"], t["imageheight"]
    m.add_object("objects", type="", name=t["properties"][0]["value"], x=px - w / 2, y=py, gid=gid, width=w, height=h)
def terrain_at(px, py): return m.get("ground", int(px // G), int(py // G))
def free(px, py, r=40):
    return all(terrain_at(px + dx, py + dy) in (tid["grass"], tid["grass_meadow"], tid["flowers"], tid["dry_grass"], tid["grass_dark"], tid["leaf_grass"], tid["forest_floor"]) for dx, dy in ((0, 0), (r, 0), (-r, 0), (0, r), (0, -r)))
m.add_object("objects", type="player_start", x=0, y=2 * G + 170)
m.add_object("objects", type="campfire", x=0, y=2 * G + 20)
for k in ("doplnky",):
    f, tl = tile_of(k)
    bld = [(f + t["id"], t) for t in tl if any(p["name"] == "kind" and p["value"] == "building" for p in t["properties"])]
    if bld: place(bld[0], -150, 2 * G - 40)
    smalls = [(f + t["id"], t) for t in tl if any(p["name"] == "kind" and p["value"] == "prop" for p in t["properties"]) and 20 < t["imageheight"] < 70]
    for i in range(min(6, len(smalls))): place(random.choice(smalls), 90 + i * 28, 2 * G - 30 + random.randint(-20, 20))
n = 0
while n < 420 and trees:
    px, py = random.uniform(X0 * G, X1 * G), random.uniform(Y0 * G + 40, Y1 * G + 40)
    e = math.hypot(px / (48 * G), py / (36 * G)); 
    if random.random() > min(1, max(0.04, (e - .35) * 1.6)) or not free(px, py, 36) or math.hypot(px, py - 50) < 260: continue
    place(random.choice(trees), px, py); n += 1
for pool, count, rad in ((bushes, 110, 30), (rocks, 40, 28), (plants, 260, 12)):
    n = 0
    while n < count and pool:
        px, py = random.uniform(X0 * G, X1 * G), random.uniform(Y0 * G, Y1 * G)
        if not free(px, py, rad) or math.hypot(px, py - 50) < 190: continue
        place(random.choice(pool), px, py); n += 1
m.save(f"{R}/mapy/start.tmj")
print("OK", R, len(m.objects("objects")), "objektu")
