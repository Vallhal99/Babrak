extends Control
## Výběr povolání před startem (test). Ve finále si hráč třídu vybere až během hry (ClassDefs.apply).

const NEXT := "res://scenes/main_turn3.tscn"


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.08, 0.06)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	var title := Label.new()
	title.text = "Vyber si povolání"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	box.add_child(title)
	var info := Label.new()
	info.text = "(najeď na ikonu pro popis)"
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_font_size_override("font_size", 14)
	var desc := Label.new()
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(620, 70)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 18)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	for id in ClassDefs.ORDER:
		var d: Dictionary = ClassDefs.CLASSES[id]
		var b := Button.new()
		b.custom_minimum_size = Vector2(110, 130)
		b.text = "%s\n\n%s" % [d["icon"], d["name"]]
		b.add_theme_font_size_override("font_size", 22)
		var sb := StyleBoxFlat.new()
		sb.bg_color = (d["color"] as Color).darkened(0.55)
		sb.border_color = d["color"]
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(10)
		b.add_theme_stylebox_override("normal", sb)
		var hov := sb.duplicate() as StyleBoxFlat
		hov.bg_color = (d["color"] as Color).darkened(0.25)
		b.add_theme_stylebox_override("hover", hov)
		b.add_theme_stylebox_override("focus", hov)
		b.add_theme_stylebox_override("pressed", hov)
		var text := "%s: %s  (HP %d, MP %d)" % [d["name"], d["desc"], d["hp"], d["mana"]]
		b.mouse_entered.connect(func() -> void: desc.text = text)
		b.focus_entered.connect(func() -> void: desc.text = text)
		b.pressed.connect(func() -> void:
			Session.class_id = id
			get_tree().change_scene_to_file(NEXT))
		row.add_child(b)
	box.add_child(desc)
	box.add_child(info)
	(row.get_child(0) as Button).grab_focus()
