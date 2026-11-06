class_name Pickup
extends Node2D
## Předmět ležící na zemi. Hráčova postava (tým "hero") ho sebere dotykem.

const RADIUS := 22.0

var item: ItemData

var _time := 0.0
var _taken := false
var _icon := Sprite2D.new()


func _ready() -> void:
	_icon.texture = item.icon
	_icon.scale = Vector2(0.6, 0.6)
	add_child(_icon)
	var tween := create_tween()  # "vyskočení" z těla nepřítele
	tween.tween_property(self, "position", position + Vector2(randf_range(-18, 18), randf_range(4, 14)), 0.3)


func _process(delta: float) -> void:
	_time += delta
	_icon.position.y = -14.0 + sin(_time * 4.0) * 2.0
	queue_redraw()
	if _time < 0.4:
		return
	for node in get_tree().get_nodes_in_group(&"characters"):
		var who := node as Character
		if who.team == &"hero" and not who.dead and who.global_position.distance_to(global_position) <= RADIUS:
			who.inventory.add(item.id)
			_float_text("+ " + item.display_name)
			return


func _draw() -> void:
	if _taken:
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 9.0, Color(0, 0, 0, 0.35))


## Předmět zmizí a nad jeho místem krátce vyplave text (je potomkem předmětu, aby se vykreslil s ním).
func _float_text(text: String) -> void:
	_taken = true
	set_process(false)
	_icon.hide()
	queue_redraw()
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	label.position = Vector2(-30, -40)
	add_child(label)
	var tween := label.create_tween()
	tween.set_parallel()
	tween.tween_property(label, "position:y", label.position.y - 22.0, 0.9)
	tween.tween_property(label, "modulate:a", 0.0, 0.9)
	tween.chain().tween_callback(queue_free)
