class_name PropFactory
extends RefCounted
## Sestaví y-řazený objekt světa: sprite (kotva = pata) + kolize u paty. Stín se přidává zvlášť (shadow_for).

const COLLISIONS := {"tent": "104,26", "barrel": "12", "log": "40,12", "stump": "10"}   # "r" = kruh, "w,h" = obdélník


static func default_collision(id: String, tex: Texture2D) -> String:
	if COLLISIONS.has(id):
		return COLLISIONS[id]
	if id.begins_with("tree_"):
		return str(clampi(int(tex.get_width() * 0.09), 8, 14))
	return ""


static func shadow_for(id: String, tex: Texture2D) -> Vector2:
	var w := float(tex.get_width())
	if id.begins_with("tree_"):
		return Vector2(w * 0.3, maxf(8.0, w * 0.07))
	return Vector2(w * 0.55, maxf(5.0, w * 0.13))


static func build(tex: Texture2D, pos: Vector2, collision := "", material: Material = null, flip := false) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.position = pos
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.offset = Vector2(0, -tex.get_height() / 2.0)
	spr.flip_h = flip
	if material:
		spr.material = material
	body.add_child(spr)
	if collision != "" and collision != "none":
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
	return body
