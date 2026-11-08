extends Node
## Test Tahu 3: třída, dialogy (nábor), questy, souboj ve třech.  res://tests/tah3_test.tscn

var result := {}

func _ready() -> void:
	Session.class_id = &"chronicler"
	var main: Node = load("res://scenes/main_turn3.tscn").instantiate()
	add_child(main)
	await main.started
	await get_tree().process_frame
	var hero: Hero = main.hero
	_check(hero.get_meta(&"class_id") == &"chronicler", "třída aplikována")
	_check(hero.equipment.get_item(ItemData.Slot.WEAPON) != null, "třída vybavila zbraň")
	_check(main.quests.status("companions") == "active", "quest Najdi společníky běží")
	# --- dialog: Mira se přidá (bez UI, přímo runner)
	for cid in ["mira", "borek"]:
		var r := DialogueRunner.new()
		r.quests = main.quests
		r.hero = hero
		r.party = main.party
		var seen := []
		r.node_shown.connect(func(sp, tx, ch): seen.append([sp, tx, ch]))
		r.action.connect(main._on_dialogue_action)
		_check(r.start(cid), "dialog %s se spustil" % cid)
		_check(seen.size() == 1 and seen[0][2].size() == 2, "intro %s má 2 volby: %s" % [cid, str(seen)])
		r.choose(0)   # "Pojď s námi"
		r.advance()
	_check(main.party.size() == 3, "družina má 3 členy (%d)" % main.party.size())
	_check(main.quests.status("companions") == "done", "quest Najdi společníky se sám odevzdal")
	_check(hero.gold >= 70, "odměna 20 zlata (%d)" % hero.gold)
	# dialog s obchodníkem: nabídka questu
	var r2 := DialogueRunner.new()
	r2.quests = main.quests
	r2.hero = hero
	r2.party = main.party
	var seen2 := []
	r2.node_shown.connect(func(sp, tx, ch): seen2.append([sp, tx, ch]))
	r2.start("merchant")
	_check(seen2[0][2].size() == 3 and "Chronicler" != "", "obchodník nabízí 3 volby (obchod, práce, nashle)")
	r2.choose(1)   # "Nemáš práci?"
	r2.choose(0)   # "Beru to"
	_check(main.quests.status("bandits") == "active", "quest zbojníci začal")
	# --- souboj ve třech
	var enemies: Array = get_tree().get_nodes_in_group(&"characters").filter(func(c): return c is TurnEnemy3)
	var e0: TurnEnemy3 = enemies[0]
	hero.global_position = e0.global_position + Vector2(-50, 0)
	for c in main.party:
		c.global_position = hero.global_position
	await get_tree().physics_frame
	main._on_contact(e0, &"")
	_check(main.in_battle, "souboj spuštěn")
	var battle: BattleScene3 = main.get_node("Battle")
	battle.autoplay = true
	battle.finished.connect(func(r): result = r)
	await get_tree().create_timer(3.0).timeout
	await _shot("/tmp/claude-0/t3_battle.png")
	for i in 2400:
		await get_tree().create_timer(0.1).timeout
		if not main.in_battle:
			break
	_check(not main.in_battle, "souboj skončil")
	print("Souboj: ", result)
	_check(result.get("outcome") == &"victory", "vítězství")
	_check("bandit" in result.get("kills", []), "zabití zbojníka se zaznamenalo")
	_check(main.quests.progress_of("bandits", main.quests.defs["bandits"]["objectives"][0]) >= 1, "quest zbojníci se posunul")
	print("TAH3 OK")
	get_tree().quit()


func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("FAIL: " + msg)
		print("FAIL: ", msg)
		get_tree().quit(1)


func _shot(path: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	if img:
		img.save_png(path)
