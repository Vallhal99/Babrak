extends Node2D
## Herní scéna "Nová hra tah 3": Tah 2 + výběr třídy (Session.class_id), družina až o 3 lidech
## (hrdina + 2 společníci z dialogů), dialogový systém (data/dialogues) a questy (data/quests).
## Souboj: scripts/battle3/. Tvorba dialogů a questů: tools/dialog_editor.html.

signal started

const HERO := preload("res://scenes/characters/hero.tscn")
const MERCHANT := preload("res://scenes/characters/merchant.tscn")
const COMPANION := preload("res://scenes/characters/companion.tscn")
const ENEMY := preload("res://scenes/characters/turn_enemy3.tscn")
const ENEMY_RESPAWN := 8.0
const MERCHANT_OFFSET := Vector2(-150, -60)
const COMPANION_OFFSETS := {&"mira": Vector2(-70, 90), &"borek": Vector2(90, -90)}
const PACK_OFFSETS: Array[Vector2] = [Vector2(260, 40), Vector2(-120, 190)]
const PACKS := [[&"bandit", &"archer"], [&"leader", &"bandit", &"archer"]]
const JOIN_RADIUS := 170.0
const MAX_GROUP := 3
const MAX_PARTY := 3
const TALK_RANGE := 70.0
const STRIKE_RANGE := 80.0

@onready var world: Hd2dWorld = $World
@onready var _panel: InventoryPanel = $InventoryPanel
@onready var _hud: Hud = $Hud
@onready var _shop: ShopPanel = $ShopPanel

var hero: Hero
var merchant: Npc
var party: Array[Character] = []   ## hrdina + společníci (max 3)
var quests := QuestLog.new()
var codex := Codex.new()
var interior: Interior
var inside_shop := false
var _door_out := Vector2.ZERO
var _door: Door
var _codex_panel: CodexPanel
var _fade: ColorRect
var villagers: Array[Villager] = []
const SHOP_DOOR := Vector2(1296, 872)   ## vchod do hostince (obchodu)
const VILLAGER := preload("res://scenes/characters/villager.tscn")
const DAY_LENGTH := 720.0               ## reálných sekund na 24 h (0 = čas stojí)
var opened_chests: Array[String] = []
var in_battle := false
var in_dialogue := false
var _dialogue: DialogueBox
var _quest_panel: QuestPanel
var _pending_shop := false
var _regen := 0.0
var _lab: LightingLab


func _ready() -> void:
	await world.built
	hero = HERO.instantiate()
	hero.name = "Hero"
	world.add_actor(hero, world.start_position)
	world.focus = hero
	var save: Dictionary = SaveGame.read(Session.pending_load) if Session.pending_load > 0 else {}
	ClassDefs.apply(hero, StringName(save["class"]) if not save.is_empty() else Session.class_id)
	party = [hero]
	Settings.load_and_apply()
	interior = Interior.new()
	world.add_child(interior)
	merchant = MERCHANT.instantiate()
	merchant.name = "Merchant"
	merchant.shop_stock.append(ItemDB.get_item(&"torch"))   # pochodeň jen v Tahu 3
	world.add_actor(merchant, interior.merchant_spot)
	_door = Door.new()
	world.add_actor(_door, SHOP_DOOR)
	for id in Villager.VILLAGERS:
		var v: Villager = VILLAGER.instantiate()
		v.setup_villager(id, world)
		world.add_actor(v, Villager.PLACES[Villager.VILLAGERS[id]["home"]])
		villagers.append(v)
	world.day_length = DAY_LENGTH
	for id in COMPANION_OFFSETS:
		var c: Companion = COMPANION.instantiate()
		c.setup_companion(id)
		c.name = String(id).capitalize()
		world.add_actor(c, world.start_position + COMPANION_OFFSETS[id])
	for item in ItemDB.all():  # testovací vybavení: všechno v batohu
		hero.inventory.add(item.id)
	_panel.setup(hero)
	_hud.setup(hero)
	_shop.setup(hero)
	hero.gold = 50
	hero.died.connect(func() -> void:
		await get_tree().create_timer(2.5).timeout
		get_tree().reload_current_scene())
	for i in PACK_OFFSETS.size():
		var pos: Vector2 = world.start_position + PACK_OFFSETS[i]
		_spawn_pack(pos, _pack_for(pos, i))
	world.fx.ui_nodes = [_panel, _shop]
	quests.hero = hero
	_dialogue = DialogueBox.new()
	add_child(_dialogue)
	_quest_panel = QuestPanel.new()
	add_child(_quest_panel)
	_quest_panel.setup(quests)
	_codex_panel = CodexPanel.new()
	add_child(_codex_panel)
	_codex_panel.setup(codex)
	codex.toast.connect(func(t: String) -> void: quests.toast.emit(t))
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	var fl := CanvasLayer.new()
	fl.layer = 50
	fl.add_child(_fade)
	add_child(fl)
	if not hero.inventory.has(&"torch"):
		hero.inventory.add(&"torch")
	codex.unlock("udoli")
	_spawn_chests()
	if save.is_empty():
		quests.start("companions")
	else:
		SaveGame.apply(self, save)
		Session.pending_load = 0
	started.emit()


