class_name Hd2dWorld
extends Node3D
## Herní svět v HD-2D (styl Octopath). Logika zůstává 2D (postavy žijí v `actors` ve 2D světě), vykreslení je 3D:
## země = vyrenderovaný 2D svět na rovině, props a každá postava = svislý sprite (billboard) se skutečnými stíny,
## kamera nakloněná s perspektivou, 3D světla, glow, mlha, tilt-shift. Osvětlení řídí LightingProfile podle hodiny (set_time).
##
## Postava / předmět / projektil přidaný do `actors` dostane vlastní SubViewport a billboard (viditelnost
## přes samostatnou 2D vrstvu, takže se nevykreslují do země).

signal built

const S := 0.02                       # 1 px = 0.02 m (1 m = 50 px)
const WORLD_DIR := "res://data/world/babrak"
const SIZES := {"character": [192, 70.0], "small": [128, 32.0]}  # [velikost viewportu px, výška středu nad zemí px]
const MAX_LAYERS := 19           # bit 0 = země, bity 1.. = jednotlivé billboardy
const TILT := 44.0                   # náklon spritů k+kameře (°), plný náklon = kolmo na pohled
const UP := Vector3(0, 0.7193, -0.6947)  # směr „nahoru“ naklonného spritu (cos/sin TILT)
const STAGE_HOURS := [12.0, 19.0, 22.0]   # den, soumrak, noc
const HERO_FEET := 70.0               # px nad zemí, kam míří střed kamery hrdinova viewportu

var focus: Node2D                      ## co kamera sleduje (hrdina)
var actors: Node2D                     ## sem patří postavy, předměty a projektily (2D logika)
var start_position := Vector2.ZERO
var tiled: TiledWorld

var _ground_vp: SubViewport
var _cam: Camera3D
var _sun: DirectionalLight3D
var _env: Environment
var _lights: Array[OmniLight3D] = []         # táborák
var _flames: Array[CPUParticles3D] = []
var profile: LightingProfile
var hour := 12.0                       ## denní doba 0–24 (řídí set_time)
var day_length := 0.0                  ## sekundy reálného času na 24 h (0 = čas stojí)
var _stage := 0
var _post: ShaderMaterial
var fx: WorldFx                       ## počasí, nálada oblasti, ambientní život
var weather_cover := 0.0              ## 0 jasno … 1 zataženo (tlumí slunce a paprsky), nastavuje WorldFx
var _ground_mat: ShaderMaterial
var _noise_tex: Texture2D
var _prop_mats: Array = []            # [ShaderMaterial, síla pohupování]
var _glow_cache: Dictionary = {}
var fx_chimneys: Array = []           # [id, pata (px), velikost textury] – komíny pro kouř
var _attr: CameraAttributesPractical
var _cloud_mat: ShaderMaterial
var _contact: MultiMeshInstance3D
var _motes: CPUParticles3D
var _lamps: Array[OmniLight3D] = []
var _cur: Dictionary = {}
var _is_built := false
var _tween: Tween
var _free_layers: Array[int] = []
var _billboards: Dictionary = {}       # Node2D -> [SubViewport, Camera2D, Sprite3D, výška středu]


func _ready() -> void:
	WorldFx.register_globals()
	profile = LightingProfile.load_file()
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
	apply_quality()
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
	fx = WorldFx.new()
	fx.name = "Fx"
	fx.world = self
	add_child(fx)
	_is_built = true
	fx.build()
	for e in fx_chimneys:
		fx.add_chimney(e[0], e[1], e[2])
	for a in actors.get_children():
		_on_actor_added(a)
	set_time(hour)
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
	_attr = attr
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
	_sun.shadow_blur = 1.6
	_sun.light_angular_distance = 0.6          # měkké stíny (Forward+/Mobile)
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
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
	_post = m
	layer.add_child(r)


