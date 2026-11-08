class_name QuestPanel
extends CanvasLayer
## Deník úkolů (klávesa J) + upozornění nahoře při změně úkolu.

var _quests: QuestLog
var _panel: PanelContainer
var _list: VBoxContainer
var _toast: Label
var _toast_time := 0.0


func setup(quests: QuestLog) -> void:
	_quests = quests
	quests.changed.connect(_rebuild)
	quests.toast.connect(_show_toast)


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.07, 0.28, 0.94)
	sb.border_color = Color(0.85, 0.88, 1.0)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(14)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.position = Vector2(60, 50)
	_panel.custom_minimum_size = Vector2(520, 0)
	_list = VBoxContainer.new()
	_panel.add_child(_list)
	_panel.visible = false
	add_child(_panel)
	_toast = Label.new()
	_toast.add_theme_font_size_override("font_size", 22)
	_toast.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.position = Vector2(200, 24)
	add_child(_toast)


func toggle() -> void:
	_panel.visible = not _panel.visible
	_rebuild()


func is_open() -> bool:
	return _panel.visible


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast_time = 3.5


func _process(delta: float) -> void:
	_toast_time = maxf(0.0, _toast_time - delta)
	_toast.modulate.a = clampf(_toast_time, 0.0, 1.0)


func _rebuild() -> void:
	if not _panel.visible:
		return
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_add("Deník úkolů  (J = zavřít)", 22, Color(1.0, 0.85, 0.3))
	var any := false
	for id in _quests.state:
		any = true
		var st: String = _quests.state[id]["state"]
		var mark: String = {"active": "", "ready": "  — ODEVZDAT", "done": "  — hotovo"}[st]
		_add("%s%s" % [_quests.defs[id]["title"], mark], 19, Color(0.6, 1.0, 0.7) if st == "done" else Color.WHITE)
		_add(str(_quests.defs[id].get("desc", "")), 14, Color(0.8, 0.85, 1.0))
		if st != "done":
			for line in _quests.lines(id):
				_add("   " + line, 15, Color(0.9, 0.9, 0.9))
	if not any:
		_add("Zatím žádné úkoly. Promluv si s lidmi (E).", 16, Color(0.8, 0.8, 0.9))


func _add(text: String, size: int, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 490
	_list.add_child(l)
