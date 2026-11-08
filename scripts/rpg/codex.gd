class_name Codex
extends RefCounted
## Deník světa: odemčené zápisky (data/lore.json) a bestiář (viděné/poražené potvory a odhalené slabiny).

signal toast(text: String)
signal changed

const LORE_FILE := "res://data/lore.json"
## Zápisek, který se odemkne prvním střetem s typem nepřítele.
const ENEMY_LORE := {&"bandit": "zbojnici", &"archer": "zbojnici", &"skeleton": "hrbitov", &"leader": "vudce", &"knight": "cerny_rytir"}
const BEAST_TEXT := {
	&"bandit": "Obyčejný lupič s mečem. Drží se v přední řadě a nechá se zastrašit i podplatit.",
	&"archer": "Střílí zpoza zbojníků, proto je v zadní řadě. Zblízka je křehký.",
	&"skeleton": "Probuzený voják. Nebojí se bolesti, ale drtivé zásahy a oheň ho rozbíjejí.",
	&"leader": "Elitní nepřítel o dvou fázích. V druhé fázi krvácí a zuří.",
	&"knight": "Přízračný rytíř. Tři fáze, nabíjený úder a řev, který nahání strach.",
}
const TYPE_NAMES := {"blade": "čepel", "blunt": "drtivé", "bow": "střelné", "fire": "oheň"}

var lore: Array[String] = []
var beasts: Dictionary = {}   ## id -> {"seen": n, "kills": n, "weak": [typ, ...]}
var _defs: Array = []


func _init() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LORE_FILE))
	_defs = parsed if parsed is Array else []


func defs() -> Array:
	return _defs


func entry(id: String) -> Dictionary:
	for d in _defs:
		if d["id"] == id:
			return d
	return {}


func unlock(id: String) -> void:
	if id in lore or entry(id).is_empty():
		return
	lore.append(id)
	toast.emit("Nový zápis v deníku: %s" % entry(id)["title"])
	changed.emit()


## Výsledek souboje: viděné nepřátelé, jejich odhalené slabiny, poražení.
func record_battle(result: Dictionary) -> void:
	for s in result.get("seen", []):
		var id := String(s["id"])
		var b: Dictionary = beasts.get(id, {"seen": 0, "kills": 0, "weak": []})
		b["seen"] += 1
		for w in s.get("revealed", []):
			if String(w) not in b["weak"]:
				b["weak"].append(String(w))
		beasts[id] = b
		if ENEMY_LORE.has(StringName(id)):
			unlock(ENEMY_LORE[StringName(id)])
	for k in result.get("kills", []):
		var b: Dictionary = beasts.get(String(k), {"seen": 1, "kills": 0, "weak": []})
		b["kills"] += 1
		beasts[String(k)] = b
	changed.emit()


func beast_text(id: String) -> String:
	var t: Dictionary = TurnEnemy3.TEMPLATES[StringName(id)]
	var b: Dictionary = beasts.get(id, {"seen": 0, "kills": 0, "weak": []})
	var weak: PackedStringArray = []
	for w in t["weak"]:
		weak.append(TYPE_NAMES.get(String(w), String(w)) if String(w) in b["weak"] else "?")
	var rank: String = {&"elite": "elitní", &"boss": "boss"}.get(t.get("rank", &""), "běžný")
	return "[b]%s[/b]  (%s)\n\nViděno: %d×   Poraženo: %d×\nZdraví: %d   Štít: %d   Rychlost: %d\nSlabiny: %s\n%s\n\n%s" % [
		t["name"], rank, b["seen"], b["kills"], t["hp"], t["shield"], t["speed"], ", ".join(weak),
		"Lidský nepřítel: lze s ním vyjednávat." if t["human"] else "Nelidský: nedá se uplatit.", BEAST_TEXT.get(StringName(id), "")]


func to_dict() -> Dictionary:
	return {"lore": lore, "beasts": beasts}


func from_dict(d: Dictionary) -> void:
	lore.assign(d.get("lore", []))
	beasts = d.get("beasts", {})
	changed.emit()
