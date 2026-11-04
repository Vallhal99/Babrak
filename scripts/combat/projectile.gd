class_name Projectile
extends Node2D
## Letící kouzlo. Zasáhne první postavu cizího týmu (ignoruje obranu = magie).

var direction := Vector2.RIGHT
var speed := 230.0
var max_distance := 320.0
var damage := 5
var team: StringName = &"hero"
var caster: Character
var color := Color(1.0, 0.5, 0.1)
var radius := 14.0

var _travelled := 0.0


func _process(delta: float) -> void:
	var step := direction * speed * delta
	position += step
	_travelled += step.length()
	queue_redraw()
	for node in get_tree().get_nodes_in_group(&"characters"):
		var other := node as Character
		if other.dead or other.invulnerable or other.team == team:
			continue
		if global_position.distance_to(other.global_position + Character.BODY_CENTER) <= radius:
			other.take_damage(damage, caster)
			queue_free()
			return
	if _travelled >= max_distance:
		queue_free()


func _draw() -> void:
	var flicker := randf_range(0.85, 1.1)
	draw_circle(Vector2.ZERO, 7.0 * flicker, color.darkened(0.2))
	draw_circle(Vector2.ZERO, 5.0 * flicker, color)
	draw_circle(Vector2.ZERO, 2.5, color.lightened(0.7))
