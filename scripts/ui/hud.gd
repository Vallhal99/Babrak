class_name Hud
extends CanvasLayer
## Základní HUD: jméno + úroveň, zdraví, mana, zkušenosti, aktivní kouzlo, hláška o postupu.

var _hero: Hero
var _name: Label
var _hp: ProgressBar
var _mana: ProgressBar
var _xp: ProgressBar
var _spell: Label
var _points: Label
var _gold: Label
var _toast: Label


func _ready() -> void:
	layer = 5
	_build()


func setup(hero: Hero) -> void:
	_hero = hero
	hero.hp_changed.connect(func(_a: int, _b: int) -> void: _refresh())
	hero.mana_changed.connect(func(_a: int, _b: int) -> void: _refresh())
	hero.xp_changed.connect(func(_a: int, _b: int) -> void: _refresh())
	hero.level_up.connect(_on_level_up)
	hero.skills_changed.connect(_refresh)
	hero.gold_changed.connect(func(_g: int) -> void: _refresh())
	_refresh()


func _process(_delta: float) -> void:
	if _hero:
		_spell.text = "[Q] %s" % (_hero.active_spell.display_name if _hero.active_spell else "—")


func _build() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(12, 10)
	box.add_theme_constant_override("separation", 3)
	add_child(box)
	_name = Label.new()
	_name.add_theme_color_override("font_outline_color", Color.BLACK)
	_name.add_theme_constant_override("outline_size", 4)
	box.add_child(_name)
	_hp = _bar(box, Color(0.8, 0.15, 0.15), Vector2(200, 16))
	_mana = _bar(box, Color(0.2, 0.4, 0.95), Vector2(200, 12))
	_xp = _bar(box, Color(0.95, 0.8, 0.2), Vector2(200, 6))
	_spell = Label.new()
	_spell.add_theme_color_override("font_outline_color", Color.BLACK)
	_spell.add_theme_constant_override("outline_size", 4)
	box.add_child(_spell)

	_points = Label.new()
	_points.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_points.add_theme_color_override("font_outline_color", Color.BLACK)
	_points.add_theme_constant_override("outline_size", 4)
	box.add_child(_points)

	_gold = Label.new()
	_gold.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_gold.add_theme_color_override("font_outline_color", Color.BLACK)
	_gold.add_theme_constant_override("outline_size", 4)
	box.add_child(_gold)

	_toast = Label.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.position.y = 80
	_toast.add_theme_font_size_override("font_size", 28)
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 8)
	_toast.modulate.a = 0.0
	add_child(_toast)


## Pruh s číslem uprostřed (text = Label dítě).
func _bar(parent: Control, color: Color, size: Vector2) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = size
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0, 0, 0, 0.65)
	back.border_color = Color(0, 0, 0, 0.9)
	back.set_border_width_all(1)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", back)
	if size.y >= 12.0:
		var label := Label.new()
		label.name = "Text"
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 11)
		bar.add_child(label)
	parent.add_child(bar)
	return bar


func _set_bar(bar: ProgressBar, value: float, max_value: float) -> void:
	bar.max_value = max_value
	bar.value = value
	var label := bar.get_node_or_null("Text") as Label
	if label:
		label.text = "%d / %d" % [value, max_value]


func _refresh() -> void:
	_name.text = "%s   úr. %d" % [_hero.display_name, _hero.level]
	_set_bar(_hp, _hero.hp, _hero.max_hp())
	_set_bar(_mana, _hero.mana, _hero.max_mana())
	_set_bar(_xp, _hero.xp, _hero.xp_needed())
	_gold.text = "Zlato: %d" % _hero.gold
	_points.text = "Volné body: %d  (I → Dovednosti)" % _hero.skill_points if _hero.skill_points > 0 else ""


func _on_level_up(level: int) -> void:
	_toast.text = "Úroveň %d!  +%d bodů" % [level, Character.POINTS_PER_LEVEL]
	_toast.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(1.2)
	tween.tween_property(_toast, "modulate:a", 0.0, 0.8)
