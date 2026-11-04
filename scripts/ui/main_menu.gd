extends Control
## Úvodní menu. Spouští se jako run/main_scene.

const GAME := "res://scenes/main.tscn"


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.08, 0.06)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 280
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)
	var title := Label.new()
	title.text = "Hero RPG"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	box.add_child(title)
	var start := _button(box, "Nová hra", func() -> void: get_tree().change_scene_to_file(GAME))
	var exit := ExitDialog.new()
	add_child(exit)
	_button(box, "Konec", exit.popup_centered)
	var help := Label.new()
	help.text = "WASD/šipky pohyb · Shift běh · Space/J útok · Q kouzlo\nI/Tab inventář · N noc/den · Esc pauza"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.add_theme_font_size_override("font_size", 12)
	box.add_child(help)
	start.grab_focus()


func _button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 44
	button.pressed.connect(action)
	parent.add_child(button)
	return button
