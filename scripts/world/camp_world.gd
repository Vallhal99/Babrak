class_name CampWorld
extends Node2D
## Ukázková mapa tábora – varianta B: vzhled vzniká za běhu (shader podkladu, rozptýlené detaily,
## stíny, vítr, světla, den/noc), ne pečením do obrázku. Vše je řízeno daty níže (pozice, hustoty).
## Objekty (stromy, stan, táborák) jsou y-řazené spritey s kolizí u paty.

signal time_changed(t: float)

@export var world_size := Vector2(1536, 1152)
@export var seed_value := 7
@export var fire_pos := Vector2(768, 560)
@export var meadow_radius := Vector2(430, 310)
@export var tuft_count := 1300
@export var max_trees := 380

## Hliněné plochy: kruhy [střed, poloměr] a cesty [body, poloměr].
var dirt_circles: Array = [[Vector2(768, 570), 150.0]]
var dirt_paths: Array = [
	[PackedVector2Array([Vector2(768, 570), Vector2(790, 700), Vector2(750, 820), Vector2(800, 950), Vector2(775, 1230)]), 40.0],
	[PackedVector2Array([Vector2(768, 570), Vector2(900, 600), Vector2(1050, 575), Vector2(1250, 650), Vector2(1620, 615)]), 34.0],
]

var objects: Node2D          ## y-řazené objekty (sem patří i hrdina)
var day_night: DayNight
var mask: TerrainMask
var start_position := Vector2(790, 700)

var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
var _shadows: Node2D
var _flat: Node2D
var _tree_mat := Fx.sway_material(1.6, 1.3, 1.8)
var _tuft_mat := Fx.sway_material(2.6, 2.0, 1.2)
var _tex: Dictionary = {}
var _fire: Campfire
var _fireflies := CPUParticles2D.new()
var _shafts_mat: ShaderMaterial


func _ready() -> void:
	_rng.seed = seed_value
	_noise.seed = seed_value
	_noise.frequency = 1.0
	_build_mask()
	_build_ground()
	_shadows = _layer("Shadows", -10)
	_flat = _layer("Flat", -5)
	objects = _layer("Objects", 0)
	objects.y_sort_enabled = true
	_build_camp()
	_build_forest()
	_build_decor()
	_build_walls()
	_build_fireflies()
	_build_overlays()
	day_night = DayNight.new()
	add_child(day_night)
	day_night.time_changed.connect(_apply_time)
	day_night.set_time(0.5)


func world_rect() -> Rect2:
	return Rect2(Vector2.ZERO, world_size)


func set_time(t: float, duration := 2.0) -> void:
	day_night.go_to(t, duration)


func cycle_time() -> void:
	day_night.cycle()


# ---------- stavba ----------

func _layer(layer_name: String, z: int) -> Node2D:
	var n := Node2D.new()
	n.name = layer_name
	n.z_index = z
	add_child(n)
	return n


func _texture(id: String) -> Texture2D:
	if not _tex.has(id):
		_tex[id] = load("res://assets/world/%s.png" % id)
	return _tex[id]


func _build_mask() -> void:
	mask = TerrainMask.new(world_size)
	for c in dirt_circles:
		mask.stamp(c[0], c[1])
	for p in dirt_paths:
		mask.stroke(p[0], p[1])
	mask.blur(2, 2)


func _build_ground() -> void:
	var noise_tex := ImageTexture.create_from_image(_noise_image(0.011, 256))
	var rect := ColorRect.new()
	rect.name = "Ground"
	rect.size = world_size
	rect.z_index = -20
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/ground.gdshader")
	mat.set_shader_parameter("mask_tex", mask.to_texture())
	mat.set_shader_parameter("grass_tex", _texture("grass_tile"))
	mat.set_shader_parameter("dirt_tex", _texture("dirt_tile"))
	mat.set_shader_parameter("noise_tex", noise_tex)
	mat.set_shader_parameter("world_size", world_size)
	rect.material = mat
	add_child(rect)


func _noise_image(freq: float, size: int) -> Image:
	var n := FastNoiseLite.new()
	n.seed = seed_value + 100
	n.frequency = freq
	n.fractal_octaves = 3
	var img := n.get_seamless_image(size, size, false, false, 0.2, true)
	img.convert(Image.FORMAT_L8)
	return img


