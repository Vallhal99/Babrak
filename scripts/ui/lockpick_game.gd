class_name LockpickGame
extends CanvasLayer
## Minihra páčení zámku (styl Skyrim). Myší / šipkami A D natáčíš paklíč, drženým Mezerníkem / levým
## tlačítkem otáčíš válcem. Skrytý bod zámku je jen jeden úhel: čím blíž, tím dál se válec otočí.
## Když tlačíš za hranici, paklíč se namáhá a praskne. Esc = vzdát se.
## Výsledek: signál finished(&"opened" | &"failed" | &"cancel"); počet paklíčů vrací `picks`.

signal finished(result: StringName)
signal pick_broken

const TOL := [0.0, 16.0, 10.0, 6.0]   # tolerance v ° podle obtížnosti 1–3
const NAMES := ["", "lehký", "střední", "těžký"]

var picks := 3
var difficulty := 2
var tolerance_bonus := 0.0   ## zloději o pár stupňů víc

var _sweet := 0.0
var _angle := 0.0
var _turn := 0.0
var _health := 1.0
var _holding := false
var _done := false
var _canvas: Control
var _info: Label


func start(diff: int, pick_count: int, bonus: float) -> void:
	difficulty = clampi(diff, 1, 3)
	picks = pick_count
	tolerance_bonus = bonus
	_sweet = randf_range(-70.0, 70.0)


func _ready() -> void:
	layer = 28
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_ui)
	add_child(_canvas)
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 16)
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_info.offset_top = -80.0
	_info.offset_bottom = -20.0
	add_child(_info)


func tolerance() -> float:
	return float(TOL[difficulty]) + tolerance_bonus


func _process(delta: float) -> void:
	if _done:
		return
	var d := absf(_angle - _sweet)
	var tol := tolerance()
	if _holding:
		var max_turn := 1.0 if d <= tol else minf(0.9, 1.0 - (d - tol) / 45.0)
		if _turn < max_turn:
			_turn = minf(max_turn, _turn + 0.9 * delta)
		else:
			_health -= delta * (0.7 + (d - tol) / 70.0)   # namáhání paklíče
	else:
		_turn = maxf(0.0, _turn - 1.8 * delta)
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		_angle = maxf(-90.0, _angle - 80.0 * delta)
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		_angle = minf(90.0, _angle + 80.0 * delta)
	if _turn >= 1.0:
		_finish(&"opened")
	elif _health <= 0.0:
		picks -= 1
		pick_broken.emit()
		if picks <= 0:
			_finish(&"failed")
		else:
			_health = 1.0
			_turn = 0.0
	_info.text = "Páčení zámku (%s) · paklíče: %d\nA/D nebo myš = paklíč · držet Mezerník / klik = otáčet · Esc = vzdát se" % [NAMES[difficulty], picks]
	_canvas.queue_redraw()


func _finish(result: StringName) -> void:
	if _done:
		return
	_done = true
	get_tree().paused = false
	finished.emit(result)
	queue_free()


func _input(event: InputEvent) -> void:
	if _done:
		return
	if event is InputEventMouseMotion:
		var c := _canvas.size * 0.5
		_angle = clampf((event.position.x - c.x) / (_canvas.size.x * 0.25) * 90.0, -90.0, 90.0)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_holding = event.pressed
	elif event is InputEventKey and not event.echo:
		if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
			_holding = event.pressed
		elif event.keycode == KEY_ESCAPE and event.pressed:
			_finish(&"cancel")
	get_viewport().set_input_as_handled()


func _draw_ui() -> void:
	var size := _canvas.size
	_canvas.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.78))
	var c := size * 0.5 + Vector2(0, -20)
	var shake := Vector2(randf_range(-3, 3), randf_range(-3, 3)) * (1.0 - _health) * (1.0 if _holding and _turn > 0.0 else 0.0)
	c += shake
	_canvas.draw_circle(c, 132.0, Color(0.16, 0.15, 0.14))
	_canvas.draw_arc(c, 132.0, 0.0, TAU, 64, Color(0.7, 0.62, 0.45), 6.0)
	_canvas.draw_circle(c, 98.0, Color(0.1, 0.09, 0.09))
	var rot := _turn * PI * 0.5   # válec
	_canvas.draw_set_transform(c, rot)
	_canvas.draw_rect(Rect2(-9, -34, 18, 44), Color(0.02, 0.02, 0.02))
	_canvas.draw_circle(Vector2(0, -34), 9.0, Color(0.02, 0.02, 0.02))
	_canvas.draw_set_transform(Vector2.ZERO, 0.0)
	var a := deg_to_rad(_angle)   # paklíč míří od středu dolů a natáčí se
	var dir := Vector2(sin(a), -cos(a))
	var tip := c + dir * 6.0
	var tail := c - dir * 150.0
	var col := Color(0.95, 0.8, 0.35).lerp(Color(1, 0.3, 0.2), 1.0 - _health)
	_canvas.draw_line(tail, tip, col, 5.0)
	_canvas.draw_line(tail, tail - dir * 36.0, Color(0.5, 0.5, 0.55), 12.0)
	_canvas.draw_rect(Rect2(c.x - 130, c.y + 160, 260, 10), Color(0.2, 0.2, 0.22))
	_canvas.draw_rect(Rect2(c.x - 130, c.y + 160, 260.0 * _health, 10), col)
