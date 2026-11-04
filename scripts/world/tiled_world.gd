class_name TiledWorld
extends Node2D
## Svět z Tiledu po chunkech (data z tools/tiled_import.py). Kolem `focus` (hrdina) se na pozadí načítají
## chunky a vzdálené se uvolňují – paměť i načítání nezávisí na velikosti mapy.
##
## Vrstvy (podle vlastností vrstvy v Tiledu):
##   hd = true      → podklad se kreslí shaderem (organické přechody terénů), dlaždice mají vlastnost `terrain`
##   above = true   → vrstva se kreslí nad postavami (koruny, střechy)
##   ostatní        → obyčejná TileMapLayer (kolize dlaždic s vlastností `solid` = true)
## Objekty (objektové vrstvy): type "prop" (id, collision...), "campfire", "light", tile-objekty (obrázek),
## "player_start" (marker). Vlastní typy: `spawners["enemy"] = Callable(obj, chunk) -> Node2D`.

const MAX_SLOTS := 8

signal chunk_shown(coord: Vector2i)
signal chunk_hidden(coord: Vector2i)

@export_dir var world_dir := "res://data/world/start"
@export_file("*.json") var terrains_path := "res://data/world/terrains.json"
@export var focus: Node2D
@export var load_radius := 2             ## chunky kolem hráče, které jsou vidět
@export var unload_margin := 1           ## o kolik dál se chunk uvolní (brání blikání na hranici)
@export var rows_per_frame := 24         ## rozpočet vykreslování dlaždic na snímek
@export var tuft_density := 0.00012      ## trsy trávy na px²
@export var edge_noise := 0.34
@export var terrain_texture_size := 48.0   ## velikost opakující se textury terénu v px (nezávisí na mřížce mapy)
@export var blur_px := 34.0               ## měkkost přechodu terénů v px

var objects: Node2D                      ## y-řazené objekty (sem patří i hrdina)
var start_position := Vector2.ZERO
var tile_size := Vector2i(48, 48)
var chunk_size := 32
var bounds_px := Rect2()
var spawners: Dictionary = {}

class Chunk:
	var coord: Vector2i
	var data: Dictionary
	var nodes: Array[Node] = []
	var cells: Array = []                # [TileMapLayer, Vector2i]
	var row := 0
	var spawned := false

var _world: Dictionary
var _index: Dictionary = {}              # Vector2i -> true (chunky, které existují)
var _data: Dictionary = {}               # Vector2i -> načtená data
var _pending: Dictionary = {}
var _results: Dictionary = {}
var _mutex := Mutex.new()
var _visual: Dictionary = {}             # Vector2i -> Chunk
var _queue: Array[Chunk] = []
var _last_chunk := Vector2i(1 << 30, 1 << 30)
var _dirty := true

var _tileset: TileSet
var _src_ranges: Array = []              # [firstgid, tilecount, source_id, columns]
var _atlas_info: Array = []              # [firstgid, tilecount, texture, columns, tw, th, margin, spacing]
var _gid_image: Dictionary = {}          # gid -> cesta obrázku (sbírka)
var _gid_props: Dictionary = {}          # gid -> vlastnosti dlaždice
var _gid_cache: Dictionary = {}
var _tex_cache: Dictionary = {}
var _tile_layers: Dictionary = {}        # jméno -> TileMapLayer
var _tile_layer_order: Array = []
var _hd_layer := ""
var _terrain_tex: Array[Texture2D] = []
var _gid_terrain: Dictionary = {}
var _noise_tex: ImageTexture
var _tuft_tex: Array[Texture2D] = []
var _tuft_mesh: Array[ArrayMesh] = []
var _tree_mat := Fx.sway_material(1.6, 1.3, 1.8)
var _tuft_mat := Fx.sway_material(2.6, 2.0, 1.2)
var _ground_root: Node2D
var _shadows: Node2D
var _flat: Node2D


