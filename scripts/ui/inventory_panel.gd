class_name InventoryPanel
extends CanvasLayer
## Inventář: vlevo přehled postavy (figurína se sloty + staty), vpravo batoh.
## Klik na předmět v batohu = nasadit, klik na slot = sundat.

## Pozice slotů kolem figuríny (sloupec, řádek). Střed (1,1) je figurína.
const DOLL_GRID := {
	ItemData.Slot.TORSO: Vector2i(0, 0),
	ItemData.Slot.HEAD: Vector2i(1, 0),
	ItemData.Slot.HANDS: Vector2i(2, 0),
	ItemData.Slot.WEAPON: Vector2i(0, 1),
	ItemData.Slot.OFFHAND: Vector2i(2, 1),
	ItemData.Slot.FEET: Vector2i(1, 2),
}
const SLOT_SIZE := Vector2(64, 64)

var _hero: Hero
var _doll: CharacterVisual
var _list: ItemList
var _spell_list: ItemList
var _points_label: Label
var _attr_values: Dictionary = {}  # atribut -> Label
var _attr_buttons: Array[Button] = []
var _info: Label
var _title: Label
var _stat_values: Dictionary = {}  # název statu -> Label
var _slot_buttons: Dictionary = {}  # Slot -> Button
var _listed: Array[ItemData] = []


func _ready() -> void:
	layer = 10
	visible = false
	add_to_group(&"inventory_ui")
	_build_ui()


func setup(hero: Hero) -> void:
	_hero = hero
	_doll.set_body(hero.visual.body_sheet, hero.visual.body_extra_sheet)
	_doll.modulate = hero.tint
	_doll.bind(hero.equipment)
	hero.inventory.changed.connect(_refresh)
	hero.equipment.slot_changed.connect(func(_slot: int) -> void: _refresh())
	hero.hp_changed.connect(func(_hp: int, _max: int) -> void: _refresh())
	hero.mana_changed.connect(func(_m: int, _max: int) -> void: _refresh())
	hero.xp_changed.connect(func(_x: int, _n: int) -> void: _refresh())
	hero.skills_changed.connect(_refresh)
	_refresh()


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"pause"):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	visible = not visible
	if _hero:
		_hero.controls_enabled = not visible
		if visible:
			_refresh()


# --- stavba UI ---
func _build_ui() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.07, 0.1, 0.96)
	style.border_color = Color(0.75, 0.62, 0.3)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	panel.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)
	root.add_child(_label("Inventář   (I / Tab = zavřít, N = noc/den)"))

	var tabs := TabContainer.new()
	root.add_child(tabs)
	var columns := HBoxContainer.new()
	columns.name = "Postava"
	columns.add_theme_constant_override("separation", 20)
	tabs.add_child(columns)
	columns.add_child(_build_character_column())
	columns.add_child(_build_bag_column())
	tabs.add_child(_build_skills_tab())
	tabs.add_child(_build_spells_tab())

	_info = _label("")
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(0, 40)
	root.add_child(_info)


func _build_character_column() -> Control:
	var box := VBoxContainer.new()
	_title = _label("")
	_title.add_theme_font_size_override("font_size", 18)
	box.add_child(_title)

	var grid := GridContainer.new()
	grid.columns = 3
	box.add_child(grid)
	for row in 3:
		for col in 3:
			var cell := Vector2i(col, row)
			if cell == Vector2i(1, 1):
				grid.add_child(_build_doll())
				continue
			var slot: int = DOLL_GRID.find_key(cell) if DOLL_GRID.values().has(cell) else -1
			grid.add_child(_make_slot_button(slot) if slot >= 0 else _spacer(SLOT_SIZE))

	box.add_child(HSeparator.new())
	var stats := GridContainer.new()
	stats.columns = 2
	stats.add_theme_constant_override("h_separation", 24)
	box.add_child(stats)
	for stat in ["Zdraví", "Mana", "Zkušenosti", "Útok", "Obrana", "Rychlost", "Světlo"]:
		stats.add_child(_label(stat))
		var value := _label("")
		stats.add_child(value)
		_stat_values[stat] = value

	var strip := Button.new()
	strip.text = "Svléct vše"
	strip.pressed.connect(func() -> void: _hero.equipment.unequip_all(_hero.inventory))
	box.add_child(strip)
	return box


func _build_doll() -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(150, 200)
	holder.clip_contents = true
	_doll = CharacterVisual.new()
	_doll.position = Vector2(75, 185)
	_doll.scale = Vector2(2.5, 2.5)
	holder.add_child(_doll)
	return holder


