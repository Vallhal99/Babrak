class_name CraftPanel
extends CanvasLayer
## Panel výroby / vaření u pracovního stolu a ohniště. Esc / E zavře.

signal crafted(recipe: Dictionary)

var hero: Character
var kind: StringName = &"workbench"
var _box: VBoxContainer


func _ready() -> void:
	layer = 22
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(&"inventory_ui")
	visible = false
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.07, 0.05, 0.97)
	sb.border_color = Color(0.9, 0.7, 0.4)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	_box = VBoxContainer.new()
	_box.custom_minimum_size.x = 560
	_box.add_theme_constant_override("separation", 6)
	panel.add_child(_box)


func open(h: Character, k: StringName) -> void:
	hero = h
	kind = k
	_fill()
	visible = true


func _fill() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	var t := Label.new()
	t.text = "Pracovní stůl – kování" if kind == &"workbench" else "Ohniště – vaření"
	t.add_theme_font_size_override("font_size", 24)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(t)
	var first: Button
	for r in Recipes.list(kind):
		var b := Button.new()
		b.text = "%s – %s\n%s" % [r["name"], r["desc"], Recipes.ingredients_text(hero, r)]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = not Recipes.can_make(hero, r)
		b.pressed.connect(func() -> void:
			if Recipes.make(hero, r):
				crafted.emit(r)
				_fill())
		_box.add_child(b)
		if first == null and not b.disabled:
			first = b
	var close_b := Button.new()
	close_b.text = "Zavřít (Esc)"
	close_b.pressed.connect(close)
	_box.add_child(close_b)
	(first if first else close_b).grab_focus()


func close() -> void:
	visible = false


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ESCAPE or event.keycode == KEY_E):
		close()
		get_viewport().set_input_as_handled()