func _ready() -> void:
	_world = JSON.parse_string(FileAccess.get_file_as_string(world_dir.path_join("world.json")))
	tile_size = Vector2i(int(_world.tile_size[0]), int(_world.tile_size[1]))
	chunk_size = int(_world.chunk_size)
	var b: Array = _world.bounds
	bounds_px = Rect2(b[0] * tile_size.x, b[1] * tile_size.y, (b[2] - b[0]) * tile_size.x, (b[3] - b[1]) * tile_size.y)
	for k in _world.chunks:
		var p := String(k).split("_")
		_index[Vector2i(int(p[0]), int(p[1]))] = true
	for m in _world.markers:
		if m.type == "player_start":
			start_position = Vector2(m.x, m.y)
	_load_terrains()
	_build_tileset()
	_build_layers()
	_build_decor_resources()
	spawners["prop"] = _spawn_prop
	spawners["campfire"] = _spawn_campfire
	spawners["light"] = _spawn_light


func chunk_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / (chunk_size * tile_size.x)), floori(pos.y / (chunk_size * tile_size.y)))


func shown_chunks() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in _visual:
		if _visual[c] not in _queue:
			out.append(c)
	return out


func all_ready() -> bool:
	return _queue.is_empty() and _pending.is_empty()


# ---------- příprava ----------

func _load_terrains() -> void:
	if not FileAccess.file_exists(terrains_path):
		return
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(terrains_path))
	var names: Array = []
	for t in cfg.terrains:
		names.append(t.name)
		_terrain_tex.append(load(t.texture))
	for ts in _world.tilesets:
		for id in ts.tiles:
			var pr: Dictionary = ts.tiles[id]
			if pr.has("terrain"):
				_gid_terrain[int(ts.firstgid) + int(id)] = maxi(names.find(pr.terrain), 0)
	var img := FastNoiseLite.new()
	img.seed = 4
	img.frequency = 0.011
	img.fractal_octaves = 3
	var im := img.get_seamless_image(256, 256, false, false, 0.2, true)
	im.convert(Image.FORMAT_L8)
	_noise_tex = ImageTexture.create_from_image(im)


func _build_tileset() -> void:
	_tileset = TileSet.new()
	_tileset.tile_size = tile_size
	_tileset.add_physics_layer()
	var tw := float(tile_size.x)
	var th := float(tile_size.y)
	var box := PackedVector2Array([Vector2(-tw / 2, -th / 2), Vector2(tw / 2, -th / 2), Vector2(tw / 2, th / 2), Vector2(-tw / 2, th / 2)])
	for ts in _world.tilesets:
		var first := int(ts.firstgid)
		for id in ts.tiles:
			_gid_props[first + int(id)] = ts.tiles[id]
		for id in ts.images:
			_gid_image[first + int(id)] = ts.images[id].image
		if not ts.has("image"):
			continue
		var tex: Texture2D = load(ts.image)
		var src := TileSetAtlasSource.new()
		var sid := _tileset.add_source(src)      # nejdřív do TileSetu, aby dlaždice znaly fyzikální vrstvu
		src.texture = tex
		src.texture_region_size = Vector2i(int(ts.tilewidth), int(ts.tileheight))
		src.margins = Vector2i(int(ts.margin), int(ts.margin))
		src.separation = Vector2i(int(ts.spacing), int(ts.spacing))
		var cols := int(ts.columns)
		for id in int(ts.tilecount):
			var ac := Vector2i(id % cols, id / cols)
			src.create_tile(ac)
			var pr: Dictionary = ts.tiles.get(str(id), {})
			if pr.get("solid", false):
				var td := src.get_tile_data(ac, 0)
				td.add_collision_polygon(0)
				td.set_collision_polygon_points(0, 0, box)
		_src_ranges.append([first, int(ts.tilecount), sid, cols])
		_atlas_info.append([first, int(ts.tilecount), tex, cols, int(ts.tilewidth), int(ts.tileheight), int(ts.margin), int(ts.spacing)])


