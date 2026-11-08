class_name BattleUnit
extends RefCounted
## Jeden účastník tahového souboje (hrdina nebo nepřítel).
## Zdraví, manu, staty a vybavení bere přímo z `source` (Character), takže souboj
## navazuje na postavu ze světa a její výsledek se do světa propíše sám.

## Typy útoku pro slabiny (Octopath). Klíč = identifikátor, hodnota = název v češtině.
const TYPE_NAMES := {
	&"blade": "Čepel",
	&"blunt": "Tupá",
	&"bow": "Střela",
	&"fire": "Oheň",
}
## Kouzlo -> typ útoku. Kouzlo, které tu není, nemá typ (&"magic") a slabinu netrefí.
const SPELL_TYPES := {&"fireball": &"fire"}

var source: Character
var is_party := false
var display_name := ""
var index := 0                      ## pořadí vzniku (rozhoduje při stejné rychlosti)
var speed := 10
var shield := 0
var max_shield := 0
var weaknesses: Array[StringName] = []
var revealed: Array[StringName] = []  ## slabiny, které hráč už odhalil
var broken := false
var defending := false
var bp := 0                         ## Boost Points (jen hrdinové)

# vizuál (nastavuje BattleScene)
var holder: Node2D
var visual: CharacterVisual
var home := Vector2.ZERO
var dir: int = AnimCatalog.Dir.LEFT
var flash_tween: Tween


static func from_character(c: Character, party: bool) -> BattleUnit:
	var u := BattleUnit.new()
	u.source = c
	u.is_party = party
	u.display_name = c.display_name
	if party:
		u.speed = 10 + 2 * int(c.attributes[&"agility"])
		u.dir = AnimCatalog.Dir.LEFT
	else:
		u.dir = AnimCatalog.Dir.RIGHT
		var e := c as TurnEnemy
		if e:
			u.speed = e.battle_speed
			u.max_shield = e.shield_points
			u.shield = e.shield_points
			u.weaknesses = e.weaknesses.duplicate()
	return u


## Typ útoku zbraně: střelná = bow, hůl/palcát/pěsti = blunt, ostatní = blade.
static func weapon_type(item: ItemData) -> StringName:
	if item == null:
		return &"blunt"
	if item.ranged:
		return &"bow"
	match item.id:
		&"blunt", &"staff":
			return &"blunt"
	return &"blade"


func weapon() -> ItemData:
	return source.equipment.get_item(ItemData.Slot.WEAPON)


func attack() -> int:
	return source.attack_power()


func defense() -> int:
	return source.defense()


func hp() -> int:
	return source.hp


func max_hp() -> int:
	return source.max_hp()


func alive() -> bool:
	return source.hp > 0


func set_hp(value: int) -> void:
	source.hp = clampi(value, 0, source.max_hp())
	source.hp_changed.emit(source.hp, source.max_hp())


## Směr, kterým se jednotka vrací na místo (opačný než čelí).
func back_dir() -> int:
	return AnimCatalog.Dir.RIGHT if dir == AnimCatalog.Dir.LEFT else AnimCatalog.Dir.LEFT


## Střed těla na obrazovce (pro efekty a čísla).
func center() -> Vector2:
	return holder.position + Vector2(0, -90)
