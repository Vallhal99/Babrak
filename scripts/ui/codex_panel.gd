class_name CodexPanel
extends CanvasLayer
## Deník světa (klávesa K): záložky Zápisky (lore) a Bestiář. Esc zavře.

var codex: Codex
var _tab := "lore"
var _list: ItemList
var _text: RichTextLabel
var _ids: Array[String] = []
var _root: PanelContainer
var _tab_buttons := {}


func setup(c: Codex) -> void:
	codex = c
	c.changed.connect(func() -> void:
		if visible: _fill())


func _ready() -> void:
	layer = 21
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(&"inventory_ui")
	visible = false
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_root = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.07, 0.28, 0.96)
	sb.border_color = Color(0.85, 0.88, 1.0)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(14)
	_root.add_theme_stylebox_override("panel", sb)
	_root.custom_minimum_size = Vector2(760, 480)
	center.add_child(_root)
	var v := VBoxContainer.new()
	_root.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	for pair in [["lore", "Zápisky"], ["beast", "Bestiář"]]:
		var b := Button.new()
		b.text = pair[1]
		b.toggle_mode = true
		b.pressed.connect(func() -> void: _set_tab(pair[0]))
		head.add_child(b)
		_tab_buttons[pair[0]] = b
	var hint := Label.new()
	hint.text = "   K / Esc = zavřít"
	hint.modulate = Color(1, 1, 1, 0.6)
	head.add_child(hint)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	v.add_child(body)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(230, 400)
	_list.item_selected.connect(_select)
	body.add_child(_list)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.custom_minimum_size = Vector2(480, 400)
	body.add_child(_text)


func toggle() -> void:
	visible = not visible
	if visible:
		_fill()


func _set_tab(t: String) -> void:
	_tab = t
	_fill()


func _fill() -> void:
	for k in _tab_buttons:
		_tab_buttons[k].set_pressed_no_signal(k == _tab)
	_list.clear()
	_ids.clear()
	if _tab == "lore":
		for d in codex.defs():
			var known: bool = d["id"] in codex.lore
			_list.add_item(d["title"] if known else "???")
			_list.set_item_disabled(_list.item_count - 1, not known)
			_ids.append(d["id"])
	else:
		for id in TurnEnemy3.TEMPLATES:
			var seen := codex.beasts.has(String(id))
			_list.add_item(TurnEnemy3.TEMPLATES[id]["name"] if seen else "???")
			_list.set_item_disabled(_list.item_count - 1, not seen)
			_ids.append(String(id))
	_text.text = "Vyber záznam vlevo." if _list.item_count > 0 else ""
	if _list.item_count > 0:
		for i in _ids.size():
			if not _list.is_item_disabled(i):
				_list.select(i)
				_select(i)
				break


func _select(i: int) -> void:
	if _tab == "lore":
		var d := codex.entry(_ids[i])
		_text.text = "[b]%s[/b]\n\n%s" % [d["title"], d["text"]]
	else:
		_text.text = codex.beast_text(_ids[i])


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_ESCAPE or event.keycode == KEY_K):
		visible = false
		get_viewport().set_input_as_handled()
