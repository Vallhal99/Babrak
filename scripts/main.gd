extends Node2D
## Herní scéna: mapa + hrdina + UI + oživování nepřátel. Později se zde bude přepínat mapy.

const ENEMY := preload("res://scenes/characters/enemy.tscn")
const ENEMY_RESPAWN := 6.0
const ENEMY_SPOTS: Array[Vector2] = [Vector2(720, 330), Vector2(250, 450)]

@onready var _map: GameMap = $Map
@onready var _hero: Hero = $Hero
@onready var _panel: InventoryPanel = $InventoryPanel
@onready var _hud: Hud = $Hud
@onready var _shop: ShopPanel = $ShopPanel


func _ready() -> void:
	_hero.position = _map.start_position
	for item in ItemDB.all():  # testovací vybavení: všechno v batohu
		_hero.inventory.add(item.id)
	_panel.setup(_hero)
	_hud.setup(_hero)
	_shop.setup(_hero)
	_hero.interacted.connect(_shop.open)
	_hero.gold = 50  # startovní zlato (test)
	_hero.died.connect(func() -> void:
		await get_tree().create_timer(2.5).timeout
		get_tree().reload_current_scene())
	for spot in ENEMY_SPOTS:
		_spawn_enemy(spot)


func _spawn_enemy(pos: Vector2) -> void:
	var enemy: Enemy = ENEMY.instantiate()
	enemy.position = pos
	add_child(enemy)
	enemy.died.connect(func() -> void:
		await get_tree().create_timer(ENEMY_RESPAWN).timeout
		if is_inside_tree():
			_spawn_enemy(pos))


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"inventory") and not _shop.visible:
		_panel.toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"toggle_night"):
		_map.set_night(not _map.is_night())