func _add_prop(id: String, pos: Vector2, collision := "", shadow := Vector2.ZERO, sway: ShaderMaterial = null, flip := false) -> StaticBody2D:
	var tex := _texture(id)
	var body := StaticBody2D.new()
	body.position = pos
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.offset = Vector2(0, -tex.get_height() / 2.0)
	spr.flip_h = flip
	if sway:
		spr.material = sway
	body.add_child(spr)
	if collision != "":
		var col := CollisionShape2D.new()
		var parts := collision.split(",")
		if parts.size() == 1:
			var c := CircleShape2D.new()
			c.radius = float(parts[0])
			col.shape = c
			col.position = Vector2(0, -c.radius * 0.5)
		else:
			var r := RectangleShape2D.new()
			r.size = Vector2(float(parts[0]), float(parts[1]))
			col.shape = r
			col.position = Vector2(0, -r.size.y * 0.5)
		body.add_child(col)
	objects.add_child(body)
	if shadow != Vector2.ZERO:
		var sh := Fx.shadow_sprite(shadow.x, shadow.y)
		sh.position = pos + Vector2(shadow.x * 0.18, -shadow.y * 0.2)
		_shadows.add_child(sh)
	return body


func _build_camp() -> void:
	_fire = Campfire.new()
	_fire.position = fire_pos
	objects.add_child(_fire)
	var sh := Fx.shadow_sprite(30, 9)
	sh.position = fire_pos + Vector2(4, -3)
	_shadows.add_child(sh)
	_add_prop("tent", fire_pos + Vector2(-125, -70), "104,26", Vector2(82, 14))
	_add_prop("barrel", fire_pos + Vector2(120, -62), "12", Vector2(20, 7))
	_add_prop("log", fire_pos + Vector2(-82, 40), "40,12", Vector2(26, 7))
	_add_prop("log", fire_pos + Vector2(88, 48), "40,12", Vector2(26, 7), null, true)
	_add_prop("stump", fire_pos + Vector2(-150, 8), "10", Vector2(16, 6))
	_add_prop("tree_oak", Vector2(1080, 380), "14", Vector2(80, 16), _tree_mat)
	_add_prop("tree_pine", Vector2(470, 300), "10", Vector2(34, 9), _tree_mat)


func _ellipse_dist(p: Vector2) -> float:
	var d := Vector2((p.x - fire_pos.x) / meadow_radius.x, (p.y - fire_pos.y) / meadow_radius.y).length()
	return d + 0.16 * _noise.get_noise_2d(p.x * 0.004, p.y * 0.004)


func _build_forest() -> void:
	var kinds := {"tree_pine": 3.0, "tree_spruce": 2.5, "tree_a": 2.0, "tree_b": 2.0, "tree_c": 2.0, "tree_d": 2.0,
		"tree_round": 1.5, "tree_conifer": 2.0, "tree_e": 1.2, "tree_f": 1.2, "tree_tall": 1.0, "tree_oak": 0.5}
	var total := 0.0
	for w in kinds.values():
		total += w
	var taken := {}
	var spacing := 52.0
	var placed := 0
	for _i in 9000:
		if placed >= max_trees:
			break
		var p := Vector2(_rng.randf_range(-20, world_size.x + 20), _rng.randf_range(24, world_size.y + 50))
		var density := clampf((_ellipse_dist(p) - 0.95) / 0.45, 0.0, 1.0)
		if density <= 0.0 or _rng.randf() > pow(density, 0.55) or mask.near_dirt(p, 48.0):
			continue
		var key := Vector2i(p / spacing)
		var clash := false
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var other: Variant = taken.get(Vector2i(key.x + dx, key.y + dy))
				if other != null and (other as Vector2).distance_to(p) < spacing:
					clash = true
		if clash:
			continue
		taken[key] = p
		var pick := _rng.randf() * total
		var id := "tree_pine"
		for k in kinds:
			pick -= kinds[k]
			if pick <= 0.0:
				id = k
				break
		var tex := _texture(id)
		var w := tex.get_width()
		_add_prop(id, p, "%d" % clampi(int(w * 0.09), 8, 14), Vector2(w * 0.3, maxf(8.0, w * 0.07)), _tree_mat, _rng.randf() < 0.5)
		placed += 1


