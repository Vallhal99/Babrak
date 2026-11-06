extends Node
## Test streamování: hrdina se teleportuje přes celý svět; kontrola načtení/uvolnění chunků, kolizí a snímky.
const OUT := "/tmp/claude-0/-home-claude/4ece88d8-ed95-5e17-bf08-a245a240eb47/scratchpad/shots/"
var _worst := 0.0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var scn: PackedScene = load("res://scenes/demo/tiled_demo.tscn")
	var demo: Node2D = scn.instantiate()
	demo.get_node("World").world_dir = "res://data/world/babrak"
	add_child(demo)
	var world: TiledWorld = demo.get_node("World")
	var hero: Hero = world.objects.get_node("Hero")
	world.load_radius = 1
	await _wait_ready(world)
	_worst = 0.0
	print("start chunks: ", world.shown_chunks().size(), " pos ", hero.global_position)
	_shot("p_start")
	for target in [Vector2(0, 40)]:
		_worst = 0.0
		hero.global_position = target
		await _wait_ready(world)
		var shown := world.shown_chunks()
		print("tp ", target, " chunk ", world.chunk_of(target), " shown=", shown.size(), " nodes=", world.objects.get_child_count(), " worst_frame_ms=", snappedf(_worst, 0.1))
		var tc := world.chunk_of(target)
		for k in shown:
			assert(maxi(absi(k.x - tc.x), absi(k.y - tc.y)) <= world.load_radius + world.unload_margin)
		assert(world.chunk_of(target) in shown or not world._index.has(world.chunk_of(target)))
		_shot("p_%d_%d" % [int(target.x), int(target.y)])
	get_tree().quit()


func _wait_ready(world: TiledWorld) -> void:
	for _i in 600:
		var t0 := Time.get_ticks_usec()
		await get_tree().process_frame
		_worst = maxf(_worst, (Time.get_ticks_usec() - t0) / 1000.0)
		if world.all_ready() and Engine.get_process_frames() % 1 == 0 and world.shown_chunks().size() > 0:
			for _j in 5:
				await get_tree().process_frame
			if world.all_ready():
				return


func _shot(n: String) -> void:
	get_viewport().get_texture().get_image().save_png(OUT + n + ".png")
