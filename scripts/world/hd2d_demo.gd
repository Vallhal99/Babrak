extends Node3D
## HD-2D ukázka (styl Octopath): stejná data a 2D logika jako tiled_demo, ale vykreslená ve 3D.
## Země = vyrenderovaný 2D svět na rovině, objekty = svislé sprity (billboardy) se skutečnými stíny,
## kamera nakloněná s perspektivou, 3D světla, glow, mlha, tilt-shift. Hrdina běží dál v 2D (vstup, kolize).
## N = den / soumrak / noc

const S := 0.02                       # 1 px = 0.02 m (1 m = 50 px)
const WORLD_DIR := "res://data/world/palouk"
const HERO_VP := 192
const TILT := 44.0                   # náklon spritů k+kameře (°), plný náklon = kolmo na pohled
const UP := Vector3(0, 0.7193, -0.6947)  # směr „nahoru“ naklonného spritu (cos/sin TILT)
const HERO_FEET := 70.0               # px nad zemí, kam míří střed kamery hrdinova viewportu

var _ground_vp: SubViewport
var _hero_vp: SubViewport
var _hero_cam: Camera2D
var _world: TiledWorld
var _hero: Hero
var _hero_sprite: Sprite3D
var _cam: Camera3D
var _sun: DirectionalLight3D
var _env: Environment
var _lights: Array[OmniLight3D] = []
var _flames: Array[CPUParticles3D] = []
var _stage := 0
var _built := false
var _tween: Tween


func _ready() -> void:
	_ground_vp = SubViewport.new()
	_ground_vp.canvas_cull_mask = 1
	_ground_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_ground_vp)
	var root2d := Node2D.new()
	_ground_vp.add_child(root2d)
	_world = TiledWorld.new()
	_world.world_dir = WORLD_DIR
	_world.load_radius = 8
	var center := Node2D.new()
	root2d.add_child(center)
	_world.focus = center
	root2d.add_child(_world)
	var rect := Rect2()
	_hero = (load("res://scenes/characters/hero.tscn") as PackedScene).instantiate()
	_hero_vp = SubViewport.new()
	_hero_vp.size = Vector2i(HERO_VP, HERO_VP)
	_hero_vp.transparent_bg = true
	_hero_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_hero_vp.world_2d = _ground_vp.world_2d
	add_child(_hero_vp)
	_hero_vp.canvas_cull_mask = 2
	_hero_vp.add_child(_hero)
	_set_layer(_hero, 2)
	_hero_cam = Camera2D.new()
	_hero_vp.add_child(_hero_cam)
	_build_environment()
	await _wait_world()
	rect = _world.bounds_px
	center.position = rect.get_center()
	_hero.position = _world.start_position
	_ground_vp.size = Vector2i(rect.size)
	var gcam := Camera2D.new()
	gcam.position = rect.get_center()
	_ground_vp.add_child(gcam)
	_build_ground(rect)
	_build_props()
	_hero_sprite = Sprite3D.new()
	_hero_sprite.texture = _hero_vp.get_texture()
	_hero_sprite.pixel_size = S
	_hero_sprite.rotation_degrees.x = -TILT
	_hero_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_hero_sprite.alpha_scissor_threshold = 0.4
	_hero_sprite.shaded = true
	_hero_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	add_child(_hero_sprite)
	_built = true
	_apply_stage(0.0, 0.0)


func _wait_world() -> void:
	for _i in 900:
		await get_tree().process_frame
		if _world.all_ready() and _world.shown_chunks().size() > 0:
			for _j in 4:
				await get_tree().process_frame
			if _world.all_ready():
				return


func _set_layer(n: Node, layer: int) -> void:
	if n is CanvasItem:
		(n as CanvasItem).visibility_layer = layer
	for c in n.get_children():
		_set_layer(c, layer)


func _build_environment() -> void:
	var we := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0.55, 0.7, 0.85)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.glow_enabled = true
	_env.glow_intensity = 0.8
	_env.glow_bloom = 0.1
	_env.fog_enabled = true
	_env.fog_density = 0.006
	we.environment = _env
	var attr := CameraAttributesPractical.new()   # hloubka ostrosti (Forward+/Mobile; Compatibility ji ignoruje)
	attr.dof_blur_far_enabled = true
	attr.dof_blur_far_distance = 26.0
	attr.dof_blur_far_transition = 14.0
	attr.dof_blur_near_enabled = true
	attr.dof_blur_near_distance = 9.0
	attr.dof_blur_near_transition = 5.0
	attr.dof_blur_amount = 0.08
	we.camera_attributes = attr
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-52, -38, 0)
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 60.0
	_sun.shadow_bias = 0.03
	_sun.shadow_normal_bias = 0.6
	add_child(_sun)
	_cam = Camera3D.new()
	_cam.fov = 26.0
	_cam.far = 200.0
	add_child(_cam)
	var layer := CanvasLayer.new()
	layer.layer = 3
	add_child(layer)
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/post_fx.gdshader")
	m.set_shader_parameter("bloom_strength", 0.0)
	m.set_shader_parameter("tilt_px", 2.6)
	m.set_shader_parameter("tilt_width", 0.2)
	m.set_shader_parameter("vignette", 0.35)
	r.material = m
	layer.add_child(r)
	var l := Label.new()
	l.text = "HD-2D ukázka   WASD – pohyb   N – den / soumrak / noc"
	l.position = Vector2(12, 684)
	l.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override(&"shadow_offset_x", 1)
	l.add_theme_constant_override(&"shadow_offset_y", 1)
	var l2 := CanvasLayer.new()
	l2.layer = 5
	add_child(l2)
	l2.add_child(l)


