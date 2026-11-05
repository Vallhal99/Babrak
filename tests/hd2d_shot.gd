extends Node
const OUT := "/tmp/claude-0/-home-claude/4ece88d8-ed95-5e17-bf08-a245a240eb47/scratchpad/shots/"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var d: Node3D = load("res://scenes/demo/hd2d_demo.tscn").instantiate()
	add_child(d)
	for _i in 600:
		await get_tree().process_frame
		if d._built:
			break
	for _i in 60:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OUT + "hd_day.png")
	d._apply_stage(0.0, 1.0)
	for _i in 20:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OUT + "hd_dusk.png")
	d._apply_stage(1.0, 0.0)
	for _i in 20:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OUT + "hd_night.png")
	d._hero_vp.get_texture().get_image().save_png(OUT + "hd_herovp.png")
	print("hero ", d._hero.global_position, " cam ", d._hero_cam.position, " vis ", d._hero.visible, " children ", d._hero.get_child_count())
	for c in d._hero.find_children("*", "CanvasItem", true, false):
		print(c.name, " ", c.visibility_layer, " ", c.visible)
	print("done")
	get_tree().quit()
