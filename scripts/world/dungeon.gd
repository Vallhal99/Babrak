class_name Dungeon
extends Node3D
## Hrobka kronikářů – dungeon za okrajem mapy (stejný svět, kamera i sprity jako venku).
## Cesta vede od jihu (vstup) na sever k bossovi Strážci archivu: vstupní síň → knihovna → krypta s pastmi
## → zrcadlová síň s mříží (klíč archivaře ze svatyně vlevo, nebo páčení) → síň archivu (boss).
## Chodí se jen po místnostech a chodbách (`walkable`), stěny se staví samy z obdélníků.

const S := 0.02
const ORIGIN := Vector2(0, 6500)
const R := {   # místnosti a chodby (px, relativně k ORIGIN)
	"hall": Rect2(-130, -170, 260, 170), "c1": Rect2(-40, -250, 80, 80),
	"library": Rect2(-200, -470, 400, 220), "c2": Rect2(-40, -550, 80, 80),
	"traps": Rect2(-150, -770, 300, 220), "c3": Rect2(-40, -850, 80, 80),
	"mirrors": Rect2(-150, -1000, 300, 150), "c4": Rect2(-40, -1080, 80, 80),
	"boss": Rect2(-220, -1380, 440, 300), "c5": Rect2(200, -400, 100, 80), "shrine": Rect2(300, -500, 200, 220),
}
const GATE_Y := -1040.0
const ENEMIES := [   # [id, šablona, pozice]
	[0, &"skeleton", Vector2(-50, -90)], [1, &"skeleton", Vector2(60, -70)],
	[2, &"skeleton", Vector2(-120, -380)], [3, &"archer", Vector2(110, -330)],
	[4, &"skeleton", Vector2(-80, -930)], [5, &"skeleton", Vector2(80, -920)],
	[6, &"guardian", Vector2(400, -390)], [7, &"archivist", Vector2(0, -1250)],
]
const TRAPS := [Vector2(-90, -620), Vector2(0, -620), Vector2(90, -620), Vector2(-45, -680), Vector2(45, -680), Vector2(-90, -740), Vector2(0, -740), Vector2(90, -740)]

var gate_open := false
var _gate: MeshInstance3D
var _rects: Array[Rect2] = []
var _spikes: Array[MeshInstance3D] = []
var _t := 0.0
var _hit_cd := 0.0
var _stone := StandardMaterial3D.new()
var _dark := StandardMaterial3D.new()


func abs_rect(key: String) -> Rect2:
	var r: Rect2 = R[key]
	return Rect2(r.position + ORIGIN, r.size)


func _ready() -> void:
	_stone.albedo_color = Color(0.36, 0.36, 0.4)
	_stone.roughness = 0.95
	_dark.albedo_color = Color(0.2, 0.2, 0.24)
	_dark.roughness = 0.9
	for k in R:
		_rects.append(abs_rect(k))
	_floors()
	_walls()
	_decor()
	# strop jen stíní (slunce dovnitř nesmí), tma kolem
	_box(Vector3(30, 0.05, 80), Vector3(ORIGIN.x * S + 4, 3.8, (ORIGIN.y - 700) * S), _dark, true)
	_box(Vector3(80, 0.05, 120), Vector3(ORIGIN.x * S, -0.15, (ORIGIN.y - 700) * S), _mat(Color(0.02, 0.02, 0.03)))


func _p(v: Vector2) -> Vector3:
	return Vector3(v.x * S, 0, v.y * S)


func _floors() -> void:
	var cols := {"hall": Color(0.3, 0.3, 0.34), "library": Color(0.34, 0.27, 0.2), "traps": Color(0.28, 0.26, 0.3), "mirrors": Color(0.25, 0.3, 0.34), "boss": Color(0.22, 0.2, 0.28), "shrine": Color(0.3, 0.3, 0.26)}
	for k in R:
		var r := abs_rect(k)
		_box(Vector3(r.size.x * S, 0.1, r.size.y * S), _p(r.get_center()) + Vector3(0, -0.05, 0), _mat(cols.get(k, Color(0.27, 0.27, 0.3))))


