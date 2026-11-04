class_name Hero
extends Character
## Hrdina ovládaný hráčem.

signal interacted(npc: Npc)

var controls_enabled := true


func _think(_delta: float) -> void:
	if not controls_enabled:
		return
	move_input = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	run_input = Input.is_action_pressed(&"run")
	attack_input = Input.is_action_just_pressed(&"attack")
	cast_input = Input.is_action_just_pressed(&"cast")
	if Input.is_action_just_pressed(&"interact"):
		try_interact()


## Promluví s nejbližším NPC v dosahu, které má co nabídnout.
func try_interact() -> void:
	for node in get_tree().get_nodes_in_group(&"characters"):
		var npc := node as Npc
		if npc and not npc.shop_stock.is_empty() and global_position.distance_to(npc.global_position) <= npc.interact_range:
			interacted.emit(npc)
			return