func _build_decor() -> void:
	var tufts := ["tuft_0", "tuft_1", "tuft_2", "tuft_3", "tuft_4"]
	var flowers := ["flower_0", "flower_1", "flower_2", "flower_3"]
	var pebbles := ["pebble_0", "pebble_1", "pebble_2"]
	var placed := 0
	for _i in tuft_count * 4:
		if placed >= tuft_count:
			break
		var p := Vector2(_rng.randf_range(0, world_size.x), _rng.randf_range(0, world_size.y))
		var m := mask.sample(p)
		var near_edge := m > 0.1 and m < 0.55
		if m > 0.55 or (not near_edge and _rng.randf() > 0.55 - 0.45 * clampf(_ellipse_dist(p) - 0.9, 0.0, 1.0)):
			continue
		var is_flower := _rng.randf() < 0.07 and not near_edge
		var id: String = flowers[_rng.randi() % flowers.size()] if is_flower else tufts[_rng.randi() % tufts.size()]
		var tex := _texture(id)
		var spr := Sprite2D.new()
		spr.texture = tex
		spr.offset = Vector2(0, -tex.get_height() / 2.0)
		spr.flip_h = _rng.randf() < 0.5
		spr.position = p
		spr.scale = Vector2.ONE * _rng.randf_range(0.8, 1.15)
		spr.modulate = Color.WHITE.darkened(_rng.randf_range(0.0, 0.12))
		spr.material = _tuft_mat
		objects.add_child(spr)
		placed += 1
	for _i in 90:                                  # kamínky na hlíně a v trávě u cesty
		var p := Vector2(_rng.randf_range(0, world_size.x), _rng.randf_range(0, world_size.y))
		if mask.sample(p) < 0.5:
			continue
		var tex := _texture(pebbles[_rng.randi() % pebbles.size()])
		var spr := Sprite2D.new()
		spr.texture = tex
		spr.position = p
		spr.flip_h = _rng.randf() < 0.5
		_flat.add_child(spr)


func _build_walls() -> void:
	var t := 64.0
	var w := world_size
	for r in [Rect2(-t, -t, w.x + 2 * t, t), Rect2(-t, w.y, w.x + 2 * t, t), Rect2(-t, 0, t, w.y), Rect2(w.x, 0, t, w.y)]:
		var body := StaticBody2D.new()
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = r.size
		shape.shape = box
		body.position = r.get_center()
		body.add_child(shape)
		add_child(body)


func _build_fireflies() -> void:
	_fireflies.texture = Fx.glow_texture()
	_fireflies.material = Fx.additive_material()
	_fireflies.amount = 46
	_fireflies.lifetime = 7.0
	_fireflies.preprocess = 7.0
	_fireflies.local_coords = false
	_fireflies.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_fireflies.emission_rect_extents = meadow_radius * 0.9
	_fireflies.position = fire_pos
	_fireflies.direction = Vector2(1, 0)
	_fireflies.spread = 180.0
	_fireflies.gravity = Vector2.ZERO
	_fireflies.initial_velocity_min = 4.0
	_fireflies.initial_velocity_max = 14.0
	_fireflies.scale_amount_min = 0.12
	_fireflies.scale_amount_max = 0.22
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 0.5, 0), Color(0.95, 1, 0.5, 1), Color(0.95, 1, 0.5, 1), Color(1, 1, 0.5, 0)])
	_fireflies.color_ramp = g
	_fireflies.z_index = 5
	add_child(_fireflies)


func _build_overlays() -> void:
	var noise_tex := ImageTexture.create_from_image(_noise_image(0.02, 128))
	var layer := CanvasLayer.new()
	layer.layer = 8
	add_child(layer)
	var shafts := ColorRect.new()
	shafts.set_anchors_preset(Control.PRESET_FULL_RECT)
	shafts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shafts_mat = ShaderMaterial.new()
	_shafts_mat.shader = load("res://shaders/shafts.gdshader")
	_shafts_mat.set_shader_parameter("noise_tex", noise_tex)
	shafts.material = _shafts_mat
	layer.add_child(shafts)
	var vig := ColorRect.new()
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vm := ShaderMaterial.new()
	vm.shader = load("res://shaders/vignette.gdshader")
	vig.material = vm
	layer.add_child(vig)


func _apply_time(t: float) -> void:
	var night := smoothstep(0.2, 1.0, t)
	var day := 1.0 - smoothstep(0.0, 0.6, t)
	var counter := day_night.counter_color()
	_fire.set_intensity(lerpf(0.55, 1.6, night))
	_fire.set_counter(counter)
	_fireflies.modulate = Color(counter.r, counter.g, counter.b, night)
	_shafts_mat.set_shader_parameter("strength", day)
	time_changed.emit(t)
