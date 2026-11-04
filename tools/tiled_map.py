"""Knihovna pro cteni a upravy map z Tiled (.tmj) - zachova vse, co nezna (vlastnosti, externi tilesety, ...).

    from tiled_map import TiledMap
    m = TiledMap.load("mapa.tmj")
    m.fill_circle("ground", 20, 10, 6, gid=2)            # dlazdice (souradnice v dlazdicich)
    m.stroke("ground", [(0, 5), (30, 8)], 1.5, gid=2)     # cesta
    m.add_object("objects", type="prop", x=960, y=500, props={"id": "tree_oak"})
    m.save("mapa_v2.tmj")
Pri ulozeni se nekonecne mapy znovu rozdeli na chunky 16x16 (jako Tiled), konecne zustanou konecne.
"""
import base64, copy, gzip, json, struct, zlib

CH = 16


def prop_list(d):
    out = []
    for k, v in d.items():
        t = "bool" if isinstance(v, bool) else "int" if isinstance(v, int) else "float" if isinstance(v, float) else "string"
        out.append({"name": k, "type": t, "value": v})
    return out


def prop_dict(lst):
    return {p["name"]: p.get("value") for p in (lst or [])}


def _decode(d, comp=None):
    if isinstance(d, list): return d
    raw = base64.b64decode(d)
    if comp == "zlib": raw = zlib.decompress(raw)
    elif comp == "gzip": raw = gzip.decompress(raw)
    elif comp: raise ValueError(f"Nepodporovana komprese {comp}")
    return list(struct.unpack("<%dI" % (len(raw) // 4), raw))


class TiledMap:
    def __init__(self, data, path=""):
        self.d, self.path = data, path
        self.tw, self.th = data["tilewidth"], data["tileheight"]
        self.infinite = bool(data.get("infinite"))
        self.cells = {}                       # jmeno vrstvy -> {(x,y): gid}
        for l in self.tile_layers(): self.cells[l["name"]] = self._read_cells(l)

    @staticmethod
    def load(path):
        return TiledMap(json.load(open(path, encoding="utf-8")), path)

    # ---- vrstvy
    def _walk(self, layers):
        for l in layers:
            if l["type"] == "group": yield from self._walk(l.get("layers", []))
            else: yield l

    def tile_layers(self): return [l for l in self._walk(self.d["layers"]) if l["type"] == "tilelayer"]
    def object_layers(self): return [l for l in self._walk(self.d["layers"]) if l["type"] == "objectgroup"]

    def layer(self, name):
        for l in self._walk(self.d["layers"]):
            if l["name"] == name: return l
        raise KeyError(f"Vrstva '{name}' neexistuje")

    def _read_cells(self, l):
        cells = {}
        regions = l["chunks"] if "chunks" in l else [{"x": l.get("startx", 0), "y": l.get("starty", 0), "width": l["width"], "data": l["data"]}]
        for r in regions:
            data = _decode(r["data"], l.get("compression"))
            for i, gid in enumerate(data):
                if gid: cells[(r["x"] + i % r["width"], r["y"] + i // r["width"])] = gid
        return cells

    # ---- dlazdice
    def get(self, layer, x, y): return self.cells[layer].get((x, y), 0)
    def set(self, layer, x, y, gid):
        if gid: self.cells[layer][(x, y)] = gid
        else: self.cells[layer].pop((x, y), None)

    def fill_rect(self, layer, x0, y0, x1, y1, gid):
        for y in range(y0, y1):
            for x in range(x0, x1): self.set(layer, x, y, gid)

    def fill_circle(self, layer, cx, cy, r, gid):
        for y in range(int(cy - r) - 1, int(cy + r) + 2):
            for x in range(int(cx - r) - 1, int(cx + r) + 2):
                if (x + .5 - cx) ** 2 + (y + .5 - cy) ** 2 <= r * r: self.set(layer, x, y, gid)

    def stroke(self, layer, pts, r, gid):
        import math
        for (ax, ay), (bx, by) in zip(pts, pts[1:]):
            n = max(1, int(math.hypot(bx - ax, by - ay) * 2))
            for i in range(n + 1): self.fill_circle(layer, ax + (bx - ax) * i / n, ay + (by - ay) * i / n, r, gid)

    # ---- objekty
    def objects(self, layer): return self.layer(layer)["objects"]

    def next_id(self):
        n = self.d.get("nextobjectid", 1)
        for l in self.object_layers():
            for o in l["objects"]: n = max(n, o["id"] + 1)
        self.d["nextobjectid"] = n + 1
        return n

    def add_object(self, layer, type="", x=0, y=0, name="", props=None, gid=None, width=0, height=0, point=None):
        o = {"id": self.next_id(), "name": name, "type": type, "x": x, "y": y, "width": width, "height": height, "rotation": 0, "visible": True}
        if gid is not None: o["gid"] = gid
        elif point is None and not width: o["point"] = True
        if point: o["point"] = True
        if props: o["properties"] = prop_list(props)
        self.layer(layer)["objects"].append(o)
        return o

    def remove_objects(self, layer, pred):
        l = self.layer(layer); n0 = len(l["objects"]); l["objects"] = [o for o in l["objects"] if not pred(o)]
        return n0 - len(l["objects"])

    # ---- ulozeni
    def _write_cells(self, l, cells):
        for k in ("encoding", "compression"): l.pop(k, None)
        if not cells:
            if "chunks" in l: l["chunks"] = []
            else: l["data"] = [0] * (l["width"] * l["height"])
            return
        if self.infinite:
            chunks = {}
            for (x, y), gid in cells.items():
                c = (x // CH * CH, y // CH * CH); chunks.setdefault(c, [0] * (CH * CH))[(y - c[1]) * CH + (x - c[0])] = gid
            l["chunks"] = [{"x": cx, "y": cy, "width": CH, "height": CH, "data": dd} for (cx, cy), dd in sorted(chunks.items())]
            xs = [c[0] for c in chunks]; ys = [c[1] for c in chunks]
            l.update(startx=min(xs), starty=min(ys), width=max(xs) + CH - min(xs), height=max(ys) + CH - min(ys))
            l.pop("data", None)
        else:
            x0 = l.get("x", 0); w, h = l["width"], l["height"]; data = [0] * (w * h)
            for (x, y), gid in cells.items():
                if 0 <= x < w and 0 <= y < h: data[y * w + x] = gid
            l["data"] = data

    def save(self, path):
        out = copy.deepcopy(self.d)
        by_name = {l["name"]: l for l in self._walk(out["layers"])}
        for name, cells in self.cells.items(): self._write_cells(by_name[name], cells)
        if self.infinite:
            allx = [x for c in self.cells.values() for x, _ in c]; ally = [y for c in self.cells.values() for _, y in c]
            if allx: out["width"] = max(allx) - min(allx) + 1; out["height"] = max(ally) - min(ally) + 1
        json.dump(out, open(path, "w", encoding="utf-8"), separators=(",", ":"))
