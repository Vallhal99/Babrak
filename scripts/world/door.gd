class_name Door
extends Node2D
## Vchod do budovy: nad hrdinou se ukáže popisek, E ho pustí dovnitř.

const NEAR := 46.0
var label := "[E] Vstoupit"
var _near := false


func _process(_d: float) -> void:
	var near := false
	for node in get_tree().get_nodes_in_group(&"characters"):
		var c := node as Character
		if c.team == &"hero" and not c.dead and c.global_position.distance_to(global_position) <= NEAR:
			near = true
	if near != _near:
		_near = near
		queue_redraw()


func is_near() -> bool:
	return _near


func _draw() -> void:
	if _near:
		draw_string(ThemeDB.fallback_font, Vector2(-50, -30), label, HORIZONTAL_ALIGNMENT_CENTER, 100, 12, Color(1, 0.95, 0.6))
