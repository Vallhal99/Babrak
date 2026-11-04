#!/usr/bin/env python3
"""Nastroje pro spolupraci na mape z Tiledu.

    python3 tools/tiled_tool.py check  mapa.tmj                 # prehled + varovani
    python3 tools/tiled_tool.py diff   stara.tmj nova.tmj       # co se zmenilo
    python3 tools/tiled_tool.py merge  zaklad.tmj moje.tmj tvoje.tmj -o vysledek.tmj   # trojcestne sloucení
(merge: 'zaklad' = verze, od ktere oba vyšli; změny z obou stran se spojí, konflikt vyhrává 'moje')."""
import argparse, copy, os, sys
from collections import Counter
sys.path.insert(0, os.path.dirname(__file__))
from tiled_map import TiledMap, prop_dict


def bbox(keys):
    xs = [k[0] for k in keys]; ys = [k[1] for k in keys]
    return f"[{min(xs)},{min(ys)} .. {max(xs)},{max(ys)}]" if keys else "-"


def tileset_info(m):
    """gid -> vlastnosti dlazdice (jen vlozene a externi .tsj; staci pro kontrolu)."""
    import json
    base = os.path.dirname(os.path.abspath(m.path)) if m.path else "."
    first, props, ranges = [], {}, []
    for ts in m.d.get("tilesets", []):
        t = ts
        if "source" in ts and ts["source"].endswith((".tsj", ".json")):
            t = json.load(open(os.path.join(base, ts["source"]), encoding="utf-8"))
        n = t.get("tilecount", 0); ranges.append((ts["firstgid"], ts["firstgid"] + max(n, 1)))
        for tile in t.get("tiles", []): props[ts["firstgid"] + tile["id"]] = prop_dict(tile.get("properties"))
    return props, ranges


def cmd_check(a):
    m = TiledMap.load(a.map); props, ranges = tileset_info(m)
    print(f"Mapa {m.tw}x{m.th}, {'nekonecna' if m.infinite else 'konecna'}")
    warn = []
    for l in m.tile_layers():
        c = m.cells[l["name"]]; p = prop_dict(l.get("properties"))
        print(f"  vrstva '{l['name']}': {len(c)} dlazdic {bbox(list(c))} {'[hd]' if p.get('hd') else ''}{'[above]' if p.get('above') else ''}")
        for gid in {g & 0x1FFFFFFF for g in c.values()}:
            if not any(a0 <= gid < b0 for a0, b0 in ranges): warn.append(f"vrstva '{l['name']}': gid {gid} nepatri zadnemu tilesetu")
        if p.get("hd"):
            miss = {g & 0x1FFFFFFF for g in c.values() if "terrain" not in props.get(g & 0x1FFFFFFF, {})}
            if miss: warn.append(f"hd vrstva '{l['name']}': dlazdice bez vlastnosti terrain: {sorted(miss)[:8]}")
    types = Counter(); starts = 0
    for l in m.object_layers():
        for o in l["objects"]:
            t = o.get("type") or o.get("class") or ("tile-objekt" if "gid" in o else "?"); types[t] += 1
            if t == "player_start": starts += 1
            if t == "prop":
                pid = prop_dict(o.get("properties")).get("id")
                if not pid: warn.append(f"objekt {o['id']}: prop bez vlastnosti id")
                elif not os.path.exists(f"assets/world/{pid}.png"): warn.append(f"objekt {o['id']}: neznamy prop '{pid}'")
    print("  objekty:", dict(types))
    if starts != 1: warn.append(f"player_start: {starts}x (ma byt prave 1)")
    for w in warn: print("  ! " + w)
    print("  OK, bez varovani" if not warn else f"  {len(warn)} varovani")


def obj_map(m):
    return {(l["name"], o["id"]): o for l in m.object_layers() for o in l["objects"]}


def cmd_diff(a):
    A, B = TiledMap.load(a.a), TiledMap.load(a.b)
    for name in B.cells:
        ca, cb = A.cells.get(name, {}), B.cells[name]
        ch = [k for k in set(ca) | set(cb) if ca.get(k) != cb.get(k)]
        if ch: print(f"vrstva '{name}': zmeneno {len(ch)} dlazdic {bbox(ch)}")
    oa, ob = obj_map(A), obj_map(B)
    add = [k for k in ob if k not in oa]; rem = [k for k in oa if k not in ob]; chg = [k for k in ob if k in oa and ob[k] != oa[k]]
    print(f"objekty: +{len(add)} -{len(rem)} zmeneno {len(chg)}")
    for k in add[:10]: print("  +", k[0], ob[k].get("type") or "tile", int(ob[k]["x"]), int(ob[k]["y"]))


def cmd_merge(a):
    base, mine, theirs = (TiledMap.load(p) for p in (a.base, a.mine, a.theirs))
    out = TiledMap(copy.deepcopy(mine.d), a.mine); conflicts = 0
    for name in set(mine.cells) | set(theirs.cells):
        cb, cm, ct = base.cells.get(name, {}), mine.cells.get(name, {}), theirs.cells.get(name, {})
        res = {}
        for k in set(cb) | set(cm) | set(ct):
            b0, m0, t0 = cb.get(k, 0), cm.get(k, 0), ct.get(k, 0)
            if m0 == t0 or t0 == b0: v = m0
            elif m0 == b0: v = t0
            else: v = m0; conflicts += 1
            if v: res[k] = v
        if name in out.cells: out.cells[name] = res
    ob, om, ot = obj_map(base), obj_map(mine), obj_map(theirs)
    next_id = max([o["id"] for (_, o) in ()] + [k[1] for k in list(ob) + list(om) + list(ot)] + [0]) + 1
    for l in out.object_layers():
        name = l["name"]; objs = {}
        keys = {k for k in set(ob) | set(om) | set(ot) if k[0] == name}
        for k in sorted(keys, key=lambda k: k[1]):
            b0, m0, t0 = ob.get(k), om.get(k), ot.get(k)
            if k in ob:
                if m0 == b0: v = t0
                elif t0 == b0: v = m0
                elif m0 == t0: v = m0
                else: v = m0; conflicts += 1
                if v is not None: objs[k] = v
            elif m0 is not None and t0 is not None and m0 != t0:   # stejne id, ruzne nove objekty
                objs[k] = m0; n = copy.deepcopy(t0); n["id"] = next_id; next_id += 1; objs[(name, n["id"])] = n
            else: objs[k] = m0 if m0 is not None else t0
        l["objects"] = [o for _, o in sorted(objs.items(), key=lambda kv: kv[0][1])]
    out.d["nextobjectid"] = next_id + 1
    out.save(a.out)
    print(f"Sloučeno -> {a.out}  (konflikty vyresene ve prospech 'moje': {conflicts})")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(); sp = ap.add_subparsers(dest="cmd", required=True)
    p = sp.add_parser("check"); p.add_argument("map"); p.set_defaults(f=cmd_check)
    p = sp.add_parser("diff"); p.add_argument("a"); p.add_argument("b"); p.set_defaults(f=cmd_diff)
    p = sp.add_parser("merge"); p.add_argument("base"); p.add_argument("mine"); p.add_argument("theirs"); p.add_argument("-o", "--out", required=True); p.set_defaults(f=cmd_merge)
    a = ap.parse_args(); a.f(a)
