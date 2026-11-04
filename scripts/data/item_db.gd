extends Node
## Autoload ItemDB: načte všechny ItemData z ITEM_DIR.

const ITEM_DIR := "res://data/items/"

var _items: Dictionary = {}  # StringName -> ItemData


func _ready() -> void:
	for file in DirAccess.get_files_at(ITEM_DIR):
		file = file.trim_suffix(".remap")  # export přejmenovává .tres na .tres.remap
		if file.ends_with(".tres"):
			var item := load(ITEM_DIR + file) as ItemData
			if item:
				_items[item.id] = item


func get_item(id: StringName) -> ItemData:
	return _items.get(id)


func all() -> Array[ItemData]:
	var result: Array[ItemData] = []
	for item in _items.values():
		result.append(item)
	return result
