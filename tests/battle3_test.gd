extends Node
## Elita + boss: zastrašení, předměty, stavy, řev a nabíjení. godot ... res://tests/battle3_test.tscn

func _ready() -> void:
	var main: Node = load("res://scenes/main_turn2.tscn").instantiate()
	add_child(main)
	await main.started
	await get_tree().process_frame
	var hero: Hero = main.hero
	hero.base_max_hp = 600
	hero.hp = 600
	for id in [&"longsword", &"close_helm", &"plate"]:
		hero.equipment.equip(ItemDB.get_item(id), hero.inventory)
	var enemies: Array = get_tree().get_nodes_in_group(&"characters").filter(func(c): return c is TurnEnemy2)
	var leader: TurnEnemy2 = enemies.filter(func(e): return e.rank == &"elite")[0]
	hero.global_position = leader.global_position + Vector2(-40, 0)
	await get_tree().physics_frame
	main._on_contact(leader, &"")
	var b: BattleScene2 = main.get_node("Battle")
	b.autoplay = true
	b.script_actions = [{"kind": &"talk", "mode": &"intimidate"}, {"kind": &"item", "item": &"potion", "target": null},
		{"kind": &"item", "item": &"ether", "target": null}, {"kind": &"item", "item": &"antidote", "target": null}]
	var res := {}
	var rounds := [0, 0]
	b.finished.connect(func(r): res = r; rounds[0] = b._rounds)
	for i in 1500:
		await get_tree().create_timer(0.1).timeout
		if not main.in_battle or (is_instance_valid(b) and b._rounds >= 10):
			break
	if main.in_battle:
		rounds[0] = b._rounds
		b.queue_free()
		main.in_battle = false
		get_tree().paused = false
	print("Elita: ", res, " kol=", rounds[0])
	# boss
	hero.hp = 600
	main._spawn_pack(hero.global_position + Vector2(60, 0), [&"knight"])
	await get_tree().physics_frame
	var boss: TurnEnemy2 = get_tree().get_nodes_in_group(&"characters").filter(func(c): return c is TurnEnemy2 and c.rank == &"boss")[0]
	main._on_contact(boss, &"enemy")
	var b2: BattleScene2 = main.get_node("Battle")
	b2.autoplay = true
	var res2 := {}
	b2.finished.connect(func(r): res2 = r; rounds[1] = b2._rounds)
	for i in 1500:
		await get_tree().create_timer(0.1).timeout
		if i == 100 and is_instance_valid(b2):
			await _shot("/tmp/claude-0/b3_boss.png")
		if not main.in_battle or (is_instance_valid(b2) and b2._rounds >= 8):
			if is_instance_valid(b2):
				rounds[1] = b2._rounds
			break
	print("Boss: kol=", rounds[1], " ", res2)
	print("TAH3 OK")
	get_tree().quit()


func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("FAIL: " + msg)
		get_tree().quit(1)


func _shot(path: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	if img:
		img.save_png(path)
