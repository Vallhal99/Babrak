extends Node
## Test načítání vlastních dat (Studio): godot --headless --path . res://tests/custom_test.tscn
func _ready() -> void:
	CustomData.load_all()
	var t := TurnEnemy3.tmpl(&"wolf")
	_check(t["name"] == "Vlk" and t["speed"] == 11 and t["weak"][0] == &"fire", "vlastní nepřítel načten")
	var e: TurnEnemy3 = load("res://scenes/characters/turn_enemy3.tscn").instantiate()
	e.apply_template(&"wolf")
	_check(e.template_id == &"wolf" and e.battle_speed == 11 and not e.human, "šablona použita")
	e.free()
	_check(TurnEnemy3.all_ids().size() >= 8, "seznam nepřátel")
	_check(Villager.all().size() >= 4, "vesničané")
	print("CUSTOM OK")
	get_tree().quit()

func _check(ok: bool, msg: String) -> void:
	if not ok:
		push_error("FAIL: " + msg)
		get_tree().quit(1)
