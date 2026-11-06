class_name Hd2dWorld
extends Node3D
## Herní svět v HD-2D (styl Octopath). Logika zůstává 2D (postavy žijí v `actors` ve 2D světě), vykreslení je 3D:
## země = vyrenderovaný 2D svět na rovině, props a každá postava = svislý sprite (billboard) se skutečnými stíny,
## kamera nakloněná s perspektivou, 3D světla, glow, mlha, tilt-shift. Dny: 0 den, 1 soumrak, 2 noc.
##
## Postava / předmět / projektil přidaný do `actors` dostane vlastní SubViewport a billboard (viditelnost
## přes samostatnou 2D vrstvu, takže se nevykreslují do země).

signal built

const S := 0.02                       # 1 px = 0.02 m (1 m = 50 px)
const WORLD_DIR := "res://data/world/palouk"
const SIZES := {"character": [192, 70.0], "small": [128, 32.0]}  # [velikost viewportu px, výška středu nad zemí px]
const MAX_LAYERS := 19           # bit 0 = země, bity 1.. = jednotlivé billboardy
const TILT := 44.0                   # náklon spritů k+kameře (°), plný náklon = kolmo na pohled
const UP := Vector3(0, 0.7193, -0.6947)  # směr „nahoru“ naklonného spritu (cos/sin TILT)
const HERO_FEET := 70.0               # px nad zemí, kam míří střed kamery hrdinova viewportu

var focus: Node2D                      ## co kamera sleduje (hrdina)
var actors: Node2D                     ## sem patří postavy, předměty a projektily (2D logika)
var start_position := Vector2.ZERO
var tiled: TiledWorld

var _ground_vp: SubViewport
var _cam: Camera3D
var _sun: DirectionalLight3D
var _env: Environment
var _lights: Array[OmniLight3D] = []
var _flames: Array[CPUParticles3D] = []
var _stage := 0
var _cur := [0.0, 0.0]
var _light_base := 2.0
var _is_built := false
var _tween: Tween
var _free_layers: Array[int] = []
var _billboards: Dictionary = {}       # Node2D -> [SubViewport, Camera2D, Sprite3D, výška středu]


func _ready() -> void:
	for i in range(MAX_LAYERS, 0, -1):
		_free_layers.append(i)
	_ground_vp = SubViewport.new()
	_ground_vp.canvas_cull_mask = 1
	_ground_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_ground_vp)
	var root2d := Node2D.new()
	_ground_vp.add_child(root2d)
	root2d.visibility_layer = 0xFFFFF   # kořen sám nic nekreslí; vrstvy řeší potomci (cull maska platí i pro podstrom)
	tiled = TiledWorld.new()
	tiled.world_dir = WORLD_DIR
	tiled.load_radius = 8
	var center := Node2D.new()
	root2d.add_child(center)
	tiled.focus = center
	root2d.add_child(tiled)
	actors = Node2D.new()
	actors.name = "Actors"
	actors.visibility_layer = 0xFFFFF   # sám nic nekreslí; potomci se řídí vlastní vrstvou
	actors.child_entered_tree.connect(_on_actor_added)
	root2d.add_child(actors)
	_build_environment()
	await _wait_world()
	var rect := tiled.bounds_px
	center.position = rect.get_center()
	start_position = tiled.start_position
	_ground_vp.size = Vector2i(rect.size)
	var gcam := Camera2D.new()
	gcam.position = rect.get_center()
	_ground_vp.add_child(gcam)
	_build_ground(rect)
	_build_props()
	_is_built = true
	for a in actors.get_children():
		_on_actor_added(a)
	_apply_stage(0.0, 0.0)
	built.emit()


func _wait_world() -> void:
	for _i in 900:
		await get_tree().process_frame
		if tiled.all_ready() and tiled.shown_chunks().size() > 0:
			for _j in 4:
				await get_tree().process_frame
			if tiled.all_ready():
				return


# ---------- postavy a předměty jako billboardy ----------

