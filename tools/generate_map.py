#!/usr/bin/env python3
"""Nacrtek (PNG, 1 px = 1 dlazdice) + legenda -> Tiled mapa (.tmj) osazena podle slovniku objektu.

    python3 tools/generate_map.py skica.png legenda.json mapa.tmj [--seed 1] [--origin -50,-38]

Legenda (JSON):
 {"colors": {"#3a7d2c": "meadow", "#1d4d1a": "forest", "#b08a50": "path", "#ff0000": "campfire"},
  "zones": {"meadow": {"terrain": "grass", "mix": [["grass_meadow", .25], ["flowers", .08]], "profile": "meadow",
                       "scatter": [{"tags": ["tree"], "density": .004, "min_dist": 90}, ...]}, ...}}
Zona "path" (profile "path") = zadne velke objekty. Barva zony s "camp": true -> ohniste ve stredu, stan a vybava kolem.
Pravidla (tag_rules) jsou v data/world/object_catalog.json - objekt se zamitne, kdyz ma tag z "forbid" profilu zony.
"""
import argparse, json, math, os, random, sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import object_catalog
from tiled_map import TiledMap
from terrains_user import TERRAINS

G = 24
PACK = os.path.join(HERE, "..", "tiled_pack")


def hexrgb(h): h = h.lstrip("#"); return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def load_tiles():
    """-> {id: dict(gid,w,h,tags,kind,name)} z tiled_pack (gidy podle start.tmj)."""
    base = json.load(open(f"{PACK}/mapy/start.tmj"))
    tiles = {}
    for ts in base["tilesets"]:
        if not ts["source"].endswith(".tsj") or "terrain" in ts["source"]: continue
        d = json.load(open(os.path.normpath(f"{PACK}/mapy/{ts['source']}")))
        for t in d.get("tiles", []):
            pr = {p["name"]: p["value"] for p in t.get("properties", [])}
            if "id" not in pr: continue
            tiles[pr["id"]] = dict(gid=ts["firstgid"] + t["id"], w=t["imagewidth"], h=t["imageheight"], kind=pr.get("kind", ""),
                                   tags=set(filter(None, pr.get("tags", "").split(","))), name=pr.get("label", pr["id"]))
    return base, tiles


