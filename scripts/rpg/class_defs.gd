class_name ClassDefs
extends RefCounted
## Povolání. Přidání nové třídy = nový záznam v CLASSES (a případně skill v BattleScene3._use_skill).
## `passives` se čtou v boji přes BattleUnit3.passive(klíč): speed, crit, dmg_taken, mp_turn, bp_start,
## fear_resist, xp_bonus, reveal (kronikář zná slabiny nepřátel).
## Cílem je, aby si hráč třídu vybral až ve hře; teď ji vybírá ikonou před startem (Session.class_id).

const ORDER: Array[StringName] = [&"warrior", &"ranger", &"mage", &"rogue", &"chronicler"]

const CLASSES := {
	&"warrior": {"name": "Válečník", "icon": "V", "color": Color(0.85, 0.35, 0.3),
		"desc": "Tvrdý a odolný. Dlouhý meč, plátová zbroj. Úder štítem omráčí nepřítele.",
		"hp": 44, "atk": 3, "def": 0, "mana": 8, "agi": 0, "items": [&"longsword", &"plate"], "spells": [],
		"passives": {"dmg_taken": -0.05},
		"skill": {"id": &"shieldbash", "label": "Úder štítem", "mp": 4}},
	&"ranger": {"name": "Lovec", "icon": "L", "color": Color(0.4, 0.75, 0.35),
		"desc": "Rychlý střelec s lukem. Šípová salva zasáhne všechny nepřátele.",
		"hp": 32, "atk": 3, "def": 0, "mana": 14, "agi": 3, "items": [&"bow", &"hood", &"boots"], "spells": [],
		"passives": {"speed": 2, "crit": 0.10},
		"skill": {"id": &"volley", "label": "Šípová salva", "mp": 6}},
	&"mage": {"name": "Mág", "icon": "M", "color": Color(0.4, 0.5, 1.0),
		"desc": "Křehký, ale mocný. Ohnivá koule a léčení. Soustředění dá 2 BP.",
		"hp": 24, "atk": 1, "def": 0, "mana": 40, "agi": 1, "items": [&"staff", &"wizard_hat"], "spells": [&"fireball", &"heal"],
		"passives": {"mp_turn": 2},
		"skill": {"id": &"focus", "label": "Soustředění", "mp": 0}},
	&"rogue": {"name": "Zloděj", "icon": "Z", "color": Color(0.7, 0.55, 0.85),
		"desc": "Nejrychlejší, kritické zásahy. Může okrást lidské nepřátele.",
		"hp": 30, "atk": 2, "def": 0, "mana": 14, "agi": 5, "items": [&"dagger", &"gloves"], "spells": [],
		"passives": {"crit": 0.15, "speed": 2},
		"skill": {"id": &"steal", "label": "Okrást", "mp": 3}},
	&"chronicler": {"name": "Kronikář", "icon": "K", "color": Color(0.95, 0.8, 0.35),
		"desc": "Originál: zná slabiny nepřátel hned na začátku souboje, víc zkušeností, zapisuje bestiář (Zápis odhalí všechny slabiny).",
		"hp": 28, "atk": 2, "def": 0, "mana": 26, "agi": 1, "items": [&"sword", &"frock_coat"], "spells": [&"heal"],
		"passives": {"reveal": 1, "xp_bonus": 0.25, "bp_start": 1},
		"skill": {"id": &"scribe", "label": "Zápis", "mp": 4}},
}


static func apply(c: Character, id: StringName) -> void:
	var d: Dictionary = CLASSES[id]
	c.set_meta(&"class_id", id)
	c.set_meta(&"class_passives", d["passives"])
	c.base_max_hp = d["hp"]
	c.base_attack = d["atk"]
	c.base_defense = d["def"]
	c.base_max_mana = d["mana"]
	c.attributes[&"agility"] = d["agi"]
	c.spells.clear()
	for sid in d["spells"]:
		c.spells.append(load("res://data/spells/%s.tres" % sid) as SpellData)
	c.active_spell = c.spells[0] if not c.spells.is_empty() else null
	for wid in d["items"]:
		c.inventory.add(wid)
		c.equipment.equip(ItemDB.get_item(wid), c.inventory)
	c.hp = c.max_hp()
	c.mana = float(c.max_mana())


static func class_name_of(c: Character) -> String:
	return CLASSES[c.get_meta(&"class_id", &"warrior")]["name"]


static func skill_of(c: Character) -> Dictionary:
	var id: StringName = c.get_meta(&"class_id", &"")
	return CLASSES[id]["skill"] if CLASSES.has(id) else {}
