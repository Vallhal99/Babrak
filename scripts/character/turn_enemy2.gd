class_name TurnEnemy2
extends Enemy
## Nepřítel na mapě pro "Nová hra tah 2". Při dotyku vyšle `contact` (s info, kdo získal iniciativu)
## a hra přepne do tahového souboje. Vzory nepřátel: TEMPLATES (apply_template před přidáním do světa).

signal contact(enemy: TurnEnemy2, first: StringName)

const TEMPLATES := {
	&"bandit": {"name": "Zbojník", "tint": Color(1, 0.75, 0.75), "hp": 14, "atk": 1, "xp": 15, "gold": 8,
		"shield": 3, "weak": [&"blunt", &"fire"], "speed": 8, "human": true, "row": 0},
	&"archer": {"name": "Lučištník", "tint": Color(0.8, 1, 0.75), "hp": 10, "atk": 1, "xp": 14, "gold": 7,
		"shield": 2, "weak": [&"blade", &"blunt"], "speed": 9, "human": true, "row": 1, "ranged": true},
	&"skeleton": {"name": "Kostlivec", "tint": Color(0.75, 0.85, 1.0), "hp": 16, "atk": 2, "xp": 18, "gold": 3,
		"shield": 3, "weak": [&"blunt", &"fire"], "speed": 7, "human": false, "row": 0},
	&"leader": {"name": "Vůdce zbojníků", "tint": Color(1, 0.55, 0.4), "hp": 40, "atk": 3, "xp": 60, "gold": 40,
		"shield": 4, "weak": [&"bow", &"fire"], "speed": 9, "human": true, "row": 0, "rank": &"elite", "phases": 2},
	&"knight": {"name": "Černý rytíř", "tint": Color(0.45, 0.45, 0.6), "hp": 90, "atk": 5, "xp": 200, "gold": 120,
		"shield": 6, "weak": [&"blade", &"fire"], "speed": 8, "human": false, "row": 0, "rank": &"boss", "phases": 3},
}

@export var shield_points := 3
@export var weaknesses: Array[StringName] = [&"blunt", &"fire"]
@export var battle_speed := 8

var human := true            ## s lidmi se dá vyjednávat
var rank: StringName = &"normal"   ## normal / elite / boss
var row := 0                 ## 0 přední řada, 1 zadní
var phases := 1              ## kolik fází (po Breaku se štít obnoví a boj pokračuje)
var ranged := false
var grace := 0.0
var _triggered := false


func apply_template(id: StringName) -> void:
	var t: Dictionary = TEMPLATES[id]
	display_name = t["name"]
	tint = t["tint"]
	base_max_hp = t["hp"]
	base_attack = t["atk"]
	xp_reward = t["xp"]
	gold_reward = t["gold"]
	shield_points = t["shield"]
	weaknesses.assign(t["weak"])
	battle_speed = t["speed"]
	human = t["human"]
	row = t["row"]
	ranged = t.get("ranged", false)
	rank = t.get("rank", &"normal")
	phases = t.get("phases", 1)


func _ready() -> void:
	super()
	invulnerable = true   # v tahovém režimu se nebojuje v reálném čase


func _think(delta: float) -> void:
	grace = maxf(0.0, grace - delta)
	if _triggered:
		return
	if _target == null or _target.dead:
		_target = _find_target()
	if _target == null:
		return
	var to := _target.global_position - global_position
	if to.length() > sight * 1.5:
		_target = null
	elif to.length() > attack_range:
		move_input = to.normalized()
	else:
		facing = dir_from(to)
		var player := _target as Hero
		if grace <= 0.0 and (player == null or player.controls_enabled):
			_triggered = true
			var first: StringName = &""
			if player:  # hrdina k nepříteli stojí zády = přepadení
				var away := (global_position - player.global_position).normalized()
				if DIR_VECTORS[player.facing].dot(away) < -0.4:
					first = &"enemy"
			contact.emit(self, first)


## Povolí nepříteli spustit souboj znovu (po zrušeném nebo uteklém souboji).
func release() -> void:
	_triggered = false


## Hráč zahájil souboj sám (útok ze zálohy).
func lock() -> void:
	_triggered = true
