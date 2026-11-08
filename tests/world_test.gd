extends Node
## Test Tahu 3 – svět: vesničané, interiér, pochodeň, deník, nastavení: res://tests/world_test.tscn

func _ready() -> void:
	var main: Node = load("res://scenes/main_turn3.tscn").instantiate()
	add_child(main)
	await main.started
	await get_tree().process_frame
	var hero: Hero = main.hero
	_check(main.villagers.size() == 4, "4 vesničané")
	main.world.set_time(10.0)
	for i in 5:
		await get_tree().process_frame
	var v: Villager = main.villagers[0]
	v._snap_to_schedule()
	_check(v.visible and v.activity != "", "ráno vesničan venku: " + v.activity)
	main.world.set_time(23.0)
	for v2 in main.villagers:
		v2._snap_to_schedule()
	_check(main.villagers.all(func(x: Villager) -> bool: return not x.visible), "v noci všichni doma")
	# plán: změna hodiny spustí cestu a dojde se
	main.world.set_time(8.0)
	v._at_key = ""
	v._process(0.1)
	_check(not v._route.is_empty() or v.visible, "ráno vyráží")
	# interiér
	hero.global_position = Vector2(1296, 880)
	await get_tree().process_frame
	_check(main._door.is_near(), "u dveří")
	main._go_shop(true)
	await get_tree().create_timer(1.0).timeout
	_check(main.inside_shop and main.interior.contains(hero.global_position), "hrdina v interiéru")
	await get_tree().create_timer(1.5).timeout
	get_viewport().get_texture().get_image().save_png("/tmp/claude-0/interior.png")
	hero.global_position = Interior.CENTER + Vector2(40, -40)
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png("/tmp/claude-0/interior2.png")
	var d: float = main.merchant.global_position.distance_to(hero.global_position)
	_check(d < 90.0, "obchodník je na dosah (%d)" % d)
	hero.global_position = main.interior.entrance + Vector2(0, 40)
	await get_tree().create_timer(1.2).timeout
	_check(not main.inside_shop and hero.global_position.y < 1000, "východ vede ven")
	# pochodeň
	var torch := ItemDB.get_item(&"torch")
	_check(torch != null and torch.light > 0.0, "pochodeň existuje")
	# deník
	main.codex.record_battle({"seen": [{"id": "bandit", "revealed": ["blunt"]}], "kills": ["bandit"]})
	_check("zbojnici" in main.codex.lore and main.codex.beasts["bandit"]["kills"] == 1, "bestiář a lore")
	_check(main.codex.beast_text("bandit").contains("drtivé"), "odhalená slabina v textu")
	main._codex_panel.toggle()
	await get_tree().process_frame
	main._codex_panel.toggle()
	# dialog vesničana s hodinou
	var runner := DialogueRunner.new()
	runner.quests = main.quests
	runner.hero = hero
	runner.codex = main.codex
	runner.hour = 8.0
	_check(runner.start("villager_hana"), "dialog vesničana")
	# nastavení
	Settings.set_value("text_speed", 2.0)
	_check(Settings.text_speed == 2.0, "nastavení platí")
	Settings.set_value("text_speed", 1.0)
	# uložení kodexu
	_check(main.save_game(3), "uloženo")
	main.codex.lore.clear()
	SaveGame.apply(main, SaveGame.read(3))
	_check("zbojnici" in main.codex.lore, "deník se načetl")
	DirAccess.remove_absolute(SaveGame.path(3))
	print("WORLD OK")
	get_tree().quit()


func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("FAIL: " + msg)
		get_tree().quit(1)
