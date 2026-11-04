class_name PauseMenu
extends CanvasLayer
## Pauza (Esc): pokračovat / restart / hlavní menu / konec. Běží i při pauze hry.

const MAIN_MENU := "res://scenes/ui/main_menu.tscn"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 240
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)
	var title := Label.new()
	title.text = "Pauza"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)
	_button(box, "Pokračovat", resume)
	_button(box, "Restart", func() -> void:
		resume()
		get_tree().reload_current_scene())
	_button(box, "Hlavní menu", func() -> void:
		resume()
		get_tree().change_scene_to_file(MAIN_MENU))
	var exit := ExitDialog.new()
	add_child(exit)
	_button(box, "Konec", exit.popup_centered)


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"pause"):
		return
	for panel: CanvasLayer in get_tree().get_nodes_in_group(&"inventory_ui"):
		if panel.visible:
			return  # Esc zavře nejdřív inventář/obchod (řeší si sám)
	if visible:
		resume()
	else:
		visible = true
		get_tree().paused = true
	get_viewport().set_input_as_handled()


func resume() -> void:
	visible = false
	get_tree().paused = false


func _button(parent: Control, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 40
	button.pressed.connect(action)
	parent.add_child(button)
