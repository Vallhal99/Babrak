class_name WorldFx
extends Node3D
## Atmosféra a „život“ HD-2D světa nad rámec denní doby (ta je v LightingProfile):
##   • počasí (jasno / zataženo / déšť / bouřka / sníh / mlha) – částice, mokro, sníh, vítr, blesky
##   • barevná nálada oblasti (LUT podle polohy hrdiny, plynulý přechod)
##   • zaostření při dialogu (okolí postavy se rozostří)
##   • ambientní život: ptáci, motýli, padající listí, kouř z komínů, kruhy od ryb, stopy v zemi
##   • rozmazané listí v popředí v lese (paralaxa)
## Hodnoty počasí čte Hd2dWorld._apply (cover, fog_add, wet, rain, snow, wind_add).

const S := Hd2dWorld.S
const TILE_PX := 24.0
const MOODS := ["neutral", "forest", "village", "graveyard", "mountain", "water"]
const ZONES_PATH := "res://data/world/babrak/zones.png"

## cover, fog (přídavek hustoty mlhy), wet, rain, snow, wind (přídavek), bouřka
const WEATHER := {
	"jasno": {"cover": 0.0, "fog": 0.0, "wet": 0.0, "rain": 0.0, "snow": 0.0, "wind": 0.0, "storm": false},
	"zataženo": {"cover": 0.6, "fog": 0.002, "wet": 0.0, "rain": 0.0, "snow": 0.0, "wind": 0.15, "storm": false},
	"déšť": {"cover": 0.7, "fog": 0.004, "wet": 1.0, "rain": 0.55, "snow": 0.0, "wind": 0.25, "storm": false},
	"bouřka": {"cover": 0.92, "fog": 0.006, "wet": 1.0, "rain": 1.0, "snow": 0.0, "wind": 0.75, "storm": true},
	"sníh": {"cover": 0.5, "fog": 0.003, "wet": 0.0, "rain": 0.0, "snow": 1.0, "wind": 0.1, "storm": false},
	"mlha": {"cover": 0.45, "fog": 0.012, "wet": 0.25, "rain": 0.0, "snow": 0.0, "wind": 0.05, "storm": false},
}
const WEATHER_ORDER := ["jasno", "zataženo", "déšť", "bouřka", "sníh", "mlha"]

var world: Hd2dWorld
var weather := "jasno"
# aktuální (plynule dohánějí cíl)
var cover := 0.0
var fog_add := 0.0
var wet := 0.0
var rain := 0.0
var snow := 0.0
var wind_add := 0.0
var mood := "neutral"                 ## aktuální nálada oblasti pod hrdinou
var ui_nodes: Array = []              ## panely (mají `visible`), při jejichž otevření se zaostří na postavu

var _rain: CPUParticles3D
var _snow: CPUParticles3D
var _leaves: CPUParticles3D
var _zones: Image
var _luts := {}
var _lut_to := "neutral"
var _lut_blend := 0.0
var _mood_timer := 0.0
var _flash := 0.0
var _storm_timer := 5.0
var _focus_amt := 0.0
var _print_pool: Array[MeshInstance3D] = []
var _print_i := 0
var _last_print := Vector2.INF
var _print_side := 1.0
var _birds: Array[Sprite3D] = []
var _butterflies: Array = []          # [Sprite3D, fáze, střed]
var _fish_timer := 3.0
var _fg: CanvasLayer
var _fg_items: Array[TextureRect] = []
var _fg_alpha := 0.0
var _smokes: Array[CPUParticles3D] = []
var _time := 0.0


## Globální shader parametry (props shader je čte) – musí existovat dřív, než se shader zkompiluje.
static var _globals_done := false


static func register_globals() -> void:
	if _globals_done:
		return
	_globals_done = true
	for n in ["fx_wind", "fx_wet", "fx_snow", "fx_glow"]:
		RenderingServer.global_shader_parameter_add(n, RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)


func build() -> void:
	var q := world.profile.quality
	_zones = load(ZONES_PATH).get_image() if ResourceLoader.exists(ZONES_PATH) else null
	for m in MOODS:
		var p := "res://data/lut/%s.png" % (m if m != "water" else "water")
		if ResourceLoader.exists(p):
			_luts[m] = load(p)
	_set_lut("lut_a", "neutral")
	_set_lut("lut_b", "neutral")
	_build_precip()
	_build_footprints()
	_build_life()
	_build_foreground()
	apply_quality()