func _build_layers() -> void:
	_ground_root = _node_layer("Ground", -30)
	var i := 0
	for meta in _world.layers:
		if meta.kind != "tiles" or not meta.visible:
			continue
		if meta.hd and not _terrain_tex.is_empty() and _hd_layer == "":
			_hd_layer = meta.name
			continue
		var tm := TileMapLayer.new()
		tm.name = String(meta.name).replace("/", "_")
		tm.tile_set = _tileset
		tm.z_index = (10 if meta.above else -20) + i
		add_child(tm)
		_tile_layers[meta.name] = tm
		_tile_layer_order.append(meta.name)
		i += 1
	_shadows = _node_layer("Shadows", -10)
	_flat = _node_layer("Flat", -5)
	objects = _node_layer("Objects", 0)
	objects.y_sort_enabled = true


func _node_layer(n: String, z: int) -> Node2D:
	var node := Node2D.new()
	node.name = n
	node.z_index = z
	add_child(node)
	return node


## Čtyřúhelník ve stejné orientaci jako Sprite2D (kotva = střed spodního okraje, UV 0,0 = levý horní roh).
## QuadMesh by byl ve 2D převrácený (osa Y míří opačně).
func _sprite_quad(w: float, h: float) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-w / 2, -h, 0), Vector3(w / 2, -h, 0), Vector3(w / 2, 0, 0), Vector3(-w / 2, 0, 0)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


func _build_decor_resources() -> void:
	for i in 5:
		var path := "res://assets/world/tuft_%d.png" % i
		if not ResourceLoader.exists(path):
			continue
		var tex: Texture2D = load(path)
		_tuft_tex.append(tex)
		_tuft_mesh.append(_sprite_quad(tex.get_width(), tex.get_height()))


# ---------- streamování ----------

func _process(_delta: float) -> void:
	_collect_results()
	var pos := focus.global_position if focus and is_instance_valid(focus) else start_position
	var c := chunk_of(pos)
	if c != _last_chunk:
		_last_chunk = c
		_refresh(c)
	if _dirty:
		_dirty = false
		_enqueue_ready(_last_chunk)
	_apply_budget()


func _refresh(c: Vector2i) -> void:
	for dx in range(-load_radius - 1, load_radius + 2):
		for dy in range(-load_radius - 1, load_radius + 2):
			var k := c + Vector2i(dx, dy)
			if _index.has(k) and not _data.has(k) and not _pending.has(k):
				_pending[k] = true
				WorkerThreadPool.add_task(_load_job.bind(k))
	for k in _visual.keys():
		if maxi(absi(k.x - c.x), absi(k.y - c.y)) > load_radius + unload_margin:
			_unload(k)
	for k in _data.keys():
		if maxi(absi(k.x - c.x), absi(k.y - c.y)) > load_radius + unload_margin + 2:
			_data.erase(k)
	_dirty = true


func _load_job(c: Vector2i) -> void:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(world_dir.path_join("chunk_%d_%d.json" % [c.x, c.y])))
	if d is Dictionary:
		var area := chunk_size * chunk_size
		for layer_name in d.tiles.keys():
			var src: Array = d.tiles[layer_name]
			var arr := PackedInt64Array()
			arr.resize(area)
			for i in area:
				arr[i] = int(src[i])
			d.tiles[layer_name] = arr
	_mutex.lock()
	_results[c] = d
	_mutex.unlock()


func _collect_results() -> void:
	_mutex.lock()
	var got := _results.duplicate()
	_results.clear()
	_mutex.unlock()
	for k in got:
		_pending.erase(k)
		if got[k] is Dictionary:
			_data[k] = got[k]
		_dirty = true


func _is_ready(k: Vector2i) -> bool:
	return not _index.has(k) or _data.has(k)


func _enqueue_ready(c: Vector2i) -> void:
	var cands: Array[Vector2i] = []
	for dx in range(-load_radius, load_radius + 1):
		for dy in range(-load_radius, load_radius + 1):
			var k := c + Vector2i(dx, dy)
			if _index.has(k) and not _visual.has(k) and _data.has(k):
				cands.append(k)
	cands.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return (a - c).length_squared() < (b - c).length_squared())
	for k in cands:
		var ok := true
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				ok = ok and _is_ready(k + Vector2i(dx, dy))
		if ok:
			var ch := Chunk.new()
			ch.coord = k
			ch.data = _data[k]
			_visual[k] = ch
			_queue.append(ch)


