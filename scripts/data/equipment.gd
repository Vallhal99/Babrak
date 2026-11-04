class_name Equipment
extends Resource
## Co má postava na sobě (slot -> ItemData). Přesouvá předměty mezi batohem a sloty.

signal slot_changed(slot: int)

var _slots: Dictionary = {}  # ItemData.Slot -> ItemData


func get_item(slot: int) -> ItemData:
	return _slots.get(slot)


func equip(item: ItemData, inventory: Inventory) -> bool:
	if item.slot == ItemData.Slot.NONE or not inventory.has(item.id):
		return false
	unequip(item.slot, inventory)
	inventory.remove(item.id)
	_slots[item.slot] = item
	slot_changed.emit(item.slot)
	return true


func unequip(slot: int, inventory: Inventory) -> void:
	var old: ItemData = _slots.get(slot)
	if old == null:
		return
	_slots.erase(slot)
	inventory.add(old.id)
	slot_changed.emit(slot)


func unequip_all(inventory: Inventory) -> void:
	for slot in _slots.keys():
		unequip(slot, inventory)


## Součet číselné vlastnosti (damage, defense, max_hp...) přes všechno nasazené.
func sum_of(prop: StringName) -> int:
	var total := 0
	for item: ItemData in _slots.values():
		total += item.get(prop)
	return total
