extends Node
## Test: hodiny, craft, vaření, spánek, sběr surovin a hrobka: res://tests/dungeon_test.tscn

func _ready() -> void:
	var main: Node = load("res://scenes/main_turn3.tscn").instantiate()
	add_child(main)
	await main.started
	await get_tree().process_frame
	var hero: Hero = main.hero
	await get_tree().process_frame
	_check(main._clock.text.contains("Den 1"), "hodiny: " + main._clock.text)
	# sběr
	var vein: Prop
	for p in main.props:
		if p.kind == &"iron_vein":
			vein = p
	hero.global_position = vein.global_position
	_check(main._nearest_prop() == vein, "u železné žíly")
	main._use_prop(vein)
	_check(hero.inventory.count(&"iron") >= 1 and vein.depleted, "sebráno železo")
	# craft
	hero.inventory.add(&"iron", 5)
	var recipe: Dictionary = Recipes.WORK[0]
	_check(Recipes.make(hero, recipe) and hero.inventory.has(&"sword"), "kování meče")
	hero.inventory.add(&"meat", 2)
	hero.inventory.add(&"mushroom", 1)
	hero.inventory.add(&"herb", 3)
	_check(Recipes.make(hero, Recipes.COOK[1]), "guláš")
	_check(Recipes.make(hero, Recipes.COOK[2]), "čaj")
	var cons := BattleScene3.consumables_of(hero)
	_check(int(cons.get(&"stew", 0)) == 1 and int(cons.get(&"tea", 0)) == 2, "jídlo mezi předměty")
	main._craft.open(hero, &"campfire")
	await get_tree().process_frame
	main._craft.close()
	# spánek
	main.world.set_time(22.0)
	main._last_hour = 22.0
	hero.gold = 50
	hero.hp = 5
	await main._sleep(true)
	_check(absf(main.world.hour - 7.0) < 0.1 and main.days == 2, "probuzení v 7:00, den 2 (%.1f, %d)" % [main.world.hour, main.days])
	_check(hero.hp == hero.max_hp() and hero.gold == 40, "spánek léčí a stojí 10 zlata")
	_check(not vein.depleted, "suroviny dorostly")
	# hrobka
	hero.global_position = main._tomb_enter + Vector2(0, 20)
	await main._go_tomb(true)
	await get_tree().create_timer(0.5).timeout
	_check(main.inside_dungeon and Dungeon.ORIGIN.distance_to(hero.global_position) < 80, "hrdina v hrobce")
	var foes := 0
	for n in get_tree().get_nodes_in_group(&"characters"):
		if n is TurnEnemy3 and n.has_meta(&"dungeon_idx"):
			foes += 1
	_check(foes == 8, "8 nepřátel v hrobce (%d)" % foes)
	for n in get_tree().get_nodes_in_group(&"characters"):
		if n is TurnEnemy3 and n.has_meta(&"dungeon_idx"):
			n.get_parent().remove_child(n)
			n.queue_free()
	hero.global_position = Dungeon.ORIGIN + Vector2(500, 500)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(main.dungeon.walkable(hero.global_position), "mimo místnosti se zastaví")
	get_viewport().get_texture().get_image().save_png("/tmp/claude-0/dungeon1.png")
	# mříž
	hero.global_position = Dungeon.ORIGIN + Vector2(0, Dungeon.GATE_Y + 30)
	_check(not main.dungeon.walkable(Dungeon.ORIGIN + Vector2(0, Dungeon.GATE_Y)), "mříž blokuje")
	hero.inventory.add(&"archive_key")
	main._use_gate(main._nearest_prop())
	_check(main.dungeon.gate_open and main.dungeon.walkable(Dungeon.ORIGIN + Vector2(0, Dungeon.GATE_Y)), "klíč otevřel mříž")
	hero.global_position = Dungeon.ORIGIN + Vector2(0, -1200)
	await get_tree().create_timer(1.8).timeout
	get_viewport().get_texture().get_image().save_png("/tmp/claude-0/dungeon2.png")
	# pasti
	hero.global_position = Dungeon.ORIGIN + Dungeon.TRAPS[1]
	var hp0 := hero.hp
	for i in 80:
		await get_tree().process_frame
	_check(hero.hp < hp0, "past ublížila")
	# boss truhla + odchod
	main._boss_chest()
	main.quests.set_flag("tomb_cleared")
	main.save_game(3)
	await main._go_tomb(false)
	await get_tree().create_timer(0.5).timeout
	_check(not main.inside_dungeon and hero.global_position.distance_to(main._door_out) < 60, "zpět venku")
	var outside := 0
	for n in get_tree().get_nodes_in_group(&"characters"):
		if n is Villager:
			outside += 1
	_check(outside == 4, "vesničané se vrátili")
	DirAccess.remove_absolute(SaveGame.path(3))
	print("DUNGEON OK")
	get_tree().quit()


func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("FAIL: " + msg)
		get_tree().quit(1)