func apply_quality() -> void:
	var q := world.profile.quality
	var k: float = q.get("particles", 1.0)
	_rain.amount = int(700 * k) + 20
	_snow.amount = int(450 * k) + 20
	_leaves.amount = int(36 * k) + 4
	var life: bool = q.get("ambient_life", true)
	for b in _birds:
		b.set_meta("on", life)
	for s in _smokes:
		s.amount = int(14 * k) + 3
	_fg.visible = q.get("foreground", true)


# ───────────────────────────── počasí ─────────────────────────────

func set_weather(name: String) -> void:
	if WEATHER.has(name):
		weather = name


func cycle_weather() -> String:
	weather = WEATHER_ORDER[(WEATHER_ORDER.find(weather) + 1) % WEATHER_ORDER.size()]
	return weather


func _build_precip() -> void:
	_rain = CPUParticles3D.new()
	_rain.lifetime = 0.7
	_rain.preprocess = 0.7
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(13, 0.1, 10)
	_rain.direction = Vector3(-0.12, -1, 0.05)
	_rain.spread = 2.0
	_rain.initial_velocity_min = 15.0
	_rain.initial_velocity_max = 18.0
	_rain.gravity = Vector3.ZERO
	var q := QuadMesh.new()
	q.size = Vector2(0.012, 0.42)
	q.material = _particle_mat(Color(0.75, 0.85, 1.0, 0.0), BaseMaterial3D.BILLBOARD_FIXED_Y)
	_rain.mesh = q
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain.emitting = false
	add_child(_rain)

	_snow = CPUParticles3D.new()
	_snow.lifetime = 7.0
	_snow.preprocess = 7.0
	_snow.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_snow.emission_box_extents = Vector3(14, 0.1, 11)
	_snow.direction = Vector3(0.25, -1, 0.1)
	_snow.spread = 20.0
	_snow.initial_velocity_min = 0.9
	_snow.initial_velocity_max = 1.6
	_snow.gravity = Vector3.ZERO
	_snow.scale_amount_min = 0.6
	_snow.scale_amount_max = 1.4
	var sq := QuadMesh.new()
	sq.size = Vector2(0.055, 0.055)
	sq.material = _particle_mat(Color(1, 1, 1, 0.0), BaseMaterial3D.BILLBOARD_PARTICLES)
	_snow.mesh = sq
	_snow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_snow.emitting = false
	add_child(_snow)


