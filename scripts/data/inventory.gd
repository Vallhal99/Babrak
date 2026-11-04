class_name Inventory
extends Resource
## Batoh: id předmětu -> počet. Jako Resource jde později rovnou uložit.

var _counts: Dictionary = {}  # StringName -> int


func add(id: StringName, amount := 1) -> void:
	_counts[id] = count(id) + amount
	emit_changed()


func remove(id: StringName, amount := 1) -> bool:
	if count(id) < amount:
		return false
	_counts[id] = count(id) - amount
	if _counts[id] == 0:
		_counts.erase(id)
	emit_changed()
	return true


func count(id: StringName) -> int:
	return _counts.get(id, 0)


func has(id: StringName) -> bool:
	return count(id) > 0


func ids() -> Array:
	var keys := _counts.keys()
	keys.sort()
	return keys
