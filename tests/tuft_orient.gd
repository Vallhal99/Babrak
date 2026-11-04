extends Node2D
## Kontrola orientace: vlevo Sprite2D, vpravo MultiMesh trs (musí vypadat stejně). Snímek do shots/.
func _ready() -> void:
	var w := TiledWorld.new()
	var tex: Texture2D = load("res://assets/world/tuft_0.png")
	var bg := ColorRect.new(); bg.size = Vector2(300, 150); bg.color = Color(0.3, 0.4, 0.2); add_child(bg)
	var spr := Sprite2D.new(); spr.texture = tex; spr.offset = Vector2(0, -tex.get_height() / 2.0); spr.position = Vector2(80, 120); spr.scale = Vector2(4, 4); add_child(spr)
	var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_2D; mm.mesh = w._sprite_quad(tex.get_width(), tex.get_height()); mm.instance_count = 1
	mm.set_instance_transform_2d(0, Transform2D(0.0, Vector2(4, 4), 0.0, Vector2(220, 120)))
	var mmi := MultiMeshInstance2D.new(); mmi.multimesh = mm; mmi.texture = tex; add_child(mmi)
	await get_tree().process_frame; await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/tmp/claude-0/-home-claude/4ece88d8-ed95-5e17-bf08-a245a240eb47/scratchpad/shots/orient.png")
	get_tree().quit()