func _particle_mat(c: Color, bb: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = bb as BaseMaterial3D.BillboardMode
	m.albedo_color = c
	m.no_depth_test = false
	return m


func _update_weather(delta: float) -> void:
	var w: Dictionary = WEATHER[weather]
	var r := clampf(delta * 0.35, 0.0, 1.0)
	cover = lerpf(cover, w.cover, r)
	fog_add = lerpf(fog_add, w.fog, r)
	wet = lerpf(wet, w.wet, clampf(delta * (0.25 if w.wet > wet else 0.05), 0.0, 1.0))   # louže vysychají pomaleji
	rain = lerpf(rain, w.rain, r)
	snow = lerpf(snow, w.snow, clampf(delta * 0.2, 0.0, 1.0))
	wind_add = lerpf(wind_add, w.wind, r)
	var cam_pos := world.focus.global_position * S if world.focus else Vector2.ZERO
	var follow := Vector3(cam_pos.x, 0.0, cam_pos.y)
	_rain.position = follow + Vector3(0, 9, 0)
	_snow.position = follow + Vector3(0, 8, 0)
	var rm := _rain.mesh.material as StandardMaterial3D
	rm.albedo_color.a = clampf(rain * 0.4, 0.0, 0.5)
	_rain.emitting = rain > 0.04
	(_snow.mesh.material as StandardMaterial3D).albedo_color.a = clampf(snow, 0.0, 0.9)
	_snow.emitting = snow > 0.04
	_rain.direction = Vector3(-0.12 - wind_add * 0.3, -1, 0.05)
	_snow.direction = Vector3(0.25 + wind_add * 1.5, -1, 0.1)
	RenderingServer.global_shader_parameter_set("fx_wet", wet)
	RenderingServer.global_shader_parameter_set("fx_snow", snow)
	# bouřka: nepravidelné blesky
	if w.storm:
		_storm_timer -= delta
		if _storm_timer <= 0.0:
			_storm_timer = randf_range(4.0, 11.0)
			_lightning()
	_flash = maxf(_flash - delta * 2.6, 0.0)


func _lightning() -> void:
	var tw := create_tween()
	tw.tween_property(self, "_flash", 0.85, 0.04)
	tw.tween_property(self, "_flash", 0.2, 0.08)
	tw.tween_property(self, "_flash", 0.7, 0.04)
	tw.tween_property(self, "_flash", 0.0, 0.5)


# ───────────────────────── nálada oblasti (LUT) ─────────────────────────

func _set_lut(param: String, m: String) -> void:
	if _luts.has(m):
		world.set_post_param(param, _luts[m])


## Nálada oblasti pod pozicí (px): podle masky zones.png (voda má přednost).
func mood_at(px: Vector2) -> String:
	if _zones == null:
		return "neutral"
	var o := world.tiled.bounds_px.position
	var t := Vector2i(((px - o) / TILE_PX).floor())
	if t.x < 0 or t.y < 0 or t.x >= _zones.get_width() or t.y >= _zones.get_height():
		return "neutral"
	var c := _zones.get_pixelv(t)
	if c.r > 0.4:
		return "water"
	return MOODS[clampi(int(roundf(c.g * 255.0 / 50.0)), 0, 4)]


func is_water_at(px: Vector2) -> bool:
	if _zones == null:
		return false
	var t := Vector2i(((px - world.tiled.bounds_px.position) / TILE_PX).floor())
	if t.x < 0 or t.y < 0 or t.x >= _zones.get_width() or t.y >= _zones.get_height():
		return false
	return _zones.get_pixelv(t).r > 0.4


func _update_mood(delta: float) -> void:
	_mood_timer -= delta
	if _mood_timer <= 0.0 and world.focus:
		_mood_timer = 0.3
		mood = mood_at(world.focus.global_position)
		if mood != _lut_to:
			if _lut_blend > 0.0:                      # rozpracovaný přechod: A převezme cíl (drobný skok)
				_a_name = _lut_to
				_set_lut("lut_a", _a_name)
				_lut_blend = 0.0
			_lut_to = mood
			_set_lut("lut_b", mood)
	if _lut_to != _a_name:
		_lut_blend = move_toward(_lut_blend, 1.0, delta * 0.45)
		if _lut_blend >= 1.0:
			_a_name = _lut_to
			_set_lut("lut_a", _a_name)
			_lut_blend = 0.0
	world.set_post_param("lut_blend", _lut_blend)
	_leaves.emitting = (mood == "forest") and world.profile.quality.get("ambient_life", true) and rain < 0.3
	_fg_alpha = move_toward(_fg_alpha, 0.55 if mood == "forest" else 0.0, delta * 0.5)


var _a_name := "neutral"


# ───────────────────────── zaostření při dialogu ─────────────────────────

func _update_focus(delta: float) -> void:
	var on := false
	for n in ui_nodes:
		if is_instance_valid(n) and n.get(&"visible"):
			on = true
	_focus_amt = move_toward(_focus_amt, 1.0 if on else 0.0, delta * 2.5)
	world.set_post_param("focus_amount", _focus_amt)
	if world.focus:
		world.set_post_param("focus_uv", world.screen_uv_of(world.focus.global_position))


# ───────────────────────── stopy v zemi ─────────────────────────

func _build_footprints() -> void:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# otisk boty: protáhlá elipsa + patka
	for y in 32:
		for x in 32:
			var p := Vector2(x - 15.5, y - 15.5)
			var a := (1.0 - clampf((Vector2(p.x / 6.5, (p.y - 3.0) / 11.0)).length(), 0.0, 1.0))
			var b := (1.0 - clampf((Vector2(p.x / 5.5, (p.y + 11.0) / 4.5)).length(), 0.0, 1.0))
			var v := clampf(maxf(a, b) * 2.2, 0.0, 1.0)
			img.set_pixel(x, y, Color(0.08, 0.06, 0.05, v * 0.55))
	var tex := ImageTexture.create_from_image(img)
	var qm := QuadMesh.new()
	qm.orientation = PlaneMesh.FACE_Y
	qm.size = Vector2(0.17, 0.26)
	for i in 36:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_texture = tex
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		var mi := MeshInstance3D.new()
		mi.mesh = qm
		mi.material_override = m
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.set_meta("age", 99.0)
		add_child(mi)
		_print_pool.append(mi)


func _update_footprints(delta: float) -> void:
	for mi in _print_pool:
		if mi.visible:
			var age: float = mi.get_meta("age") + delta
			mi.set_meta("age", age)
			var life := 9.0 + wet * 6.0
			var a := clampf(1.0 - age / life, 0.0, 1.0)
			var m := mi.material_override as StandardMaterial3D
			m.albedo_color = Color(1, 1, 1, a * (0.5 + wet * 0.4))
			if age > life:
				mi.visible = false
	if world.focus == null:
		return
	var gp: Vector2 = world.focus.global_position
	if _last_print == Vector2.INF:
		_last_print = gp
	var d := gp - _last_print
	if d.length() > 15.0 and not is_water_at(gp):
		var mi := _print_pool[_print_i]
		_print_i = (_print_i + 1) % _print_pool.size()
		var dir := d.normalized()
		_print_side = -_print_side
		var side := Vector2(-dir.y, dir.x) * 3.5 * _print_side
		var pos := gp + side
		mi.position = Vector3(pos.x * S, 0.045, pos.y * S)
		mi.rotation.y = atan2(-dir.x, -dir.y) + PI
		mi.visible = true
		mi.set_meta("age", 0.0)
		(mi.material_override as StandardMaterial3D).albedo_color = Color(1, 1, 1, 0.6)
		_last_print = gp


# ───────────────────────── ambientní život ─────────────────────────

func _build_life() -> void:
	# ptáci: tmavé „V“ siluety, mávání křídel = natahování sprite
	var bt := _bird_texture()
	for i in 7:
		var s := Sprite3D.new()
		s.texture = bt
		s.pixel_size = 0.012
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.shaded = false
		s.modulate = Color(0.1, 0.1, 0.12, 0.9)
		s.visible = false
		s.set_meta("vel", Vector3.ZERO)
		s.set_meta("ph", randf() * 6.28)
		add_child(s)
		_birds.append(s)
	# motýli
	var bf := _butterfly_texture()
	var cols := [Color(1, 0.75, 0.2), Color(0.95, 0.95, 1.0), Color(0.5, 0.75, 1.0), Color(1, 0.55, 0.7)]
	for i in 8:
		var s := Sprite3D.new()
		s.texture = bf
		s.pixel_size = 0.012
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.shaded = false
		s.modulate = cols[i % cols.size()]
		s.visible = false
		add_child(s)
		_butterflies.append([s, randf() * 100.0, Vector3.ZERO])
	# padající listí
	_leaves = CPUParticles3D.new()
	_leaves.lifetime = 9.0
	_leaves.preprocess = 9.0
	_leaves.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_leaves.emission_box_extents = Vector3(13, 0.2, 10)
	_leaves.direction = Vector3(0.3, -1, 0.2)
	_leaves.spread = 25.0
	_leaves.initial_velocity_min = 0.35
	_leaves.initial_velocity_max = 0.8
	_leaves.gravity = Vector3(0.1, -0.15, 0.0)
	_leaves.angle_min = 0.0
	_leaves.angle_max = 360.0
	_leaves.angular_velocity_min = -90.0
	_leaves.angular_velocity_max = 90.0
	_leaves.color_initial_ramp = _leaf_ramp()
	var lq := QuadMesh.new()
	lq.size = Vector2(0.09, 0.06)
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	lm.vertex_color_use_as_albedo = true
	lq.material = lm
	_leaves.mesh = lq
	_leaves.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_leaves.emitting = false
	add_child(_leaves)


func _leaf_ramp() -> Gradient:
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(0.75, 0.5, 0.15), Color(0.55, 0.6, 0.2), Color(0.7, 0.3, 0.12), Color(0.4, 0.5, 0.15)])
	g.offsets = PackedFloat32Array([0.0, 0.35, 0.7, 1.0])
	return g


