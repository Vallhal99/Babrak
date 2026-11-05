extends Node
## Spuštění: godot --headless --path . res://tests/smoke_test.tscn
## (s xvfb-run + --rendering-driver opengl3 vznikají i screenshoty v /tmp/claude-0/)

func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var hero: Hero = main.get_node("Hero")
	var enemy: Enemy = get_tree().get_nodes_in_group(&"characters").filter(func(c): return c.team == &"enemy")[0]
	var panel: InventoryPanel = main.get_node("InventoryPanel")
	for entry in enemy.loot:
		entry.chance = 1.0
	var merchant: Npc = main.get_node("Merchant")
	_check(merchant.invulnerable and merchant.team == &"npc", "obchodník je neutrální")
	var n := ItemDB.all().size()
	_check(hero.inventory.ids().size() == n and n == 18, "batoh má 18 předmětů")
	for id in [&"longsword", &"close_helm", &"boots"]:
		_check(hero.equipment.equip(ItemDB.get_item(id), hero.inventory), "equip " + id)
	_check(hero.attack_power() == 7 and hero.defense() == 5, "staty z vybavení")
	# všechny animace a směry (včetně kombinovaných) nesmí spadnout
	for a in AnimCatalog.ANIMS:
		for d in 8:
			hero.visual.play(a, d, true)
			for i in 40:
				hero.visual._process(0.05)
	_check(AnimCatalog.dir8(Vector2(1, 1)) == AnimCatalog.Dir.DOWN_RIGHT and AnimCatalog.dir8(Vector2(-1, 0)) == AnimCatalog.Dir.LEFT, "8 směrů z vektoru")
	_check(AnimCatalog.resolve(&"walk", AnimCatalog.Dir.UP_LEFT) == [&"walk_diag", 0] and AnimCatalog.resolve(&"idle", AnimCatalog.Dir.DOWN_LEFT) == [&"idle", AnimCatalog.Dir.DOWN], "diagonály: jen chůze/běh mají vlastní animaci")
	hero.visual.play(&"walk", AnimCatalog.Dir.LEFT, true)
	main.get_node("Map").set_night(true)
	await _shot("/tmp/claude-0/shot_walk.png")
	hero.visual.play(&"walk", AnimCatalog.Dir.DOWN_RIGHT, true)
	hero.visual._process(0.3)
	await _shot("/tmp/claude-0/shot_diag.png")
	# souboj: nepřítel vedle hrdiny
	enemy.global_position = hero.global_position + Vector2(40, 0)
	hero.facing = AnimCatalog.Dir.RIGHT
	var start_hp := enemy.hp
	hero._start_attack()
	for i in 60:
		await get_tree().physics_frame
	_check(enemy.hp < start_hp, "hrdina zranil nepřítele (%d -> %d)" % [start_hp, enemy.hp])
	for i in 400:  # nepřítel se brání / hrdina dobíjí
		hero.facing = Character.dir_from(enemy.global_position - hero.global_position)
		hero.attack_input = true
		hero._start_attack() if not hero._attacking and not enemy.dead else null
		await get_tree().physics_frame
		if enemy.dead: break
	_check(enemy.dead, "nepřítel padl")
	var drops := main.get_children().filter(func(c): return c is Pickup)
	_check(drops.size() == 4, "spadly 4 předměty (%d)" % drops.size())
	var before := hero.inventory.count(&"chainmail")
	hero.global_position = (drops[0] as Pickup).global_position
	for i in 60:
		await get_tree().physics_frame
	_check(hero.inventory.count(&"chainmail") + hero.inventory.count(&"hood") > before, "sebrání předmětu")
	_check(hero.hp < hero.max_hp(), "nepřítel zranil hrdinu")
	hero.equipment.unequip_all(hero.inventory)
	_check(hero.inventory.ids().size() == n, "svlečeno vše zpět v batohu")
	hero.equipment.equip(ItemDB.get_item(&"sword"), hero.inventory)
	main.get_node("Map").set_night(false)
	panel.toggle()
	_check(not hero.controls_enabled, "inventář zamkne ovládání")
	await _shot("/tmp/claude-0/shot_inventory.png")
	merchant.take_damage(99)
	_check(merchant.hp == merchant.max_hp() and not merchant.dead, "obchodník nejde zranit")
	# obchod
	var shop: ShopPanel = main.get_node("ShopPanel")
	hero.equipment.unequip_all(hero.inventory)
	hero.global_position = merchant.global_position + Vector2(0, 30)
	hero.try_interact()
	_check(shop.visible and not hero.controls_enabled, "interakce otevře obchod")
	await _shot("/tmp/claude-0/shot_shop.png")
	var g0 := hero.gold
	_check(g0 == 50 + 8, "zlato za zabití (%d)" % g0)
	var sword := ItemDB.get_item(&"longsword")
	_check(not shop.buy(sword), "nelze koupit bez zlata")
	hero.add_gold(100)
	var cnt := hero.inventory.count(&"longsword")
	_check(shop.buy(sword) and hero.gold == g0 + 100 - 120 + 0 and hero.inventory.count(&"longsword") == cnt + 1, "nákup")
	_check(shop.sell(sword) and hero.gold == g0 + 100 - 120 + 60 and hero.inventory.count(&"longsword") == cnt, "prodej za polovinu")
	shop.close()
	_check(hero.controls_enabled, "obchod zavřen")
	# úroveň / mana / kouzla
	_check(hero.xp == 15 and hero.level == 1, "XP za zabití (%d)" % hero.xp)
	hero.gain_xp(30)
	_check(hero.level == 2 and hero.skill_points == 5, "level up dá 5 bodů")
	var mhp := hero.max_hp()
	_check(hero.spend_point(&"vitality") and hero.max_hp() == mhp + 4 and hero.skill_points == 4, "utracení bodu")
	for i in 4:
		hero.spend_point(&"strength")
	_check(not hero.spend_point(&"spirit"), "bez bodů nejde")
	var e2: Enemy = get_tree().get_nodes_in_group(&"characters").filter(func(c): return c.team == &"enemy" and not c.dead)[0]
	e2.global_position = hero.global_position + Vector2(100, 0)
	e2.sight = 0.0  # nehýbe se
	hero.facing = AnimCatalog.Dir.RIGHT
	var mana0 := hero.mana
	var hp0 := e2.hp
	while hero._attacking:
		await get_tree().physics_frame
	_check(hero.cast(hero.spells[0]), "kouzlo seslano")
	for i in 90:
		await get_tree().physics_frame
	_check(hero.mana < mana0 and e2.hp < hp0, "ohnivá koule zranila (%d -> %d)" % [hp0, e2.hp])
	var hp1 := hero.hp
	hero.hp = 5
	_check(hero.cast(hero.spells[1]), "léčení seslano")
	for i in 40:
		await get_tree().physics_frame
	_check(hero.hp > 5, "léčení léčí")
	(panel.find_children("*", "TabContainer", true, false)[0] as TabContainer).current_tab = 1  # 1 = Dovednosti, 2 = Kouzla
	await _shot("/tmp/claude-0/shot_spells.png")
	panel.toggle()
	hero.facing = AnimCatalog.Dir.RIGHT
	hero.mana = 20.0
	hero.cast(hero.spells[0])
	for i in 28:
		await get_tree().physics_frame
	await _shot("/tmp/claude-0/shot_hud.png")
	print("SMOKE OK")
	get_tree().quit()

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("FAIL: " + msg)
		get_tree().quit(1)

func _shot(path: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	if img: img.save_png(path)