func _apply_budget() -> void:
	var budget := rows_per_frame
	while not _queue.is_empty() and budget > 0:
		var ch := _queue[0]
		if not ch.spawned:
			ch.spawned = true
			_spawn_chunk_nodes(ch)
			budget -= 12
			continue
		var n := mini(budget, chunk_size - ch.row)
		for y in range(ch.row, ch.row + n):
			_apply_row(ch, y)
		ch.row += n
		budget -= n
		if ch.row >= chunk_size:
			_queue.pop_front()
			chunk_shown.emit(ch.coord)


func _unload(k: Vector2i) -> void:
	var ch: Chunk = _visual.get(k)
	if ch == null:
		return
	for pair in ch.cells:
		(pair[0] as TileMapLayer).erase_cell(pair[1])
	for n in ch.nodes:
		if is_instance_valid(n):
			n.queue_free()
	_queue.erase(ch)
	_visual.erase(k)
	chunk_hidden.emit(k)


# ---------- dlaždice ----------

func _apply_row(ch: Chunk, y: int) -> void:
	var cs := chunk_size
	for layer_name in _tile_layer_order:
		var arr: PackedInt64Array = ch.data.tiles.get(layer_name, PackedInt64Array())
		if arr.is_empty():
			continue
		var layer: TileMapLayer = _tile_layers[layer_name]
		for x in cs:
			var gid := arr[y * cs + x]
			if gid == 0:
				continue
			var d: Array = _decode(gid)
			if d.is_empty():
				continue
			var cell := Vector2i(ch.coord.x * cs + x, ch.coord.y * cs + y)
			layer.set_cell(cell, d[0], d[1], d[2])
			ch.cells.append([layer, cell])


func _decode(gid: int) -> Array:
	if _gid_cache.has(gid):
		return _gid_cache[gid]
	var id := gid & 0x1FFFFFFF
	var res: Array = []
	for r in _src_ranges:
		if id >= r[0] and id < r[0] + r[1]:
			var local: int = id - r[0]
			var alt := 0
			if gid & 0x80000000:
				alt |= TileSetAtlasSource.TRANSFORM_FLIP_H
			if gid & 0x40000000:
				alt |= TileSetAtlasSource.TRANSFORM_FLIP_V
			if gid & 0x20000000:
				alt |= TileSetAtlasSource.TRANSFORM_TRANSPOSE
			res = [r[2], Vector2i(local % r[3], local / r[3]), alt]
			break
	_gid_cache[gid] = res
	return res


func _terrain_at(t: Vector2i) -> int:
	var cs := chunk_size
	var c := Vector2i(floori(t.x / float(cs)), floori(t.y / float(cs)))
	var d: Variant = _data.get(c)
	if d == null or _hd_layer == "" or not (d as Dictionary).tiles.has(_hd_layer):
		return 0
	var arr: PackedInt64Array = d.tiles[_hd_layer]
	var local := (t.y - c.y * cs) * cs + (t.x - c.x * cs)
	return _gid_terrain.get(arr[local] & 0x1FFFFFFF, 0)


func _has_detail(t: Vector2i) -> bool:
	var cs := chunk_size
	var c := Vector2i(floori(t.x / float(cs)), floori(t.y / float(cs)))
	var d: Variant = _data.get(c)
	if d == null:
		return false
	var local := (t.y - c.y * cs) * cs + (t.x - c.x * cs)
	for layer_name in _tile_layer_order:
		var arr: PackedInt64Array = (d as Dictionary).tiles.get(layer_name, PackedInt64Array())
		if not arr.is_empty() and arr[local] != 0:
			return true
	return false


# ---------- uzly chunku: podklad, detaily, objekty ----------

func _spawn_chunk_nodes(ch: Chunk) -> void:
	if _hd_layer != "":
		_build_ground(ch)
		_build_tufts(ch)
	for o in ch.data.get("objects", []):
		var fn: Callable = spawners.get(String(o.type), Callable())
		if not fn.is_valid() and o.has("gid"):
			fn = _spawn_tile_object
		if fn.is_valid():
			var n: Node = fn.call(o, ch)
			if n:
				ch.nodes.append(n)


