extends Node2D
## Herní scéna: HD-2D svět + hrdina + obchodník + UI + oživování nepřátel.

signal started

const HERO := preload("res://scenes/characters/hero.tscn")
const MERCHANT := preload("res://scenes/characters/merchant.tscn")
const ENEMY := preload("res://scenes/characters/enemy.tscn")
const ENEMY_RESPAWN := 6.0
const MERCHANT_OFFSET := Vector2(-150, -60)
const ENEMY_OFFSETS: Array[Vector2] = [Vector2(260, 40), Vector2(-120, 190)]

@onready var world: Hd2dWorld = $World
@onready var _panel: InventoryPanel = $InventoryPanel
@onready var _hud: Hud = $Hud
@onready var _shop: ShopPanel = $ShopPanel

var hero: Hero
var merchant: Npc
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
	var enemy: Enemy = ENEMY.instantiate()
	world.add_actor(enemy, pos)
	enemy.died.connect(func() -> void:
		await get_tree().create_timer(ENEMY_RESPAWN).timeout
		if is_inside_tree():
			_spawn_enemy(pos))


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"inventory") and not _shop.visible:
		_panel.toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"toggle_night"):
		world.cycle_stage()
