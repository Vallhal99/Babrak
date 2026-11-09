extends Node
## Snímky světa na zadaných místech: res://tests/shots_test.tscn  (SHOTS="x,y;x,y" → /tmp/claude-0/shot_N.png)

func _ready() -> void:
	var main: Node = load("res://scenes/main_turn3.tscn").instantiate()
	add_child(main)
	await main.started
	for n in get_tree().get_nodes_in_group(&"characters"):
		if n is TurnEnemy3:
			n.get_parent().remove_child(n)
	var spots := OS.get_environment("SHOTS").split(";")
	var i := 0
	for s in spots:
		var p := s.split(",")
		main.hero.global_position = Vector2(float(p[0]), float(p[1]))
		main.world.snap_camera()
		await get_tree().create_timer(3.0).timeout
		get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shot_%d.png" % i)
		i += 1
	print("SHOTS OK")
	get_tree().quit()
