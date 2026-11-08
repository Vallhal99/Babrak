class_name Interior
extends Node3D
## Interiér obchodu (hostinec): malá 3D místnost daleko za okrajem mapy, ve stejném světě (stejná kamera,
## sprity, stíny). Dřevěná podlaha, stěny, regály s lahvemi, pult, sudy, teplé světlo. Strop vrhá jen stín,
## takže dovnitř nesvítí slunce. Hráč se tam přenese; pohyb omezuje `clamp_hero`.

const S := 0.02
const CENTER := Vector2(0, 4200)       ## střed místnosti (px)
const HALF := Vector2(180, 110)        ## polovina rozměru (px)
const COUNTER_Y := -40.0               ## hráč nesmí za pult (y vůči středu)
const EXIT_Y := 92.0                   ## u spodního okraje = odchod

var entrance: Vector2 = CENTER + Vector2(0, 80)
var merchant_spot: Vector2 = CENTER + Vector2(70, -62)


func _ready() -> void:
	var wood := _mat(Color(0.3, 0.2, 0.11))
	var dark := _mat(Color(0.3, 0.19, 0.1))
	var wall := _mat(Color(0.42, 0.34, 0.26))
	var w := HALF.x * 2.0 * S
	var d := HALF.y * 2.0 * S
	var c := Vector3(CENTER.x * S, 0, CENTER.y * S)
	_box(Vector3(w + 1.0, 0.1, d + 1.0), c + Vector3(0, -0.05, 0), wood)
	for i in 9:   # prkna
		_box(Vector3(0.02, 0.012, d), c + Vector3(-w * 0.5 + (i + 1) * w / 10.0, 0.002, 0), dark)
	_box(Vector3(w + 0.4, 3.2, 0.3), c + Vector3(0, 1.6, -d * 0.5 - 0.15), wall)
	_box(Vector3(0.3, 3.2, d + 0.4), c + Vector3(-w * 0.5 - 0.15, 1.6, 0), wall)
	_box(Vector3(0.3, 3.2, d + 0.4), c + Vector3(w * 0.5 + 0.15, 1.6, 0), wall)
	_box(Vector3(w, 0.18, 0.12), c + Vector3(0, 3.0, -d * 0.5 + 0.06), dark)   # trám
	_box(Vector3(60, 0.05, 60), c + Vector3(0, -0.12, 0), _mat(Color(0.03, 0.02, 0.02)))   # tma kolem
	var cz := c.z - d * 0.5
	for i in 3:   # regály vzadu
		var x := c.x - 2.2 + i * 2.2
		_box(Vector3(1.8, 2.0, 0.35), Vector3(x, 1.0, cz + 0.2), dark)
		for r in 3:
			for k in 4:
				var col := Color.from_hsv(randf(), 0.55, 0.9)
				_sphere(0.09, Vector3(x - 0.65 + k * 0.42, 0.42 + r * 0.6, cz + 0.42), col)
	_box(Vector3(2.4, 0.7, 0.6), Vector3(c.x - 0.8, 0.35, c.z - 0.9), wood)   # pult
	_box(Vector3(2.6, 0.07, 0.75), Vector3(c.x - 0.8, 0.72, c.z - 0.9), dark)
	for sx in [-1.0, 1.0]:   # sudy
		var b := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.4
		cm.bottom_radius = 0.45
		cm.height = 0.9
		b.mesh = cm
		b.material_override = wood
		b.position = Vector3(c.x + sx * 2.9, 0.45, cz + 0.9)
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(b)
	_box(Vector3(1.2, 0.08, 0.8), c + Vector3(-2.2, 0.55, 0.6), wood)   # stůl
	_box(Vector3(0.1, 0.55, 0.1), c + Vector3(-2.2, 0.27, 0.6), dark)
	_box(Vector3(w + 1.0, 0.05, d + 1.0), c + Vector3(0, 3.6, 0), wall, true)   # strop jen stíní
	for lx in [-1.8, 1.8]:
		var l := OmniLight3D.new()
		l.position = Vector3(c.x + lx, 2.3, c.z)
		l.light_color = Color(1.0, 0.72, 0.4)
		l.light_energy = 0.7
		l.omni_range = 6.0
		l.shadow_enabled = true
		add_child(l)
	var mat := _box(Vector3(1.2, 0.02, 0.6), c + Vector3(0, 0.01, d * 0.5 - 0.3), _mat(Color(0.5, 0.15, 0.15)))   # rohožka = východ


func clamp_hero(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, CENTER.x - HALF.x + 18, CENTER.x + HALF.x - 18), clampf(p.y, CENTER.y + COUNTER_Y, CENTER.y + EXIT_Y + 6))


func at_exit(p: Vector2) -> bool:
	return p.y >= CENTER.y + EXIT_Y


func contains(p: Vector2) -> bool:
	return absf(p.x - CENTER.x) < 600 and absf(p.y - CENTER.y) < 400


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m


func _box(size: Vector3, pos: Vector3, mat: Material, shadow_only := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	if shadow_only:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	add_child(mi)
	return mi


func _sphere(r: float, pos: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	mi.mesh = sm
	mi.material_override = _mat(col)
	mi.position = pos
	add_child(mi)
