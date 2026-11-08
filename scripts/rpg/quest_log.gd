class_name QuestLog
extends RefCounted
## Základ questů. Definice: data/quests/*.json (jeden objekt nebo pole objektů), tvoří se v nástroji
## tools/dialog_editor.html. Stav questů a příznaky (flags) žijí tady.
##
## Quest: {id, title, desc, giver, objectives:[{id, type: kill|talk|collect|flag, target, count, text}],
##         rewards:{gold, xp, items:[id], flags:[flag]}}
## Stavy: new (nezačatý) -> active -> ready (cíle splněné, čeká na odevzdání) -> done.
## Události posílá hra: notify("kill", "bandit"), notify("talk", "mira"); "collect" se počítá z batohu
## (refresh), "flag" se splní nastavením příznaku (set_flag).

signal changed
signal toast(text: String)

const DIR := "res://data/quests/"

var defs := {}     ## id -> definice
var state := {}    ## id -> {"state": String, "progress": {obj_id: int}}
var flags := {}
var hero: Character


func _init() -> void:
	for file in DirAccess.get_files_at(DIR):
		file = file.trim_suffix(".remap")
		if not file.ends_with(".json"):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + file))
		var list: Array = parsed if parsed is Array else [parsed]
		for q in list:
			if q is Dictionary and q.has("id"):
				defs[q["id"]] = q


func status(id: String) -> String:
	return state[id]["state"] if state.has(id) else "new"


func start(id: String) -> bool:
	if not defs.has(id) or state.has(id):
		return false
	state[id] = {"state": "active", "progress": {}}
	toast.emit("Nový úkol: %s" % defs[id]["title"])
	refresh()
	return true


func notify(type: String, target: String, amount := 1) -> void:
	for id in state:
		if state[id]["state"] != "active":
			continue
		for o in defs[id].get("objectives", []):
			if o["type"] == type and o["target"] == target:
				var p: Dictionary = state[id]["progress"]
				p[o["id"]] = mini(int(o.get("count", 1)), int(p.get(o["id"], 0)) + amount)
	refresh()


func set_flag(f: String) -> void:
	flags[f] = true
	refresh()


func clear_flag(f: String) -> void:
	flags.erase(f)


func has_flag(f: String) -> bool:
	return flags.has(f)


func progress_of(id: String, o: Dictionary) -> int:
	match o["type"]:
		"collect":
			return mini(int(o.get("count", 1)), hero.inventory.count(StringName(o["target"])) if hero else 0)
		"flag":
			return 1 if has_flag(o["target"]) else 0
	return int(state[id]["progress"].get(o["id"], 0))


func objective_done(id: String, o: Dictionary) -> bool:
	return progress_of(id, o) >= int(o.get("count", 1))


## Přepočítá cíle; z active udělá ready, když je vše splněno.
func refresh() -> void:
	var auto: Array[String] = []
	for id in state:
		if state[id]["state"] != "active":
			continue
		var all := true
		for o in defs[id].get("objectives", []):
			all = all and objective_done(id, o)
		if all:
			state[id]["state"] = "ready"
			if defs[id].get("auto", false):
				auto.append(id)   # "auto": true = odevzdá se samo
			else:
				toast.emit("Úkol splněn: %s (odevzdej ho)" % defs[id]["title"])
	for id in auto:
		complete(id)
	changed.emit()


## Odevzdání: vyplatí odměny. Vrací false, pokud quest ještě není ready.
func complete(id: String) -> bool:
	refresh()
	if status(id) != "ready":
		return false
	state[id]["state"] = "done"
	var r: Dictionary = defs[id].get("rewards", {})
	if hero:
		hero.add_gold(int(r.get("gold", 0)))
		hero.gain_xp(int(r.get("xp", 0)))
		for item in r.get("items", []):
			hero.inventory.add(StringName(item))
	for f in r.get("flags", []):
		flags[f] = true
	toast.emit("Odměna: %s" % defs[id]["title"])
	changed.emit()
	return true


func lines(id: String) -> PackedStringArray:
	var out := PackedStringArray()
	for o in defs[id].get("objectives", []):
		out.append("%s %s (%d/%d)" % ["[x]" if objective_done(id, o) else "[ ]", o.get("text", o["id"]), progress_of(id, o), int(o.get("count", 1))])
	return out
