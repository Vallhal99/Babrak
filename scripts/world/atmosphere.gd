class_name Atmosphere
extends Node2D
## Atmosféra a post-processing: bloom, grading, tilt-shift, vinětace, stíny mraků, mlha,
## částice (pyl / světlušky, listí, déšť, sníh). Navázáno na denní dobu a počasí.
##   var atm := Atmosphere.new(); add_child(atm)   # a kamera Camera2D v aktuálním viewportu
##   atm.set_time(t)  (0 den, 0.5 soumrak, 1 noc)     atm.set_weather(Atmosphere.Weather.RAIN)

enum Weather { CLEAR, FOG, RAIN, SNOW }

@export var post_enabled := true
@export var cloud_shadows := true
@export var leaves := true

var weather := Weather.CLEAR
var time := 0.0

var _post: ColorRect
var _clouds: ColorRect
var _post_mat: ShaderMaterial
var _cloud_mat: ShaderMaterial
var _wind := Vector2.ZERO
var _motes: CPUParticles2D
var _leaves: CPUParticles2D
var _rain: CPUParticles2D
var _snow: CPUParticles2D
var _tween: Tween
var _fx := {"fog": 0.0, "cloud": 0.22}   # plynule animované hodnoty


func _ready() -> void:
	z_index = 50
	_clouds = _make_rect(2, "res://shaders/clouds.gdshader")
	_cloud_mat = _clouds.material
	var img := FastNoiseLite.new()
	img.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	img.frequency = 0.012
	img.fractal_octaves = 3
	_cloud_mat.set_shader_parameter("noise_tex", ImageTexture.create_from_image(img.get_seamless_image(256, 256)))
	_post = _make_rect(3, "res://shaders/post_fx.gdshader")
	_post_mat = _post.material
	_motes = _make_particles(_dot_texture(8), 26, 9.0, true)
	_motes.gravity = Vector2.ZERO
	_motes.initial_velocity_min = 3.0
	_motes.initial_velocity_max = 10.0
	_motes.direction = Vector2(1, -0.4)
	_motes.spread = 180.0
	_motes.scale_amount_min = 0.25
	_motes.scale_amount_max = 0.6
	_leaves = _make_particles(_leaf_texture(), 9, 11.0, false)
	_leaves.gravity = Vector2(12, 8)
	_leaves.initial_velocity_min = 18.0
	_leaves.initial_velocity_max = 34.0
	_leaves.direction = Vector2(1, 0.45)
	_leaves.spread = 25.0
	_leaves.angular_velocity_min = -120.0
	_leaves.angular_velocity_max = 120.0
	_leaves.color = Color(0.55, 0.62, 0.25, 0.95)
	_leaves.scale_amount_min = 0.7
	_leaves.scale_amount_max = 1.3
	_rain = _make_particles(_streak_texture(), 340, 0.9, false)
	_rain.gravity = Vector2(-60, 1500)
	_rain.initial_velocity_min = 80.0
	_rain.initial_velocity_max = 120.0
	_rain.direction = Vector2(-0.05, 1)
	_rain.spread = 2.0
	_rain.color = Color(0.7, 0.8, 1.0, 0.5)
	_rain.emitting = false
	_snow = _make_particles(_dot_texture(8), 220, 9.0, false)
	_snow.gravity = Vector2(0, 8)
	_snow.initial_velocity_min = 8.0
	_snow.initial_velocity_max = 22.0
	_snow.direction = Vector2(0.3, 1)
	_snow.spread = 40.0
	_snow.scale_amount_min = 0.3
	_snow.scale_amount_max = 0.7
	_snow.color = Color(1, 1, 1, 0.85)
	_snow.emitting = false
	set_time(time)
	_apply_weather(0.0)


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var c := cam.get_screen_center_position()
	global_position = c
	var size := get_viewport_rect().size / cam.zoom
	for p in [_motes, _leaves, _snow]:
		p.emission_rect_extents = size * 0.6
	_rain.emission_rect_extents = Vector2(size.x * 0.65, 10)
	_rain.position = Vector2(0, -size.y * 0.6)
	_rain.lifetime = (size.y * 1.3) / 1100.0 + 0.1
	_wind += Vector2(0.004, 0.0015) * delta * (3.0 if weather == Weather.RAIN else 1.0)
	_cloud_mat.set_shader_parameter("cam_pos", c)
	_cloud_mat.set_shader_parameter("zoom", cam.zoom.x)
	_cloud_mat.set_shader_parameter("wind", _wind)
	_cloud_mat.set_shader_parameter("fog_density", _fx["fog"])
	_cloud_mat.set_shader_parameter("cloud_density", _fx["cloud"] if cloud_shadows else 0.0)
	_post.visible = post_enabled
	_clouds.visible = cloud_shadows or _fx["fog"] > 0.01


