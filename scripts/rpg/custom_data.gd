class_name CustomData
extends RefCounted
## Vlastní data z Babrak Studia: data/enemies/*.json (nepřátelé), data/villagers/*.json (vesničané s denním
## plánem). Načtou se jednou při startu hry a přidají se k vestavěným (TurnEnemy3.TEMPLATES, Villager.VILLAGERS).
## Nepřítel s polem "pack": [id, …] se začne objevovat ve světě jako další skupina.

static var _loaded := false
static var extra_packs: Array = []


static func _files(dir: String) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".json"):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(f)))
			if parsed is Dictionary:
				out.append(parsed)
	return out


static func _color(v: Variant, fallback: Color) -> Color:
	if v is Array and v.size() >= 3:
		return Color(float(v[0]), float(v[1]), float(v[2]))
	return fallback


static func load_all() -> void:
	if _loaded:
		return
	_loaded = true
	for d in _files("res://data/enemies"):
		var id := StringName(d.get("id", ""))
		if id == &"":
			continue
		var weak: Array = []
		for w in d.get("weak", []):
			weak.append(StringName(w))
		TurnEnemy3.CUSTOM[id] = {
			"name": d.get("name", String(id)), "tint": _color(d.get("tint"), Color.WHITE), "hp": int(d.get("hp", 14)),
			"atk": int(d.get("atk", 1)), "xp": int(d.get("xp", 10)), "gold": int(d.get("gold", 5)), "shield": int(d.get("shield", 3)),
			"weak": weak, "speed": int(d.get("speed", 8)), "human": bool(d.get("human", true)), "row": int(d.get("row", 0)),
			"rank": StringName(d.get("rank", "normal")), "phases": int(d.get("phases", 1)), "ranged": bool(d.get("ranged", false)),
			"sheet": String(d.get("sheet", "")), "desc": String(d.get("desc", "")),
		}
		if d.has("pack"):
			var pack: Array = [id]
			for p in d["pack"]:
				pack.append(StringName(p))
			extra_packs.append(pack)
	for d in _files("res://data/villagers"):
		var id := StringName(d.get("id", ""))
		if id == &"" or not d.has("plan"):
			continue
		var plan: Array = []
		for e in d["plan"]:
			plan.append({"h": float(e["h"]), "at": String(e["at"]), "act": String(e.get("act", "")), "in": bool(e.get("in", false))})
		Villager.CUSTOM[id] = {"name": d.get("name", String(id)), "tint": _color(d.get("tint"), Color.WHITE),
			"sheet": String(d.get("sheet", "res://assets/characters/merchant/merchant.png")), "home": String(d.get("home", "hostinec")), "plan": plan}
