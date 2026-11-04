class_name Npc
extends Character
## Neutrální postava (obchodník…): stojí na místě, nedá se zranit, nad hlavou má jméno.

## Nabídka obchodu (nekonečné zásoby). Prázdné = nic neprodává.
@export var shop_stock: Array[ItemData] = []
@export var interact_range := 56.0

var _hero_near := false


func _ready() -> void:
	super()
	team = &"npc"
	invulnerable = true


func _process(delta: float) -> void:
	super(delta)
	var near := false
	for node in get_tree().get_nodes_in_group(&"characters"):
		var other := node as Character
		if other.team == &"hero" and not other.dead and other.global_position.distance_to(global_position) <= interact_range:
			near = true
	if near != _hero_near:
		_hero_near = near
		queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-40, -68), display_name, HORIZONTAL_ALIGNMENT_CENTER, 80, 12, Color(1, 0.9, 0.5))
	if _hero_near and not shop_stock.is_empty():
		draw_string(font, Vector2(-50, -80), "[E] Obchodovat", HORIZONTAL_ALIGNMENT_CENTER, 100, 11, Color.WHITE)
