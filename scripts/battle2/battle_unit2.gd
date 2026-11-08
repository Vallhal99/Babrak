class_name BattleUnit2
extends RefCounted
## Jeden účastník tahového souboje (hrdina, spojenec nebo nepřítel).
## Zdraví, manu, staty a vybavení bere přímo z `source` (Character).

const TYPE_NAMES := {&"blade": "Čepel", &"blunt": "Tupá", &"bow": "Střela", &"fire": "Oheň"}
const SPELL_TYPES := {&"fireball": &"fire"}
const STATUS_SHORT := {&"bleed": "Krvácí", &"burn": "Hoří", &"poison": "Jed", &"stun": "Omráčen",
	&"fear": "Strach", &"armorbreak": "Bez zbroje"}
## Pasivky vybavení v souboji: id předmětu -> {efekt: hodnota}.
const PASSIVES := {
	&"boots": {"speed": 3}, &"gloves": {"crit": 0.10}, &"hood": {"fear_resist": 1},
	&"mail_coif": {"fear_resist": 1}, &"close_helm": {"fear_resist": 1, "speed": -1},
	&"wizard_hat": {"mp_turn": 2}, &"plate": {"dmg_taken": -0.15, "speed": -2},
	&"chainmail": {"dmg_taken": -0.08}, &"frock_coat": {"bp_start": 1}, &"dagger": {"speed": 4, "crit": 0.10},
}
const PASSIVE_TEXT := {"speed": "Rychlost %+d", "crit": "Krit %+d %%", "fear_resist": "Odolnost proti strachu",
	"mp_turn": "+%d MP za tah", "dmg_taken": "Zranění %+d %%", "bp_start": "+%d BP na startu"}

var source: Character
var is_party := false
var display_name := ""
var index := 0
var speed := 10
var shield := 0
var max_shield := 0
var weaknesses: Array[StringName] = []
var revealed: Array[StringName] = []
var locked: Array[StringName] = []    ## slabiny zamčené Pozorováním (+15 % zranění)
var broken := false
var defending := false
var bp := 0
var row := 0
var human := false
var rank: StringName = &"normal"
var phases_left := 1
var phases := 1
var morale := 100
var low_morale_hit := false
var fled := false
var ranged := false
var charge := false
var turns := 0
var statuses := {}                    ## StringName -> zbývající tahy
var hidden_slots: Array[int] = []

var holder: Node2D
var visual: CharacterVisual
var home := Vector2.ZERO
var dir: int = AnimCatalog.Dir.LEFT
var flash_tween: Tween


static func from_character(c: Character, party: bool) -> BattleUnit2:
	var u := BattleUnit2.new()
	u.source = c
	u.is_party = party
	u.display_name = c.display_name
	if party:
		u.speed = 10 + 2 * int(c.attributes[&"agility"]) + int(u.passive("speed"))
		u.dir = AnimCatalog.Dir.LEFT
	else:
		u.dir = AnimCatalog.Dir.RIGHT
		var e := c as TurnEnemy2
		if e:
			u.speed = e.battle_speed
			u.max_shield = e.shield_points
			u.shield = e.shield_points
			u.weaknesses = e.weaknesses.duplicate()
			u.row = e.row
			u.human = e.human
			u.rank = e.rank
			u.phases = e.phases
			u.phases_left = e.phases
			u.ranged = e.ranged
	return u


static func weapon_type(item: ItemData) -> StringName:
	if item == null:
		return &"blunt"
	if item.ranged:
		return &"bow"
	match item.id:
		&"blunt", &"staff":
			return &"blunt"
	return &"blade"


## Součet pasivky (jen družina) přes nasazené vybavení.
func passive(key: String) -> float:
	var total := 0.0
	if not is_party:
		return total
	for slot in ItemData.Slot.values():
		var item := source.equipment.get_item(slot)
		if item and PASSIVES.has(item.id):
			total += float(PASSIVES[item.id].get(key, 0))
	return total


func passive_text() -> String:
	var parts := PackedStringArray()
	for key in PASSIVE_TEXT:
		var v := passive(key)
		if v == 0.0:
			continue
		var fmt: String = PASSIVE_TEXT[key]
		if key == "crit" or key == "dmg_taken":
			parts.append(fmt % roundi(v * 100.0))
		elif "%" in fmt:
			parts.append(fmt % int(v))
		else:
			parts.append(fmt)
	return ", ".join(parts) if not parts.is_empty() else "žádné"


func weapon() -> ItemData:
	return source.equipment.get_item(ItemData.Slot.WEAPON)


func attack() -> int:
	return source.attack_power()


## Obrana: rozbité kusy vybavení a stav "Bez zbroje" ji snižují.
func defense() -> int:
	var d := source.defense()
	for s in hidden_slots:
		var it := source.equipment.get_item(s)
		if it:
			d -= it.defense
	if statuses.has(&"armorbreak"):
		d = d / 2
	return maxi(0, d)


## Rozbije jeden nasazený kus (hlava, tělo, rukavice, boty) a skryje jeho vrstvu. Vrátí jeho název ("" = nic).
func break_piece() -> String:
	for slot in [ItemData.Slot.HEAD, ItemData.Slot.TORSO, ItemData.Slot.HANDS, ItemData.Slot.FEET]:
		var item := source.equipment.get_item(slot)
		if item and not hidden_slots.has(slot):
			hidden_slots.append(slot)
			visual.hidden_slots = hidden_slots.duplicate()
			visual._apply()
			return item.display_name
	return ""


func add_status(name: StringName, turns_left: int) -> bool:
	if name == &"fear" and passive("fear_resist") > 0.0:
		return false
	statuses[name] = maxi(int(statuses.get(name, 0)), turns_left)
	return true


func hp() -> int:
	return source.hp


func max_hp() -> int:
	return source.max_hp()


func alive() -> bool:
	return source.hp > 0 and not fled


func set_hp(value: int) -> void:
	source.hp = clampi(value, 0, source.max_hp())
	source.hp_changed.emit(source.hp, source.max_hp())


func back_dir() -> int:
	return AnimCatalog.Dir.RIGHT if dir == AnimCatalog.Dir.LEFT else AnimCatalog.Dir.LEFT


func center() -> Vector2:
	return holder.position + Vector2(0, -90)
