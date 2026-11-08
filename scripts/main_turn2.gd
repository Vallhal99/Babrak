extends Node2D
## Herní scéna "Nová hra tah 2": mapa a hra jako "Nová hra tah", ale tahový souboj má nové prvky
## (řady a dosah, stavy, řetězení slabin, schopnosti zbraní, pasivky, předměty, vyjednávání, spojenec,
## morálka, znamení, hodnocení, elita/boss, počasí a denní doba, iniciativa podle příchodu).

signal started

const HERO := preload("res://scenes/characters/hero.tscn")
const MERCHANT := preload("res://scenes/characters/merchant.tscn")
const ENEMY := preload("res://scenes/characters/turn_enemy2.tscn")
const ENEMY_RESPAWN := 8.0
const MERCHANT_OFFSET := Vector2(-150, -60)
const PACK_OFFSETS: Array[Vector2] = [Vector2(260, 40), Vector2(-120, 190)]
const PACKS := [[&"bandit", &"archer"], [&"leader", &"bandit", &"archer"]]
const JOIN_RADIUS := 170.0
const MAX_GROUP := 3
const ALLY_RADIUS := 300.0     ## obchodník se k souboji přidá, když stojí takhle blízko
const STRIKE_RANGE := 80.0     ## útok ze zálohy: hráč zaútočí dřív, než se nepřítel dotkne

@onready var world: Hd2dWorld = $World
@onready var _panel: InventoryPanel = $InventoryPanel
@onready var _hud: Hud = $Hud
@onready var _shop: ShopPanel = $ShopPanel

var hero: Hero
var merchant: Npc
var in_battle := false
var _lab: LightingLab


func _ready() -> void:
	await world.built
	hero = HERO.instantiate()
	hero.name = "Hero"
	world.add_actor(hero, world.start_position)
	world.focus = hero
	merchant = MERCHANT.instantiate()
	merchant.name = "Merchant"
	world.add_actor(merchant, world.start_position + MERCHANT_OFFSET)
	for item in ItemDB.all():  # testovací vybavení: všechno v batohu
		hero.inventory.add(item.id)
	_panel.setup(hero)
	_hud.setup(hero)
	_shop.setup(hero)
	hero.interacted.connect(_shop.open)
	hero.gold = 50  # startovní zlato (test)
	hero.died.connect(func() -> void:
		await get_tree().create_timer(2.5).timeout
		get_tree().reload_current_scene())
	for i in PACK_OFFSETS.size():
		var pos: Vector2 = world.start_position + PACK_OFFSETS[i]
		_spawn_pack(pos, _pack_for(pos, i))
	world.fx.ui_nodes = [_panel, _shop]
	started.emit()


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


## Nepřátelé podle místa: na hřbitově kostlivci, jinak zbojníci.
func _pack_for(pos: Vector2, idx: int) -> Array:
	var mood := world.fx.mood_at(pos) if world.fx else "forest"
	if mood == "graveyard":
		return [&"skeleton", &"skeleton", &"skeleton"]
	return PACKS[idx % PACKS.size()]


func _spawn_pack(pos: Vector2, templates: Array) -> void:
	for j in templates.size():
		var enemy: TurnEnemy2 = ENEMY.instantiate()
		enemy.apply_template(templates[j])
		enemy.set_meta(&"spawn", pos)
		enemy.set_meta(&"pack", templates)
		world.add_actor(enemy, pos + Vector2(34.0 * j, 22.0 * (j % 2)))
		enemy.contact.connect(_on_contact)


func _respawn_later(pos: Vector2, templates: Array) -> void:
	await get_tree().create_timer(ENEMY_RESPAWN).timeout
	if is_inside_tree():
		_spawn_pack(pos, templates)


func _process(_delta: float) -> void:
	# útok ze zálohy: hráč zaútočí na nepřítele před sebou, dřív než se ho dotkne
	if in_battle or hero == null or hero.dead or not hero.controls_enabled:
		return
	if not Input.is_action_just_pressed(&"attack"):
		return
	var facing_vec: Vector2 = Character.DIR_VECTORS[hero.facing]
	for node in get_tree().get_nodes_in_group(&"characters"):
		var e := node as TurnEnemy2
		if e == null or e.dead:
			continue
		var to := e.global_position - hero.global_position
		if to.length() <= STRIKE_RANGE and facing_vec.dot(to.normalized()) > 0.3:
			_on_contact(e, &"hero")
			return


func _on_contact(enemy: TurnEnemy2, first: StringName) -> void:
	if in_battle or hero == null or hero.dead:
		enemy.release()
		return
	_battle(enemy, first)


func _battle(first_enemy: TurnEnemy2, first_side: StringName) -> void:
	in_battle = true
	hero.controls_enabled = false
	var group: Array[Character] = [first_enemy]
	for node in get_tree().get_nodes_in_group(&"characters"):
		var other := node as TurnEnemy2
		if other == null or other == first_enemy or other.dead or group.size() >= MAX_GROUP:
			continue
		if other.global_position.distance_to(first_enemy.global_position) <= JOIN_RADIUS:
			group.append(other)
	for e in group:
		(e as TurnEnemy2).lock()
	var mood := world.fx.mood_at(first_enemy.global_position) if world.fx else "forest"
	var env := {"hour": world.hour, "weather": world.fx.weather if world.fx else "jasno", "mood": mood}
	var opts := {"first": first_side}
	if merchant and merchant.global_position.distance_to(hero.global_position) <= ALLY_RADIUS:
		opts["ally"] = merchant   # obchodník pomůže, když je nablízku
	var battle := BattleScene2.new()
	battle.name = "Battle"
	add_child(battle)
	get_tree().paused = true  # svět stojí, BattleScene2 běží dál
	battle.start(hero, group, _battle_background(mood), env, opts)
	var result: Dictionary = await battle.finished
	battle.queue_free()
	get_tree().paused = false
	if merchant:
		merchant.hp = merchant.max_hp()   # obchodník se po souboji vždy zotaví
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
				var turn_enemy := e as TurnEnemy2
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


## Pozadí podle místa setkání: assets/battle/bg_<nálada>.png (chybějící = les).
func _battle_background(mood: String) -> Texture2D:
	var tex := BattleScene2.load_texture(BattleScene2.BG_DIR + "bg_%s.png" % mood)
	if tex == null:
		tex = BattleScene2.load_texture(BattleScene2.BG_DIR + "bg_forest.png")
	return tex


func _input(event: InputEvent) -> void:
	if in_battle:
		return
	if event.is_action_pressed(&"inventory") and not _shop.visible:
		_panel.toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"toggle_night"):
		world.cycle_stage()