func _build_ground(ch: Chunk) -> void:
	var cs := chunk_size
	var pad := ceili(40.0 / tile_size.x)          # okraj masky přes sousední chunky (kvůli měkkému přechodu)
	var side := cs + 2 * pad
	# 1) které terény chunk používá (max. 8 slotů; nižší index = základ, vyšší se kreslí přes)
	var count: Dictionary = {}
	var grid := PackedInt32Array()
	grid.resize(side * side)
	for y in range(-pad, cs + pad):
		for x in range(-pad, cs + pad):
			var t := _terrain_at(Vector2i(ch.coord.x * cs + x, ch.coord.y * cs + y))
			grid[(y + pad) * side + x + pad] = t
			count[t] = count.get(t, 0) + 1
	var used: Array = count.keys()
	if used.size() > MAX_SLOTS:
		used.sort_custom(func(a: int, b: int) -> bool: return count[a] > count[b])
		used = used.slice(0, MAX_SLOTS)
	used.sort()
	var slot_of: Dictionary = {}
	for i in used.size():
		slot_of[used[i]] = i
	# 2) masky: slot 1..4 -> mask_a (RGBA), 5..7 -> mask_b (RGB); slot 0 = základ (maska 0)
	var ia := Image.create(side, side, false, Image.FORMAT_RGBA8)
	var ib := Image.create(side, side, false, Image.FORMAT_RGBA8)
	for y in side:
		for x in side:
			var t: int = grid[y * side + x]
			var slot: int = slot_of.get(t, -1)
			if slot < 0:                              # nevešel se: nejbližší nižší použitý
				slot = 0
				for u in used:
					if u <= t:
						slot = slot_of[u]
			var ca := Color(0, 0, 0, 0)          # alfa = datový kanál (slot 4), proto výchozí 0
			var cb := Color(0, 0, 0, 0)
			match slot:
				1: ca.r = 1.0
				2: ca.g = 1.0
				3: ca.b = 1.0
				4: ca.a = 1.0
				5: cb.r = 1.0
				6: cb.g = 1.0
				7: cb.b = 1.0
			ia.set_pixel(x, y, ca)
			ib.set_pixel(x, y, cb)
	var origin := Vector2(ch.coord * cs * tile_size)
	var rect := ColorRect.new()
	rect.position = origin
	rect.size = Vector2(cs * tile_size.x, cs * tile_size.y)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/ground_terrain.gdshader")
	mat.set_shader_parameter("mask_a", ImageTexture.create_from_image(ia))
	mat.set_shader_parameter("mask_b", ImageTexture.create_from_image(ib))
	for i in MAX_SLOTS:
		var terrain: int = used[mini(i, used.size() - 1)]
		mat.set_shader_parameter("tex%d" % i, _terrain_tex[mini(terrain, _terrain_tex.size() - 1)])
	mat.set_shader_parameter("noise_tex", _noise_tex)
	mat.set_shader_parameter("rect_origin", origin)
	mat.set_shader_parameter("mask_origin", origin - Vector2(tile_size) * pad)
	mat.set_shader_parameter("mask_size", Vector2(side * tile_size.x, side * tile_size.y))
	mat.set_shader_parameter("tile", terrain_texture_size)
	mat.set_shader_parameter("blur_px", blur_px)
	mat.set_shader_parameter("edge_noise", edge_noise)
	rect.material = mat
	_ground_root.add_child(rect)
	ch.nodes.append(rect)