## Stěny: po obvodu každého obdélníku, mimo průchody do sousedních místností. Jižní (přivrácené ke kameře) jsou nízké.
func _walls() -> void:
	for r in _rects:
		for side in 4:   # 0 sever, 1 jih, 2 západ, 3 východ
			var horiz := side < 2
			var fixed: float = r.position.y if side == 0 else r.end.y if side == 1 else r.position.x if side == 2 else r.end.x
			var lo: float = r.position.x if horiz else r.position.y
			var hi: float = r.end.x if horiz else r.end.y
			var gaps: Array = []
			for o in _rects:
				if o == r:
					continue
				var o_fixed_a: float = (o.end.y if side == 0 else o.position.y) if horiz else (o.end.x if side == 2 else o.position.x)
				if absf(o_fixed_a - fixed) < 1.0:
					var a: float = maxf(lo, o.position.x if horiz else o.position.y)
					var b: float = minf(hi, o.end.x if horiz else o.end.y)
					if b > a:
						gaps.append([a, b])
			gaps.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
			var cur := lo
			for g in gaps:
				if g[0] > cur:
					_wall(horiz, fixed, cur, g[0], side)
				cur = maxf(cur, g[1])
			if hi > cur:
				_wall(horiz, fixed, cur, hi, side)
	# mříž
	_gate = _box(Vector3(1.6, 2.4, 0.12), _p(Vector2(ORIGIN.x, ORIGIN.y + GATE_Y)) + Vector3(0, 1.2, 0), _mat(Color(0.12, 0.12, 0.14)))
	for i in 7:
		_box(Vector3(0.05, 2.4, 0.16), _gate.position + Vector3(-0.7 + i * 0.233, 0, 0), _mat(Color(0.55, 0.55, 0.6)))


func _wall(horiz: bool, fixed: float, a: float, b: float, side: int) -> void:
	var h := 0.5 if side == 1 else 3.2
	var th := 0.3
	var len := (b - a) * S
	var mid := (a + b) * 0.5
	if horiz:
		var off := th * 0.5 * (-1.0 if side == 0 else 1.0)
		_box(Vector3(len, h, th), Vector3(mid * S, h * 0.5, fixed * S + off), _stone)
	else:
		var off := th * 0.5 * (-1.0 if side == 2 else 1.0)
		_box(Vector3(th, h, len), Vector3(fixed * S + off, h * 0.5, mid * S), _stone)


func _decor() -> void:
	var o := ORIGIN
	for x in [-90.0, 90.0]:   # sloupy ve vstupní síni
		for y in [-130.0, -40.0]:
			_cyl(0.35, 2.8, _p(o + Vector2(x, y)), _stone)
	for sx in [-1.0, 1.0]:    # knihovna: regály podél stěn
		for i in 4:
			var shelf := _box(Vector3(0.5, 2.2, 1.4), _p(o + Vector2(sx * 178, -440 + i * 52)) + Vector3(0, 1.1, 0), _mat(Color(0.35, 0.22, 0.12)))
			for k in 5:
				_box(Vector3(0.1, 0.4, 0.9), shelf.position + Vector3(-sx * 0.28, -0.7 + k * 0.4, 0), _mat(Color.from_hsv(randf(), 0.5, 0.7)))
	_box(Vector3(1.8, 0.8, 0.9), _p(o + Vector2(0, -360)) + Vector3(0, 0.4, 0), _mat(Color(0.4, 0.26, 0.14)))   # čtecí pult
	for p in TRAPS:           # pasti
		_box(Vector3(0.7, 0.04, 0.7), _p(o + p) + Vector3(0, 0.02, 0), _dark)
		var sp := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.22
		cm.height = 0.6
		sp.mesh = cm
		sp.material_override = _mat(Color(0.7, 0.72, 0.78))
		sp.position = _p(o + p) + Vector3(0, -0.3, 0)
		add_child(sp)
		_spikes.append(sp)
	var mirror := StandardMaterial3D.new()   # zrcadla v zrcadlové a bossovské síni
	mirror.albedo_color = Color(0.3, 0.9, 0.9)
	mirror.emission_enabled = true
	mirror.emission = Color(0.2, 0.8, 0.85)
	mirror.emission_energy_multiplier = 1.3
	for pos in [Vector2(-80, -1000), Vector2(0, -1000), Vector2(80, -1000), Vector2(-150, -1380), Vector2(-75, -1380), Vector2(0, -1380), Vector2(75, -1380), Vector2(150, -1380)]:
		_box(Vector3(1.0, 1.8, 0.06), _p(o + pos) + Vector3(0, 1.4, 0.2 if pos.y > -1100 and pos.y < -990 else 0.2), mirror)
	for pos in [Vector2(-130, -1160), Vector2(130, -1160), Vector2(-130, -1280), Vector2(130, -1280)]:   # sarkofágy
		_box(Vector3(1.0, 0.7, 2.0), _p(o + pos) + Vector3(0, 0.35, 0), _stone)
	for pos in [Vector2(-60, -50), Vector2(60, -50), Vector2(-60, -860), Vector2(60, -860), Vector2(-100, -1100), Vector2(100, -1100)]:
		_torch_light(o + pos, Color(1.0, 0.65, 0.3), 0.9)
	_torch_light(o + Vector2(0, -360), Color(1.0, 0.8, 0.5), 0.8)
	_torch_light(o + Vector2(0, -650), Color(0.6, 0.7, 1.0), 0.7)
	_torch_light(o + Vector2(0, -1250), Color(0.4, 0.95, 1.0), 1.3)
	_torch_light(o + Vector2(400, -390), Color(0.9, 0.9, 0.5), 0.8)
	_cyl(0.4, 0.3, _p(o + Vector2(400, -390)) + Vector3(0, 0, 0), _mat(Color(0.5, 0.5, 0.2)))   # oltář svatyně


