class_name Chest
extends Node2D
## Truhla ve světě (HD-2D billboard jako ostatní předměty). Otevírá se klávesou E; zamčené truhly
## se páčí v minihře (LockpickGame). Obrázky: assets/props/chest_closed.png / chest_open.png
## (zatím dočasné z tools/make_chest.py, oficiální stačí uložit pod stejnými názvy).

const CLOSED := "res://assets/props/chest_closed.png"
const OPEN := "res://assets/props/chest_open.png"
const NEAR := 64.0

var chest_id := ""
var difficulty := 0      ## 0 odemčeno, 1 lehká, 2 střední, 3 těžká zámek
var loot := {}           ## {"gold": [min, max], "cons": {id: n}, "items": [id], "picks": n}
var opened := false

var _sprite := Sprite2D.new()
var _near := false


func _ready() -> void:
	_sprite.centered = true
	add_child(_sprite)
	_apply()


func _apply() -> void:
	var tex := BattleScene3.load_texture(OPEN if opened else CLOSED)
	_sprite.texture = tex
	if tex:
		_sprite.position = Vector2(0, -tex.get_height() * 0.5)
	queue_redraw()


func set_open(value: bool) -> void:
	opened = value
	_apply()


func _process(_delta: float) -> void:
	var near := false
	for node in get_tree().get_nodes_in_group(&"characters"):
		var c := node as Character
		if c.team == &"hero" and not c.dead and c.global_position.distance_to(global_position) <= NEAR:
			near = true
	if near != _near:
		_near = near
		queue_redraw()


func _draw() -> void:
	if _near and not opened:
		var text := "[E] Otevřít" if difficulty == 0 else "[E] Páčit zámek"
		draw_string(ThemeDB.fallback_font, Vector2(-50, -52), text, HORIZONTAL_ALIGNMENT_CENTER, 100, 11, Color.WHITE)
