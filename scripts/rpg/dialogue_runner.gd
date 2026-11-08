class_name DialogueRunner
extends RefCounted
## Běh dialogu z data/dialogues/<id>.json (tvoří se v tools/dialog_editor.html).
##
## Uzel: {speaker, text, choices:[{text, if, do, next}], next, do:[akce], branch:[{if, next}]}
##  - branch = skrytý rozcestník (první splněná podmínka vyhrává, poslední bez "if" je výchozí)
##  - do = akce při vstupu do uzlu; choices[].do = akce při výběru
##  - next prázdný / chybí = konec dialogu
## Podmínky (všechny uvedené musí platit): flag, not_flag, quest_new, quest_active, quest_ready, quest_done,
##   class, gold (min), level (min), in_party, party_space.
## Akce: {"set":f} {"clear":f} {"gold":n} {"xp":n} {"item":id,"n":1} {"quest_start":id} {"quest_complete":id}
##   {"talk":npc_id} {"recruit":id} {"shop":true}
## V textu: {hero} = jméno hrdiny, {class} = povolání.

signal node_shown(speaker: String, text: String, choices: Array)
signal finished
signal action(name: String, arg: Variant)

const DIR := "res://data/dialogues/"

var quests: QuestLog
var hero: Character
var party: Array = []     ## členové družiny (hrdina první), hra ji drží aktuální
var data := {}
var _choices: Array = []  ## aktuálně viditelné volby (původní slovníky)
var _node_id := ""


static func exists(id: String) -> bool:
	return FileAccess.file_exists(DIR + id + ".json")


func start(id: String) -> bool:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + id + ".json"))
	if not (parsed is Dictionary) or not parsed.has("nodes"):
		push_warning("Dialog %s se nenačetl" % id)
		return false
	data = parsed
	_enter(str(data.get("start", "start")))
	return true


func advance() -> void:
	if not _choices.is_empty():
		return
	_enter(str(data["nodes"].get(_node_id, {}).get("next", "")))


func choose(i: int) -> void:
	if i < 0 or i >= _choices.size():
		return
	var c: Dictionary = _choices[i]
	_do(c.get("do", []))
	_enter(str(c.get("next", "")))


func _enter(id: String) -> void:
	var nodes: Dictionary = data["nodes"]
	var guard := 0
	while nodes.has(id) and nodes[id].has("branch") and guard < 20:   # rozcestníky
		guard += 1
		var target := ""
		for b in nodes[id]["branch"]:
			if check(b.get("if", {})):
				target = str(b.get("next", ""))
				break
		id = target
	if not nodes.has(id):
		_node_id = ""
		finished.emit()
		return
	_node_id = id
	var node: Dictionary = nodes[id]
	_do(node.get("do", []))
	_choices.clear()
	var shown := []
	for c in node.get("choices", []):
		if check(c.get("if", {})):
			_choices.append(c)
			shown.append(_fmt(str(c.get("text", "..."))))
	if str(node.get("text", "")) == "" and shown.is_empty():   # uzel jen s akcemi
		_enter(str(node.get("next", "")))
		return
	node_shown.emit(_fmt(str(node.get("speaker", ""))), _fmt(str(node.get("text", ""))), shown)


func _fmt(s: String) -> String:
	return s.replace("{hero}", hero.display_name if hero else "Hrdina").replace("{class}", ClassDefs.class_name_of(hero) if hero else "")


func check(c: Dictionary) -> bool:
	for key in c:
		var v: Variant = c[key]
		match key:
			"flag":
				if not quests.has_flag(str(v)): return false
			"not_flag":
				if quests.has_flag(str(v)): return false
			"quest_new":
				if quests.status(str(v)) != "new": return false
			"quest_active":
				if quests.status(str(v)) != "active": return false
			"quest_ready":
				if quests.status(str(v)) != "ready": return false
			"quest_done":
				if quests.status(str(v)) != "done": return false
			"class":
				if str(hero.get_meta(&"class_id", "")) != str(v): return false
			"gold":
				if hero.gold < int(v): return false
			"level":
				if hero.level < int(v): return false
			"in_party":
				if not party.any(func(m: Character) -> bool: return str(m.get_meta(&"companion_id", "")) == str(v)): return false
			"party_space":
				if (party.size() < 3) != bool(v): return false
	return true


func _do(list: Array) -> void:
	for a in list:
		for key in a:
			var v: Variant = a[key]
			match key:
				"set": quests.set_flag(str(v))
				"clear": quests.clear_flag(str(v))
				"gold": hero.add_gold(int(v)) if int(v) >= 0 else hero.spend_gold(-int(v))
				"xp": hero.gain_xp(int(v))
				"item": hero.inventory.add(StringName(str(v)), int(a.get("n", 1)))
				"quest_start": quests.start(str(v))
				"quest_complete": quests.complete(str(v))
				"talk": quests.notify("talk", str(v))
				"recruit": action.emit("recruit", str(v))
				"shop": action.emit("shop", true)
