class_name LootEntry
extends Resource
## Jedna položka loot tabulky nepřítele: předmět + šance (0–1), že spadne.

@export var item: ItemData
@export_range(0.0, 1.0) var chance := 0.25
