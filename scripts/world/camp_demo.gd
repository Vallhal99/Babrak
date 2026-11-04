extends Node2D
## Ukázka: mapa tábora (živé efekty) + hrdina, který se po ní hýbe. N = den / soumrak / noc.

@onready var _map: CampWorld = $Map
@onready var _hero: Hero = $Hero
@onready var _panel: InventoryPanel = $InventoryPanel
@onready var _hud: Hud = $Hud


func _ready() -> void:
	_hero.reparent(_map.objects)                    # hrdina se řadí do hloubky spolu se stromy
	_hero.position = _map.start_position
	_hero.add_child(_make_shadow())
	_hero.move_child(_hero.get_child(_hero.get_child_count() - 1), 0)
	var cam := Camera2D.new()
	cam.zoom = Vector2(1.25, 1.25)
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 6.0
	var r := _map.world_rect()
	cam.limit_left = int(r.position.x)
	cam.limit_top = int(r.position.y)
	cam.limit_right = int(r.end.x)
	cam.limit_bottom = int(r.end.y)
	_hero.add_child(cam)
	for item in ItemDB.all():
		_hero.inventory.add(item.id)
	_panel.setup(_hero)
	_hud.setup(_hero)
	_add_help()


func _make_shadow() -> Sprite2D:
	var s := Fx.shadow_sprite(15, 6)
	s.position = Vector2(0, -2)
	return s


func _add_help() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 9
	add_child(layer)
	var l := Label.new()
	l.text = "WASD / šipky – pohyb   Shift – běh   J – útok   Q – kouzlo   I – inventář   N – den / soumrak / noc"
	l.position = Vector2(12, 684)
	l.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.8))
	l.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override(&"shadow_offset_x", 1)
	l.add_theme_constant_override(&"shadow_offset_y", 1)
	layer.add_child(l)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"inventory"):
		_panel.toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"toggle_night"):
		_map.cycle_time()