def noise(w, h, scale, rng):
    """hladky sum 0..1 (bilinearne interpolovana mrizka)"""
    gw, gh = int(w / scale) + 3, int(h / scale) + 3
    g = rng.random((gh, gw))
    ys, xs = np.mgrid[0:h, 0:w] / scale
    x0, y0 = xs.astype(int), ys.astype(int); fx, fy = xs - x0, ys - y0
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    return (g[y0, x0] * (1 - fx) * (1 - fy) + g[y0, x0 + 1] * fx * (1 - fy) + g[y0 + 1, x0] * (1 - fx) * fy + g[y0 + 1, x0 + 1] * fx * fy)


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("sketch"); ap.add_argument("legend"); ap.add_argument("out")
    ap.add_argument("--seed", type=int, default=1); ap.add_argument("--origin", default="")
    a = ap.parse_args()
    rng = np.random.default_rng(a.seed); random.seed(a.seed)
    leg = json.load(open(a.legend, encoding="utf-8")); cat = object_catalog.load(); trules = object_catalog.rules()
    base, tiles = load_tiles()
    for t in tiles.values(): t["tags"] |= set(cat.get(next((k for k, v in tiles.items() if v is t), ""), {}).get("tags", []))
    img = np.array(Image.open(a.sketch).convert("RGB")).astype(int); H, W = img.shape[:2]
    ox, oy = (int(v) for v in a.origin.split(",")) if a.origin else (-W // 2, -H // 2)
    pal = [(hexrgb(c), z) for c, z in leg["colors"].items()]
    cols = np.array([p[0] for p in pal])
    d = ((img[:, :, None, :] - cols[None, None]) ** 2).sum(-1); zi = d.argmin(-1)
    names = [p[1] for p in pal]
    zone = np.array([[names[i] for i in row] for row in zi])

    tid = {n: i + 1 for i, (n, *_) in enumerate(TERRAINS)}
    m = TiledMap({**base, "tilesets": base["tilesets"], "layers": [dict(l, chunks=[]) if l["type"] == "tilelayer" else dict(l, objects=[]) for l in base["layers"]]})
    m.d["nextobjectid"] = 1
    # --- zem
    n1, n2 = noise(W, H, 6, rng), noise(W, H, 9, rng)
    path_mask = np.zeros((H, W), bool); zdef = leg["zones"]
    for y in range(H):
        for x in range(W):
            z = zdef.get(zone[y, x], {}); t = z.get("terrain")
            if not t: continue
            for k, (mt, frac) in enumerate(z.get("mix", [])):
                if (n1 if k % 2 == 0 else n2)[y, x] > 1 - frac * 1.6: t = mt; break
            m.set("ground", x + ox, y + oy, tid[t])
            if z.get("profile") == "path": path_mask[y, x] = True
    # --- objekty
    def px_zone(px, py):
        x, y = int(px // G) - ox, int(py // G) - oy
        return zone[y, x] if 0 <= x < W and 0 <= y < H else None
    def near_path(px, py, r):
        x0, x1, y0, y1 = (int((px - r) // G) - ox, int((px + r) // G) - ox, int((py - r * .6) // G) - oy, int((py + r * .3) // G) - oy)
        return path_mask[max(0, y0):max(0, y1) + 1, max(0, x0):max(0, x1) + 1].any()
    placed = []; grid = {}
    def clear(px, py, md):
        cx, cy = int(px // 64), int(py // 64)
        for gx in range(cx - 2, cx + 3):
            for gy in range(cy - 2, cy + 3):
                for (qx, qy, qm) in grid.get((gx, gy), ()):
                    if math.hypot(px - qx, py - qy) < max(md, qm): return False
        return True
    def put(tile, px, py, md):
        m.add_object("objects", type="", name=tile["name"], x=px - tile["w"] / 2, y=py, gid=tile["gid"], width=tile["w"], height=tile["h"])
        grid.setdefault((int(px // 64), int(py // 64)), []).append((px, py, md)); placed.append(tile)
    def candidates(profile, tags, none_tags=()):
        pr = trules.get(profile, {}); forbid = set(pr.get("forbid", [])) | set(none_tags)
        return [t for t in tiles.values() if set(tags) & t["tags"] and not (t["tags"] & forbid) and "composite" not in t["tags"] and t["kind"] != ""]
    stats = {}
    for zname, z in zdef.items():
        ys, xs = np.where(zone == zname)
        if len(xs) == 0: continue
        profile = z.get("profile", zname); n = 0
        for r in z.get("scatter", []):
            pool = candidates(profile, r["tags"], r.get("none_tags", []))
            if r.get("max_h"): pool = [t for t in pool if t["h"] <= r["max_h"]]
            if r.get("min_h"): pool = [t for t in pool if t["h"] >= r["min_h"]]
            if not pool: print(f"! zona {zname}: pravidlo {r['tags']} nema zadne objekty"); continue
            target = int(len(xs) * r.get("density", .01)); tries = 0; ok = 0
            while ok < target and tries < target * 25:
                tries += 1
                i = rng.integers(len(xs)); px = (xs[i] + ox + rng.random()) * G; py = (ys[i] + oy + rng.random()) * G
                t = pool[rng.integers(len(pool))]
                if px_zone(px, py) != zname or not clear(px, py, r.get("min_dist", 40)): continue
                if profile != "path" and near_path(px, py, t["w"] * .35) and not (t["tags"] <= set(trules["path"]["allow"]) | {"path_ok"}): continue
                put(t, px, py, r.get("min_dist", 40)); ok += 1
            n += ok
        stats[zname] = n
        # tabor: ohniste ve stredu zony + vybava kolem
        if z.get("camp"):
            cx, cy = (xs.mean() + ox + .5) * G, (ys.mean() + oy + .5) * G
            m.add_object("objects", type="campfire", x=cx, y=cy)
            m.add_object("objects", type="player_start", x=cx, y=cy + 120)
            grid.setdefault((int(cx // 64), int(cy // 64)), []).append((cx, cy, 50))
            spec = z.get("camp_items", [{"tags": ["tent"], "count": 1, "r": [150, 200]}, {"tags": ["barrel", "crate", "pot", "bucket", "sack"], "count": 6, "r": [60, 140]},
                                       {"tags": ["firewood", "log"], "count": 3, "r": [70, 130]}, {"tags": ["chest", "tool"], "count": 2, "r": [90, 150]}])
            for sp in spec:
                pool = [t for t in candidates("camp", sp["tags"]) if t["h"] < 200 or "tent" in t["tags"]]
                for _ in range(sp.get("count", 1)):
                    for _try in range(60):
                        ang = rng.random() * 6.283; rr = rng.uniform(*sp.get("r", [60, 140])); px, py = cx + math.cos(ang) * rr, cy + math.sin(ang) * rr * .8
                        t = pool[rng.integers(len(pool))] if pool else None
                        if t and px_zone(px, py) == zname and clear(px, py, 36) and not near_path(px, py, t["w"] * .35): put(t, px, py, 36); break
    m.save(a.out)
    print("OK", a.out, "objektu:", len(m.objects("objects")), "| zony:", stats)


if __name__ == "__main__": main()
