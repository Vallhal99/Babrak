extends Node
## Arch počasí: pro místo WX_SPOT projde kombinace (počasí, hodina) a uloží /tmp/claude-0/weather_<místo>.png.
## Spuštění: WX_SPOT=Osada xvfb-run ... res://tests/weather_sheet.tscn

const COMBOS := [["jasno", 12.0], ["jasno", 20.5], ["déšť", 16.5], ["bouřka", 19.0], ["sníh", 12.0], ["mlha", 8.0], ["jasno", 8.0], ["déšť", 20.5]]

func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await main.started
	var w: Hd2dWorld = main.world
	var spot := OS.get_environment("WX_SPOT") if OS.has_environment("WX_SPOT") else "Osada"
	main.hero.global_position = LightingLab.spot_position(LightingLab.SPOTS[spot])
	w.snap_camera()
	var tiles: Array[Image] = []
	for c in COMBOS:
		w.fx.set_weather(c[0])
		w.set_time(c[1])
		for i in 150:   # počasí se plynule dorovná
			w.fx._process(0.1)
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.resize(480, 360, Image.INTERPOLATE_BILINEAR)
		tiles.append(img)
	var sheet := Image.create(480 * 4, 360 * 2, false, Image.FORMAT_RGBA8)
	for i in tiles.size():
		sheet.blit_rect(tiles[i], Rect2i(0, 0, 480, 360), Vector2i((i % 4) * 480, (i / 4) * 360))
	sheet.save_png("/tmp/claude-0/weather_%s.png" % spot)
	print("WX OK")
	get_tree().quit()
