extends Node
## Snímky atmosféry: den/soumrak/noc a počasí.
const OUT := "/tmp/claude-0/-home-claude/4ece88d8-ed95-5e17-bf08-a245a240eb47/scratchpad/shots/"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var demo: Node2D = load("res://scenes/demo/tiled_demo.tscn").instantiate()
	demo.get_node("World").world_dir = "res://data/world/palouk"
	add_child(demo)
	var world: TiledWorld = demo.get_node("World")
	for _i in 240:
		await get_tree().process_frame
	var atm: Atmosphere = demo._atm
	var dn: DayNight = demo._day_night
	var cases := [["day", 0.0, Atmosphere.Weather.CLEAR], ["dusk", 0.5, Atmosphere.Weather.CLEAR], ["night", 1.0, Atmosphere.Weather.CLEAR],
		["fog", 0.0, Atmosphere.Weather.FOG], ["rain", 0.5, Atmosphere.Weather.RAIN], ["snow", 0.0, Atmosphere.Weather.SNOW]]
	for c in cases:
		dn.set_time(c[1])
		atm.set_weather(c[2], 0.01)
		for _i in 90:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(OUT + "atm_" + c[0] + ".png")
		print("shot ", c[0])
	get_tree().quit()
