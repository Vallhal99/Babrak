extends Node2D
## Ukázka: svět z Tiledu (chunky) + hrdina. N = den / soumrak / noc.

@onready var _world: TiledWorld = $World
@onready var _hero: Hero = $Hero
@onready var _panel: InventoryPanel = $InventoryPanel
@onready var _hud: Hud = $Hud
var _day_night := DayNight.new()


func _ready() -> void:
	_hero.reparent(_world.objects)
	_hero.position = _world.start_position
	_world.focus = _hero
	var shadow := Fx.shadow_sprite(15, 6)
	shadow.position = Vector2(0, -2)
	_hero.add_child(shadow)
	_hero.move_child(shadow, 0)
	var cam := Camera2D.new()
	cam.zoom = Vector2(1.25, 1.25)
	cam.position_smoothing_enabled = true
	cam.limit_left = int(_world.bounds_px.position.x)
	cam.limit_top = int(_world.bounds_px.position.y)
	cam.limit_right = int(_world.bounds_px.end.x)
	cam.limit_bottom = int(_world.bounds_px.end.y)
	_hero.add_child(cam)
	for item in ItemDB.all():
		_hero.inventory.add(item.id)
	_panel.setup(_hero)
	_hud.setup(_hero)
	add_child(_day_night)
	_day_night.time_changed.connect(_apply_time)
	_day_night.set_time(0.5)
	_add_overlay()


func _apply_time(t: float) -> void:
	var night := smoothstep(0.2, 1.0, t)
	for f in get_tree().get_nodes_in_group(&"campfires"):
		var fire := f as Campfire
		fire.set_intensity(lerpf(0.55, 1.6, night))
		fire.set_counter(_day_night.counter_color())


func _add_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 8
	add_child(layer)
	var vig := ColorRect.new()
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vm := ShaderMaterial.new()
	vm.shader = load("res://shaders/vignette.gdshader")
	vig.material = vm
	layer.add_child(vig)
	var l := Label.new()
	l.text = "WASD / šipky – pohyb   Shift – běh   I – inventář   N – den / soumrak / noc"
	l.position = Vector2(12, 684)
	l.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override(&"shadow_offset_x", 1)
	l.add_theme_constant_override(&"shadow_offset_y", 1)
	layer.add_child(l)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"inventory"):
		_panel.toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"toggle_night"):
		_day_night.cycle()
