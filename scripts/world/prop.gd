class_name Prop
extends Node2D
## Rekvizita světa bez vlastního billboardu (šetří omezených 19 vrstev): Sprite3D přímo v 3D světě.
## `kind` říká main_turn3, co dělá E (workbench, campfire, bed, hay, iron_vein, herb_bush, mushrooms, logs,
## tomb_entrance, gate, desk ...). Bez obrázku je rekvizita neviditelná (jen zóna s popiskem).

const NEAR := 48.0

var kind: StringName = &""
var prompt := "[E] Použít"
var texture_path := ""
var depleted := false
var one_shot := false
var _spr: Sprite3D
var _world: Hd2dWorld


func setup(world: Hd2dWorld, k: StringName, p: String, tex: String = "") -> Prop:
	_world = world
	kind = k
	prompt = p
	texture_path = tex
	add_to_group(&"props")
	return self


func _ready() -> void:
	var tex := BattleScene3.load_texture(texture_path) if texture_path != "" else null
	if tex == null:
		return
	_spr = Sprite3D.new()
	_spr.texture = tex
	_spr.pixel_size = Hd2dWorld.S
	_spr.rotation_degrees.x = -Hd2dWorld.TILT
	_spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_spr.alpha_scissor_threshold = 0.4
	_spr.shaded = true
	_spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_world.add_child(_spr)
	_sync()


func _sync() -> void:
	if _spr == null:
		return
	var gp := global_position
	_spr.position = Vector3(gp.x * Hd2dWorld.S, _spr.texture.get_height() * 0.5 * Hd2dWorld.S, gp.y * Hd2dWorld.S)
	_spr.modulate = Color(0.45, 0.45, 0.45) if depleted else Color.WHITE


func set_depleted(v: bool) -> void:
	depleted = v
	_sync()


func set_shown(v: bool) -> void:
	if _spr:
		_spr.visible = v


func _process(_d: float) -> void:
	_sync()


func _exit_tree() -> void:
	if _spr and is_instance_valid(_spr):
		_spr.queue_free()


func usable() -> bool:
	return not depleted and visible and is_inside_tree()
