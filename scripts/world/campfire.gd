class_name Campfire
extends StaticBody2D
## Táborák: kameny + polena, živé plameny a jiskry (částice), plápolající světlo, kolize.

var base_energy := 1.4
var base_scale := 3.2
var _light := PointLight2D.new()
var _flames := CPUParticles2D.new()
var _sparks := CPUParticles2D.new()
var _t := randf() * 10.0


func _ready() -> void:
	add_to_group(&"campfires")
	for id in ["campfire_ring", "campfire_logs"]:
		var tex: Texture2D = load("res://assets/world/%s.png" % id)
		var s := Sprite2D.new()
		s.texture = tex
		s.offset = Vector2(0, -tex.get_height() / 2.0)
		add_child(s)
	var col := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 16
	col.shape = circle
	col.position = Vector2(0, -8)
	add_child(col)

	_light.texture = Fx.light_texture()
	_light.color = Color(1.0, 0.62, 0.28)
	_light.texture_scale = base_scale
	_light.energy = base_energy
	_light.position = Vector2(0, -16)
	add_child(_light)

	var glow := Fx.glow_texture()
	var add := Fx.additive_material()
	_setup_flames(glow, add)
	_setup_sparks(glow, add)


func _setup_flames(glow: Texture2D, mat: Material) -> void:
	_flames.texture = glow
	_flames.material = mat
	_flames.amount = 26
	_flames.lifetime = 0.75
	_flames.preprocess = 1.0
	_flames.local_coords = false
	_flames.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_flames.emission_sphere_radius = 6.0
	_flames.direction = Vector2(0, -1)
	_flames.spread = 14.0
	_flames.gravity = Vector2(0, -22)
	_flames.initial_velocity_min = 14.0
	_flames.initial_velocity_max = 30.0
	_flames.scale_amount_min = 0.45
	_flames.scale_amount_max = 0.85
	var shrink := Curve.new()
	shrink.add_point(Vector2(0, 0.7))
	shrink.add_point(Vector2(0.3, 1.0))
	shrink.add_point(Vector2(1, 0.0))
	_flames.scale_amount_curve = shrink
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	g.colors = PackedColorArray([Color(1, 0.95, 0.6, 0.95), Color(1, 0.55, 0.15, 0.75), Color(0.8, 0.1, 0.0, 0.0)])
	_flames.color_ramp = g
	_flames.position = Vector2(0, -16)
	add_child(_flames)


func _setup_sparks(glow: Texture2D, mat: Material) -> void:
	_sparks.texture = glow
	_sparks.material = mat
	_sparks.amount = 14
	_sparks.lifetime = 1.5
	_sparks.preprocess = 1.5
	_sparks.local_coords = false
	_sparks.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_sparks.emission_sphere_radius = 8.0
	_sparks.direction = Vector2(0, -1)
	_sparks.spread = 38.0
	_sparks.gravity = Vector2(0, -14)
	_sparks.initial_velocity_min = 30.0
	_sparks.initial_velocity_max = 75.0
	_sparks.scale_amount_min = 0.07
	_sparks.scale_amount_max = 0.14
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([Color(1, 0.85, 0.35, 1), Color(1, 0.3, 0.0, 0.0)])
	_sparks.color_ramp = g
	_sparks.position = Vector2(0, -18)
	add_child(_sparks)


## Síla světla podle denní doby (ve dne slabé, v noci silné).
func set_intensity(e: float) -> void:
	base_energy = e


## Vyrušení ztmavení CanvasModulate, aby plameny zářily plnou barvou.
func set_counter(c: Color) -> void:
	_flames.modulate = c
	_sparks.modulate = c


func _process(delta: float) -> void:
	_t += delta
	var flick := 0.92 + 0.08 * sin(_t * 11.0) + 0.06 * sin(_t * 23.7 + 1.3) + randf_range(-0.03, 0.03)
	_light.energy = base_energy * flick
	_light.texture_scale = base_scale * (1.0 + 0.03 * sin(_t * 9.0))
