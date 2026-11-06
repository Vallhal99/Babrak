class_name CharacterVisual
extends Node2D
## Skládá postavu z vrstev (tělo + sloty vybavení) a přehrává animace ze sheetů.
## Všechny vrstvy sdílejí jeden čas/snímek, takže jsou vždy synchronní.

signal finished(anim: StringName)
signal frame_changed(anim: StringName, frame: int)

const HAIR := 99  # pseudo-slot: vlasy (vrstva nad tělem, skrytá přilbou)
## Pořadí kreslení zdola nahoru. Slot NONE = tělo.
const DRAW_ORDER: Array[int] = [
	ItemData.Slot.NONE, HAIR, ItemData.Slot.TORSO, ItemData.Slot.FEET, ItemData.Slot.HANDS, ItemData.Slot.HEAD,
	ItemData.Slot.OFFHAND, ItemData.Slot.WEAPON,
]
const ORIGIN := Vector2(-32, -61)  # levý horní roh 64px snímku vůči patám postavy

@export var body_sheet: Texture2D
@export var hair_sheet: Texture2D

var anim: StringName = &"idle"
var dir: int = AnimCatalog.Dir.DOWN

var _time := 0.0
var _last_frame := 0
var _done := false
var _equipment: Equipment
var _sheets: Dictionary = {}  # Slot -> Texture2D
var _big_anims: Dictionary = {}  # Slot -> animace, které má sheet v oversize variantě
var _sprites: Dictionary = {}  # Slot -> Sprite2D


func _ready() -> void:
	for slot in DRAW_ORDER:
		_sprites[slot] = _make_sprite()
		_sheets[slot] = null
	_sheets[ItemData.Slot.NONE] = body_sheet
	_sheets[HAIR] = hair_sheet
	_apply()


## Změna těla za běhu (např. figurína v inventáři).
func set_body(sheet: Texture2D, hair: Texture2D = null) -> void:
	body_sheet = sheet
	hair_sheet = hair
	_sheets[ItemData.Slot.NONE] = sheet
	_sheets[HAIR] = hair
	_apply()


func bind(equipment: Equipment) -> void:
	_equipment = equipment
	equipment.slot_changed.connect(_set_layer)
	for slot in DRAW_ORDER:
		_set_layer(slot)


func play(new_anim: StringName, new_dir: int = dir, restart := false) -> void:
	var resolved := AnimCatalog.resolve(new_anim, new_dir)
	new_anim = resolved[0]
	new_dir = resolved[1]
	if new_anim == anim and new_dir == dir and not restart and not _done:
		return
	if new_anim != anim or restart or _done:
		_time = 0.0
		_last_frame = 0
		_done = false
	anim = new_anim
	dir = new_dir
	_apply()


func _process(delta: float) -> void:
	if _done:
		return
	_time += delta * AnimCatalog.fps(anim)
	var count := AnimCatalog.frame_count(anim)
	var wrapped := false
	if _time >= count:
		if AnimCatalog.is_loop(anim):
			_time = fmod(_time, count)
			wrapped = true
		else:
			_time = count - 0.001
			_done = true
	_apply()
	_emit_frames(int(_time), wrapped, count)  # i když se kvůli lagu přeskočí snímky, žádný se nevynechá
	if _done:
		finished.emit(anim)


func _emit_frames(new_frame: int, wrapped: bool, count: int) -> void:
	var current := anim
	var f := _last_frame
	while f != new_frame or wrapped:
		f += 1
		if f >= count:
			f = 0
			wrapped = false
		_last_frame = f
		frame_changed.emit(current, f)
		if anim != current:  # posluchač přepnul animaci
			return


func _make_sprite() -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.region_enabled = true
	add_child(sprite)
	return sprite


func _set_layer(slot: int) -> void:
	if slot == ItemData.Slot.NONE or not _sheets.has(slot):
		return
	var item := _equipment.get_item(slot)
	_sheets[slot] = item.layer_sheet if item else null
	_big_anims[slot] = item.big_anims if item else []
	_apply()


func _hair_hidden() -> bool:
	for slot in DRAW_ORDER:
		var item := _equipment.get_item(slot) if _equipment and slot != HAIR else null
		if item and item.hides_hair:
			return true
	return false


func _apply() -> void:
	var frame := mini(int(_time), AnimCatalog.frame_count(anim) - 1)
	var hair_hidden := _hair_hidden()
	for slot in DRAW_ORDER:
		var sprite: Sprite2D = _sprites[slot]
		var tex: Texture2D = _sheets[slot]
		sprite.visible = tex != null and not (slot == HAIR and hair_hidden)
		if not sprite.visible:
			continue
		var big: bool = AnimCatalog.has_big(anim) and anim in _big_anims.get(slot, [])
		sprite.texture = tex
		sprite.region_rect = AnimCatalog.rect(anim, dir, frame, big)
		sprite.position = ORIGIN - Vector2.ONE * AnimCatalog.BIG_OFFSET if big else ORIGIN
