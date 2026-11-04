#!/usr/bin/env python3
"""Import mapy z Tiled (.tmj/.json, tilesety .tsj/.tsx/vlozene) -> chunky pro Godot (TiledWorld).

Pouziti (z korene projektu):
    python3 tools/tiled_import.py cesta/k/mape.tmj [--name svet] [--chunk-size 32]

Vystup:
    data/world/<name>/world.json            metadata (tilesety, vrstvy, hranice, seznam chunku, markery)
    data/world/<name>/chunk_<cx>_<cy>.json  dlazdice po vrstvach + objekty v danem chunku
    assets/tilesets/<name>/*.png            kopie obrazku tilesetu
Podporuje: konecne i nekonecne (infinite) mapy, CSV i base64 (zlib/gzip) data, vnorene skupiny vrstev,
tilesety vlozene, externi .tsj a .tsx, sbirky obrazku (image collection), vlastni vlastnosti, priznaky otoceni.
"""
import argparse, base64, gzip, json, math, os, shutil, struct, sys, zlib
import xml.etree.ElementTree as ET

FLAGS = 0xE0000000
MARKER_TYPES = {"player_start", "marker"}      # objekty uloze jen do world.json (potrebne hned po startu)


def props(lst):
    return {p["name"]: p.get("value") for p in (lst or [])}


def conv(v, t):
    if t == "bool": return v == "true"
    if t == "int": return int(v)
    if t == "float": return float(v)
    return v


def load_tsx(path):
    r = ET.parse(path).getroot()
    ts = {k: r.get(k) for k in ("name", "tilewidth", "tileheight", "tilecount", "columns", "margin", "spacing")}
    for k in ("tilewidth", "tileheight", "tilecount", "columns", "margin", "spacing"):
        ts[k] = int(ts[k] or 0)
    img = r.find("image")
    if img is not None:
        ts["image"] = img.get("source"); ts["imagewidth"] = int(img.get("width")); ts["imageheight"] = int(img.get("height"))
    tiles = []
    for t in r.findall("tile"):
        d = {"id": int(t.get("id"))}
        pr = t.find("properties")
        if pr is not None:
            d["properties"] = [{"name": p.get("name"), "value": conv(p.get("value"), p.get("type", "string"))} for p in pr.findall("property")]
        im = t.find("image")
        if im is not None:
            d["image"] = im.get("source"); d["imagewidth"] = int(im.get("width")); d["imageheight"] = int(im.get("height"))
        tiles.append(d)
    ts["tiles"] = tiles
    return ts


def load_tilesets(refs, base):
    out = []
    for ref in refs:
        ts = dict(ref); tsdir = base
        if "source" in ref:
            p = os.path.normpath(os.path.join(base, ref["source"])); tsdir = os.path.dirname(p)
            ext = load_tsx(p) if p.lower().endswith(".tsx") else json.load(open(p, encoding="utf-8"))
            ext["firstgid"] = ref["firstgid"]; ts = ext
        ts["_dir"] = tsdir
        out.append(ts)
    return sorted(out, key=lambda t: t["firstgid"])


