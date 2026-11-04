class_name SpellData
extends Resource
## Definice kouzla. Nové kouzlo = nový .tres (a přidat postavě do `spells`).

enum Effect { PROJECTILE, HEAL }

@export var id: StringName
@export var display_name := ""
@export_multiline var description := ""
@export var effect: Effect = Effect.PROJECTILE
@export var mana_cost := 5
@export var power := 6  # poškození / léčení (+ úroveň sesilatele)
@export var color := Color(1.0, 0.5, 0.1)
@export var cast_anim: StringName = &"spellcast"


func stats_text() -> String:
	var what := "Léčení" if effect == Effect.HEAL else "Poškození"
	return "Mana %d, %s %d" % [mana_cost, what, power]
