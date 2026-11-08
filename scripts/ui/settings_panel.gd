class_name SettingsPanel
extends CenterContainer
## Nastavení (hlavní menu i pauza). Změny se ukládají hned.

signal closed


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func open() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.08, 0.1, 1.0)
	sb.border_color = Color(0.5, 0.6, 0.6)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 460
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := Label.new()
	title.text = "Nastavení"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	box.add_child(title)
	_slider(box, "Hlasitost", "volume", 0.0, 1.0, 0.05)
	_slider(box, "Rychlost textu dialogů", "text_speed", 0.5, 3.0, 0.25)
	_check(box, "Celá obrazovka", "fullscreen")
	_check(box, "Vertikální synchronizace (VSync)", "vsync")
	_check(box, "3D bojiště v soubojích (vypni na slabším PC)", "arena3d")
	var help := Label.new()
	help.text = "Ovládání: WASD/šipky pohyb · E mluvit/otevřít · I inventář · J úkoly · K deník\nF3 počasí · N noc/den · Esc pauza · v souboji šipky + Enter, B = boost"
	help.add_theme_font_size_override("font_size", 12)
	help.modulate = Color(1, 1, 1, 0.7)
	box.add_child(help)
	var back := Button.new()
	back.text = "Zpět"
	back.pressed.connect(close)
	box.add_child(back)
	visible = true
	back.grab_focus()


func close() -> void:
	visible = false
	closed.emit()


func _slider(box: Control, label: String, key: String, lo: float, hi: float, step: float) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 230
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(Settings.values[key])
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(func(v: float) -> void: Settings.set_value(key, v))
	row.add_child(s)
	box.add_child(row)


func _check(box: Control, label: String, key: String) -> void:
	var c := CheckBox.new()
	c.text = label
	c.button_pressed = bool(Settings.values[key])
	c.toggled.connect(func(on: bool) -> void: Settings.set_value(key, on))
	box.add_child(c)
