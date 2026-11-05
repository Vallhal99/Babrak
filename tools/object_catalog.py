"""Slovnik objektu: nacte data/world/object_catalog.json a rozvine rozsahy id.
    from object_catalog import load
    cat = load(); cat["okoli1_017"]  -> {"name","kind","tags":[...],...}
"""
import json, os

PATH = os.path.join(os.path.dirname(__file__), "..", "data", "world", "object_catalog.json")


def _expand(spec):
    for part in spec.split(","):
        if "-" in part:
            a, b = part.split("-"); yield from range(int(a), int(b) + 1)
        else: yield int(part)


def load(path=PATH):
    raw = json.load(open(path, encoding="utf-8"))
    out = {}
    for it in raw["items"]:
        for i in _expand(it["r"]):
            e = {k: v for k, v in it.items() if k not in ("s", "r")}; e["id"] = f"{it['s']}_{i:03d}"
            out[e["id"]] = e
    return out


def rules(path=PATH): return json.load(open(path, encoding="utf-8"))["tag_rules"]