def decode_data(d, enc=None, comp=None):
    if isinstance(d, list): return d
    raw = base64.b64decode(d)
    if comp == "zlib": raw = zlib.decompress(raw)
    elif comp == "gzip": raw = gzip.decompress(raw)
    elif comp: sys.exit(f"Nepodporovana komprese '{comp}' - v Tiledu zvol Tile Layer Format = CSV nebo Base64 (zlib).")
    return list(struct.unpack("<%dI" % (len(raw) // 4), raw))


def flatten(layers, prefix=""):
    for l in layers:
        if l["type"] == "group":
            yield from flatten(l.get("layers", []), prefix + l["name"] + "/")
        else:
            l = dict(l); l["name"] = prefix + l["name"]; yield l


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tmj"); ap.add_argument("--name"); ap.add_argument("--chunk-size", type=int, default=0, help="dlazdic na chunk (vychozi: ~1536 px)")
    a = ap.parse_args()
    base = os.path.dirname(os.path.abspath(a.tmj))
    m = json.load(open(a.tmj, encoding="utf-8"))
    name = a.name or os.path.splitext(os.path.basename(a.tmj))[0]
    tw, th = m["tilewidth"], m["tileheight"]; cs = a.chunk_size or max(8, 1536 // tw)
    out_dir = os.path.join("data", "world", name); ts_dir = os.path.join("assets", "tilesets", name)
    shutil.rmtree(out_dir, ignore_errors=True); shutil.rmtree(ts_dir, ignore_errors=True); os.makedirs(out_dir); os.makedirs(ts_dir, exist_ok=True)

    # --- tilesety
    tilesets, copied = [], {}
    def copy_img(src, d):
        p = os.path.normpath(os.path.join(d, src))
        if p not in copied:
            dst = os.path.basename(p)
            while dst in copied.values(): dst = "_" + dst
            shutil.copy(p, os.path.join(ts_dir, dst)); copied[p] = dst
        return "res://" + ts_dir.replace(os.sep, "/") + "/" + copied[p]
    for t in load_tilesets(m.get("tilesets", []), base):
        e = {"firstgid": t["firstgid"], "name": t.get("name", ""), "tilewidth": t["tilewidth"], "tileheight": t["tileheight"],
             "columns": t.get("columns", 0), "tilecount": t.get("tilecount", 0), "margin": t.get("margin", 0),
             "spacing": t.get("spacing", 0), "tiles": {}, "images": {}}
        if t.get("image"): e["image"] = copy_img(t["image"], t["_dir"])
        for tile in t.get("tiles", []):
            if tile.get("properties"): e["tiles"][str(tile["id"])] = props(tile["properties"])
            if tile.get("image"): e["images"][str(tile["id"])] = {"image": copy_img(tile["image"], t["_dir"]), "w": tile.get("imagewidth"), "h": tile.get("imageheight")}
        tilesets.append(e)

    # --- vrstvy -> chunky
    chunks = {}                  # (cx,cy) -> {"tiles": {layer: [..]}, "objects": []}
    layers_meta, markers = [], []
    minx = miny = 10**9; maxx = maxy = -10**9
    def chunk(c): return chunks.setdefault(c, {"tiles": {}, "objects": []})
    for l in flatten(m["layers"]):
        pr = props(l.get("properties"))
        if (l.get("offsetx") or l.get("offsety")): print(f"! vrstva '{l['name']}' ma offset - ignoruji", file=sys.stderr)
        if l["type"] == "tilelayer":
            layers_meta.append({"name": l["name"], "kind": "tiles", "above": bool(pr.get("above")), "hd": bool(pr.get("hd")), "visible": l.get("visible", True), "props": pr})
            regions = l["chunks"] if "chunks" in l else [{"x": l.get("startx", 0), "y": l.get("starty", 0), "width": l["width"], "height": l["height"], "data": l["data"]}]
            for r in regions:
                data = decode_data(r["data"], l.get("encoding"), l.get("compression"))
                for i, gid in enumerate(data):
                    if gid == 0: continue
                    tx, ty = r["x"] + i % r["width"], r["y"] + i // r["width"]
                    c = (tx // cs, ty // cs)
                    arr = chunk(c)["tiles"].setdefault(l["name"], [0] * (cs * cs))
                    arr[(ty - c[1] * cs) * cs + (tx - c[0] * cs)] = gid
                    minx, miny, maxx, maxy = min(minx, tx), min(miny, ty), max(maxx, tx), max(maxy, ty)
        elif l["type"] == "objectgroup":
            layers_meta.append({"name": l["name"], "kind": "objects", "above": False, "hd": False, "visible": l.get("visible", True), "props": pr})
            for o in l.get("objects", []):
                d = {"type": o.get("class") or o.get("type") or "", "name": o.get("name", ""), "x": o["x"], "y": o["y"],
                     "w": o.get("width", 0), "h": o.get("height", 0), "rot": o.get("rotation", 0), "props": props(o.get("properties")),
                     "layer": l["name"]}
                if "gid" in o: d["gid"] = o["gid"]
                if d["type"] in MARKER_TYPES: markers.append(d)
                else: chunk((math.floor(o["x"] / (cs * tw)), math.floor(o["y"] / (cs * th))))["objects"].append(d)

    for (cx, cy), c in chunks.items():
        json.dump(c, open(os.path.join(out_dir, f"chunk_{cx}_{cy}.json"), "w"), separators=(",", ":"))
    if minx > maxx: minx = miny = maxx = maxy = 0
    world = {"version": 1, "tile_size": [tw, th], "chunk_size": cs, "bounds": [minx, miny, maxx + 1, maxy + 1],
             "layers": layers_meta, "tilesets": tilesets, "markers": markers,
             "chunks": [f"{cx}_{cy}" for (cx, cy) in sorted(chunks)]}
    json.dump(world, open(os.path.join(out_dir, "world.json"), "w"), indent=1)
    print(f"OK: {len(chunks)} chunku, {len(layers_meta)} vrstev, {len(tilesets)} tilesetu, hranice (dlazdice) {world['bounds']} -> {out_dir}")


if __name__ == "__main__":
    main()