func _build_ground(rect: Rect2) -> void:
	# vlastní hrdina a props se do země nevykreslují (props jsou ve 3D)
	tiled.objects.visible = false
	_ground_vp.render_target_update_mode = SubViewport.UPDATE_ONCE   # svět je celý načtený; dál se nepřekresluje
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = rect.size * S
	mi.mesh = pm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/ground3d.gdshader")
	mat.set_shader_parameter("ground_tex", _ground_vp.get_texture())
	if ResourceLoader.exists(WorldFx.ZONES_PATH):
		mat.set_shader_parameter("zones_tex", load(WorldFx.ZONES_PATH))
	mat.set_shader_parameter("noise_tex", noise_texture())
	mat.set_shader_parameter("world_size", rect.size * S)
	_ground_mat = mat
	mi.material_override = mat
	mi.position = Vector3(rect.get_center().x * S, 0, rect.get_center().y * S)
	add_child(mi)


func _build_props() -> void:
	var n := 0
	var contacts: Array[Transform3D] = []
	for c in tiled.objects.get_children():
		if not (c is Node2D):
			continue
		var spr: Sprite2D
		for s in c.find_children("*", "Sprite2D", true, false):
			spr = s
			break
		var pid := String(c.get_meta("prop_id", ""))
		if spr and spr.texture:
			var p := Sprite3D.new()
			p.texture = spr.texture
			p.pixel_size = S
			var gp := (c as Node2D).global_position
			var rnd := _hash01(gp)                       # variace: každá instance trochu jiná (zrcadlení, velikost, barva)
			var natural := _sway_of(pid) > 0.0
			p.flip_h = spr.flip_h != (natural and rnd > 0.5)
			var sc := 1.0 + ((rnd * 7.0) - floorf(rnd * 7.0) - 0.5) * 0.16 if natural else 1.0
			p.scale = Vector3(sc, sc, 1.0)
			p.rotation_degrees.x = -TILT
			p.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
			p.alpha_scissor_threshold = 0.5
			p.shaded = true
			p.double_sided = true
			p.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			p.material_override = _prop_material(spr.texture, pid, rnd, natural)
			var h := float(spr.texture.get_height())
			p.position = Vector3(gp.x * S, 0, gp.y * S) + UP * h * 0.5 * S * sc
			var vr: float = profile.quality.get("prop_range", 90.0)
			if natural and h < 90.0:
				p.visibility_range_end = vr * 0.6    # drobnosti se ve dálce vypínají (výkon)
				p.visibility_range_end_margin = 4.0
				p.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			add_child(p)
			n += 1
			if pid.begins_with("v_"):
				fx_chimneys.append([pid, gp, Vector2(spr.texture.get_size())])
		if c.has_meta("shadow_size"):
			var sv: Vector2 = c.get_meta("shadow_size")
			var gp2 := (c as Node2D).global_position
			contacts.append(Transform3D(Basis.from_scale(Vector3(sv.x * S * 1.5, 1.0, sv.y * S * 2.4)), Vector3(gp2.x * S + sv.x * S * 0.1, 0.02, gp2.y * S)))
		if "lampa" in pid and spr and spr.texture:
			var gp3 := (c as Node2D).global_position
			var lamp := OmniLight3D.new()
			lamp.position = Vector3(gp3.x * S, spr.texture.get_height() * S * 0.8, gp3.y * S + 0.3)
			lamp.light_color = Color(1.0, 0.78, 0.45)
			lamp.omni_range = 6.0
			lamp.omni_attenuation = 1.8
			lamp.light_energy = 0.0
			lamp.visible = false
			add_child(lamp)
			_lamps.append(lamp)
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
	_build_contact_shadows(contacts)
	_build_atmosphere()
	print("HD-2D: ", n, " spritů, ", _lamps.size(), " lamp")


## Deterministické „náhodné“ číslo 0–1 z pozice (stejný svět = stejné variace).
func _hash01(p: Vector2) -> float:
	return fposmod(sin(p.x * 12.9898 + p.y * 78.233) * 43758.5453, 1.0)


## Jak moc se objekt pohupuje ve větru (0 = pevný): stromy, keře, tráva, kvítí.
func _sway_of(pid: String) -> float:
	var id := pid.to_lower()
	for k in ["trs", "stéblo", "trav", "kapradí", "kvít", "květ", "kytic", "levand", "růž", "rostlin", "cibul"]:
		if k in id:
			return 1.0
	for k in ["keř", "keří", "plot"]:
		if k in id:
			return 0.55
	for k in ["strom", "smrk", "dub", "akác", "cypř", "koruna", "lián"]:
		if k in id:
			return 0.5
	return 0.0


