extends Node
## Snímky ukázky tábora (den / soumrak / noc + pohyb hrdiny). Spouštět přes xvfb + opengl3.
const OUT := "/tmp/claude-0/-home-claude/4ece88d8-ed95-5e17-bf08-a245a240eb47/scratchpad/shots/"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var demo: Node2D = load("res://scenes/demo/camp_demo.tscn").instantiate()
	add_child(demo)
	var map: CampWorld = demo.get_node("Map")
	var hero: Hero = map.objects.get_node("Hero")
	await _frames(20)
	map.day_night.set_time(0.0)
	await _frames(10)
	_shot("day")
	map.day_night.set_time(0.5)
	await _frames(5)
	_shot("dusk")
	map.day_night.set_time(1.0)
	await _frames(5)
	_shot("night")
	# pohyb: hrdina jde 1.5 s nahoru po cestě k táboráku
	var p0 := hero.global_position
	Input.action_press(&"move_up")
	await get_tree().create_timer(1.6).timeout
	Input.action_release(&"move_up")
	await _frames(10)
	print("hero moved: ", p0, " -> ", hero.global_position)
	_shot("night_moved")
	map.day_night.set_time(0.5)
	await _frames(5)
	_shot("dusk_moved")
	print("trees+objs: ", map.objects.get_child_count())
	get_tree().quit()


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png(OUT + name + ".png")
