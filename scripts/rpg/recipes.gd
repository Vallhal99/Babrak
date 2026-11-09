class_name Recipes
extends RefCounted
## Receptury: pracovní stůl (kování, výroba) a ohniště (vaření). Ingredience jsou předměty v batohu.
## out: {"item": id} → předmět do batohu · {"cons": {id: n}} → bojové předměty · {"picks": n} → paklíče.

const WORK := [
	{"name": "Meč", "in": {&"iron": 3}, "out": {"item": &"sword"}, "desc": "Základní zbraň z kovu."},
	{"name": "Dýka", "in": {&"iron": 2}, "out": {"item": &"dagger"}, "desc": "Rychlá a lehká."},
	{"name": "Uzavřená přilba", "in": {&"iron": 4}, "out": {"item": &"close_helm"}, "desc": "Pevná ochrana hlavy."},
	{"name": "Paklíče ×3", "in": {&"iron": 1}, "out": {"picks": 3}, "desc": "Na zámky a truhly."},
	{"name": "Pochodeň", "in": {&"wood": 2}, "out": {"item": &"torch"}, "desc": "Svítí a odhalí slabiny v noci."},
	{"name": "Ohnivá bomba ×2", "in": {&"iron": 1, &"herb": 1}, "out": {"cons": {&"bomb": 2}}, "desc": "14 ohně, hoření."},
]
const COOK := [
	{"name": "Pečené maso", "in": {&"meat": 1}, "out": {"cons": {&"roast": 1}}, "desc": "V boji +35 HP."},
	{"name": "Lovecký guláš", "in": {&"meat": 1, &"mushroom": 1, &"herb": 1}, "out": {"cons": {&"stew": 1}}, "desc": "V boji +60 HP."},
	{"name": "Bylinný čaj ×2", "in": {&"herb": 2}, "out": {"cons": {&"tea": 2}}, "desc": "V boji +15 MP."},
	{"name": "Houbová polévka", "in": {&"mushroom": 2, &"herb": 1}, "out": {"cons": {&"antidote": 1}}, "desc": "Léčí stavy."},
]


static func list(kind: StringName) -> Array:
	return WORK if kind == &"workbench" else COOK


static func can_make(hero: Character, r: Dictionary) -> bool:
	for id in r["in"]:
		if hero.inventory.count(id) < int(r["in"][id]):
			return false
	return true


static func make(hero: Character, r: Dictionary) -> bool:
	if not can_make(hero, r):
		return false
	for id in r["in"]:
		hero.inventory.remove(id, int(r["in"][id]))
	var out: Dictionary = r["out"]
	if out.has("item"):
		hero.inventory.add(out["item"])
	if out.has("cons"):
		var cons := BattleScene3.consumables_of(hero)
		for id in out["cons"]:
			cons[id] = int(cons.get(id, 0)) + int(out["cons"][id])
	if out.has("picks"):
		hero.set_meta(&"lockpicks", int(hero.get_meta(&"lockpicks", 2)) + int(out["picks"]))
	return true


static func ingredients_text(hero: Character, r: Dictionary) -> String:
	var parts: PackedStringArray = []
	for id in r["in"]:
		var it := ItemDB.get_item(id)
		parts.append("%d× %s (máš %d)" % [r["in"][id], it.display_name if it else str(id), hero.inventory.count(id)])
	return ", ".join(parts)