func _prop_material(tex: Texture2D, pid: String, rnd: float, natural: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/prop3d.gdshader")
	m.set_shader_parameter("tex", tex)
	m.set_shader_parameter("glow_tex", _window_mask(tex, pid))
	_prop_mats.append([m, _sway_of(pid)])
	m.set_shader_parameter("sway", _sway_of(pid) if profile.quality.get("sway", true) else 0.0)
	m.set_shader_parameter("phase", rnd * 40.0)
	var v := (rnd * 13.0) - floorf(rnd * 13.0)
	var t := Vector3(1, 1, 1)
	if natural:   # odstín listí a světlost lehce kolísá
		t = Vector3(0.93 + v * 0.12, 0.95 + (1.0 - v) * 0.08, 0.92 + v * 0.06)
	m.set_shader_parameter("tint", t)
	return m


## Maska svítících oken: modré/tyrkysové sklo v textuře budovy (+ oranžové žhnutí kovárny). Ostatní props = prázdná.
func _window_mask(tex: Texture2D, pid: String) -> Texture2D:
	if _glow_cache.has(tex):
		return _glow_cache[tex]
	var result: Texture2D
	if (pid.begins_with("v_") and not pid.begins_with("v_stanek")) or pid == "g_krypta" or pid == "g_mauzoleum":
		var img := tex.get_image()
		if img.is_compressed():
			img.decompress()
		var out := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_R8)
		var any := false
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				var r := c.r * 255.0
				var g := c.g * 255.0
				var b := c.b * 255.0
				if c.a > 0.78 and b > 115.0 and b > r + 35.0 and g > r + 10.0:
					out.set_pixel(x, y, Color(1, 0, 0))
					any = true
		result = ImageTexture.create_from_image(out) if any else _black_tex()
	else:
		result = _black_tex()
	_glow_cache[tex] = result
	return result


var _black: Texture2D
func _black_tex() -> Texture2D:
	if _black == null:
		var img := Image.create(1, 1, false, Image.FORMAT_R8)
		_black = ImageTexture.create_from_image(img)
	return _black


## Sdílená šumová textura (kanály R/G/B = různé frekvence) pro vodu, louže, mech.
func noise_texture() -> Texture2D:
	if _noise_tex == null:
		var imgs: Array[Image] = []
		for i in 3:
			var n := FastNoiseLite.new()
			n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
			n.frequency = 0.012 + i * 0.006
			n.fractal_octaves = 4
			n.seed = 100 + i * 17
			imgs.append(n.get_seamless_image(256, 256))
		var out := Image.create(256, 256, false, Image.FORMAT_RGB8)
		for y in 256:
			for x in 256:
				out.set_pixel(x, y, Color(imgs[0].get_pixel(x, y).r, imgs[1].get_pixel(x, y).r, imgs[2].get_pixel(x, y).r))
		out.generate_mipmaps()
		_noise_tex = ImageTexture.create_from_image(out)
	return _noise_tex


func set_post_param(name: String, v: Variant) -> void:
	if _post:
		_post.set_shader_parameter(name, v)


## Pozice bodu na zemi (px) → UV na obrazovce (0–1).
func screen_uv_of(px: Vector2) -> Vector2:
	var vs := get_viewport().get_visible_rect().size
	var p := _cam.unproject_position(Vector3(px.x * S, 0.8, px.y * S))
	return Vector2(p.x / vs.x, p.y / vs.y)


## Aktuální síla větru 0–1 (profil + počasí).
func current_wind() -> float:
	return clampf(float(_cur.get("wind", 0.3)) + (fx.wind_add if fx else 0.0), 0.0, 1.0)


func refresh() -> void:
	if _is_built and not _cur.is_empty():
		_apply(_cur)