func _bird_texture() -> Texture2D:
	var img := Image.create(32, 16, false, Image.FORMAT_RGBA8)
	for x in 32:
		var dx := absf(x - 15.5) / 15.5
		var y := int(4.0 + (1.0 - dx) * -0.0 + dx * 7.0 * (1.0 - dx * 0.2))
		for t in 2:
			img.set_pixel(x, clampi(y + t, 0, 15), Color.WHITE)
	return ImageTexture.create_from_image(img)


func _butterfly_texture() -> Texture2D:
	var img := Image.create(16, 12, false, Image.FORMAT_RGBA8)
	for y in 12:
		for x in 16:
			var p := Vector2(absf(x - 7.5), y - 5.5)
			var wing := (Vector2(p.x - 4.0, p.y * 0.8)).length() < 4.2
			if wing:
				img.set_pixel(x, y, Color.WHITE)
			elif p.x < 0.8 and absf(p.y) < 3.5:
				img.set_pixel(x, y, Color(0.15, 0.1, 0.1))
	return ImageTexture.create_from_image(img)


## Komíny: kouř z vybraných domů. `p` = pozice spritu (střed paty), size = rozměr textury v px.
func add_chimney(id: String, foot: Vector2, size: Vector2) -> void:
	var rel := {"v_dum_cihla_a": Vector2(0.46, 0.04), "v_dum_vysoky": Vector2(0.57, 0.02), "v_dum_hodiny": Vector2(0.1, 0.16),
		"v_hostinec": Vector2(0.45, 0.06), "v_kovarna": Vector2(0.18, 0.06), "v_dum_cerveny": Vector2(0.55, 0.05)}
	if not rel.has(id):
		return
	var r: Vector2 = rel[id]
	var p := CPUParticles3D.new()
	p.position = Vector3((foot.x - size.x * 0.5 + size.x * r.x) * S, size.y * (1.0 - r.y) * S * 0.78, foot.y * S + 0.1)
	p.amount = 14
	p.lifetime = 4.5
	p.preprocess = 4.5
	p.direction = Vector3(0.25, 1, 0)
	p.spread = 8.0
	p.initial_velocity_min = 0.45
	p.initial_velocity_max = 0.7
	p.gravity = Vector3(0.12, 0.05, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.0
	p.scale_amount_curve = _grow_curve()
	var sq := QuadMesh.new()
	sq.size = Vector2(0.4, 0.4)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_dot()
	sq.material = m
	p.mesh = sq
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(0.75, 0.75, 0.78, 0.0), Color(0.7, 0.7, 0.74, 0.34), Color(0.65, 0.65, 0.7, 0.0)])
	g.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	p.color_ramp = g
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	_smokes.append(p)


