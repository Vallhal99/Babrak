extends Node
## Projde místa nové mapy a uloží screenshoty (/tmp/claude-0/tour_*.png). Spuštění viz smoke test.
const SPOTS := {"village": Vector2(830, 800), "church": Vector2(200, 850), "chata": Vector2(885, 440), "dungeon": Vector2(590, 250),
	"mountain": Vector2(300, 255), "peak_edge": Vector2(870, 305), "cave": Vector2(590, 235), "river": Vector2(120, 520), "glade": Vector2(160, 480), "edge": Vector2(720, 560), "camp": Vector2(420, 460)}
const S := 6.0

func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await main.started
	var w: Hd2dWorld = main.world
	var org := Vector2(-93, -76)
	for k in (OS.get_environment("TOUR").split(",") if OS.has_environment("TOUR") else SPOTS.keys()):
		var p: Vector2 = ((Vector2(SPOTS[k].x + 20.0, SPOTS[k].y - 80.0) / S) + org) * 24.0
		main.hero.global_position = p
		w._cam.position = Vector3(p.x * w.S, 17.6, p.y * w.S + 17.1)
		for i in 50:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("/tmp/claude-0/tour_%s.png" % k)
	print("TOUR OK")
	get_tree().quit()
