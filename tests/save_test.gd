extends Node
## Test ukládání, truhel a páčení: res://tests/save_test.tscn

func _ready() -> void:
	var main: Node = load("res://scenes/main_turn3.tscn").instantiate()
	add_child(main)
	await main.started
	await get_tree().process_frame
	var hero: Hero = main.hero
	var chests := get_tree().get_nodes_in_group(&"chests")
	_check(chests.size() == 3, "3 truhly (%d)" % chests.size())
	# odemčená truhla
	var c0: Chest = chests[0]
	hero.global_position = c0.global_position
	var g0 := hero.gold
	main._open_chest(c0)
	_check(c0.opened and hero.gold > g0, "odemčená truhla dala zlato")
	# páčení: simulace ideálního hráče
	var c1: Chest = chests[1]
	main._open_chest(c1)
	await get_tree().process_frame
	var game: LockpickGame = null
	for n in main.get_children():
		if n is LockpickGame:
			game = n
	_check(game != null, "minihra se spustila")
	game._angle = game._sweet
	game._holding = true
	for i in 120:
		await get_tree().process_frame
		if not is_instance_valid(game):
			break
	_check(c1.opened, "zámek se podařilo vypáčit")
	# uložení a načtení
	hero.gold = 777
	hero.level = 4
	_check(main.save_game(3), "uloženo")
	_check(SaveGame.summary(3).contains("úr. 4"), "popis slotu: " + SaveGame.summary(3))
	var d := SaveGame.read(3)
	hero.gold = 1
	hero.level = 1
	c0.set_open(false)
	main.opened_chests.clear()
	SaveGame.apply(main, d)
	_check(hero.gold == 777 and hero.level == 4, "načtení obnovilo hrdinu")
	_check(c0.opened and c1.opened and not (chests[2] as Chest).opened, "načtení obnovilo truhly")
	DirAccess.remove_absolute(SaveGame.path(3))
	print("SAVE OK")
	get_tree().quit()


func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("FAIL: " + msg)
		get_tree().quit(1)
