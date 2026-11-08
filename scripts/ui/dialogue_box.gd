class_name DialogueBox
extends CanvasLayer
## Okno dialogu: jméno, text po písmenkách, volby (klávesy 1–4, šipky + Enter, myš).
## Použití: box.open(runner, "merchant") -> await box.closed. Při otevření zastaví svět (pause).

signal closed

const SPEED := 55.0   # písmen za sekundu

var _runner: DialogueRunner
var _panel: PanelContainer
var _name: Label
var _text: Label
var _choices: VBoxContainer
var _hint: Label
var _shown := 0.0
var _has_choices := false


func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.07, 0.28, 0.94)
	sb.border_color = Color(0.85, 0.88, 1.0)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(14)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_left = 40.0
	_panel.offset_right = -40.0
	_panel.offset_top = -210.0
	_panel.offset_bottom = -24.0
	var box := VBoxContainer.new()
	_panel.add_child(box)
	_name = Label.new()
	_name.add_theme_font_size_override("font_size", 20)
	_name.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	box.add_child(_name)
	_text = Label.new()
	_text.add_theme_font_size_override("font_size", 20)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(0, 62)
	box.add_child(_text)
	_choices = VBoxContainer.new()
	box.add_child(_choices)
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	_hint.text = "Enter / E / klik = dál"
	box.add_child(_hint)
	add_child(_panel)


func open(runner: DialogueRunner, id: String) -> bool:
	_runner = runner
	runner.node_shown.connect(_on_node)
	runner.finished.connect(_on_finished)
	if not runner.start(id):
		return false
	visible = true
	get_tree().paused = true
	return true


func _on_node(speaker: String, text: String, choices: Array) -> void:
	_name.text = speaker
	_name.visible = speaker != ""
	_text.text = text
	_text.visible_characters = 0
	_shown = 0.0
	for c in _choices.get_children():
		_choices.remove_child(c)
		c.queue_free()
	_has_choices = not choices.is_empty()
	for i in choices.size():
		var b := Button.new()
		b.text = "%d. %s" % [i + 1, choices[i]]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(_pick.bind(i))
		b.visible = false
		_choices.add_child(b)
	_hint.visible = not _has_choices


func _on_finished() -> void:
	visible = false
	get_tree().paused = false
	_runner.node_shown.disconnect(_on_node)
	_runner.finished.disconnect(_on_finished)
	closed.emit()


func _process(delta: float) -> void:
	if not visible:
		return
	_shown += SPEED * delta
	var total := _text.text.length()
	_text.visible_characters = mini(total, int(_shown))
	if _text.visible_characters >= total and _has_choices and not _choices.get_child(0).visible:
		for b in _choices.get_children():
			(b as Button).visible = true
		(_choices.get_child(0) as Button).grab_focus()


func _pick(i: int) -> void:
	_runner.choose(i)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	var accept: bool = event.is_action_pressed(&"ui_accept") or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
		or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E)
	if _text.visible_characters < _text.text.length():
		if accept:
			_shown = 9999.0
			get_viewport().set_input_as_handled()
		return
	if _has_choices:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode >= KEY_1 and event.keycode <= KEY_4:
			_pick(event.keycode - KEY_1)
			get_viewport().set_input_as_handled()
		return
	if accept:
		_runner.advance()
		get_viewport().set_input_as_handled()