func add_actor(n: Node2D, pos: Vector2) -> void:
	n.position = pos
	actors.add_child(n)


func _on_actor_added(n: Node) -> void:
	if not _is_built or not (n is Node2D) or _billboards.has(n):
		return
	var kind := "character" if n is Character else "small"
	var layer_bit: int = 1 << _free_layers.pop_back()
	_watch(n, layer_bit)
	var size: int = SIZES[kind][0]
	var lift: float = SIZES[kind][1]
	var vp := SubViewport.new()
	vp.size = Vector2i(size, size)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.world_2d = _ground_vp.world_2d
	vp.canvas_cull_mask = layer_bit
	var cam := Camera2D.new()
	vp.add_child(cam)
	add_child(vp)
	var spr := Sprite3D.new()
	spr.texture = vp.get_texture()
	spr.pixel_size = S
	spr.rotation_degrees.x = -TILT
	spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	spr.alpha_scissor_threshold = 0.4
	spr.shaded = true
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	add_child(spr)
	_billboards[n] = [vp, cam, spr, lift, layer_bit]
	n.tree_exiting.connect(_remove_billboard.bind(n))


func _remove_billboard(n: Node) -> void:
	var b: Array = _billboards.get(n, [])
	if b.is_empty():
		return
	_billboards.erase(n)
	_free_layers.append(int(log(b[4]) / log(2.0) + 0.5))
	b[0].queue_free()
	b[2].queue_free()


## Nastaví vrstvu viditelnosti celému podstromu, i potomkům přidaným později (sprity se vytvářejí až v _ready).
func _watch(n: Node, layer: int) -> void:
	if n is CanvasItem:
		(n as CanvasItem).visibility_layer = layer
	var cb := _watch.bind(layer)
	if not n.child_entered_tree.is_connected(cb):
		n.child_entered_tree.connect(cb)
	for c in n.get_children():
		_watch(c, layer)


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
	layer.layer = -1   # pod HUD, nad 3D
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


func _build_ground(rect: Rect2) -> void:
	# vlastní hrdina a props se do země nevykreslují (props jsou ve 3D)
	tiled.objects.visible = false
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
	for c in tiled.objects.get_children():
		if not (c is Node2D):
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
	if not _is_built:
		return
	for n: Node2D in _billboards:
		var b: Array = _billboards[n]
		var gp := n.global_position
		(b[1] as Camera2D).position = gp + Vector2(0, -b[3])
		(b[2] as Sprite3D).position = Vector3(gp.x * S, 0, gp.y * S) + UP * b[3] * S
	if focus:
		var hp := focus.global_position
		var target := Vector3(hp.x * S, 0.6, hp.y * S)
		var offs := Vector3(0, 17.0, 14.0)
		_cam.position = _cam.position.lerp(target + offs, clampf(delta * 5.0, 0.0, 1.0))
		_cam.look_at(_cam.position - offs)
	var t := Time.get_ticks_msec() / 1000.0
	for o in _lights:
		o.light_energy = o.light_energy * 0.9 + (_light_base * (1.0 + 0.12 * sin(t * 17.0) * sin(t * 6.3))) * 0.1


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

## Nastaví denní dobu (0 den, 1 soumrak, 2 noc); plynule, nebo hned.
func set_stage(stage: int, instant := false) -> void:
	_stage = stage
	var goal: Array = [[0.0, 0.0], [0.0, 1.0], [1.0, 0.0]][stage]
	if _tween:
		_tween.kill()
	if instant:
		_cur = goal
		_apply_stage(goal[0], goal[1])
		return
	var from := _cur
	_tween = create_tween()
	_tween.tween_method(func(k: float) -> void: _apply_stage(lerpf(from[0], goal[0], k), lerpf(from[1], goal[1], k)), 0.0, 1.0, 1.5)
	_tween.finished.connect(func() -> void: _cur = goal)


func cycle_stage() -> void:
	set_stage((_stage + 1) % 3)
