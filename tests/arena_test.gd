extends Node
## Snímek HD-2D bojiště: res://tests/arena_test.tscn (ukládá /tmp/claude-0/arena.png)

func _ready() -> void:
	var main: Node = load("res://scenes/main_turn3.tscn").instantiate()
	add_child(main)
	await main.started
	var enemies := []
	for c in get_tree().get_nodes_in_group(&"characters"):
		if c is TurnEnemy3:
			enemies.append(c)
	main.hero.global_position = enemies[0].global_position + Vector2(-20, 0)
	for i in 30:
		await get_tree().physics_frame
	_check(main.in_battle, "souboj začal")
	await get_tree().create_timer(2.5).timeout
	for n in main.get_node("Battle").get_children():
		if n is BattleArena3D:
			var v: SubViewport = n.get_child(0)
			print("ARENA size ", n.size, " vp ", v.size, " vis ", n.visible, " tex ", v.get_texture().get_image().get_pixel(100, 100), " ", v.get_texture().get_image().get_pixel(600, 600))
	get_viewport().get_texture().get_image().save_png("/tmp/claude-0/arena.png")
	print("ARENA OK")
	get_tree().quit()


func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("FAIL: " + msg)
		get_tree().quit(1)
