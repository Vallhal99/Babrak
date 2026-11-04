class_name ItemData
extends Resource
## Definice předmětu. Nový předmět = nový .tres v res://data/items/ (ItemDB ho najde sám).

## Nový slot: přidat sem + do SLOT_NAMES + do CharacterVisual.DRAW_ORDER + do InventoryPanel.SLOTS.
enum Slot { NONE, WEAPON, HEAD, FEET, OFFHAND }

const SLOT_NAMES := {
	Slot.NONE: "",
	Slot.WEAPON: "Zbraň",
	Slot.HEAD: "Hlava",
	Slot.FEET: "Boty",
	Slot.OFFHAND: "Druhá ruka",
}

@export var id: StringName
@export var display_name := ""
@export_multiline var description := ""
@export var icon: Texture2D
@export var slot: Slot = Slot.NONE
## Cena v obchodě (prodej = polovina).
@export var price := 10
## Vrstva postavy ve standardním layoutu sheetu (viz AnimCatalog).
@export var layer_sheet: Texture2D
## Vrstva pro "extra" pózy (např. plamen pochodně), layout viz AnimCatalog (extra: true).
@export var extra_sheet: Texture2D
## Postoj: předmět mění chůzi/stání na animace "<stance>_idle/_walk/_run" (pochodeň = &"torch").
@export var stance: StringName = &""
## Poloměr světla v px (0 = nesvítí).
@export var light := 0.0
## Statistiky (sčítají se přes vybavení, viz Equipment.sum_of).
@export var damage := 0
@export var defense := 0
@export var max_hp := 0
@export var max_mana := 0
## Jen zbraně: animace útoku (slash / backslash / halfslash / thrust ...).
@export var attack_anim: StringName = &"slash"


func stats_text() -> String:
	var parts: PackedStringArray = []
	if damage: parts.append("Útok +%d" % damage)
	if defense: parts.append("Obrana +%d" % defense)
	if max_hp: parts.append("Zdraví +%d" % max_hp)
	if max_mana: parts.append("Mana +%d" % max_mana)
	if light > 0.0: parts.append("Svítí")
	return ", ".join(parts)
