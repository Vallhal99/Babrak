extends Node
## Kontaktní arch osvětlení: pro vybraná místa projde všechny klíčové snímky dne a uloží /tmp/claude-0/light_<místo>.png.
## Spuštění: LIGHT_SPOTS="Osada,Tábor" xvfb-run ... res://tests/light_sheet.tscn

func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await main.started
	var w: Hd2dWorld = main.world
	var spots: PackedStringArray = OS.get_environment("LIGHT_SPOTS").split(",") if OS.has_environment("LIGHT_SPOTS") else PackedStringArray(["Osada"])
	for s in spots:
		main.hero.global_position = LightingLab.spot_position(LightingLab.SPOTS[s])
		w.snap_camera()
		var tiles: Array[Image] = []
		for k in w.profile.keys:
			w.set_time(float(k.hour))
			for i in 14:
				await get_tree().process_frame
			var img := get_viewport().get_texture().get_image()
			img.resize(480, 360, Image.INTERPOLATE_BILINEAR)
			tiles.append(img)
		var cols := 4
		var rows := ceili(tiles.size() / float(cols))
		var sheet := Image.create(480 * cols, 360 * rows, false, Image.FORMAT_RGBA8)
		for i in tiles.size():
			sheet.blit_rect(tiles[i], Rect2i(0, 0, 480, 360), Vector2i((i % cols) * 480, (i / cols) * 360))
		sheet.save_png("/tmp/claude-0/light_%s.png" % s.replace(" ", "_"))
	print("SHEET OK")
	get_tree().quit()
