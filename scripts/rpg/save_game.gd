class_name SaveGame
extends RefCounted
## Ukládání hry (Tah 3): user://save_<slot>.json, 3 sloty. Ukládá hrdinu, družinu, batoh, vybavení,
## questy a příznaky, otevřené truhly, čas a počasí, polohu. Nepřátelé se po načtení vytvoří znovu.

const SLOTS := 3


static func path(slot: int) -> String:
	return "user://save_%d.json" % slot


static func exists(slot: int) -> bool:
	return FileAccess.file_exists(path(slot))


static func read(slot: int) -> Dictionary:
	if not exists(slot):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path(slot)))
	return parsed if parsed is Dictionary else {}


static func summary(slot: int) -> String:
	var d := read(slot)
	if d.is_empty():
		return "Prázdný slot"
	var cls: String = ClassDefs.CLASSES.get(StringName(d.get("class", "")), {}).get("name", "?")
	return "%s · úr. %d · družina %d · %s" % [cls, int(d["hero"]["level"]), 1 + d["party"].size(), d.get("time", "")]


static func write(slot: int, main: Node) -> bool:
	var f := FileAccess.open(path(slot), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(collect(main)))
	return true


static func _char(c: Character) -> Dictionary:
	var inv := {}
	for id in c.inventory.ids():
		inv[String(id)] = c.inventory.count(id)
	var eq := {}
	for slot in ItemData.Slot.values():
		var it := c.equipment.get_item(slot)
		if it:
			eq[str(slot)] = String(it.id)
	var attrs := {}
	for k in c.attributes:
		attrs[String(k)] = c.attributes[k]
	return {"level": c.level, "xp": c.xp, "points": c.skill_points, "attrs": attrs, "hp": c.hp, "mana": c.mana,
		"gold": c.gold, "inv": inv, "eq": eq}


static func collect(main: Node) -> Dictionary:
	var hero: Hero = main.hero
	var party := []
	for m in main.party.slice(1):
		party.append({"id": String((m as Companion).companion_id), "c": _char(m)})
	var cons := {}
	for k in hero.get_meta(&"consumables", {}):
		cons[String(k)] = hero.get_meta(&"consumables")[k]
	return {"version": 1, "time": Time.get_datetime_string_from_system().replace("T", " ").substr(0, 16),
		"class": String(hero.get_meta(&"class_id", &"warrior")), "hero": _char(hero), "party": party,
		"pos": [main._door_out.x if main.inside_shop else hero.global_position.x, main._door_out.y if main.inside_shop else hero.global_position.y],
		"codex": main.codex.to_dict(), "hour_set": true, "hour": main.world.hour,
		"weather": main.world.fx.weather if main.world.fx else "jasno",
		"quests": {"state": main.quests.state, "flags": main.quests.flags},
		"chests": main.opened_chests, "cons": cons, "picks": int(hero.get_meta(&"lockpicks", 0))}


static func _apply_char(c: Character, d: Dictionary) -> void:
	c.level = int(d["level"])
	c.xp = int(d["xp"])
	c.skill_points = int(d["points"])
	for k in d["attrs"]:
		c.attributes[StringName(k)] = int(d["attrs"][k])
	c.equipment.unequip_all(c.inventory)
	c.inventory._counts.clear()
	for k in d["inv"]:
		c.inventory._counts[StringName(k)] = int(d["inv"][k])
	c.inventory.emit_changed()
	for slot in d["eq"]:
		var item := ItemDB.get_item(StringName(d["eq"][slot]))
		if item:
			c.inventory.add(item.id)
			c.equipment.equip(item, c.inventory)
	c.gold = int(d["gold"])
	c.hp = clampi(int(d["hp"]), 1, c.max_hp())
	c.mana = minf(float(d["mana"]), float(c.max_mana()))
	c.hp_changed.emit(c.hp, c.max_hp())


## Načte uloženou hru do už vytvořené herní scény (hrdina, společníci, truhly i obchodník stojí).
static func apply(main: Node, d: Dictionary) -> void:
	var hero: Hero = main.hero
	_apply_char(hero, d["hero"])
	hero.global_position = Vector2(d["pos"][0], d["pos"][1])
	main.world.set_time(float(d["hour"]))
	if main.world.fx:
		main.world.fx.set_weather(String(d["weather"]))
	for entry in d["party"]:
		for node in main.get_tree().get_nodes_in_group(&"characters"):
			var c := node as Companion
			if c != null and String(c.companion_id) == entry["id"] and not c.joined:
				c.joined = true
				c.leader = hero
				c.global_position = hero.global_position + Vector2(-30, 20)
				_apply_char(c, entry["c"])
				main.party.append(c)
	if d.has("codex"):
		main.codex.from_dict(d["codex"])
	main.quests.state = d["quests"]["state"]
	main.quests.flags = d["quests"]["flags"]
	main.quests.changed.emit()
	main.opened_chests.assign(d["chests"])
	for node in main.get_tree().get_nodes_in_group(&"chests"):
		(node as Chest).set_open((node as Chest).chest_id in main.opened_chests)
	var cons := {}
	for k in d["cons"]:
		cons[StringName(k)] = int(d["cons"][k])
	hero.set_meta(&"consumables", cons)
	hero.set_meta(&"lockpicks", int(d["picks"]))