func _go_shop(enter: bool) -> void:
	hero.controls_enabled = false
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.25)
	await tw.finished
	inside_shop = enter
	if enter:
		_door_out = SHOP_DOOR + Vector2(0, 30)
		hero.global_position = interior.entrance
		hero.invulnerable = true
		codex.unlock("vesnice")
	else:
		hero.global_position = _door_out
		hero.invulnerable = false
	world.snap_camera()
	await get_tree().create_timer(0.1).timeout
	var tw2 := create_tween()
	tw2.tween_property(_fade, "color:a", 0.0, 0.25)
	hero.controls_enabled = not in_dialogue and not in_battle


func save_game(slot: int) -> bool:
	return SaveGame.write(slot, self)


# ---------------------------------------------------------------- truhly

## id, posun od startu, obtížnost zámku (0 = odemčeno, 1–3), kořist
const CHESTS := [
	{"id": "c_start", "off": Vector2(-60, 150), "diff": 0, "loot": {"gold": [15, 30], "cons": {&"potion": 1}}},
	{"id": "c_lock", "off": Vector2(200, 160), "diff": 1, "loot": {"gold": [40, 70], "cons": {&"ether": 1, &"bomb": 1}, "picks": 2}},
	{"id": "c_hard", "off": Vector2(-230, 60), "diff": 3, "loot": {"gold": [120, 200], "items": [&"mail_coif"], "cons": {&"potion": 2}}},
]


func _spawn_chests() -> void:
	for def in CHESTS:
		var c := Chest.new()
		c.chest_id = def["id"]
		c.difficulty = def["diff"]
		c.loot = def["loot"]
		c.add_to_group(&"chests")
		world.add_actor(c, world.start_position + def["off"])


func _nearest_chest() -> Chest:
	var best: Chest
	var best_d := Chest.NEAR
	for node in get_tree().get_nodes_in_group(&"chests"):
		var c := node as Chest
		var d := c.global_position.distance_to(hero.global_position)
		if not c.opened and d <= best_d:
			best = c
			best_d = d
	return best


func _open_chest(c: Chest) -> void:
	if c.difficulty == 0:
		_loot_chest(c)
		return
	var picks := int(hero.get_meta(&"lockpicks", 2))
	if picks <= 0:
		quests.toast.emit("Zamčeno – nemáš paklíč")
		return
	var game := LockpickGame.new()
	var bonus := 5.0 if hero.get_meta(&"class_id", &"") == &"rogue" else 0.0
	game.start(c.difficulty, picks, bonus)
	add_child(game)
	hero.controls_enabled = false
	game.pick_broken.connect(func() -> void:
		hero.set_meta(&"lockpicks", int(hero.get_meta(&"lockpicks", 2)) - 1)
		quests.toast.emit("Paklíč se zlomil"))
	var result: StringName = await game.finished
	hero.controls_enabled = true
	if result == &"opened":
		_loot_chest(c)
	elif result == &"failed":
		quests.toast.emit("Zámek odolal – došly paklíče")


