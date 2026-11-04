class_name GameMap
extends Node2D
## Základ mapy: pozadí (dítě Sprite2D) + neviditelné zdi kolem chůzeschopné oblasti + noc.

## Kam smí pata postavy (souřadnice mapy).
@export var walkable := Rect2(30, 70, 900, 480)
@export var start_position := Vector2(480, 300)
@export var night_color := Color(0.16, 0.18, 0.3)

var _night := CanvasModulate.new()


func _ready() -> void:
	var t := 64.0
	var w := walkable
	_add_wall(Rect2(w.position.x - t, w.position.y - t, w.size.x + 2 * t, t))  # nahoře
	_add_wall(Rect2(w.position.x - t, w.end.y, w.size.x + 2 * t, t))  # dole
	_add_wall(Rect2(w.position.x - t, w.position.y, t, w.size.y))  # vlevo
	_add_wall(Rect2(w.end.x, w.position.y, t, w.size.y))  # vpravo
	add_child(_night)
	set_night(false)


func set_night(on: bool) -> void:
	_night.color = night_color if on else Color.WHITE


func is_night() -> bool:
	return _night.color != Color.WHITE


func _add_wall(rect: Rect2) -> void:
	var body := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = rect.size
	shape.shape = box
	body.position = rect.get_center()
	body.add_child(shape)
	add_child(body)
