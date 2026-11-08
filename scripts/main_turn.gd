extends Node2D
## Herní scéna "Nová hra tah" (test): totožná s main.gd (stejná mapa Babrak, hrdina, obchodník, UI),
## jen nepřátelé nebojují v reálném čase. Dotyk s nepřítelem spustí tahový souboj (BattleScene),
## po něm se hra vrací na mapu. Původní main.gd zůstává nedotčený.

signal started

const HERO := preload("res://scenes/characters/hero.tscn")
const MERCHANT := preload("res://scenes/characters/merchant.tscn")
const ENEMY := preload("res://scenes/characters/turn_enemy.tscn")
const ENEMY_RESPAWN := 6.0
const MERCHANT_OFFSET := Vector2(-150, -60)
const ENEMY_OFFSETS: Array[Vector2] = [Vector2(260, 40), Vector2(-120, 190)]
const JOIN_RADIUS := 170.0   ## nepřátelé v tomhle okruhu od prvního se k souboji přidají
const MAX_GROUP := 3

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
	for offset in ENEMY_OFFSETS:
		_spawn_enemy(world.start_position + offset)
	world.fx.ui_nodes = [_panel, _shop]
	started.emit()


func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F3 and world.fx:
		print("Počasí: ", world.fx.cycle_weather())
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F2 and hero:
		if _lab == null:
			_lab = LightingLab.new()
			add_child(_lab)
			_lab.setup(world, hero)
		else:
			_lab.queue_free()
			_lab = null


func _spawn_enemy(pos: Vector2) -> void:
	var enemy: TurnEnemy = ENEMY.instantiate()
	enemy.set_meta(&"spawn", pos)
	world.add_actor(enemy, pos)
	enemy.contact.connect(_on_contact)


func _respawn_later(pos: Vector2) -> void:
	await get_tree().create_timer(ENEMY_RESPAWN).timeout
	if is_inside_tree():
		_spawn_enemy(pos)


func _on_contact(enemy: TurnEnemy) -> void:
	if in_battle or hero == null or hero.dead:
		enemy.release()
		return
	_battle(enemy)


## Souboj s nepřítelem, který se dotkl hrdiny, a s těmi, kdo stojí poblíž.
func _battle(first: TurnEnemy) -> void:
	in_battle = true
	hero.controls_enabled = false
	var group: Array[Character] = [first]
	for node in get_tree().get_nodes_in_group(&"characters"):
		var other := node as TurnEnemy
		if other == null or other == first or other.dead or group.size() >= MAX_GROUP:
			continue
		if other.global_position.distance_to(first.global_position) <= JOIN_RADIUS:
			group.append(other)
	var battle := BattleScene.new()
	battle.name = "Battle"
	add_child(battle)
	get_tree().paused = true  # svět stojí, BattleScene běží dál (process_mode ALWAYS)
	battle.start(hero, group, _battle_background(first.global_position))
	var result: Dictionary = await battle.finished
	battle.queue_free()
	get_tree().paused = false
	match result.get("outcome", &"fled"):
		&"victory":
			for e in group:
				var spawn: Vector2 = e.get_meta(&"spawn", e.global_position)
				e.queue_free()
				_respawn_later(spawn)
		&"fled":
			for e in group:
				var turn_enemy := e as TurnEnemy
				turn_enemy.grace = 3.0
				turn_enemy.release()
			hero.global_position += (hero.global_position - first.global_position).normalized() * 36.0
		&"defeat":
			await get_tree().create_timer(0.3).timeout
			get_tree().reload_current_scene()
			return
	await get_tree().create_timer(0.2).timeout
	hero.controls_enabled = true
	in_battle = false


## Pozadí souboje podle místa setkání: assets/battle/bg_<nálada>.png (forest, village, graveyard,
## mountain, water, neutral). Co chybí, nahradí se lesem – stačí doplnit obrázek se správným názvem.
func _battle_background(pos: Vector2) -> Texture2D:
	var mood := "forest"
	if world.fx:
		mood = world.fx.mood_at(pos)
	var tex := BattleScene.load_texture(BattleScene.BG_DIR + "bg_%s.png" % mood)
	if tex == null:
		tex = BattleScene.load_texture(BattleScene.BG_DIR + "bg_forest.png")
	return tex


func _input(event: InputEvent) -> void:
	if in_battle:
		return
	if event.is_action_pressed(&"inventory") and not _shop.visible:
		_panel.toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"toggle_night"):
		world.cycle_stage()