## 0 = den, 0.5 = soumrak, 1 = noc
func set_time(t: float) -> void:
	time = t
	if _post_mat == null:
		return
	var dusk := 1.0 - absf(t - 0.5) * 2.0          # 1 v soumraku
	var night := smoothstep(0.5, 1.0, t)
	var gain := Color(1.04, 1.0, 0.94).lerp(Color(1.12, 0.88, 0.74), clampf(dusk, 0.0, 1.0)).lerp(Color(0.8, 0.9, 1.12), night)
	_post_mat.set_shader_parameter("gain", gain)
	_post_mat.set_shader_parameter("shadow_tint", Color(0.93, 0.96, 1.0).lerp(Color(0.78, 0.84, 1.1), night))
	_post_mat.set_shader_parameter("bloom_strength", lerpf(0.22, 0.75, maxf(dusk * 0.6, night)))
	_post_mat.set_shader_parameter("bloom_threshold", lerpf(0.72, 0.36, night))
	_post_mat.set_shader_parameter("vignette", lerpf(0.38, 0.55, night))
	# přes den pyl a listí, v noci světlušky
	_motes.color = Color(1.0, 0.97, 0.75, 0.55).lerp(Color(0.8, 1.0, 0.4, 1.0), night)
	_motes.amount = 26 if night < 0.5 else 38
	_leaves.emitting = leaves and weather == Weather.CLEAR and night < 0.6
	if _cloud_mat:
		_fx["cloud"] = (0.22 if weather == Weather.CLEAR else 0.3) * (1.0 - night * 0.8)
		_cloud_mat.set_shader_parameter("fog_color", Color(0.78, 0.84, 0.9).lerp(Color(0.16, 0.2, 0.34), night).lerp(Color(0.95, 0.72, 0.6), dusk * 0.5))
	_motes.modulate = Color(1.6, 1.6, 1.6) if night > 0.5 else Color.WHITE


func set_weather(w: Weather, duration := 2.5) -> void:
	weather = w
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	var fog: float = {Weather.CLEAR: 0.0, Weather.FOG: 0.55, Weather.RAIN: 0.18, Weather.SNOW: 0.25}[w]
	_tween.tween_property(self, "_fx:fog", fog, duration)
	_apply_weather(duration)
	set_time(time)


func _apply_weather(_d: float) -> void:
	_rain.emitting = weather == Weather.RAIN
	_snow.emitting = weather == Weather.SNOW
	_motes.emitting = weather == Weather.CLEAR or weather == Weather.FOG
	_leaves.emitting = leaves and weather == Weather.CLEAR
	if _post_mat:
		_post_mat.set_shader_parameter("saturation", 0.92 if weather == Weather.RAIN else 1.02)


# ---------- pomocné ----------
func _make_rect(layer_i: int, shader_path: String) -> ColorRect:
	var layer := CanvasLayer.new()
	layer.layer = layer_i
	add_child(layer)
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = load(shader_path)
	r.material = m
	layer.add_child(r)
	return r


func _make_particles(tex: Texture2D, amount: int, life: float, additive: bool) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = tex
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	p.preprocess = life
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(600, 400)
	if additive:
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		p.material = mat
	add_child(p)
	return p


func _dot_texture(size: int) -> Texture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = size
	t.height = size
	return t


func _streak_texture() -> Texture2D:
	var im := Image.create(2, 14, false, Image.FORMAT_RGBA8)
	for y in 14:
		for x in 2:
			im.set_pixel(x, y, Color(1, 1, 1, float(y) / 13.0))
	return ImageTexture.create_from_image(im)


func _leaf_texture() -> Texture2D:
	var im := Image.create(6, 4, false, Image.FORMAT_RGBA8)
	for y in 4:
		for x in 6:
			var d := absf(x - 2.5) / 3.0 + absf(y - 1.5) / 2.0
			if d < 1.0:
				im.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(im)