## Měkké „okluzní“ stíny pod props (falešné AO): jeden MultiMesh, průhledná tmavá skvrna s měkkým okrajem.
func _build_contact_shadows(list: Array[Transform3D]) -> void:
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(0.04, 0.03, 0.09, 0.62), Color(0.04, 0.03, 0.09, 0.0)])
	g.offsets = PackedFloat32Array([0.0, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = tex
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var q := QuadMesh.new()
	q.orientation = PlaneMesh.FACE_Y
	q.size = Vector2.ONE
	q.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = q
	mm.instance_count = list.size()
	for i in list.size():
		mm.set_instance_transform(i, list[i])
	_contact = MultiMeshInstance3D.new()
	_contact.multimesh = mm
	_contact.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_contact)
	_contact.visible = profile.quality.contact_shadows


## Stíny plovoucích mraků po zemi a poletující prach / světlušky kolem hrdiny.
func _build_atmosphere() -> void:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.01
	noise.fractal_octaves = 3
	var nt := NoiseTexture2D.new()
	nt.noise = noise
	nt.seamless = true
	nt.width = 512
	nt.height = 512
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/cloud_shadow3d.gdshader")
	sm.set_shader_parameter("noise_tex", nt)
	sm.set_shader_parameter("strength", 0.0)
	_cloud_mat = sm
	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = tiled.bounds_px.size * S
	plane.mesh = pm
	plane.material_override = sm
	plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plane.position = Vector3(tiled.bounds_px.get_center().x * S, 0.04, tiled.bounds_px.get_center().y * S)
	add_child(plane)
	_motes = CPUParticles3D.new()
	_motes.amount = 90
	_motes.lifetime = 7.0
	_motes.preprocess = 7.0
	_motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_motes.emission_box_extents = Vector3(14, 2.5, 10)
	_motes.direction = Vector3(0.3, 0.2, 0.1)
	_motes.spread = 180.0
	_motes.initial_velocity_min = 0.05
	_motes.initial_velocity_max = 0.35
	_motes.gravity = Vector3.ZERO
	_motes.scale_amount_min = 0.5
	_motes.scale_amount_max = 1.3
	var mq := QuadMesh.new()
	mq.size = Vector2(0.07, 0.07)
	var mm2 := StandardMaterial3D.new()
	mm2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm2.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mm2.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mm2.albedo_color = Color(1.0, 0.95, 0.55, 0.9)
	mm2.vertex_color_use_as_albedo = false
	mq.material = mm2
	_motes.mesh = mq
	_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_motes)
	_apply(_cur if not _cur.is_empty() else profile.sample(hour))


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
	if day_length > 0.0:
		set_time(hour + delta * 24.0 / day_length)
	var t := Time.get_ticks_msec() / 1000.0
	var fire: float = _cur.get("fire_energy", 2.0)
	for o in _lights:
		o.light_energy = fire * (1.0 + 0.12 * sin(t * 17.0) * sin(t * 6.3))
	if _motes and focus:
		_motes.position = Vector3(focus.global_position.x * S, 1.6, focus.global_position.y * S)


## Nastaví denní dobu (0–24 h) a promítne ji do světel, prostředí a post-processingu.
func set_time(h: float) -> void:
	hour = fposmod(h, 24.0)
	_cur = profile.sample(hour)
	_apply(_cur)