func _build_ground(rect: Rect2) -> void:
	# vlastní hrdina a props se do země nevykreslují (props jsou ve 3D)
	_world.objects.visible = false
	_ground_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = rect.size * S
	mi.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _ground_vp.get_texture()
	mat.roughness = 1.0
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mi.material_override = mat
	mi.position = Vector3(rect.get_center().x * S, 0, rect.get_center().y * S)
	add_child(mi)


func _build_props() -> void:
	var n := 0
	for c in _world.objects.get_children():
		if c == _hero or not (c is Node2D):
			continue
		var spr: Sprite2D
		for s in c.find_children("*", "Sprite2D", true, false):
			spr = s
			break
		if spr and spr.texture:
			var p := Sprite3D.new()
			p.texture = spr.texture
			p.pixel_size = S
			p.flip_h = spr.flip_h
			p.rotation_degrees.x = -TILT
			p.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
			p.alpha_scissor_threshold = 0.5
			p.shaded = true
			p.double_sided = true
			p.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			var h := float(spr.texture.get_height())
			var gp := (c as Node2D).global_position
			p.position = Vector3(gp.x * S, 0, gp.y * S) + UP * h * 0.5 * S
			add_child(p)
			n += 1
		if c is Campfire:
			var gp := (c as Node2D).global_position
			var o := OmniLight3D.new()
			o.position = Vector3(gp.x * S, 0.7, gp.y * S)
			o.light_color = Color(1.0, 0.6, 0.25)
			o.omni_range = 9.0
			o.shadow_enabled = true
			o.light_energy = 2.0
			add_child(o)
			_lights.append(o)
			var fl := _flame(Vector3(gp.x * S, 0.15, gp.y * S))
			add_child(fl)
			_flames.append(fl)
		c.visible = false
	print("HD-2D: ", n, " spritů")


func _flame(pos: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.position = pos
	p.amount = 14
	p.lifetime = 0.9
	var q := QuadMesh.new()
	q.size = Vector2(0.22, 0.3)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	var gt := GradientTexture2D.new()
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 0.9, 0.5, 1), Color(1, 0.3, 0.05, 0)])
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1, 0.5)
	m.albedo_texture = gt
	m.albedo_color = Color(1.0, 0.5, 0.15, 0.55)
	q.material = m
	p.mesh = q
	p.direction = Vector3.UP
	p.spread = 12.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.3
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.15
	return p


func _process(delta: float) -> void:
	if not _built:
		return
	var hp := _hero.global_position
	_hero_cam.position = hp + Vector2(0, -HERO_FEET)
	_hero_sprite.position = Vector3(hp.x * S, 0, hp.y * S) + UP * HERO_FEET * S
	var target := Vector3(hp.x * S, 0.6, hp.y * S)
	var offs := Vector3(0, 17.0, 14.0)
	_cam.position = _cam.position.lerp(target + offs, clampf(delta * 5.0, 0.0, 1.0))
	_cam.look_at(_cam.position - offs + Vector3(0, 0, 0))
	var t := Time.get_ticks_msec() / 1000.0
	for o in _lights:
		o.light_energy = o.light_energy * 0.9 + (_light_base * (1.0 + 0.12 * sin(t * 17.0) * sin(t * 6.3))) * 0.1


var _light_base := 2.0


func _apply_stage(night: float, dusk: float) -> void:
	var day_col := Color(1.0, 0.96, 0.88)
	var dusk_col := Color(1.0, 0.55, 0.3)
	var night_col := Color(0.35, 0.45, 0.85)
	_sun.light_color = day_col.lerp(dusk_col, dusk).lerp(night_col, night)
	_sun.light_energy = lerpf(lerpf(0.85, 0.8, dusk), 0.25, night)
	_sun.rotation_degrees.x = lerpf(-52.0, -16.0, dusk) + night * -30.0
	_env.ambient_light_color = Color(0.62, 0.7, 0.85).lerp(Color(0.7, 0.5, 0.5), dusk).lerp(Color(0.12, 0.16, 0.34), night)
	_env.ambient_light_energy = lerpf(0.5, 0.4, maxf(dusk, night))
	_env.background_color = Color(0.55, 0.7, 0.85).lerp(Color(0.95, 0.6, 0.4), dusk).lerp(Color(0.05, 0.07, 0.15), night)
	_env.fog_light_color = _env.background_color
	_env.glow_intensity = lerpf(0.5, 1.2, maxf(dusk, night))
	_env.glow_hdr_threshold = lerpf(1.0, 0.7, night)
	_light_base = lerpf(0.5, 4.0, maxf(dusk * 0.6, night))
	for f in _flames:
		f.visible = maxf(dusk, night) > 0.15


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_night"):
		_stage = (_stage + 1) % 3
		var goal: Array = [[0.0, 0.0], [0.0, 1.0], [1.0, 0.0]][_stage]
		if _tween:
			_tween.kill()
		_tween = create_tween()
		_tween.tween_method(func(k: float) -> void: _apply_stage(lerpf(_cur[0], goal[0], k), lerpf(_cur[1], goal[1], k)), 0.0, 1.0, 1.5)
		_tween.finished.connect(func() -> void: _cur = goal)


var _cur := [0.0, 0.0]
