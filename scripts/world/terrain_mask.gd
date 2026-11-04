class_name TerrainMask
extends RefCounted
## Maska hlíny (0 = tráva, 1 = hlína) v nízkém rozlišení. Kreslí se tahy (kruh, cesta), pak se rozmaže.
## Shader z ní + šumu udělá organický přechod. Později půjde naplnit z vrstvy dlaždic (Tiled).

var cell := 6.0                  # světových px na pixel masky
var size: Vector2i
var data: PackedFloat32Array


func _init(world: Vector2) -> void:
	size = Vector2i(ceili(world.x / cell), ceili(world.y / cell))
	data = PackedFloat32Array()
	data.resize(size.x * size.y)


func stamp(center: Vector2, radius: float) -> void:
	var c := center / cell
	var r := radius / cell
	for y in range(maxi(0, int(c.y - r)), mini(size.y, int(c.y + r) + 1)):
		for x in range(maxi(0, int(c.x - r)), mini(size.x, int(c.x + r) + 1)):
			if Vector2(x + 0.5, y + 0.5).distance_squared_to(c) <= r * r:
				data[y * size.x + x] = 1.0


## Cesta hladkou křivkou (Catmull-Rom) o dané šířce (poloměr).
func stroke(points: PackedVector2Array, radius: float) -> void:
	var curve := Curve2D.new()
	curve.bake_interval = cell
	for i in points.size():
		var prev := points[maxi(i - 1, 0)]
		var next := points[mini(i + 1, points.size() - 1)]
		var tangent := (next - prev) / 6.0
		curve.add_point(points[i], -tangent, tangent)
	for p in curve.get_baked_points():
		stamp(p, radius)


func blur(radius := 2, passes := 2) -> void:
	for _p in passes:
		_blur_axis(true, radius)
		_blur_axis(false, radius)


func _blur_axis(horizontal: bool, radius: int) -> void:
	var out := PackedFloat32Array()
	out.resize(data.size())
	var n := float(radius * 2 + 1)
	for y in size.y:
		for x in size.x:
			var sum := 0.0
			for k in range(-radius, radius + 1):
				var sx := clampi(x + (k if horizontal else 0), 0, size.x - 1)
				var sy := clampi(y + (0 if horizontal else k), 0, size.y - 1)
				sum += data[sy * size.x + sx]
			out[y * size.x + x] = sum / n
	data = out


func sample(world_pos: Vector2) -> float:
	var x := clampi(int(world_pos.x / cell), 0, size.x - 1)
	var y := clampi(int(world_pos.y / cell), 0, size.y - 1)
	return data[y * size.x + x]


## Je v okolí (poloměr) hlína? Použito pro rozmístění stromů mimo cesty.
func near_dirt(world_pos: Vector2, radius: float, threshold := 0.02) -> bool:
	if sample(world_pos) > threshold:
		return true
	for i in 8:
		var a := TAU * i / 8.0
		if sample(world_pos + Vector2(cos(a), sin(a)) * radius) > threshold:
			return true
	return false


func to_texture() -> ImageTexture:
	var bytes := PackedByteArray()
	bytes.resize(data.size())
	for i in data.size():
		bytes[i] = int(clampf(data[i], 0.0, 1.0) * 255.0)
	return ImageTexture.create_from_image(Image.create_from_data(size.x, size.y, false, Image.FORMAT_L8, bytes))
