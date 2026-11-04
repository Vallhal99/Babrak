class_name CharacterVisual
extends Node2D
## Skládá postavu z vrstev (tělo + sloty vybavení) a přehrává animace ze sheetů.
## Každá vrstva = 2 sprity (horní/dolní půlka), aby šly kombinovat animace (viz AnimCatalog "top").
## Všechny vrstvy sdílejí jeden čas/snímek, takže jsou vždy synchronní.

signal finished(anim: StringName)
signal frame_changed(anim: StringName, frame: int)

## Pořadí kreslení zdola nahoru. Slot NONE = tělo.
const DRAW_ORDER: Array[int] = [
	ItemData.Slot.NONE, ItemData.Slot.FEET, ItemData.Slot.HEAD, ItemData.Slot.OFFHAND, ItemData.Slot.WEAPON,
]
const ORIGIN := Vector2(-32, -61)  # levý horní roh 64px snímku vůči patám postavy
const SPLIT_Y := 42  # pas: hranice horní/dolní půlky
const TOP := 0
const BOTTOM := 1

@export var body_sheet: Texture2D
@export var body_extra_sheet: Texture2D

var anim: StringName = &"idle"
var dir: int = AnimCatalog.Dir.DOWN

var _time := 0.0
var _last_frame := 0
var _done := false
var _equipment: Equipment
var _sheets: Dictionary = {}  # Slot -> [hlavní sheet, extra sheet]
var _parts: Dictionary = {}  # Slot -> [horní Sprite2D, dolní Sprite2D]


func _ready() -> void:
	for slot in DRAW_ORDER:
		_sheets[slot] = [null, null]
		_parts[slot] = [_make_sprite(), _make_sprite()]
	_sheets[ItemData.Slot.NONE] = [body_sheet, body_extra_sheet]
	_apply()


## Změna těla za běhu (např. figurína v inventáři).
func set_body(sheet: Texture2D, extra_sheet: Texture2D = null) -> void:
	body_sheet = sheet
	body_extra_sheet = extra_sheet
	_sheets[ItemData.Slot.NONE] = [sheet, extra_sheet]
	_apply()


func bind(equipment: Equipment) -> void:
	_equipment = equipment
	equipment.slot_changed.connect(_set_layer)
	for slot in DRAW_ORDER:
		_set_layer(slot)


func play(new_anim: StringName, new_dir: int = dir, restart := false) -> void:
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
	_sheets[slot] = [item.layer_sheet, item.extra_sheet] if item else [null, null]
	_apply()


func _apply() -> void:
	var frame := mini(int(_time), AnimCatalog.frame_count(anim) - 1)
	for slot in DRAW_ORDER:
		for part in 2:
			var sprite: Sprite2D = _parts[slot][part]
			var src := _resolve(slot, part, frame)
			sprite.visible = not src.is_empty()
			if sprite.visible:
				sprite.texture = src["tex"]
				sprite.region_rect = src["rect"]
				sprite.position = src["pos"]


## Odkud vzít obrázek pro danou vrstvu a půlku. Prázdný výsledek = nekreslit.
func _resolve(slot: int, part: int, frame: int) -> Dictionary:
	var a := anim
	var f := frame
	var split := AnimCatalog.is_split(a)
	if split and part == TOP:
		a = AnimCatalog.top_of(a)
		f = frame % AnimCatalog.frame_count(a)
	var tex: Texture2D = _sheets[slot][0]
	var extra: Texture2D = _sheets[slot][1]
	if AnimCatalog.is_extra(a):
		if extra:
			tex = extra
		else:  # vrstva nemá vlastní extra snímky -> použije alias (např. idle)
			f /= AnimCatalog.alias_div(a)
			a = AnimCatalog.alias_of(a)
	if tex == null:
		return {}
	# Oversize efekt útoku má jen zbraň a jen pokud ho její sheet obsahuje.
	if slot == ItemData.Slot.WEAPON and not split and AnimCatalog.has_big(a) and tex.get_height() > AnimCatalog.BIG_Y:
		if part == BOTTOM:
			return {}
		return {"tex": tex, "rect": AnimCatalog.rect(a, dir, f, true), "pos": ORIGIN - Vector2.ONE * AnimCatalog.BIG_OFFSET}
	var rect := AnimCatalog.rect(a, dir, f)
	if not split:
		return {} if part == BOTTOM else {"tex": tex, "rect": rect, "pos": ORIGIN}
	if part == TOP:
		rect.size.y = SPLIT_Y
		return {"tex": tex, "rect": rect, "pos": ORIGIN}
	rect.position.y += SPLIT_Y
	rect.size.y = AnimCatalog.FRAME - SPLIT_Y
	return {"tex": tex, "rect": rect, "pos": ORIGIN + Vector2(0, SPLIT_Y)}