func _loot_chest(c: Chest) -> void:
	c.set_open(true)
	if c.chest_id not in opened_chests:
		opened_chests.append(c.chest_id)
	var parts: PackedStringArray = []
	var g: Array = c.loot.get("gold", [0, 0])
	var gold := randi_range(int(g[0]), int(g[1]))
	hero.gold += gold
	parts.append("%d zlata" % gold)
	var cons: Dictionary = BattleScene3.consumables_of(hero)
	for id in c.loot.get("cons", {}):
		cons[id] = int(cons.get(id, 0)) + int(c.loot["cons"][id])
		parts.append("%s ×%d" % [id, c.loot["cons"][id]])
	for id in c.loot.get("items", []):
		hero.inventory.add(id)
		parts.append(String(id))
	var picks: int = int(c.loot.get("picks", 0))
	if picks > 0:
		hero.set_meta(&"lockpicks", int(hero.get_meta(&"lockpicks", 2)) + picks)
		parts.append("paklíče ×%d" % picks)
	quests.toast.emit("Truhla: " + ", ".join(parts))


# ---------------------------------------------------------------- dialogy a společníci

## Nejbližší postava, se kterou se dá mluvit (obchodník, společník, který ještě nepatří do družiny).
func _talk_target() -> Node2D:
	var best: Node2D
	var best_d := TALK_RANGE
	for node in get_tree().get_nodes_in_group(&"characters"):
		var ok := node == merchant or (node is Companion and not (node as Companion).joined) \
				or (node is Villager and (node as Villager).is_available())
		if not ok:
			continue
		var d := (node as Node2D).global_position.distance_to(hero.global_position)
		if d <= best_d:
			best_d = d
			best = node
	return best


func start_dialogue(id: String) -> void:
	if in_dialogue or in_battle or not DialogueRunner.exists(id):
		return
	in_dialogue = true
	hero.controls_enabled = false
	var runner := DialogueRunner.new()
	runner.quests = quests
	runner.hero = hero
	runner.party = party
	runner.codex = codex
	runner.hour = world.hour
	runner.action.connect(_on_dialogue_action)
	if _dialogue.open(runner, id):
		await _dialogue.closed
	hero.controls_enabled = true
	in_dialogue = false
	if _pending_shop:
		_pending_shop = false
		_shop.open(merchant)


func _on_dialogue_action(action: String, arg: Variant) -> void:
	match action:
		"shop":
			_pending_shop = true
		"recruit":
			_recruit(StringName(arg))


func _recruit(id: StringName) -> void:
	if party.size() >= MAX_PARTY:
		return
	for node in get_tree().get_nodes_in_group(&"characters"):
		var c := node as Companion
		if c != null and c.companion_id == id and not c.joined:
			c.joined = true
			c.leader = hero
			c.queue_redraw()
			party.append(c)
			quests.toast.emit("%s se přidává do družiny" % c.display_name)


# ---------------------------------------------------------------- svět a nepřátelé

func _unhandled_key_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	if e.keycode == KEY_F3 and world.fx:
		print("Počasí: ", world.fx.cycle_weather())
	elif e.keycode == KEY_F5 and hero and not in_battle:  # ladění: přivolá bosse
		_spawn_pack(hero.global_position + Vector2(150, 0), [&"knight"])
	elif e.keycode == KEY_F2 and hero:
		if _lab == null:
			_lab = LightingLab.new()
			add_child(_lab)
			_lab.setup(world, hero)
		else:
			_lab.queue_free()
			_lab = null


func _pack_for(pos: Vector2, idx: int) -> Array:
	var mood := world.fx.mood_at(pos) if world.fx else "forest"
	if mood == "graveyard":
		return [&"skeleton", &"skeleton", &"skeleton"]
	return PACKS[idx % PACKS.size()]


func _spawn_pack(pos: Vector2, templates: Array) -> void:
	for j in templates.size():
		var enemy: TurnEnemy3 = ENEMY.instantiate()
		enemy.apply_template(templates[j])
		enemy.set_meta(&"spawn", pos)
		enemy.set_meta(&"pack", templates)
		world.add_actor(enemy, pos + Vector2(34.0 * j, 22.0 * (j % 2)))
		enemy.contact.connect(_on_contact)


func _respawn_later(pos: Vector2, templates: Array) -> void:
	await get_tree().create_timer(ENEMY_RESPAWN).timeout
	if is_inside_tree():
		_spawn_pack(pos, templates)