func _torch_light(px: Vector2, col: Color, energy: float) -> void:
	var l := OmniLight3D.new()
	l.position = _p(px) + Vector3(0, 2.0, 0)
	l.light_color = col
	l.light_energy = energy
	l.omni_range = 6.5
	add_child(l)
	var f := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.1
	sm.height = 0.2
	f.mesh = sm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = col
	fm.emission_enabled = true
	fm.emission = col
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	f.material_override = fm
	f.position = l.position
	add_child(f)


func open_gate() -> void:
	gate_open = true
	if _gate:
		var tw := create_tween()
		tw.tween_property(_gate, "position:y", 4.5, 1.2)
		for c in get_children():
			if c is MeshInstance3D and c != _gate and c.mesh is BoxMesh and absf(c.position.z - _gate.position.z) < 0.02 and absf(c.position.y - _gate.position.y) < 0.01:
				create_tween().tween_property(c, "position:y", 4.5, 1.2)


func walkable(p: Vector2) -> bool:
	for r in _rects:
		if r.grow(-12.0).has_point(p):
			if not gate_open and p.y < ORIGIN.y + GATE_Y + 14.0 and p.y > ORIGIN.y + GATE_Y - 14.0 and absf(p.x - ORIGIN.x) < 60.0:
				return false
			return true
	return false


## Zadá-li se pohyb mimo místnosti, ponechá povolenou osu (klouzání po stěně).
func clamp_move(prev: Vector2, p: Vector2) -> Vector2:
	if walkable(p):
		return p
	if walkable(Vector2(p.x, prev.y)):
		return Vector2(p.x, prev.y)
	if walkable(Vector2(prev.x, p.y)):
		return Vector2(prev.x, p.y)
	return prev


func at_exit(p: Vector2) -> bool:
	return p.y >= ORIGIN.y - 14.0


## Pasti: střídavě vysunuté bodce; vrací zásah (0 = nic).
func update_traps(delta: float, hero_pos: Vector2) -> int:
	_t += delta
	_hit_cd = maxf(0.0, _hit_cd - delta)
	var dmg := 0
	for i in TRAPS.size():
		var phase := fposmod(_t + float(i % 3) * 0.7 + float(i / 3) * 0.35, 2.4)
		var up := phase < 1.0
		var warn := phase > 2.0
		_spikes[i].position.y = lerpf(_spikes[i].position.y, 0.28 if up else (-0.05 if warn else -0.35), minf(1.0, delta * 14.0))
		if up and _hit_cd <= 0.0 and hero_pos.distance_to(ORIGIN + TRAPS[i]) < 24.0:
			dmg = 6
			_hit_cd = 1.0
	return dmg


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


func _cyl(r: float, h: float, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r * 1.1
	cm.height = h
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos + Vector3(0, h * 0.5, 0)
	add_child(mi)
