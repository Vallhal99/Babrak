class_name ShopPanel
extends CanvasLayer
## Obchod: vlevo nabídka obchodníka (klik = koupit), vpravo tvůj batoh (klik = prodat za polovinu ceny).
## Esc zavře (skupina inventory_ui kvůli pauze).

var _hero: Hero
var _stock: Array[ItemData] = []
var _bag: Array[ItemData] = []
var _stock_list: ItemList
var _bag_list: ItemList
var _gold: Label
var _info: Label


func _ready() -> void:
	layer = 11
	visible = false
	add_to_group(&"inventory_ui")
	_build_ui()


func setup(hero: Hero) -> void:
	_hero = hero
	hero.gold_changed.connect(func(_g: int) -> void: _refresh())
	hero.inventory.changed.connect(_refresh)


func open(npc: Npc) -> void:
	_stock = npc.shop_stock
	_info.text = "%s: Čím posloužím?" % npc.display_name
	visible = true
	_hero.controls_enabled = false
	_refresh()


func close() -> void:
	visible = false
	_hero.controls_enabled = true


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"pause"):
		close()
		get_viewport().set_input_as_handled()


static func sell_price(item: ItemData) -> int:
	return maxi(1, item.price / 2)


func buy(item: ItemData) -> bool:
	if not _hero.spend_gold(item.price):
		_info.text = "Nemáš dost zlata."
		return false
	_hero.inventory.add(item.id)
	_info.text = "Koupeno: %s" % item.display_name
	return true


func sell(item: ItemData) -> bool:
	if not _hero.inventory.remove(item.id):
		return false
	_hero.add_gold(sell_price(item))
	_info.text = "Prodáno: %s (+%d zl.)" % [item.display_name, sell_price(item)]
	return true


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
	_gold = Label.new()
	_gold.add_theme_font_size_override("font_size", 18)
	root.add_child(_gold)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	root.add_child(columns)
	_stock_list = _column(columns, "Nabídka (klik = koupit)")
	_stock_list.item_selected.connect(func(i: int) -> void: buy(_stock[i]))
	_bag_list = _column(columns, "Tvůj batoh (klik = prodat)")
	_bag_list.item_selected.connect(func(i: int) -> void: sell(_bag[i]))
	_info = Label.new()
	root.add_child(_info)
	var close_button := Button.new()
	close_button.text = "Zavřít (Esc)"
	close_button.pressed.connect(close)
	root.add_child(close_button)


func _column(parent: Control, title: String) -> ItemList:
	var box := VBoxContainer.new()
	var label := Label.new()
	label.text = title
	box.add_child(label)
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(380, 360)
	list.fixed_icon_size = Vector2i(40, 40)
	box.add_child(list)
	parent.add_child(box)
	return list


func _refresh() -> void:
	_gold.text = "Zlato: %d" % _hero.gold
	_stock_list.clear()
	for item in _stock:
		_stock_list.add_item("%s  —  %d zl.  %s" % [item.display_name, item.price, item.stats_text()], item.icon)
	_bag_list.clear()
	_bag.clear()
	for id in _hero.inventory.ids():
		var item := ItemDB.get_item(id)
		_bag.append(item)
		var amount := _hero.inventory.count(id)
		_bag_list.add_item("%s%s  —  %d zl." % [item.display_name, " ×%d" % amount if amount > 1 else "", sell_price(item)], item.icon)
