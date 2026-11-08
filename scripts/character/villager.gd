class_name Villager
extends Npc
## Vesničan s denním režimem. Postava = zástupná (merchant.png + barevný odstín); finální vzhled:
## stačí změnit `visual.body_sheet` (viz VILLAGERS[...]["sheet"]) – chování zůstává.
## Plán dne: seznam {h: hodina, at: místo, act: činnost, in: true = zajde dovnitř (domů/hospoda)}.
## Cesty vedou ulicí ROAD_Y: dveře → ulice → x cíle → cíl. Zaseknutý vesničan se po 2 s přesune.

const ROAD_Y := 965.0
const SPEED := 55.0
const PLACES := {
	"cihla": Vector2(708, 872), "vysoky": Vector2(968, 872), "hostinec": Vector2(1296, 872), "stit": Vector2(1588, 872),
	"lektvary": Vector2(929, 985), "zbrane": Vector2(1311, 995), "lavice_l": Vector2(937, 1090), "lavice_p": Vector2(1265, 1090),
	"studna": Vector2(1069, 1040), "lampa_l": Vector2(1040, 985), "lampa_p": Vector2(1230, 985), "zelenina": Vector2(800, 1150),
}
const VILLAGERS := {
	&"hana": {"name": "Hana (bylinkářka)", "tint": Color(1, 0.85, 0.95), "sheet": "res://assets/characters/merchant/merchant.png",
		"home": "vysoky", "plan": [{"h": 6.5, "at": "lektvary", "act": "třídí bylinky"}, {"h": 12.0, "at": "lavice_l", "act": "obědvá"},
		{"h": 13.5, "at": "lektvary", "act": "míchá lektvary"}, {"h": 18.0, "at": "hostinec", "act": "jde na večeři", "in": true}, {"h": 21.0, "at": "vysoky", "act": "spí", "in": true}]},
	&"tomas": {"name": "Tomáš (strážný)", "tint": Color(0.8, 0.9, 1.0), "sheet": "res://assets/characters/merchant/merchant.png",
		"home": "stit", "plan": [{"h": 6.0, "at": "lampa_l", "act": "hlídkuje"}, {"h": 9.0, "at": "lampa_p", "act": "hlídkuje"}, {"h": 12.0, "at": "lampa_l", "act": "hlídkuje"},
		{"h": 15.0, "at": "lampa_p", "act": "hlídkuje"}, {"h": 19.0, "at": "hostinec", "act": "pije pivo", "in": true}, {"h": 22.0, "at": "stit", "act": "spí", "in": true}]},
	&"jakub": {"name": "Jakub (rolník)", "tint": Color(0.9, 1.0, 0.8), "sheet": "res://assets/characters/merchant/merchant.png",
		"home": "cihla", "plan": [{"h": 6.0, "at": "zelenina", "act": "sklízí zeleninu"}, {"h": 11.5, "at": "lavice_p", "act": "odpočívá"},
		{"h": 14.0, "at": "zelenina", "act": "tahá bedny"}, {"h": 18.5, "at": "studna", "act": "nabírá vodu"}, {"h": 20.0, "at": "cihla", "act": "spí", "in": true}]},
	&"eliska": {"name": "Eliška (dcera hostinského)", "tint": Color(1.0, 0.95, 0.7), "sheet": "res://assets/characters/merchant/merchant.png",
		"home": "hostinec", "plan": [{"h": 7.0, "at": "studna", "act": "nosí vodu"}, {"h": 10.0, "at": "lavice_p", "act": "krmí ptáky"},
		{"h": 13.0, "at": "zbrane", "act": "kouká na zbraně"}, {"h": 16.0, "at": "lavice_l", "act": "si povídá"}, {"h": 19.0, "at": "hostinec", "act": "obsluhuje", "in": true}, {"h": 23.0, "at": "hostinec", "act": "spí", "in": true}]},
}

var villager_id: StringName = &""
var dialogue_id := ""
var world: Hd2dWorld
var activity := ""
var inside := false

var _plan: Array = []
var _home := Vector2.ZERO
var _route: Array[Vector2] = []
var _at_key := ""
var _stuck := 0.0
var _last := Vector2.ZERO


func setup_villager(id: StringName, w: Hd2dWorld) -> void:
	villager_id = id
	world = w
	var d: Dictionary = VILLAGERS[id]
	display_name = d["name"]
	tint = d["tint"]
	_plan = d["plan"]
	_home = PLACES[d["home"]]
	dialogue_id = "villager_%s" % id
	name = String(id).capitalize()


func _ready() -> void:
	super()
	var sheet: String = VILLAGERS[villager_id]["sheet"]
	if sheet != "":
		visual.body_sheet = load(sheet)
	_last = global_position
	_snap_to_schedule()


## Kam patří vesničan v dané hodině (poslední záznam plánu před ní; před prvním = poslední z předchozího dne).
func _entry(hour: float) -> Dictionary:
	var cur: Dictionary = _plan[-1]
	for e in _plan:
		if hour >= float(e["h"]):
			cur = e
	return cur


func _snap_to_schedule() -> void:
	var e := _entry(world.hour)
	_at_key = e["at"]
	activity = e["act"]
	if e.get("in", false):
		_hide_inside()
	else:
		_show_at(PLACES[e["at"]])


func _hide_inside() -> void:
	inside = true
	visible = false
	global_position = _home + Vector2(0, 6)
	_route.clear()


func _show_at(p: Vector2) -> void:
	inside = false
	visible = true
	global_position = p
	_route.clear()


func _process(delta: float) -> void:
	super(delta)
	if world == null:
		return
	var e := _entry(world.hour)
	if String(e["at"]) != _at_key:
		_at_key = e["at"]
		activity = String(e["act"])
		_plan_route(PLACES[_at_key], bool(e.get("in", false)))


func _plan_route(target: Vector2, enter: bool) -> void:
	var start: Vector2 = _home if inside else global_position
	if inside:
		_show_at(_home + Vector2(0, 14))
	_route.clear()
	_route.append(Vector2(start.x, ROAD_Y))
	_route.append(Vector2(target.x, ROAD_Y))
	_route.append(target)
	_pending_enter = enter


var _pending_enter := false


func _think(delta: float) -> void:
	if _route.is_empty():
		return
	var to := _route[0] - global_position
	if to.length() < 6.0:
		_route.pop_front()
		if _route.is_empty() and _pending_enter and _at_key != "":
			_hide_inside_at_door()
		return
	move_input = to.normalized() * (SPEED / walk_speed)
	_stuck += delta
	if global_position.distance_to(_last) > 10.0:
		_last = global_position
		_stuck = 0.0
	elif _stuck > 2.0:   # zaseknutý → skok na další bod
		global_position = _route[0]
		_stuck = 0.0


func _hide_inside_at_door() -> void:
	inside = true
	visible = false
	global_position = PLACES[_at_key]


func is_available() -> bool:
	return visible and not inside


func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-60, -68), display_name, HORIZONTAL_ALIGNMENT_CENTER, 120, 11, Color(0.8, 1, 0.8))
	if activity != "":
		draw_string(font, Vector2(-60, -80), activity, HORIZONTAL_ALIGNMENT_CENTER, 120, 10, Color(1, 1, 1, 0.65))
	if _hero_near:
		draw_string(font, Vector2(-50, -92), "[E] Mluvit", HORIZONTAL_ALIGNMENT_CENTER, 100, 11, Color.WHITE)
