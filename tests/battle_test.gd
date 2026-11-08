extends Node
## Test tahového souboje: godot --headless --path . res://tests/battle_test.tscn
## (s xvfb-run + --rendering-driver opengl3 vznikají i screenshoty v /tmp/claude-0/)

func _ready() -> void:
	var main: Node = load("res://scenes/main_turn.tscn").instantiate()
	add_child(main)
	await main.started
	await get_tree().process_frame
	var hero: Hero = main.hero
	var enemies: Array[Character] = []
	for c in get_tree().get_nodes_in_group(&"characters"):
		if c is TurnEnemy:
			enemies.append(c)
	_check(enemies.size() == 2, "dva nepřátelé na mapě (%d)" % enemies.size())
	# dotek nepřítele spustí souboj (ne reálný útok)
	var e0: TurnEnemy = enemies[0]
	hero.global_position = e0.global_position + Vector2(-20, 0)
	for i in 30:
		await get_tree().physics_frame
	_check(main.in_battle, "dotek nepřítele spustí tahový souboj")
	var battle: BattleScene = main.get_node("Battle")
	battle.autoplay = true
	await _shot("/tmp/claude-0/battle_start.png")
	await get_tree().create_timer(3.0).timeout
	await _shot("/tmp/claude-0/battle_mid.png")
	var hp0 := hero.hp
	# čekáme na konec souboje
	for i in 900:
		await get_tree().create_timer(0.1).timeout
		if not main.in_battle:
			break
	_check(not main.in_battle, "souboj skončil")
	_check(hero.xp > 0 or hero.level > 1, "hrdina dostal zkušenosti")
	_check(hero.gold > 50, "hrdina dostal zlato")
	_check(hero.controls_enabled, "ovládání vráceno")
	_check(not get_tree().paused, "svět se odpauzoval")
	print("HP před/po: %d/%d, XP %d, zlato %d" % [hp0, hero.hp, hero.xp, hero.gold])
	print("BATTLE OK")
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