func _process(delta: float) -> void:
	if inside_shop and hero != null:
		hero.global_position = interior.clamp_hero(hero.global_position)
		if interior.at_exit(hero.global_position) and hero.controls_enabled:
			_go_shop(false)
	if hero == null or hero.dead:
		return
	if not in_battle and not in_dialogue:   # pomalé hojení mimo souboj
		_regen += delta
		if _regen >= 2.0:
			_regen = 0.0
			for m in party:
				if m.hp < m.max_hp():
					m.hp += 1
					m.hp_changed.emit(m.hp, m.max_hp())
	if in_battle or in_dialogue or not hero.controls_enabled:
		return
	if not Input.is_action_just_pressed(&"attack"):
		return
	var facing_vec: Vector2 = Character.DIR_VECTORS[hero.facing]
	for node in get_tree().get_nodes_in_group(&"characters"):
		var e := node as TurnEnemy3
		if e == null or e.dead:
			continue
		var to := e.global_position - hero.global_position
		if to.length() <= STRIKE_RANGE and facing_vec.dot(to.normalized()) > 0.3:
			_on_contact(e, &"hero")
			return


func _on_contact(enemy: TurnEnemy3, first: StringName) -> void:
	if in_battle or in_dialogue or hero == null or hero.dead:
		enemy.release()
		return
	_battle(enemy, first)


func _battle(first_enemy: TurnEnemy3, first_side: StringName) -> void:
	in_battle = true
	hero.controls_enabled = false
	var group: Array[Character] = [first_enemy]
	for node in get_tree().get_nodes_in_group(&"characters"):
		var other := node as TurnEnemy3
		if other == null or other == first_enemy or other.dead or group.size() >= MAX_GROUP:
			continue
		if other.global_position.distance_to(first_enemy.global_position) <= JOIN_RADIUS:
			group.append(other)
	for e in group:
		(e as TurnEnemy3).lock()
	var mood := world.fx.mood_at(first_enemy.global_position) if world.fx else "forest"
	var env := {"hour": world.hour, "weather": world.fx.weather if world.fx else "jasno", "mood": mood}
	var opts := {"first": first_side, "allies": party.slice(1)}
	var battle := BattleScene3.new()
	battle.name = "Battle"
	add_child(battle)
	get_tree().paused = true
	battle.start(hero, group, _battle_background(mood), env, opts)
	var result: Dictionary = await battle.finished
	battle.queue_free()
	get_tree().paused = false
	codex.record_battle(result)
	for k in result.get("kills", []):
		quests.notify("kill", k)
	match result.get("outcome", &"fled"):
		&"victory", &"negotiated":
			for e in group:
				var spawn: Vector2 = e.get_meta(&"spawn", e.global_position)
				var pack: Array = e.get_meta(&"pack", [&"bandit"])
				e.queue_free()
				if e == group[0]:
					_respawn_later(spawn, pack)
		&"fled":
			for e in group:
				var turn_enemy := e as TurnEnemy3
				turn_enemy.grace = 3.0
				turn_enemy.release()
			hero.global_position += (hero.global_position - first_enemy.global_position).normalized() * 36.0
		&"defeat":
			await get_tree().create_timer(0.3).timeout
			get_tree().reload_current_scene()
			return
	await get_tree().create_timer(0.2).timeout
	hero.controls_enabled = true
	in_battle = false


func _battle_background(mood: String) -> Texture2D:
	var tex := BattleScene3.load_texture(BattleScene3.BG_DIR + "bg_%s.png" % mood)
	if tex == null:
		tex = BattleScene3.load_texture(BattleScene3.BG_DIR + "bg_forest.png")
	return tex


func _input(event: InputEvent) -> void:
	if in_battle or in_dialogue:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_K:
		_codex_panel.toggle()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_J:
		_quest_panel.toggle()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E \
			and hero.controls_enabled and not _shop.visible and not _panel.visible:
		if not inside_shop and _door.is_near():
			_go_shop(true)
			get_viewport().set_input_as_handled()
			return
		var chest := _nearest_chest()
		if chest != null:
			_open_chest(chest)
			get_viewport().set_input_as_handled()
			return
		var t := _talk_target()
		if t != null:
			start_dialogue("merchant" if t == merchant else (t as Villager).dialogue_id if t is Villager else (t as Companion).dialogue_id)
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"inventory") and not _shop.visible:
		_panel.toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"toggle_night"):
		world.cycle_stage()
