class_name BattleArena3D
extends SubViewportContainer
## HD-2D bojiště: skutečná 3D scéna (země s trávou, stromy, kameny, světlo se stíny, mlha, hloubková
## ostrost) vykreslená pod 2D postavami souboje – stejný princip jako svět hry (2D sprity v 3D).
## Pozadí z assets/battle/bg_<nálada>.png slouží jako vzdálená kulisa za stromy; finální obrázek
## se tedy zapojí sám. Světlo reaguje na denní dobu a počasí.

var backdrop: Texture2D
var hour := 12.0
var weather := "jasno"
var mood := "forest"

var _vp := SubViewport.new()
var _cam := Camera3D.new()
var _time := 0.0
var _fireflies: GPUParticles3D


func _ready() -> void:
	stretch = true
	position = Vector2.ZERO
	size = get_viewport_rect().size   # rodič je CanvasLayer, kotvy by daly nulu
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.handle_input_locally = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_build()


func _night() -> bool:
	return hour < 5.5 or hour >= 20.5


func _build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var night := _night()
	var dusk := not night and (hour >= 17.5 or hour < 7.0)
	var gloom := weather == "déšť" or weather == "bouře" or weather == "zataženo"
	# kamera: lehce shora, horizont ~ 38 % výšky obrazu
	_cam.fov = 38.0
	_cam.position = Vector3(0, 3.4, 9.5)
	_cam.rotation_degrees = Vector3(-14.0, 0, 0)
	_cam.far = 120.0
	_vp.add_child(_cam)
	_cam.make_current()
	# prostředí
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	var sky_col := Color(0.62, 0.78, 0.6)
	var ambient := Color(0.55, 0.62, 0.55)
	var sun_col := Color(1.0, 0.93, 0.76)
	var sun_e := 0.8
	if dusk:
		sky_col = Color(0.95, 0.62, 0.38); ambient = Color(0.62, 0.5, 0.45); sun_col = Color(1.0, 0.6, 0.32); sun_e = 1.0
	if night:
		sky_col = Color(0.07, 0.1, 0.2); ambient = Color(0.2, 0.26, 0.42); sun_col = Color(0.55, 0.65, 1.0); sun_e = 0.45
	if gloom:
		sky_col = sky_col.lerp(Color(0.5, 0.54, 0.56), 0.6); sun_e *= 0.55
	env.background_color = sky_col
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = ambient
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = sky_col.lerp(Color(1, 1, 0.85), 0.25)
	env.fog_density = 0.012 if not gloom else 0.035
	env.glow_enabled = true
	env.glow_intensity = 0.25
	env.glow_bloom = 0.1
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	var we := WorldEnvironment.new()
	we.environment = env
	var attrs := CameraAttributesPractical.new()
	attrs.dof_blur_far_enabled = true
	attrs.dof_blur_far_distance = 16.0
	attrs.dof_blur_far_transition = 14.0
	attrs.dof_blur_amount = 0.08
	we.camera_attributes = attrs
	_vp.add_child(we)
	# slunce / měsíc
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35 if not dusk else -70, 0)
	sun.light_color = sun_col
	sun.light_energy = sun_e
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	_vp.add_child(sun)
	# země: tráva s šumem
	var noise := FastNoiseLite.new()
	noise.frequency = 0.02
	var ntex := NoiseTexture2D.new()
	ntex.noise = noise
	ntex.width = 256
	ntex.height = 256
	ntex.seamless = true
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(0.1, 0.22, 0.09), Color(0.24, 0.37, 0.14)])
	ntex.color_ramp = grad
	var gmat := StandardMaterial3D.new()
	gmat.albedo_texture = ntex
	gmat.uv1_scale = Vector3(8, 8, 1)
	gmat.roughness = 1.0
	var ground := MeshInstance3D.new()
	var gm := PlaneMesh.new()
	gm.size = Vector2(90, 70)
	ground.mesh = gm
	ground.material_override = gmat
	ground.position = Vector3(0, 0, -20)
	_vp.add_child(ground)
	# vyšlapaná hlína v místě souboje (průsečík paprsku ze středu bojiště se zemí)
	var spot := _ground_at(Vector2(0.52, 0.60))
	var dirt := MeshInstance3D.new()
	var dm := PlaneMesh.new()
	dm.size = Vector2(15, 8)
	dirt.mesh = dm
	var dmat := StandardMaterial3D.new()
	var rg := GradientTexture2D.new()
	rg.fill = GradientTexture2D.FILL_RADIAL
	rg.fill_from = Vector2(0.5, 0.5)
	rg.fill_to = Vector2(1.0, 0.5)
	var dgrad := Gradient.new()
	dgrad.colors = PackedColorArray([Color(0.3, 0.22, 0.14, 1), Color(0.3, 0.22, 0.14, 0)])
	dgrad.offsets = PackedFloat32Array([0.55, 1.0])
	rg.gradient = dgrad
	dmat.albedo_texture = rg
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.roughness = 1.0
	dirt.material_override = dmat
	dirt.position = spot + Vector3(0, 0.01, 0)
	_vp.add_child(dirt)
	# stromy a kameny
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.27, 0.18, 0.11)
	var leaf := StandardMaterial3D.new()
	leaf.albedo_color = Color(0.1, 0.27, 0.11)
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color(0.45, 0.46, 0.48)
	rock.roughness = 0.9
	for i in 26:
		var side := -1.0 if i % 2 == 0 else 1.0
		var x := side * rng.randf_range(5.5, 26.0)
		var z := rng.randf_range(-34.0, 2.0)
		var h := rng.randf_range(4.0, 8.0)
		var tree := Node3D.new()
		tree.position = Vector3(x, 0, z)
		var trunk := MeshInstance3D.new()
		var tm := CylinderMesh.new()
		tm.top_radius = 0.22
		tm.bottom_radius = 0.38
		tm.height = h * 0.6
		trunk.mesh = tm
		trunk.material_override = bark
		trunk.position.y = h * 0.3
		tree.add_child(trunk)
		for k in 3:
			var crown := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = rng.randf_range(1.5, 2.4) * (1.0 - 0.18 * k)
			sm.height = sm.radius * 1.7
			crown.mesh = sm
			var lm: StandardMaterial3D = leaf.duplicate()
			lm.albedo_color = leaf.albedo_color.lerp(Color(0.22, 0.38, 0.14), rng.randf() * 0.6)
			crown.material_override = lm
			crown.position = Vector3(rng.randf_range(-0.6, 0.6), h * 0.55 + k * 1.1, rng.randf_range(-0.6, 0.6))
			tree.add_child(crown)
		_vp.add_child(tree)
	for i in 14:
		var r := MeshInstance3D.new()
		var rm := SphereMesh.new()
		rm.radius = rng.randf_range(0.25, 0.7)
		rm.height = rm.radius * 1.2
		r.mesh = rm
		r.material_override = rock
		var rx := rng.randf_range(-12.0, 12.0)
		r.position = Vector3(rx, 0.0, rng.randf_range(-12.0, 1.0))
		if absf(rx) < 5.5 and r.position.z > -4.0:
			r.position.x = signf(rx) * 6.0   # bojiště nechat volné
		_vp.add_child(r)
	# tráva (MultiMesh křížených listů)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var blade := QuadMesh.new()
	blade.size = Vector2(0.07, 0.28)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.17, 0.33, 0.12)
	bmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	bmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	blade.material = bmat
	mm.mesh = blade
	mm.instance_count = 1400
	for i in mm.instance_count:
		var p := Vector3(rng.randf_range(-16, 16), 0.14, rng.randf_range(-18, -1.5))
		mm.set_instance_transform(i, Transform3D(Basis(), p))
	var grass := MultiMeshInstance3D.new()
	grass.multimesh = mm
	grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vp.add_child(grass)
	# kulisa vzadu (obrázek bg_<nálada>.png nebo mlžný pás)
	var back := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(110, 40)
	back.mesh = qm
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_color = sky_col.lerp(Color.WHITE, 0.15) if backdrop == null else Color(0.8, 0.8, 0.8) if night else Color.WHITE
	if backdrop != null:
		bm.albedo_texture = backdrop
	bm.disable_fog = true
	back.material_override = bm
	back.position = Vector3(0, 14, -48)
	_vp.add_child(back)
	# světlušky v noci / za soumraku
	if night or dusk:
		_fireflies = GPUParticles3D.new()
		_fireflies.amount = 40
		_fireflies.lifetime = 5.0
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(10, 1.5, 6)
		pm.gravity = Vector3(0, 0.05, 0)
		pm.initial_velocity_min = 0.1
		pm.initial_velocity_max = 0.4
		pm.direction = Vector3(0, 1, 0)
		pm.spread = 180.0
		_fireflies.process_material = pm
		var fm := SphereMesh.new()
		fm.radius = 0.04
		fm.height = 0.08
		var fmat := StandardMaterial3D.new()
		fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fmat.albedo_color = Color(1.0, 0.95, 0.5)
		fm.material = fmat
		_fireflies.draw_pass_1 = fm
		_fireflies.position = Vector3(0, 1.4, 0)
		_vp.add_child(_fireflies)


## Bod na zemi (y = 0) pod pozicí na obrazovce (poměr 0–1).
func _ground_at(frac: Vector2) -> Vector3:
	var size := Vector2(1280, 960)
	var o := _cam.project_ray_origin(size * frac)
	var n := _cam.project_ray_normal(size * frac)
	if absf(n.y) < 0.0001:
		return Vector3.ZERO
	return o + n * (-o.y / n.y)


func _process(delta: float) -> void:
	_time += delta
	_cam.position.x = sin(_time * 0.25) * 0.18   # jemné "dýchání" kamery
	_cam.position.y = 3.4 + sin(_time * 0.2) * 0.05