func _grow_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0, 0.3))
	c.add_point(Vector2(1, 1.6))
	return c


var _soft_tex: Texture2D
func _soft_dot() -> Texture2D:
	if _soft_tex == null:
		var gt := GradientTexture2D.new()
		var g := Gradient.new()
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		gt.width = 64
		gt.height = 64
		_soft_tex = gt
	return _soft_tex


func _update_life(delta: float) -> void:
	var q := world.profile.quality
	if world.focus == null or not q.get("ambient_life", true):
		for b in _birds:
			b.visible = false
		for bf in _butterflies:
			(bf[0] as Sprite3D).visible = false
		return
	var hp: Vector2 = world.focus.global_position
	var hero3 := Vector3(hp.x * S, 0.0, hp.y * S)
	var h := world.hour
	var day := h > 6.0 and h < 18.5
	var calm := rain < 0.2 and snow < 0.2 and cover < 0.75
	# ptáci přelétají vysoko nad hrdinou
	for b in _birds:
		var vel: Vector3 = b.get_meta("vel")
		if vel == Vector3.ZERO or (b.position - hero3).length() > 34.0:
			var ang := randf() * TAU
			vel = Vector3(cos(ang), 0, sin(ang)) * randf_range(2.5, 4.0)
			b.position = hero3 - vel.normalized() * 28.0 + Vector3(randf_range(-8, 8), randf_range(7.0, 11.0), randf_range(-8, 8))
			b.set_meta("vel", vel)
		b.position += vel * delta
		b.position.y += sin(_time * 1.3 + b.get_meta("ph")) * delta * 0.4
		var flap := sin(_time * 9.0 + b.get_meta("ph"))
		b.scale = Vector3(1.0, 0.55 + 0.45 * flap, 1.0)
		b.visible = day and calm
	# motýli poletují nad loukou
	var meadow := (mood == "neutral" or mood == "village") and day and calm and not is_water_at(hp) and h > 8.0
	for e in _butterflies:
		var s: Sprite3D = e[0]
		s.visible = meadow
		if not meadow:
			continue
		var ph: float = e[1]
		var c: Vector3 = e[2]
		if c == Vector3.ZERO or (c - hero3).length() > 14.0:
			c = hero3 + Vector3(randf_range(-9, 9), 0, randf_range(-6, 6))
			e[2] = c
		var t := _time * 0.6 + ph
		s.position = c + Vector3(sin(t * 1.3) * 1.6 + sin(t * 0.7) * 1.0, 0.55 + sin(t * 2.1) * 0.25, cos(t * 0.9) * 1.4)
		s.scale = Vector3(0.35 + 0.65 * absf(sin(_time * 14.0 + ph)), 1.0, 1.0)
	# listí padá po větru
	_leaves.position = hero3 + Vector3(0, 7.0, 0)
	_leaves.gravity = Vector3(0.1 + wind_add * 1.5 + world.current_wind() * 0.8, -0.15, 0.0)
	# kruhy po rybách na hladině
	_fish_timer -= delta
	if _fish_timer <= 0.0:
		_fish_timer = randf_range(2.5, 6.0)
		if day or h > 5.0:
			_fish_ring(hp)


