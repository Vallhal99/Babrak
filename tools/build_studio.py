#!/usr/bin/env python3
"""Sestaví tools/studio.html (Babrak Studio) z tools/studio.tpl.html: vloží data projektu (předměty, nepřátelé, postavy,
animace, questy, dialogy, spritesheety) a šablony editorů questů a dialogů. Spuštění: python3 tools/build_studio.py"""
import base64, json, re
from pathlib import Path
ROOT = Path(__file__).resolve().parent.parent

def gd_dict(text, name):
    """Vytáhne `const NAME := { ... }` z GDScriptu a převede ho na Python slovník."""
    i = text.index(f"const {name} := {{")
    j = text.index("{", i)
    depth, k = 0, j
    while True:
        c = text[k]
        depth += c == "{"; depth -= c == "}"
        if depth == 0: break
        k += 1
    src = text[j:k + 1]
    src = re.sub(r"&\"", '"', src)
    src = re.sub(r"Color\(([^)]*)\)", r"[\1]", src)
    src = re.sub(r"Vector2\(([^)]*)\)", r"[\1]", src)
    src = src.replace("true", "True").replace("false", "False")
    src = re.sub(r"#[^\n]*", "", src)
    return eval(src)

def data_url(p):
    return "data:image/png;base64," + base64.b64encode(Path(p).read_bytes()).decode()

def parse_tres(path):
    t = path.read_text()
    ext = dict(re.findall(r'\[ext_resource type="[^"]+" path="([^"]+)" id="([^"]+)"\]', t)[::1] and [(i, p) for p, i in re.findall(r'\[ext_resource type="[^"]+" path="([^"]+)" id="([^"]+)"\]', t)])
    body = t.split("[resource]")[1]
    f = {}
    for k, v in re.findall(r"^(\w+) = (.+)$", body, re.M):
        f[k] = v.strip()
    def s(k, d=""):
        v = f.get(k)
        if v is None: return d
        m = re.match(r'^&?"(.*)"$', v)
        return m.group(1) if m else v
    def ref(k):
        m = re.match(r'ExtResource\("([^"]+)"\)', f.get(k, ""))
        return ext.get(m.group(1), "") if m else ""
    big = re.findall(r'&"(\w+)"', f.get("big_anims", ""))
    return {"id": s("id"), "name": s("display_name"), "desc": s("description"), "slot": int(f.get("slot", "0")),
            "price": int(f.get("price", "10")), "damage": int(f.get("damage", "0")), "defense": int(f.get("defense", "0")),
            "hp": int(f.get("max_hp", "0")), "mp": int(f.get("max_mana", "0")), "light": float(f.get("light", "0")),
            "attack_anim": s("attack_anim", "slash"), "ranged": f.get("ranged") == "true", "hides_hair": f.get("hides_hair") == "true",
            "stance": s("stance"), "big_anims": big, "icon_path": ref("icon").replace("res://", ""), "layer": ref("layer_sheet").replace("res://", "")}

def main():
    sheets = {}
    def add(p):
        rel = str(Path(p).relative_to(ROOT))
        if rel not in sheets: sheets[rel] = data_url(p)
        return rel
    items = []
    for f in sorted((ROOT / "data/items").glob("*.tres")):
        it = parse_tres(f)
        if it["icon_path"] and (ROOT / it["icon_path"]).exists():
            it["icon"] = data_url(ROOT / it["icon_path"])
        if it["layer"] and (ROOT / it["layer"]).exists():
            add(ROOT / it["layer"])
        items.append(it)
    for p in [ROOT / "assets/characters/hero/body/body.png", ROOT / "assets/characters/hero/body/hair.png", ROOT / "assets/characters/merchant/merchant.png"]:
        add(p)
    enemies_src = (ROOT / "scripts/character/turn_enemy3.gd").read_text()
    enemies = []
    for k, v in gd_dict(enemies_src, "TEMPLATES").items():
        v = dict(v); v["id"] = k
        v["tint"] = v["tint"][:3]
        v["rank"] = v.get("rank", "normal"); v["phases"] = v.get("phases", 1); v["ranged"] = v.get("ranged", False)
        enemies.append(v)
    for f in sorted((ROOT / "data/enemies").glob("*.json")):
        enemies.append(json.loads(f.read_text()))
    vil = gd_dict((ROOT / "scripts/character/villager.gd").read_text(), "VILLAGERS")
    places = gd_dict((ROOT / "scripts/character/villager.gd").read_text(), "PLACES")
    anims = gd_dict((ROOT / "scripts/character/anim_catalog.gd").read_text(), "ANIMS")
    quests = []
    for f in sorted((ROOT / "data/quests").glob("*.json")):
        d = json.loads(f.read_text()); quests += d if isinstance(d, list) else [d]
    dialogues = {f.stem: json.loads(f.read_text()) for f in sorted((ROOT / "data/dialogues").glob("*.json"))}
    lore = json.loads((ROOT / "data/lore.json").read_text())
    data = {"items": items, "enemies": enemies, "villagers": {k: {**v, "tint": v["tint"][:3]} for k, v in vil.items()}, "places": places,
            "anims": anims, "quests": quests, "dialogues": dialogues, "lore": lore, "sheets": sheets}
    tpl = (ROOT / "tools/studio.tpl.html").read_text()
    out = (tpl.replace("__DATA__", json.dumps(data, ensure_ascii=False).replace("</","<\\/"))
              .replace("__QUEST_TPL__", json.dumps((ROOT / "tools/quest_editor.tpl.html").read_text()).replace("</","<\\/"))
              .replace("__DIALOG_TPL__", json.dumps((ROOT / "tools/dialog_editor.tpl.html").read_text()).replace("</","<\\/")))
    (ROOT / "tools/studio.html").write_text(out)
    print("studio.html", len(out) // 1024, "kB")

main()