func _make_slot_button(slot: int) -> Button:
	var button := Button.new()
	button.custom_minimum_size = SLOT_SIZE
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_font_size_override("font_size", 11)
	button.pressed.connect(func() -> void: _hero.equipment.unequip(slot, _hero.inventory))
	_slot_buttons[slot] = button
	return button


func _build_bag_column() -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(_label("Batoh"))
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(400, 380)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.fixed_icon_size = Vector2i(40, 40)
	_list.item_selected.connect(_on_item_selected)
	box.add_child(_list)
	return box


func _build_skills_tab() -> Control:
	var box := VBoxContainer.new()
	box.name = "Dovednosti"
	box.add_theme_constant_override("separation", 10)
	_points_label = _label("")
	_points_label.add_theme_font_size_override("font_size", 18)
	box.add_child(_points_label)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 10)
	box.add_child(grid)
	for key in Character.ATTRIBUTES:
		grid.add_child(_label(Character.ATTRIBUTES[key][0]))
		var value := _label("")
		grid.add_child(value)
		_attr_values[key] = value
		var plus := Button.new()
		plus.text = " + "
		plus.pressed.connect(func() -> void: _hero.spend_point(key))
		_attr_buttons.append(plus)
		grid.add_child(plus)
		grid.add_child(_label(Character.ATTRIBUTES[key][1] + " za bod"))
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(700, 260)
	box.add_child(pad)
	return box


func _build_spells_tab() -> Control:
	var box := VBoxContainer.new()
	box.name = "Kouzla"
	box.add_child(_label("Naučená kouzla – klik nastaví aktivní kouzlo (sesílá se klávesou Q)"))
	_spell_list = ItemList.new()
	_spell_list.custom_minimum_size = Vector2(700, 380)
	_spell_list.item_selected.connect(_on_spell_selected)
	box.add_child(_spell_list)
	return box


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _spacer(size: Vector2) -> Control:
	var c := Control.new()
	c.custom_minimum_size = size
	return c


# --- obsah ---
func _refresh() -> void:
	_title.text = "%s   (úroveň %d)" % [_hero.display_name, _hero.level]
	_list.clear()
	_listed.clear()
	for id in _hero.inventory.ids():
		var item := ItemDB.get_item(id)
		_listed.append(item)
		var stats := item.stats_text()
		var amount := _hero.inventory.count(id)
		_list.add_item(item.display_name + (" ×%d" % amount if amount > 1 else "") + ("  —  " + stats if stats else ""), item.icon)
	for slot in _slot_buttons:
		var item := _hero.equipment.get_item(slot)
		var button: Button = _slot_buttons[slot]
		button.icon = item.icon if item else null
		button.text = "" if item else ItemData.SLOT_NAMES[slot]
		button.tooltip_text = "%s\n%s\n(klik = sundat)" % [item.display_name, item.stats_text()] if item else ""
	_stat_values["Zdraví"].text = "%d / %d" % [_hero.hp, _hero.max_hp()]
	_stat_values["Mana"].text = "%d / %d" % [_hero.mana, _hero.max_mana()]
	_stat_values["Zkušenosti"].text = "%d / %d" % [_hero.xp, _hero.xp_needed()]
	_spell_list.clear()
	for spell in _hero.spells:
		_spell_list.add_item("%s%s  —  %s" % ["▶ " if spell == _hero.active_spell else "    ", spell.display_name, spell.stats_text()])
	_stat_values["Útok"].text = "%d" % _hero.attack_power()
	_stat_values["Obrana"].text = "%d" % _hero.defense()
	_stat_values["Rychlost"].text = "%d" % (_hero.walk_speed * _hero.speed_mult())
	_points_label.text = "Volné body: %d" % _hero.skill_points
	for key in _attr_values:
		_attr_values[key].text = str(_hero.attributes[key])
	for button in _attr_buttons:
		button.disabled = _hero.skill_points <= 0
	var off := _hero.equipment.get_item(ItemData.Slot.OFFHAND)
	_stat_values["Světlo"].text = "ano" if off and off.light > 0.0 else "ne"
	_doll.play(_hero.loco(&"idle"), AnimCatalog.Dir.DOWN)


func _on_spell_selected(index: int) -> void:
	_hero.active_spell = _hero.spells[index]
	_info.text = "%s – %s" % [_hero.active_spell.display_name, _hero.active_spell.description]
	_refresh()


func _on_item_selected(index: int) -> void:
	var item := _listed[index]
	_info.text = "%s – %s %s" % [item.display_name, item.description, item.stats_text()]
	_hero.equipment.equip(item, _hero.inventory)