func _fish_ring(hp: Vector2) -> void:
	for i in 12:
		var p := hp + Vector2(randf_range(-260, 260), randf_range(-200, 200))
		if is_water_at(p) and _zones.get_pixelv(Vector2i(((p - world.tiled.bounds_px.position) / TILE_PX).floor())).r > 0.8:
			var mi := MeshInstance3D.new()
			var qm := QuadMesh.new()
			qm.orientation = PlaneMesh.FACE_Y
			qm.size = Vector2.ONE
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_texture = _ring_tex()
			m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
			mi.mesh = qm
			mi.material_override = m
			mi.position = Vector3(p.x * S, 0.05, p.y * S)
			mi.scale = Vector3.ONE * 0.15
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			var tw := create_tween().set_parallel(true)
			tw.tween_property(mi, "scale", Vector3.ONE * 1.1, 1.8)
			tw.tween_property(m, "albedo_color:a", 0.0, 1.8).from(0.9)
			tw.chain().tween_callback(mi.queue_free)
			return


var _ring: Texture2D
func _ring_tex() -> Texture2D:
	if _ring == null:
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		for y in 64:
			for x in 64:
				var d := Vector2(x - 31.5, y - 31.5).length() / 31.5
				var a := clampf(1.0 - absf(d - 0.8) / 0.12, 0.0, 1.0) * clampf((1.0 - d) * 6.0, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, a * 0.8))
		_ring = ImageTexture.create_from_image(img)
	return _ring


# ───────────────────────── popředí (rozmazané listí) ─────────────────────────

func _build_foreground() -> void:
	_fg = CanvasLayer.new()
	_fg.layer = -1
	add_child(_fg)
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.frequency = 0.035
	noise.fractal_octaves = 2
	noise.seed = 11
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	for y in 256:
		for x in 256:
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var rad := clampf(1.0 - Vector2(x, y).length() / 256.0, 0.0, 1.0)   # silné v rohu (0,0)
			var a := smoothstep(0.4, 0.8, n * 0.5 + rad * 0.9 - 0.1) * smoothstep(0.02, 0.4, rad)
			img.set_pixel(x, y, Color(0.04, 0.09, 0.03, a))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	# čtyři rohy: zrcadlení textury
	var defs := [[Vector2(0, 0), Vector2(1, 1)], [Vector2(1, 0), Vector2(-1, 1)], [Vector2(0, 1), Vector2(1, -1)], [Vector2(1, 1), Vector2(-1, -1)]]
	for d in defs:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		tr.size = Vector2(520, 380)
		tr.pivot_offset = tr.size * 0.5
		tr.scale = d[1]
		tr.set_meta("corner", d[0])
		tr.modulate.a = 0.0
		_fg.add_child(tr)
		_fg_items.append(tr)


func _update_foreground(delta: float) -> void:
	var vs := get_viewport().get_visible_rect().size
	var drift := Vector2.ZERO
	if world.focus:
		drift = (world.focus.global_position * 0.55)
	var sway := sin(_time * 0.9) * (6.0 + 22.0 * world.current_wind())
	var i := 0
	for tr in _fg_items:
		var c: Vector2 = tr.get_meta("corner")
		var base := Vector2(c.x * (vs.x - tr.size.x), c.y * (vs.y - tr.size.y))
		var off := Vector2(fposmod(drift.x + i * 91.0, 60.0) - 30.0, fposmod(drift.y + i * 53.0, 40.0) - 20.0)
		tr.position = base + off + Vector2(sway * (1.0 if i % 2 == 0 else -1.0), sway * 0.4) + Vector2(c.x * 2.0 - 1.0, c.y * 2.0 - 1.0) * 70.0
		tr.modulate.a = _fg_alpha
		i += 1


# ───────────────────────── smyčka ─────────────────────────

func _process(delta: float) -> void:
	if world == null or not world._is_built:
		return
	_time += delta
	_update_weather(delta)
	_update_mood(delta)
	_update_focus(delta)
	_update_footprints(delta)
	_update_life(delta)
	_update_foreground(delta)
	world.set_post_param("flash", _flash)
	world.refresh()