func _build_tufts(ch: Chunk) -> void:
	if tuft_density <= 0.0 or _tuft_tex.is_empty():
		return
	var cs := chunk_size
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(ch.coord) + 77
	var px := Vector2(cs * tile_size.x, cs * tile_size.y)
	var origin := Vector2(ch.coord * cs * tile_size)
	var buckets: Array = []
	for _i in _tuft_tex.size():
		buckets.append([])
	for _i in int(px.x * px.y * tuft_density):
		var p := Vector2(rng.randf() * px.x, rng.randf() * px.y)
		var tile := Vector2i(origin / Vector2(tile_size)) + Vector2i(p / Vector2(tile_size))
		var s := rng.randf_range(0.8, 1.15)
		var flip := rng.randf() < 0.5
		var variant := rng.randi() % _tuft_tex.size()
		if _terrain_at(tile) != 0 or _has_detail(tile):
			continue
		buckets[variant].append(Transform2D(0.0, Vector2(-s if flip else s, s), 0.0, origin + p))
	for v in _tuft_tex.size():
		var list: Array = buckets[v]
		if list.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.mesh = _tuft_mesh[v]
		mm.instance_count = list.size()
		for k in list.size():
			mm.set_instance_transform_2d(k, list[k])
		var mmi := MultiMeshInstance2D.new()
		mmi.multimesh = mm
		mmi.texture = _tuft_tex[v]
		mmi.material = _tuft_mat
		_flat.add_child(mmi)
		ch.nodes.append(mmi)


# ---------- objekty ----------

func _texture(path: String) -> Texture2D:
	if not _tex_cache.has(path):
		_tex_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex_cache[path]


func _tile_texture(gid: int) -> Texture2D:
	if _gid_image.has(gid):
		return _texture(_gid_image[gid])
	for a in _atlas_info:
		if gid >= a[0] and gid < a[0] + a[1]:
			var local: int = gid - a[0]
			var t := AtlasTexture.new()
			t.atlas = a[2]
			t.region = Rect2(a[6] + (local % a[3]) * (a[4] + a[7]), a[6] + (local / a[3]) * (a[5] + a[7]), a[4], a[5])
			return t
	return null


func _add_prop(ch: Chunk, id: String, tex: Texture2D, pos: Vector2, pr: Dictionary) -> Node:
	var collision := String(pr.get("collision", PropFactory.default_collision(id, tex)))
	var swayed: bool = pr.get("sway", id.begins_with("tree_"))
	var body := PropFactory.build(tex, pos, collision, _tree_mat if swayed else null, pr.get("flip", false))
	objects.add_child(body)
	if pr.get("shadow", true):
		var sv := PropFactory.shadow_for(id, tex)
		if pr.has("shadow_size"):
			var q := String(pr.shadow_size).split(",")
			sv = Vector2(float(q[0]), float(q[1]))
		var sh := Fx.shadow_sprite(sv.x, sv.y)
		sh.position = pos + Vector2(sv.x * 0.18, -sv.y * 0.2)
		_shadows.add_child(sh)
		ch.nodes.append(sh)
	return body


func _spawn_prop(o: Dictionary, ch: Chunk) -> Node:
	var id := String(o.props.get("id", o.name))
	var tex := _texture("res://assets/world/%s.png" % id)
	if tex == null:
		push_warning("TiledWorld: neznámý prop '%s'" % id)
		return null
	return _add_prop(ch, id, tex, Vector2(o.x, o.y), o.props)


func _spawn_tile_object(o: Dictionary, ch: Chunk) -> Node:
	var gid := int(o.gid) & 0x1FFFFFFF
	var tex := _tile_texture(gid)
	if tex == null:
		return null
	var pr: Dictionary = _gid_props.get(gid, {}).duplicate()
	pr.merge(o.props, true)
	var w: float = o.w if o.w > 0 else tex.get_width()
	return _add_prop(ch, String(pr.get("id", o.name)), tex, Vector2(o.x + w / 2.0, o.y), pr)


func _spawn_campfire(o: Dictionary, ch: Chunk) -> Node:
	var fire := Campfire.new()
	fire.position = Vector2(o.x, o.y)
	objects.add_child(fire)
	var sh := Fx.shadow_sprite(30, 9)
	sh.position = fire.position + Vector2(4, -3)
	_shadows.add_child(sh)
	ch.nodes.append(sh)
	return fire


func _spawn_light(o: Dictionary, _ch: Chunk) -> Node:
	var l := PointLight2D.new()
	l.texture = Fx.light_texture()
	l.position = Vector2(o.x, o.y)
	l.color = Color.html(String(o.props.get("color", "#ffb070")))
	l.energy = float(o.props.get("energy", 1.0))
	l.texture_scale = float(o.props.get("radius", 300.0)) / 128.0
	add_child(l)
	return l
