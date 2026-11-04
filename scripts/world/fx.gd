class_name Fx
extends RefCounted
## Pomocné generátory textur a materiálů pro efekty (bez externích souborů).


## Radiální gradient: stops = [[offset, Color], ...] (střed = offset 0, okraj = 1).
static func radial(size: int, stops: Array) -> GradientTexture2D:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for s in stops:
		offs.append(s[0])
		cols.append(s[1])
	g.offsets = offs
	g.colors = cols
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = size
	t.height = size
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t


static func light_texture(size := 256) -> GradientTexture2D:
	return radial(size, [[0.0, Color.WHITE], [0.35, Color(0.55, 0.55, 0.55)], [0.7, Color(0.12, 0.12, 0.12)], [1.0, Color.BLACK]])


static func glow_texture(size := 32) -> GradientTexture2D:
	return radial(size, [[0.0, Color(1, 1, 1, 1)], [0.45, Color(1, 1, 1, 0.45)], [1.0, Color(1, 1, 1, 0)]])


static func shadow_texture(size := 64) -> GradientTexture2D:
	return radial(size, [[0.0, Color(0, 0, 0, 0.55)], [0.6, Color(0, 0, 0, 0.3)], [1.0, Color(0, 0, 0, 0)]])


static func additive_material() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return m


static func sway_material(amp: float, speed := 1.4, power := 1.6) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/sway.gdshader")
	m.set_shader_parameter("amp", amp)
	m.set_shader_parameter("speed", speed)
	m.set_shader_parameter("power", power)
	return m


static func shadow_sprite(rx: float, ry: float) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = shadow_texture()
	s.scale = Vector2(rx * 2.0 / 64.0, ry * 2.0 / 64.0)
	return s
