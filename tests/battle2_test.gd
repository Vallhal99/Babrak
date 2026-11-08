extends Node
## Test Tahu 2: godot --headless --path . res://tests/battle2_test.tscn  (xvfb + opengl3 pro snímky)

var result := {}

func _ready() -> void:
	var main: Node = load("res://scenes/main_turn2.tscn").instantiate()
	add_child(main)
	await main.started
	await get_tree().process_frame
	var hero: Hero = main.hero
	for id in [&"sword", &"boots", &"gloves", &"wizard_hat", &"plate"]:
		hero.equipment.equip(ItemDB.get_item(id), hero.inventory)
	var enemies: Array = get_tree().get_nodes_in_group(&"characters").filter(func(c): return c is TurnEnemy2)
	_check(enemies.size() == 5, "5 nepřátel (2 smečky): %d" % enemies.size())
	_check(enemies.any(func(e): return e.rank == &"elite"), "na mapě je elita")
	# --- souboj 1: noc + déšť, spojenec, zálusk
	main.world.set_stage(2, true)
	main.world.fx.set_weather("déšť")
	var e0: TurnEnemy2 = enemies[0]
	main.merchant.global_position = e0.global_position + Vector2(-100, 0)
	hero.global_position = e0.global_position + Vector2(-50, 0)
	hero.facing = AnimCatalog.Dir.RIGHT
	for i in 5:
		await get_tree().physics_frame
	main._on_contact(e0, &"hero")
	_check(main.in_battle, "souboj spuštěn")
	var battle: BattleScene2 = main.get_node("Battle")
	battle.autoplay = true
	battle.finished.connect(func(r): result = r)
	await get_tree().create_timer(2.5).timeout
	await _shot("/tmp/claude-0/b2_start.png")
	await get_tree().create_timer(6.0).timeout
	await _shot("/tmp/claude-0/b2_mid.png")
	for i in 1800:
		await get_tree().create_timer(0.1).timeout
		if not main.in_battle:
			break
	_check(not main.in_battle, "souboj 1 skončil")
	print("Souboj 1: ", result, " kol=", "?")
	_check(hero.controls_enabled and not get_tree().paused, "ovládání vráceno")
	# --- souboj 2: den, vyjednávání (úplatek) s druhou smečkou
	main.world.fx.set_weather("jasno")
	main.world.set_stage(0, true)
	hero.add_gold(300)
	hero.hp = hero.max_hp()
	var e1: TurnEnemy2 = enemies[3] if is_instance_valid(enemies[3]) else null
	_check(e1 != null, "druhá smečka existuje")
	hero.global_position = e1.global_position + Vector2(-40, 0)
	await get_tree().physics_frame
	main._on_contact(e1, &"enemy")
	var b2: BattleScene2 = main.get_node("Battle")
	b2.autoplay = true
	b2.script_actions = [{"kind": &"talk", "mode": &"bribe"}]
	b2.finished.connect(func(r): result = r)
	await _shot("/tmp/claude-0/b2_elite.png")
	for i in 900:
		await get_tree().create_timer(0.1).timeout
		if not main.in_battle:
			break
	_check(not main.in_battle, "souboj 2 skončil")
	_check(result.get("outcome") == &"negotiated", "úplatek ukončil souboj: %s" % str(result))
	print("TAH2 OK")
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