func _apply(v: Dictionary) -> void:
	var cover: float = fx.cover if fx else 0.0
	weather_cover = cover
	var wet: float = maxf(v.wetness, fx.wet if fx else 0.0)
	var wind: float = current_wind()
	_sun.light_color = (v.sun_color as Color).lerp(Color(0.72, 0.78, 0.9), cover * 0.8)
	_sun.light_energy = v.sun_energy * (1.0 - 0.65 * cover)
	_sun.shadow_opacity = v.shadow_opacity
	_sun.rotation_degrees = Vector3(-v.sun_elev, v.sun_azim, 0.0)
	_env.ambient_light_color = v.ambient_color
	_env.ambient_light_energy = v.ambient_energy * (1.0 + 0.2 * cover)
	_env.background_color = v.sky_color
	_env.fog_light_color = (v.fog_color as Color).lerp(Color(0.6, 0.64, 0.7) * clampf(v.ambient_energy + 0.3, 0.3, 1.0), cover * 0.6)
	_env.fog_density = v.fog_density + (fx.fog_add if fx else 0.0)
	_env.glow_intensity = v.glow_intensity
	_env.glow_hdr_threshold = v.glow_threshold
	var night: float = clampf(v.lamp_energy / 3.0, 0.0, 1.0)
	for f in _flames:
		f.visible = night > 0.12
	for l in _lamps:
		l.light_energy = v.lamp_energy
		l.visible = v.lamp_energy > 0.05
	RenderingServer.global_shader_parameter_set("fx_glow", v.window_glow)
	RenderingServer.global_shader_parameter_set("fx_wind", wind)
	if _ground_mat:
		_ground_mat.set_shader_parameter("sky_color", (v.sky_color as Color).lerp(v.fog_color, 0.4) * clampf(0.5 + v.ambient_energy, 0.4, 1.4))
		_ground_mat.set_shader_parameter("sun_color", v.sun_color)
		_ground_mat.set_shader_parameter("sun_power", v.sun_energy * (1.0 - cover))
		_ground_mat.set_shader_parameter("wetness", wet)
		_ground_mat.set_shader_parameter("rain", fx.rain if fx else 0.0)
		_ground_mat.set_shader_parameter("snow", fx.snow if fx else 0.0)
	if _cloud_mat:
		_cloud_mat.set_shader_parameter("strength", v.cloud_shadow * (1.0 - cover * 0.8))
	if _motes:
		(_motes.mesh.material as StandardMaterial3D).albedo_color.a = clampf(v.fireflies, 0.0, 1.0)
		_motes.emitting = v.fireflies > 0.02
	if _post:
		_post.set_shader_parameter("tilt_px", v.tilt_px)
		_post.set_shader_parameter("tilt_width", v.tilt_width)
		_post.set_shader_parameter("bloom_strength", v.bloom)
		_post.set_shader_parameter("saturation", v.saturation * (1.0 - 0.3 * cover))
		_post.set_shader_parameter("contrast", v.contrast)
		_post.set_shader_parameter("gain", (v.gain as Color).lerp(Color(0.85, 0.9, 1.0), cover * 0.75))
		_post.set_shader_parameter("shadow_tint", v.shadow_tint)
		_post.set_shader_parameter("vignette", v.vignette)
		_post.set_shader_parameter("grain", v.grain)
		_post.set_shader_parameter("chroma", v.chroma)
		_post.set_shader_parameter("shafts", v.shafts * (1.0 if profile.quality.get("shafts", true) else 0.0) * (1.0 - weather_cover))
		_post.set_shader_parameter("shaft_color", v.sun_color)
		_post.set_shader_parameter("sun_uv", Vector2(0.5 + 0.55 * sin(deg_to_rad(v.sun_azim)), -0.4))
		_post.set_shader_parameter("lut_mix", v.lut_mix if _post.get_shader_parameter("lut_a") else 0.0)


## Kvalita a efekty z profile.quality (SSAO, DOF, objemová mlha, vzdálenost stínů, kontaktní stíny).
func apply_quality() -> void:
	var q := profile.quality
	_env.ssao_enabled = q.ssao
	_env.ssao_radius = q.ssao_radius
	_env.ssao_intensity = q.ssao_intensity
	_env.ssil_enabled = q.get("ssil", false)
	_env.volumetric_fog_enabled = q.volumetric_fog
	_env.volumetric_fog_density = q.volumetric_density
	_attr.dof_blur_far_enabled = q.dof
	_attr.dof_blur_near_enabled = q.dof
	_attr.dof_blur_amount = q.dof_amount
	_sun.directional_shadow_max_distance = q.shadow_distance
	for e in _prop_mats:
		(e[0] as ShaderMaterial).set_shader_parameter("sway", e[1] if q.get("sway", true) else 0.0)
	_sun.shadow_blur = 1.6 if q.shadow_distance > 40.0 else 0.8
	if _contact:
		_contact.visible = q.contact_shadows
	if fx:
		fx.apply_quality()


## Plynulý přechod na denní dobu `to` (vždy dopředu, přes půlnoc), nebo hned.
func transition_to(to: float, instant := false, duration := 1.6) -> void:
	if _tween:
		_tween.kill()
	if instant:
		set_time(to)
		return
	var from := hour
	var goal := to if to >= from else to + 24.0
	_tween = create_tween()
	_tween.tween_method(set_time, from, goal, duration)


## Okamžitě přesune kameru na sledovaný cíl (po teleportu).
func snap_camera() -> void:
	if focus:
		var hp := focus.global_position
		_cam.position = Vector3(hp.x * S, 0.6, hp.y * S) + Vector3(0, 17.0, 14.0)


func set_stage(stage: int, instant := false) -> void:
	_stage = stage
	transition_to(STAGE_HOURS[stage], instant)


func cycle_stage() -> void:
	set_stage((_stage + 1) % 3)
