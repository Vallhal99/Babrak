class_name BattleScene3
extends CanvasLayer
## Tahový souboj ve stylu Final Fantasy / Octopath Traveler.
##
## Hrdina stojí vpravo, nepřátelé vlevo před pozadím (les). Tahy jdou podle rychlosti,
## pořadí je vidět nahoře. Příkazy: Útok, Kouzla, Obrana, Boost, Útěk.
## Octopath prvky: Boost Points (BP) zvyšují počet zásahů / sílu kouzla, nepřátelé mají
## štít a slabiny (zásah do slabiny ubírá štít, na nule se nepřítel zlomí = ztratí tah a
## dostává víc zranění).
##
## Zdraví, mana, staty i vybavení se berou z postav ze světa (viz BattleUnit3), animace
## z existujících sheetů (AnimCatalog). Co postava nemá (např. animaci), se prostě přeskočí.
##
## Použití: add_child(BattleScene3.new()) -> start(hero, nepřátelé, pozadí) -> await finished.
## Výsledek: {"outcome": &"victory" | &"defeat" | &"fled", "xp", "gold", "loot", "leveled"}.

signal finished(result: Dictionary)
signal _menu_done(id: Variant)
signal _picked(unit: Variant)
signal _confirmed

static var use_arena := true          # HD-2D 3D bojiště (false = ploché pozadí)
const SCALE := 3.0                 # velikost postav na bojišti
const MAX_BP := 5
const MAX_BOOST := 3
const FLEE_CHANCE := 0.6
const WEAK_BONUS := 1.25           # zásah do slabiny
const BREAK_BONUS := 1.5           # zlomený nepřítel
const RUN_SPEED := 720.0           # px/s při náběhu na cíl
const REACH := 105.0               # vzdálenost, ze které se útočí zblízka
const PANEL_BG := Color(0.04, 0.07, 0.30, 0.92)
const PANEL_EDGE := Color(0.85, 0.88, 1.0)
const GOLD := Color(1.0, 0.85, 0.3)
const BG_DIR := "res://assets/battle/"
const ITEM_DEFS := {
	&"potion": {"name": "Lektvar léčení", "desc": "+20 HP"},
	&"ether": {"name": "Elixír many", "desc": "+12 MP"},
	&"bomb": {"name": "Ohnivá bomba", "desc": "14 ohně, hoření"},
	&"antidote": {"name": "Protilátka", "desc": "léčí stavy"},
	&"smoke": {"name": "Kouřová bomba", "desc": "jistý útěk"},
}
const RANK_MULT := {"S": 1.5, "A": 1.25, "B": 1.0, "C": 0.8}
const BRIBE_COST := 15   ## za nepřítele (elita ×3)


## Počasí a denní doba přes pozadí (déšť, sníh jako čáry a tečky).
class WeatherLayer extends Node2D:
	var kind := ""
	var area := Vector2(960, 720)
	var t := 0.0

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		if kind == "rain":
			for i in 90:
				var x := fposmod(float(i) * 97.0 + t * 80.0, area.x + 100.0) - 50.0
				var y := fposmod(float(i) * 53.0 + t * 900.0 + float(i * i % 17) * 40.0, area.y + 60.0) - 30.0
				draw_line(Vector2(x, y), Vector2(x - 8.0, y + 22.0), Color(0.75, 0.82, 1.0, 0.45), 1.5)
		elif kind == "snow":
			for i in 70:
				var x := fposmod(float(i) * 131.0 + sin(t + float(i)) * 20.0, area.x)
				var y := fposmod(float(i) * 47.0 + t * 60.0, area.y)
				draw_circle(Vector2(x, y), 2.5, Color(1, 1, 1, 0.8))

## Pro testy a ladění: hrdina hraje sám (1. tah kouzlo, pak útok, při 2+ BP s Boostem).
var autoplay := false
## Skriptované příkazy pro testy (bere se první, než se použije výchozí automat).
var script_actions: Array = []

var _env := {}
var _night := false
var _rain := false
var _first: StringName = &""       # kdo útočí první v 1. kole: &"hero" / &"enemy" / prázdné
var _rounds := 0
var _dmg_taken := 0
var _items_used := 0
var _chain := 0
var _chain_type: StringName = &""
var _omen_fog := false
var _angry := false
var _ally: BattleUnit3
var _p_pass: Label
var _party_rows: Array[Dictionary] = []
var _kills: Array[String] = []

var _hero: Hero
var _size := Vector2(960, 720)
var _party: Array[BattleUnit3] = []
var _enemies: Array[BattleUnit3] = []
var _state: StringName = &""        # prázdné = souboj běží; jinak victory / defeat / fled
var _result := {}
var _boost := 0
var _turn_no := 0
var _active: BattleUnit3
var _time := 0.0
var _next_index := 0

var _menu_open := false
var _cancel_ok := false
var _menu_title := ""
var _menu_memory := {}
var _menu_buttons: Array[Button] = []
var _picking := false
var _pick_list: Array[BattleUnit3] = []
var _pick_idx := 0
var _confirm_wait := false

var _stage: Node2D
var _ui: Control
var _cursor: Polygon2D
var _flash: ColorRect
var _timeline: HBoxContainer
var _banner: PanelContainer
var _banner_label: Label
var _cmd_panel: PanelContainer
var _cmd_title: Label
var _cmd_list: VBoxContainer
var _p_name: Label
var _p_hp: Label
var _p_hp_bar: ProgressBar
var _p_mp: Label
var _p_mp_bar: ProgressBar
var _pips: Array[ColorRect] = []
var _tags: Dictionary = {}          # BattleUnit3 -> {label, bg, fill, click}


## Načte texturu pozadí. Funguje i pro PNG, který editor ještě neimportoval.
static func load_texture(path: String) -> Texture2D:
	if not OS.has_feature("editor") or FileAccess.file_exists(path + ".import"):
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
		return null
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null:
		return null
	return ImageTexture.create_from_image(img)


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS   # běží i při pauze světa
	add_to_group(&"inventory_ui")             # PauseMenu pak při souboji nereaguje na Esc


func start(hero: Hero, enemies: Array[Character], bg: Texture2D, env := {}, opts := {}) -> void:
	_hero = hero
	_env = env
	var hour := float(env.get("hour", 12.0))
	_night = hour >= 20.5 or hour < 5.5
	_rain = String(env.get("weather", "jasno")) in ["déšť", "bouřka"]
	_first = opts.get("first", &"")
	_size = get_viewport().get_visible_rect().size
	_ensure_items()
	_build_ui(bg)
	_build_units(enemies, opts.get("allies", []))
	_run()


# ---------------------------------------------------------------- hlavní smyčka

func _run() -> void:
	await _intro()
	while _state == &"":
		_rounds += 1
		_omen_fog = false
		await _omen()
		_state = _outcome()
		if _state != &"":
			break
		var order := _round_order()
		for i in order.size():
			var u: BattleUnit3 = order[i]
			if not u.alive():
				continue
			_refresh_timeline(order, i)
			await _take_turn(u)
			if _state == &"":
				_state = _outcome()
			if _state != &"":
				break
	await _outro()
	_result["outcome"] = _state
	finished.emit(_result)


func _take_turn(u: BattleUnit3) -> void:
	if await _tick(u):
		return
	if u.is_party:
		await _party_turn(u)
	else:
		await _enemy_turn(u)


## Pořadí tahů v kole: rychlejší první, při shodě podle pořadí vzniku.
func _round_order() -> Array[BattleUnit3]:
	var all: Array[BattleUnit3] = []
	for u in _party + _enemies:
		if u.alive():
			all.append(u)
	all.sort_custom(_by_speed)
	if _rounds <= 1 and _first != &"":  # iniciativa: zálusk / přepadení
		var a: Array[BattleUnit3] = []
		var b: Array[BattleUnit3] = []
		for u in all:
			if u.is_party == (_first == &"hero"):
				a.append(u)
			else:
				b.append(u)
		a.append_array(b)
		return a
	return all


static func _by_speed(a: BattleUnit3, b: BattleUnit3) -> bool:
	if a.speed != b.speed:
		return a.speed > b.speed
	return a.index < b.index


func _outcome() -> StringName:
	if _alive(_enemies).is_empty():
		return &"victory"
	if _alive(_party).is_empty():
		return &"defeat"
	return &""


func _alive(list: Array[BattleUnit3]) -> Array[BattleUnit3]:
	var out: Array[BattleUnit3] = []
	for u in list:
		if u.alive():
			out.append(u)
	return out


# ---------------------------------------------------------------- tahy

func _tick(u: BattleUnit3) -> bool:
	var skip := false
	for st in u.statuses.keys():
		match st:
			&"bleed":
				await _dot(u, maxi(2, u.max_hp() / 16), Color(0.85, 0.1, 0.1))
			&"burn":
				await _dot(u, maxi(2, u.max_hp() / 10), Color(1.0, 0.55, 0.1))
			&"poison":
				await _dot(u, maxi(2, u.max_hp() / 12), Color(0.5, 0.9, 0.3))
			&"stun":
				skip = true
		u.statuses[st] = int(u.statuses[st]) - 1
		if int(u.statuses[st]) <= 0:
			u.statuses.erase(st)
		if not u.alive():
			return true
	if skip:
		_popup(u, "Omráčen", Color(1, 1, 0.5), 26)
		await _wait(0.7)
	return skip


func _dot(u: BattleUnit3, amount: int, color: Color) -> void:
	var floor_hp := 1 if u.is_party else 0
	u.set_hp(maxi(floor_hp, u.hp() - amount))
	_popup(u, str(amount), color, 26)
	_hit_fx(u)
	if not u.alive():
		_kill(u)
	await _wait(0.5)


func _status_text(u: BattleUnit3) -> String:
	var parts := PackedStringArray()
	for st in u.statuses:
		parts.append(String(BattleUnit3.STATUS_SHORT.get(st, st)))
	return ", ".join(parts)


func _party_turn(u: BattleUnit3) -> void:
	_turn_no += 1
	u.turns += 1
	if u.turns > 1:
		u.bp = mini(MAX_BP, u.bp + 1)
	var gain := int(u.passive("mp_turn"))
	if gain > 0:
		u.source.mana = minf(float(u.source.max_mana()), u.source.mana + float(gain))
	u.defending = false
	u.visual.modulate = _rest_color(u)
	_boost = 0
	_active = u
	_p_pass.text = "%s (%s): %s" % [u.display_name, ClassDefs.class_name_of(u.source), u.passive_text()]
	var act: Dictionary = await _choose_action(u)
	_active = null
	if u.statuses.has(&"fear") and act["kind"] != &"flee" and randf() < 0.3:
		_popup(u, "Ztuhl strachem!", Color(0.8, 0.6, 1.0), 26)
		await _wait(0.8)
		_boost = 0
		return
	await _execute(u, act)
	_boost = 0


## Spojenec z NPC: léčí hrdinu, jinak hází kameny.



func _enemy_turn(u: BattleUnit3) -> void:
	if u.morale <= 0 and u.rank == &"normal":
		await _flee_enemy(u)
		return
	if u.broken:  # zlomený nepřítel ztratí tah; elita/boss přejde do další fáze
		u.broken = false
		if u.phases_left > 1:
			u.phases_left -= 1
			_popup(u, "Další fáze!", Color(1.0, 0.4, 0.3), 30, -30.0)
		u.shield = u.max_shield
		u.visual.modulate = _rest_color(u)
		_popup(u, "Probral se", Color.WHITE, 24)
		await _wait(0.8)
		return
	var targets := _alive(_party)
	if targets.is_empty():
		return
	var target: BattleUnit3 = targets[randi() % targets.size()]
	var power := 1.15 if _angry else 1.0
	u.turns += 1
	if u.charge:
		u.charge = false
		await _say("%s: Drtivý úder!" % u.display_name, 0.8)
		await _attack(u, target, 0, 2.2 * power, _enemy_fx(u, 1.0))
		return
	if u.rank != &"normal" and u.turns % 3 == 0:
		if u.rank == &"boss" and u.phases_left < u.phases:
			await _say("%s: Děsivý řev!" % u.display_name, 0.9)
			for p in _alive(_party):
				if p.add_status(&"fear", 3):
					_popup(p, "Strach", Color(0.8, 0.6, 1.0), 26)
			await _wait(0.4)
		else:
			u.charge = true
			await _say("%s sbírá sílu... (Obrana zmírní ránu)" % u.display_name, 1.1)
		return
	var heavy := randf() < 0.2
	if heavy:
		await _say("%s: Zuřivý úder!" % u.display_name, 0.8)
	await _attack(u, target, 0, (1.5 if heavy else 1.0) * power, _enemy_fx(u, 0.35))


## Nepřátelé občas přidají stav: elita krvácení, kostlivec jed.
func _enemy_fx(u: BattleUnit3, chance: float) -> Dictionary:
	if randf() > chance:
		return {}
	if u.rank == &"elite":
		return {"bleed": 3}
	if u.source is TurnEnemy3 and not u.human and u.rank == &"normal":
		return {"poison": 3}
	return {}


func _flee_enemy(u: BattleUnit3) -> void:
	await _say("%s se zalekl a utíká!" % u.display_name, 0.8)
	u.fled = true
	u.visual.play(&"run", AnimCatalog.Dir.LEFT, true)
	var tw := create_tween()
	tw.tween_property(u.holder, "position:x", -240.0, 0.7)
	await tw.finished
	u.holder.visible = false


## Výběr příkazu hrdiny; vrací {"kind", "target", "spell"}.
func _choose_action(u: BattleUnit3) -> Dictionary:
	if autoplay:
		return _auto_action(u)
	while true:
		var items: Array[Dictionary] = [
			{"id": &"attack", "label": "Útok"},
			{"id": &"skill", "label": "Schopnost"},
			{"id": &"spell", "label": "Kouzla", "disabled": u.source.spells.is_empty()},
			{"id": &"item", "label": "Předměty"},
			{"id": &"talk", "label": "Mluvit", "disabled": not _can_talk()},
			{"id": &"defend", "label": "Obrana"},
			{"id": &"boost", "label": _boost_label()},
			{"id": &"flee", "label": "Útěk"},
		]
		var id: Variant = await _menu(items, false, u.display_name)
		match id:
			&"boost":
				_cycle_boost(u)
			&"attack":
				var target := await _pick_enemy(_reach_list(u))
				if target != null:
					return {"kind": &"attack", "target": target}
			&"skill":
				var act := await _skill_choice(u)
				if not act.is_empty():
					return act
			&"spell":
				var act := await _spell_choice(u)
				if not act.is_empty():
					return act
			&"item":
				var act := await _item_choice(u)
				if not act.is_empty():
					return act
			&"talk":
				var act := await _talk_choice()
				if not act.is_empty():
					return act
			&"defend":
				return {"kind": &"defend"}
			&"flee":
				return {"kind": &"flee"}
	return {}


## Koho zbraň dosáhne: zblízka jen přední řadu (dokud stojí), luk a kouzla celé pole.
func _reach_list(u: BattleUnit3, kind: StringName = &"") -> Array[BattleUnit3]:
	var foes := _alive(_enemies)
	var w := u.weapon()
	if kind == &"spell" or (w != null and w.ranged):
		return foes
	var front: Array[BattleUnit3] = []
	for f in foes:
		if f.row == 0:
			front.append(f)
	return front if not front.is_empty() else foes


func _skills_for(u: BattleUnit3) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var w := u.weapon()
	var wt := BattleUnit3.weapon_type(w)
	if w != null and w.id == &"dagger":
		out.append({"id": &"backstab", "label": "Vpich do zad", "mp": 4})
	elif wt == &"blade":
		out.append({"id": &"rip", "label": "Rozpárat", "mp": 5})
	elif wt == &"bow":
		out.append({"id": &"pierce", "label": "Probodnout štít", "mp": 5})
	elif w != null:
		out.append({"id": &"smash", "label": "Rozbít zbroj", "mp": 5})
		if w.id == &"staff":
			out.append({"id": &"stun", "label": "Omráčit", "mp": 6})
	var cs := ClassDefs.skill_of(u.source)
	if not cs.is_empty():
		out.append(cs)
	out.append({"id": &"observe", "label": "Pozorovat", "mp": 0})
	return out


func _skill_choice(u: BattleUnit3) -> Dictionary:
	var skills := _skills_for(u)
	var items: Array[Dictionary] = []
	for i in skills.size():
		var sk: Dictionary = skills[i]
		items.append({"id": i, "label": "%s   %d MP" % [sk["label"], sk["mp"]], "disabled": int(u.source.mana) < int(sk["mp"])})
	var id: Variant = await _menu(items, true, "Schopnost")
	if typeof(id) != TYPE_INT:
		return {}
	var sk: Dictionary = skills[int(id)]
	var target: BattleUnit3 = null
	if not (sk["id"] in [&"volley", &"focus", &"scribe"]):
		var list := _alive(_enemies) if sk["id"] == &"observe" else _reach_list(u)
		target = await _pick_enemy(list)
		if target == null:
			return {}
	return {"kind": &"skill", "skill": sk, "target": target}


func _item_choice(_u: BattleUnit3) -> Dictionary:
	var cons := _ensure_items()
	var items: Array[Dictionary] = []
	for id in ITEM_DEFS:
		var n := int(cons.get(id, 0))
		if n > 0:
			items.append({"id": id, "label": "%s ×%d" % [ITEM_DEFS[id]["name"], n]})
	if items.is_empty():
		_popup(_party[0], "Nemáš předměty", Color(0.8, 0.8, 0.8), 20)
		return {}
	var id: Variant = await _menu(items, true, "Předměty")
	if id == null:
		return {}
	var target: BattleUnit3 = null
	if id == &"bomb":
		target = await _pick_enemy(_alive(_enemies))
		if target == null:
			return {}
	elif id in [&"potion", &"ether", &"antidote"]:
		target = await _pick_enemy(_alive(_party))
		if target == null:
			return {}
	return {"kind": &"item", "item": id, "target": target}


func _can_talk() -> bool:
	var foes := _alive(_enemies)
	if foes.is_empty():
		return false
	for f in foes:
		if not f.human or f.rank == &"boss":
			return false
	return true


func _bribe_cost() -> int:
	var cost := 0
	for f in _alive(_enemies):
		cost += BRIBE_COST * (3 if f.rank == &"elite" else 1)
	return cost


func _talk_choice() -> Dictionary:
	var cost := _bribe_cost()
	var items: Array[Dictionary] = [
		{"id": &"intimidate", "label": "Zastrašit"},
		{"id": &"bribe", "label": "Uplatit   %d zl" % cost, "disabled": _hero.gold < cost},
	]
	var id: Variant = await _menu(items, true, "Mluvit")
	if id == null:
		return {}
	return {"kind": &"talk", "mode": id}


func _spell_choice(u: BattleUnit3) -> Dictionary:
	var items: Array[Dictionary] = []
	for i in u.source.spells.size():
		var sp: SpellData = u.source.spells[i]
		items.append({
			"id": i,
			"label": "%s   %d MP" % [sp.display_name, sp.mana_cost],
			"disabled": int(u.source.mana) < sp.mana_cost,
		})
	var id: Variant = await _menu(items, true, "Kouzla")
	if typeof(id) != TYPE_INT:
		return {}
	var spell: SpellData = u.source.spells[int(id)]
	if spell.effect == SpellData.Effect.HEAL:
		var ht := await _pick_enemy(_alive(_party))
		if ht == null:
			return {}
		return {"kind": &"spell", "spell": spell, "target": ht}
	var target := await _pick_enemy()
	if target == null:
		return {}
	return {"kind": &"spell", "spell": spell, "target": target}


func _auto_action(u: BattleUnit3) -> Dictionary:
	if not script_actions.is_empty():
		return script_actions.pop_front()
	var foes := _alive(_enemies)
	var reach := _reach_list(u)
	match _turn_no:
		1:
			if not u.source.spells.is_empty():
				var sp: SpellData = u.source.spells[0]
				if sp.effect == SpellData.Effect.PROJECTILE and int(u.source.mana) >= sp.mana_cost:
					return {"kind": &"spell", "spell": sp, "target": foes[0]}
		2:
			return {"kind": &"skill", "skill": _skills_for(u)[-1], "target": foes[0]}
		3:
			var sk := _skills_for(u)[0]
			if sk["id"] != &"observe" and int(u.source.mana) >= int(sk["mp"]):
				return {"kind": &"skill", "skill": sk, "target": reach[0]}
		4:
			if int(_ensure_items().get(&"bomb", 0)) > 0:
				return {"kind": &"item", "item": &"bomb", "target": foes[0]}
	if u.bp >= 2:
		_boost = 1
	return {"kind": &"attack", "target": reach[0]}


func _execute(u: BattleUnit3, act: Dictionary) -> void:
	var boost := mini(_boost, u.bp)
	match act["kind"]:
		&"attack":
			u.bp -= boost
			_boost = 0
			await _attack(u, act["target"], boost)
		&"skill":
			u.bp -= boost
			_boost = 0
			await _use_skill(u, act["skill"], act["target"], boost)
		&"spell":
			u.bp -= boost
			_boost = 0
			await _cast(u, act["spell"], act["target"], boost)
		&"item":
			await _use_item(u, act["item"], act["target"])
		&"talk":
			await _talk(u, act["mode"])
		&"defend":
			u.defending = true
			u.visual.modulate = _rest_color(u)
			_popup(u, "Obrana", Color(0.7, 0.85, 1.0), 24)
			await _wait(0.7)
		&"flee":
			await _say("%s se pokouší utéct..." % u.display_name, 0.7)
			if randf() < FLEE_CHANCE:
				_state = &"fled"
			else:
				await _say("Nepodařilo se utéct!", 0.8)


func _use_skill(u: BattleUnit3, sk: Dictionary, t: BattleUnit3, boost: int) -> void:
	u.source.mana = maxf(0.0, u.source.mana - float(sk["mp"]))
	u.source._emit_mana()
	await _say(sk["label"], 0.6)
	match sk["id"]:
		&"observe":  # odhalí a zamkne jednu slabinu (funguje i v noci)
			var pick: StringName = &""
			for w in t.weaknesses:
				if not (w in t.locked):
					pick = w
					break
			if pick == &"":
				_popup(t, "Nic nového", Color.WHITE, 22)
			else:
				t.locked.append(pick)
				if not (pick in t.revealed):
					t.revealed.append(pick)
				_popup(t, "Slabina: %s" % BattleUnit3.TYPE_NAMES.get(pick, "?"), GOLD, 26)
			await _wait(0.9)
		&"rip":
			await _attack(u, t, boost, 1.5, {"bleed": 3})
		&"backstab":
			await _attack(u, t, boost, 1.2, {"backstab": true})
		&"pierce":
			await _attack(u, t, boost, 1.0, {"shield": 2})
		&"smash":
			await _attack(u, t, boost, 1.0, {"armorbreak": true})
		&"stun":
			await _attack(u, t, boost, 0.8, {"stun": true})
		&"shieldbash":
			await _attack(u, t, boost, 0.9, {"stun": true})
		&"volley":
			for f in _alive(_enemies):
				await _attack(u, f, 0, 0.6)
		&"focus":
			u.bp = mini(MAX_BP, u.bp + 2)
			_popup(u, "+2 BP", GOLD, 28)
			await _wait(0.8)
		&"steal":
			if t.human:
				var g := 6 + 2 * u.source.level
				_hero.add_gold(g)
				_popup(u, "+%d zl" % g, GOLD, 28)
			else:
				_popup(u, "Nic k ukradení", Color(0.8, 0.8, 0.8), 22)
			await _wait(0.8)
		&"scribe":
			for f in _alive(_enemies):
				for w in f.weaknesses:
					if not (w in f.locked):
						f.locked.append(w)
					if not (w in f.revealed):
						f.revealed.append(w)
			_popup(u, "Zapsáno do bestiáře", GOLD, 24)
			await _wait(0.9)


func _use_item(u: BattleUnit3, id: StringName, t: BattleUnit3) -> void:
	var cons := _ensure_items()
	if int(cons.get(id, 0)) <= 0:
		return
	cons[id] = int(cons[id]) - 1
	_items_used += 1
	await _say(ITEM_DEFS[id]["name"], 0.6)
	match id:
		&"potion":
			_heal(t, 20, Color(0.4, 1.0, 0.5))
			await _wait(0.5)
		&"ether":
			t.source.mana = minf(float(t.source.max_mana()), t.source.mana + 12.0)
			t.source._emit_mana()
			_popup(t, "+12 MP", Color(0.5, 0.7, 1.0), 28)
			await _wait(0.6)
		&"antidote":
			for st in [&"bleed", &"burn", &"poison", &"fear", &"stun"]:
				t.statuses.erase(st)
			_popup(t, "Vyléčen", Color(0.6, 1.0, 0.8), 26)
			await _wait(0.6)
		&"bomb":
			_launch(u.center(), t.center(), Color(1.0, 0.5, 0.1), false, _strike.bind(u, t, 1.0, &"fire", 14.0, 1, {"burn": 3}))
			await _wait(0.9)
		&"smoke":
			_state = &"fled"


func _talk(u: BattleUnit3, mode: StringName) -> void:
	var foes := _alive(_enemies)
	match mode:
		&"bribe":
			var cost := _bribe_cost()
			if not _hero.spend_gold(cost):
				return
			await _say("%s hází měšec: „Tohle ať stačí.“" % u.display_name, 1.0)
			await _say("Nepřátelé vzali peníze a odešli.", 1.0)
			_state = &"negotiated"
		&"intimidate":
			var frac := 0.0
			for f in foes:
				frac += float(f.hp()) / float(maxi(1, f.max_hp()))
			frac /= float(foes.size())
			var chance := 0.25 + 0.04 * float(_hero.level) + 0.35 * (1.0 - frac)
			for f in foes:
				if f.rank == &"elite":
					chance -= 0.15
			chance = clampf(chance, 0.1, 0.9)
			await _say("%s: „Odejděte, dokud můžete!“" % u.display_name, 0.9)
			if randf() < chance:
				for f in foes:
					f.morale -= 100 if f.rank == &"normal" else 60
				_popup(u, "Zalekli se!", GOLD, 28)
			else:
				_angry = true
				_popup(u, "Neúčinné!", Color(1.0, 0.5, 0.5), 28)
				await _say("Nepřátelé se rozzuřili!", 0.9)
			await _wait(0.4)


func _cycle_boost(u: BattleUnit3) -> void:
	var limit := mini(MAX_BOOST, u.bp)
	if limit == 0:
		_popup(u, "Žádné BP", Color(0.8, 0.8, 0.8), 20)
		return
	_boost = (_boost + 1) % (limit + 1)
	for b in _menu_buttons:
		if b.get_meta(&"id", null) == &"boost":
			b.text = _boost_label()


func _boost_label() -> String:
	return ("Boost  +%d" % _boost) if _boost > 0 else "Boost"


# ---------------------------------------------------------------- útoky a kouzla

## Zblízka: doběhne k cíli, udeří (1 + boost zásahů) a vrátí se. Střelná zbraň střílí z místa.
func _attack(a: BattleUnit3, t: BattleUnit3, boost := 0, mult := 1.0, fx := {}) -> void:
	var weapon := a.weapon()
	var wtype := BattleUnit3.weapon_type(weapon)
	var shoots := (weapon != null and weapon.ranged) or a.ranged
	var anim: StringName = weapon.attack_anim if weapon else &"thrust"
	if a.ranged and not (weapon != null and weapon.ranged):
		anim = &"shoot"
	var hits := 1 + boost
	fx = fx.duplicate()
	if wtype == &"blunt" and not shoots and a.is_party:
		fx["aoe"] = true   # palcát zasáhne i souseda
	if boost > 0:
		_popup(a, "Boost %d" % boost, GOLD, 26)
	a.holder.z_index = 1000
	if shoots:
		for i in hits:
			if not t.alive():
				break
			await _anim(a, anim, a.dir, _fire_at.bind(a, t, wtype, mult, fx))
			await _wait(0.3)
	else:
		await _move(a, _stop_point(a, t), &"run", a.dir)
		for i in hits:
			if not t.alive():
				break
			await _anim(a, anim, a.dir, _strike.bind(a, t, mult, wtype, -1.0, 1, fx))
		await _move(a, a.home, &"run", a.back_dir())
	a.holder.z_index = int(a.home.y)
	_idle(a)


func _cast(u: BattleUnit3, spell: SpellData, t: BattleUnit3, boost: int) -> void:
	u.source.mana = maxf(0.0, u.source.mana - float(spell.mana_cost))
	u.source._emit_mana()
	await _say(spell.display_name, 0.6)
	var power := float(spell.power + u.source.level) * (1.0 + 0.6 * float(boost))
	if boost > 0:
		_popup(u, "Boost %d" % boost, GOLD, 26)
	match spell.effect:
		SpellData.Effect.HEAL:
			await _anim(u, spell.cast_anim, u.dir, _heal.bind(t, roundi(power), spell.color))
			await _wait(0.5)
		_:
			var wtype: StringName = BattleUnit3.SPELL_TYPES.get(spell.id, &"magic")
			var fx := {"burn": 3} if wtype == &"fire" else {}
			await _anim(u, spell.cast_anim, u.dir, _fire_spell.bind(u, t, spell.color, power, wtype, 1 + boost, fx))
			await _wait(0.45)
	_idle(u)


func _fire_at(a: BattleUnit3, t: BattleUnit3, wtype: StringName, mult: float, fx := {}) -> void:
	_launch(a.center(), t.center(), Color(0.85, 0.7, 0.45), true, _strike.bind(a, t, mult, wtype, -1.0, 1, fx))


func _fire_spell(u: BattleUnit3, t: BattleUnit3, color: Color, power: float, wtype: StringName, shield_hits: int, fx := {}) -> void:
	_launch(u.center(), t.center(), color, false, _strike.bind(u, t, 1.0, wtype, power, shield_hits, fx))


## Jeden zásah. base_override >= 0 = kouzlo (ignoruje obranu); jinak fyzický útok.
func _strike(a: BattleUnit3, t: BattleUnit3, mult: float, wtype: StringName, base_override: float, shield_hits: int, fx := {}) -> void:
	_hit(a, t, mult, wtype, base_override, shield_hits, fx)
	if fx.get("aoe", false):
		for n in _neighbors(t):
			_hit(a, n, mult * 0.6, wtype, base_override, 1, {})


func _neighbors(t: BattleUnit3) -> Array[BattleUnit3]:
	var same: Array[BattleUnit3] = []
	for u in _enemies:
		if u.alive() and u.row == t.row and u != t:
			same.append(u)
	same.sort_custom(func(x: BattleUnit3, y: BattleUnit3) -> bool: return absf(x.home.y - t.home.y) < absf(y.home.y - t.home.y))
	same.resize(mini(1, same.size()))
	return same


func _hit(a: BattleUnit3, t: BattleUnit3, mult: float, wtype: StringName, base_override: float, shield_hits: int, fx: Dictionary) -> void:
	if not t.alive():
		return
	if _omen_fog and randf() < 0.25:
		_popup(t, "Mine", Color(0.8, 0.8, 0.9), 24)
		return
	var base := base_override
	if base < 0.0:
		base = float(a.attack()) * 1.6 - float(t.defense()) * 0.8
	var value := base * mult * randf_range(0.9, 1.1)
	if wtype == &"fire":
		if _rain:
			value *= 0.6   # v dešti oheň slábne
		elif not _night:
			value *= 1.2
	var weak := wtype in t.weaknesses
	if weak:
		value *= WEAK_BONUS
		if wtype in t.locked:
			value *= 1.15
		if a.is_party:   # řetězení stejné slabiny
			_chain = _chain + 1 if _chain_type == wtype else 1
			_chain_type = wtype
			if _chain >= 2:
				value *= 1.0 + 0.2 * float(mini(_chain - 1, 3))
				_popup(a, "Řetěz ×%d" % _chain, Color(1.0, 0.7, 0.2), 22, -30.0)
	elif a.is_party:
		_chain = 0
	if fx.get("backstab", false) and (t.broken or t.statuses.has(&"stun")):
		value *= 2.0
	var crit := a.is_party and randf() < 0.08 + a.passive("crit")
	if crit:
		value *= 1.5
	if t.broken:
		value *= BREAK_BONUS
	if t.defending:
		value *= 0.5
	if t.row == 1 and not t.is_party:
		value *= 1.3   # zadní řada je křehká
	if t.is_party:
		value *= 1.0 + t.passive("dmg_taken")
	if not a.is_party and _night:
		value *= 1.15
	if a.statuses.has(&"fear"):
		value *= 0.85
	var dmg := maxi(1, roundi(value))
	t.set_hp(t.hp() - dmg)
	if t.is_party:
		_dmg_taken += dmg
	var color := Color(1.0, 0.5, 0.5) if t.is_party else (GOLD if weak else Color.WHITE)
	_popup(t, str(dmg), color, 36 if (weak or crit) else 30)
	_hit_fx(t)
	if crit:
		_popup(a, "Kritický zásah!", Color(1.0, 0.9, 0.4), 22, -56.0)
		_morale_all(-8)
	if weak and not t.broken:
		var can_reveal := not _night or _has_torch()
		if can_reveal and not (wtype in t.revealed):
			t.revealed.append(wtype)
		_popup(t, "Slabost!" if can_reveal else "Slabost?", GOLD, 20, -36.0)
		t.shield = maxi(0, t.shield - shield_hits)
		if t.shield == 0 and t.max_shield > 0 and t.alive():
			_break(t)
	if fx.get("shield", 0) > 0 and t.alive() and not t.broken and t.max_shield > 0:
		t.shield = maxi(0, t.shield - int(fx["shield"]))
		_popup(t, "Štít probit", Color(0.7, 0.9, 1.0), 20, -36.0)
		if t.shield == 0:
			_break(t)
	if t.alive():
		_apply_fx(t, fx)
		if t.is_party and dmg * 10 >= t.max_hp() * 3:   # tvrdý zásah poškodí vybavení
			var piece := t.break_piece()
			if piece != "":
				_popup(t, "Rozbito: %s" % piece, Color(1.0, 0.6, 0.3), 20, -60.0)
		if not t.is_party and t.hp() * 10 < t.max_hp() * 3 and not t.low_morale_hit:
			t.low_morale_hit = true
			t.morale -= 30
	if not t.alive():
		_kill(t)


func _apply_fx(t: BattleUnit3, fx: Dictionary) -> void:
	for st in [&"bleed", &"poison"]:
		if fx.has(st) and t.add_status(st, int(fx[st])):
			_popup(t, String(BattleUnit3.STATUS_SHORT[st]), Color(0.9, 0.4, 0.4), 18, -20.0)
	if fx.has(&"burn") and not _rain and t.add_status(&"burn", int(fx[&"burn"])):
		_popup(t, "Hoří", Color(1.0, 0.6, 0.2), 18, -20.0)
	if fx.get("stun", false) and t.add_status(&"stun", 1):
		_popup(t, "Omráčen", Color(1.0, 1.0, 0.5), 20, -20.0)
	if fx.get("armorbreak", false):
		t.add_status(&"armorbreak", 3)
		var piece := t.break_piece()
		_popup(t, "Rozbito: %s" % piece if piece != "" else "Zbroj rozbita", Color(1.0, 0.6, 0.3), 20, -20.0)


func _has_torch() -> bool:
	var off := _hero.equipment.get_item(ItemData.Slot.OFFHAND)
	return off != null and off.light > 0.0


func _morale_all(delta: int) -> void:
	for u in _enemies:
		if u.alive():
			u.morale += delta


func _break(t: BattleUnit3) -> void:
	t.broken = true
	_morale_all(-20)
	if t.flash_tween:
		t.flash_tween.kill()
	t.visual.modulate = _rest_color(t)
	_popup(t, "BREAK!", Color(1.0, 0.6, 0.1), 42, -72.0)
	_screen_flash(Color(1, 1, 1, 0.55), 0.3)


func _heal(u: BattleUnit3, amount: int, color: Color) -> void:
	var before := u.hp()
	u.set_hp(before + amount)
	_popup(u, "+%d" % (u.hp() - before), Color(0.5, 1.0, 0.6), 32)
	if u.flash_tween:
		u.flash_tween.kill()
	u.visual.modulate = color.lightened(0.5)
	u.flash_tween = create_tween()
	u.flash_tween.tween_property(u.visual, "modulate", _rest_color(u), 0.5)


## Smrt: animace pádu (hurt). Nepřítel pak zmizí, hrdina zůstane ležet.
func _kill(u: BattleUnit3) -> void:
	if u.flash_tween:
		u.flash_tween.kill()
	u.visual.position = Vector2.ZERO
	u.visual.modulate = u.source.tint
	u.visual.play(&"hurt", u.dir, true)
	if u.is_party:
		return
	_morale_all(-45 if u.rank != &"normal" else -10)   # padlý vůdce / druh stráší ostatní
	await _wait(0.9)
	var tw := create_tween()
	tw.tween_property(u.visual, "modulate:a", 0.0, 0.5)
	await tw.finished
	u.holder.visible = false


func _hit_fx(t: BattleUnit3) -> void:
	if t.flash_tween:
		t.flash_tween.kill()
	t.visual.modulate = Color(1.0, 0.35, 0.35)
	t.flash_tween = create_tween()
	t.flash_tween.tween_property(t.visual, "modulate", _rest_color(t), 0.3)
	var shake := create_tween()
	shake.tween_property(t.visual, "position", Vector2(5, 0), 0.04)
	shake.tween_property(t.visual, "position", Vector2(-5, 0), 0.06)
	shake.tween_property(t.visual, "position", Vector2.ZERO, 0.05)


func _rest_color(u: BattleUnit3) -> Color:
	if u.broken:
		return Color(1.0, 0.9, 0.35)
	if u.defending:
		return Color(0.7, 0.85, 1.0)
	return u.source.tint


func _stop_point(a: BattleUnit3, t: BattleUnit3) -> Vector2:
	return t.home + Vector2(REACH if a.is_party else -REACH, 0.0)


# ---------------------------------------------------------------- znamení

func _omen() -> void:
	if _rounds < 2 or randf() > 0.3:
		return
	var pool: Array[StringName] = [&"fog", &"howl"]
	if _rain:
		pool.append(&"lightning")
	if _night:
		pool.append(&"star")
		pool.append(&"dread")
	if not _night and not _rain:
		pool.append(&"breeze")
	var hero := _party[0]
	match pool[randi() % pool.size()]:
		&"fog":
			_omen_fog = true
			_screen_flash(Color(0.9, 0.92, 0.95, 0.5), 0.8)
			await _say("Znamení: Zhoustla mlha – zásahy mohou minout", 1.4)
		&"howl":
			_morale_all(-12)
			await _say("Znamení: Z lesa se ozvalo vytí – nepřátelé znejistěli", 1.4)
		&"lightning":
			await _say("Znamení: Blesk!", 0.7)
			var all := _alive(_party) + _alive(_enemies)
			var v: BattleUnit3 = all[randi() % all.size()]
			_screen_flash(Color(1, 1, 1, 0.8), 0.4)
			v.set_hp(maxi(1 if v.is_party else 0, v.hp() - 8))
			_popup(v, "8", Color(0.9, 0.9, 1.0), 34)
			_hit_fx(v)
			if not v.alive():
				_kill(v)
			await _wait(0.5)
		&"star":
			for p in _alive(_party):
				p.bp = mini(MAX_BP, p.bp + 2)
			await _say("Znamení: Padající hvězda – +2 BP", 1.3)
		&"dread":
			var scared := false
			for p in _alive(_party):
				scared = p.add_status(&"fear", 2) or scared
			if scared:
				await _say("Zlé znamení: Družinu svírá strach", 1.3)
		&"breeze":
			for p in _alive(_party):
				p.set_hp(p.hp() + maxi(1, p.max_hp() * 15 / 100))
				_popup(p, "+", Color(0.5, 1.0, 0.6), 28)
			await _say("Znamení: Vlídný vítr zacelil rány", 1.3)


# ---------------------------------------------------------------- animace a efekty

## Přehraje animaci jednotky; ve snímku zásahu zavolá on_hit, vrátí se po doběhnutí animace.
func _anim(u: BattleUnit3, anim: StringName, dir: int, on_hit := Callable()) -> void:
	if not AnimCatalog.ANIMS.has(anim):
		anim = &"slash"
	var state := {"hit": false, "done": false}
	var hit_frame := AnimCatalog.hit_frame(anim)
	var on_frame := func(_a: StringName, f: int) -> void:
		if f == hit_frame and not state["hit"]:
			state["hit"] = true
			if on_hit.is_valid():
				on_hit.call()
	var on_done := func(_a: StringName) -> void:
		state["done"] = true
	u.visual.frame_changed.connect(on_frame)
	u.visual.finished.connect(on_done)
	u.visual.play(anim, dir, true)
	var waited := 0.0
	while not state["done"] and waited < 4.0:   # pojistka proti zaseknutí
		await get_tree().process_frame
		waited += get_process_delta_time()
	u.visual.frame_changed.disconnect(on_frame)
	u.visual.finished.disconnect(on_done)
	if not state["hit"] and on_hit.is_valid():
		on_hit.call()


func _move(u: BattleUnit3, to: Vector2, anim: StringName, dir: int) -> void:
	var dist := u.holder.position.distance_to(to)
	if dist < 2.0:
		return
	u.visual.play(anim, dir, true)
	var tw := create_tween()
	tw.tween_property(u.holder, "position", to, dist / RUN_SPEED)
	await tw.finished


func _idle(u: BattleUnit3) -> void:
	if u.alive():
		u.visual.play(&"combat", u.dir, true)


## Letící kulička (kouzlo) nebo šíp; po dopadu zavolá on_arrive.
func _launch(from: Vector2, to: Vector2, color: Color, arrow: bool, on_arrive: Callable) -> void:
	var p := Polygon2D.new()
	if arrow:
		p.polygon = PackedVector2Array([Vector2(-18, -3), Vector2(14, -3), Vector2(24, 0), Vector2(14, 3), Vector2(-18, 3)])
		p.rotation = (to - from).angle()
	else:
		p.polygon = _ellipse(14.0, 14.0)
		var glow := Polygon2D.new()
		glow.polygon = _ellipse(24.0, 24.0)
		glow.color = Color(color, 0.35)
		p.add_child(glow)
	p.color = color
	p.position = from
	p.z_index = 2000
	_stage.add_child(p)
	var tw := create_tween()
	tw.tween_property(p, "position", to, maxf(0.12, from.distance_to(to) / 900.0))
	tw.tween_callback(on_arrive)
	tw.tween_callback(p.queue_free)


func _ellipse(rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * float(i) / 20.0
		pts.append(Vector2(cos(a) * rx, sin(a) * ry))
	return pts


## Číslo / nápis, který vyletí nad jednotkou.
func _popup(u: BattleUnit3, text: String, color: Color, font_size := 30, dy := 0.0) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.position = u.center() + Vector2(-34.0 + randf_range(-14.0, 14.0), -60.0 + dy)
	_ui.add_child(l)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 46.0, 0.9)
	tw.tween_property(l, "modulate:a", 0.0, 0.45).set_delay(0.5)
	tw.chain().tween_callback(l.queue_free)


func _screen_flash(color: Color, seconds: float) -> void:
	_flash.color = color
	var tw := create_tween()
	tw.tween_property(_flash, "color:a", 0.0, seconds)


## Zpráva nahoře (název kouzla, hláška); čeká zadanou dobu.
func _say(text: String, seconds := 0.9) -> void:
	_banner_label.text = text
	_banner.visible = true
	await _wait(seconds)
	_banner.visible = false


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


# ---------------------------------------------------------------- úvod a závěr

func _intro() -> void:
	_flash.color = Color(1, 1, 1, 1)
	var all: Array[BattleUnit3] = _party + _enemies
	for u in all:
		u.holder.position = u.home + Vector2(420.0 if u.is_party else -420.0, 0.0)
		u.visual.play(&"walk", u.dir, true)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_flash, "color:a", 0.0, 0.6)
	for u in all:
		tw.tween_property(u.holder, "position", u.home, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tw.finished
	for u in all:
		_idle(u)
	var names := PackedStringArray()
	for u in _enemies:
		names.append(u.display_name)
	if names.size() == 1:
		await _say("%s se objevil!" % names[0], 1.0)
	else:
		await _say("Objevili se: %s!" % ", ".join(names), 1.2)
	for m in _party:
		if m.alive() and m.passive("reveal") > 0.0:
			for e in _enemies:
				for w in e.weaknesses:
					if not (w in e.revealed):
						e.revealed.append(w)
			await _say("%s zná slabiny nepřátel." % m.display_name, 1.1)
			break
	if _first == &"hero":
		for e in _enemies:
			e.shield = maxi(0, e.shield - 1)
		await _say("Útok ze zálohy! Nepřátelé jsou zaskočeni.", 1.2)
	elif _first == &"enemy":
		await _say("Přepadení! Nepřátelé útočí první!", 1.2)


func _revive_party() -> void:
	for u in _party:
		if u.hp() == 0:
			u.set_hp(1)
			u.visual.play(&"combat", u.dir, true)


func _outro() -> void:
	if _state != &"defeat":
		_revive_party()
	match _state:
		&"victory":
			await _victory()
		&"defeat":
			await _say("Hrdina padl...", 1.6)
		&"fled":
			await _fled()
		&"negotiated":
			_result = {}
	_flash.color = Color(0, 0, 0, 0)
	var tw := create_tween()
	tw.tween_property(_flash, "color:a", 1.0, 0.45)
	await tw.finished


func _victory() -> void:
	await _wait(1.6)
	var xp := 0
	var gold := 0
	var loot: Array[String] = []
	for u in _enemies:
		var f := 0.5 if u.fled else 1.0
		xp += roundi(float(u.source.xp_reward) * f)
		gold += roundi(float(u.source.gold_reward) * f)
		var e := u.source as Enemy
		if e and not u.fled:
			if u.source is TurnEnemy3:
				_kills.append(String((u.source as TurnEnemy3).template_id))
			for entry in e.loot:
				if entry.item and randf() < entry.chance:
					_hero.inventory.add(entry.item.id)
					loot.append(entry.item.display_name)
	var rank := _rating()
	var mult: float = RANK_MULT[rank]
	xp = roundi(float(xp) * mult)
	gold = roundi(float(gold) * mult)
	var cons := _ensure_items()
	var drops := {&"potion": 0.4, &"ether": 0.25, &"bomb": 0.2, &"antidote": 0.15}
	for id in drops:
		if randf() < float(drops[id]):
			cons[id] = int(cons.get(id, 0)) + 1
			loot.append(ITEM_DEFS[id]["name"])
	var leveled: Array[String] = []
	for m in _party:   # zkušenosti dostane celá družina (kronikář víc)
		var before := m.source.level
		m.source.gain_xp(roundi(float(xp) * (1.0 + m.passive("xp_bonus"))))
		if m.source.level > before:
			leveled.append("%s %d" % [m.display_name, m.source.level])
	_hero.add_gold(gold)
	_result = {"xp": xp, "gold": gold, "loot": loot, "leveled": leveled, "rank": rank, "kills": _kills, "seen": _seen_enemies()}
	var tw := create_tween()
	tw.set_loops(2)
	for m in _party:
		if m.alive():
			tw.parallel().tween_property(m.holder, "position:y", m.home.y - 34.0, 0.16)
	tw.chain()
	for m in _party:
		if m.alive():
			tw.parallel().tween_property(m.holder, "position:y", m.home.y, 0.16)
	var wrap := _show_rewards(xp, gold, loot, leveled, rank)
	await _wait_confirm()
	wrap.queue_free()


## Hodnocení souboje: rychlost, přijaté zranění, spotřebované předměty, zálusk.
func _rating() -> String:
	var score := 100.0
	score -= 6.0 * float(maxi(0, _rounds - 4))
	score -= 0.8 * float(_dmg_taken)
	score -= 7.0 * float(_items_used)
	if _first == &"hero":
		score += 10.0
	if score >= 88.0:
		return "S"
	if score >= 70.0:
		return "A"
	if score >= 50.0:
		return "B"
	return "C"


func _fled() -> void:
	for u in _party:
		_popup(u, "Útěk!", Color.WHITE, 30)
		u.visual.play(&"run", AnimCatalog.Dir.RIGHT, true)
	var tw := create_tween()
	tw.set_parallel(true)
	for u in _party:
		tw.tween_property(u.holder, "position:x", _size.x + 220.0, 0.8)
	await tw.finished


func _show_rewards(xp: int, gold: int, loot: Array[String], leveled: Array[String], rank: String) -> Control:
	var wrap := CenterContainer.new()
	wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.custom_minimum_size = Vector2(360, 0)
	wrap.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var title := _label("Vítězství!", 32, GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	box.add_child(_label("Hodnocení: %s  (odměny ×%.2f)" % [rank, RANK_MULT[rank]], 22, GOLD))
	box.add_child(_label("Zkušenosti: +%d" % xp, 20, Color.WHITE))
	box.add_child(_label("Zlato: +%d" % gold, 20, Color.WHITE))
	if not leveled.is_empty():
		box.add_child(_label("Nová úroveň: %s" % ", ".join(leveled), 20, Color(0.5, 1.0, 0.6)))
	if not loot.is_empty():
		var l := _label("Kořist: %s" % ", ".join(loot), 18, Color(0.85, 0.9, 1.0))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 330
		box.add_child(l)
	box.add_child(_label("Enter / klik = pokračovat", 14, Color(0.7, 0.7, 0.8)))
	_ui.add_child(wrap)
	return wrap


func _wait_confirm() -> void:
	if autoplay:
		await _wait(0.3)
		return
	_confirm_wait = true
	await _confirmed
	_confirm_wait = false


# ---------------------------------------------------------------- menu a výběr cíle

## Zobrazí příkazy a vrátí id vybrané položky (null = zrušeno, jen když cancelable).
func _menu(items: Array[Dictionary], cancelable: bool, title: String) -> Variant:
	for c in _cmd_list.get_children():
		_cmd_list.remove_child(c)
		c.queue_free()
	_menu_buttons.clear()
	_menu_title = title
	_cmd_title.text = title
	var want: Variant = _menu_memory.get(title, null)
	var focus_btn: Button
	for it in items:
		var id: Variant = it["id"]
		var b := Button.new()
		b.text = it["label"]
		b.disabled = it.get("disabled", false)
		b.set_meta(&"id", id)
		_style_button(b)
		b.pressed.connect(_finish_menu.bind(id))
		_cmd_list.add_child(b)
		_menu_buttons.append(b)
		if not b.disabled and (focus_btn == null or id == want):
			focus_btn = b
	var h := 58.0 + 31.0 * float(items.size())
	_cmd_panel.custom_minimum_size = Vector2(250, h)
	_cmd_panel.size = Vector2(250, h)
	_cmd_panel.position = Vector2(14.0, _size.y - h - 14.0)
	_cancel_ok = cancelable
	_menu_open = true
	_cmd_panel.visible = true
	if focus_btn:
		focus_btn.grab_focus()
	var result: Variant = await _menu_done
	return result


func _finish_menu(id: Variant) -> void:
	if not _menu_open:
		return
	_menu_open = false
	if id != null:
		_menu_memory[_menu_title] = id
	_cmd_panel.visible = false
	_menu_done.emit(id)


## Výběr nepřítele šipkami + Enter (nebo klikem); Esc = zpět (vrátí null).
func _pick_enemy(allowed: Array[BattleUnit3] = []) -> BattleUnit3:
	var foes := allowed if not allowed.is_empty() else _alive(_enemies)
	if foes.size() == 1:
		return foes[0]
	_pick_list = foes
	_pick_idx = 0
	_picking = true
	_set_clickable(true)
	var r: Variant = await _picked
	_picking = false
	_cursor.visible = false
	_set_clickable(false)
	return r as BattleUnit3


func _move_pick(step: int) -> void:
	_pick_idx = posmod(_pick_idx + step, _pick_list.size())


func _confirm_pick() -> void:
	if not _picking:
		return
	_picking = false
	_picked.emit(_pick_list[_pick_idx])


func _on_enemy_clicked(u: BattleUnit3) -> void:
	if _picking and u in _pick_list:
		_pick_idx = _pick_list.find(u)
		_confirm_pick()


func _set_clickable(on: bool) -> void:
	for u in _enemies:
		var click: Button = _tags[u]["click"]
		click.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE


func _input(event: InputEvent) -> void:
	if (_menu_open or _picking) and _active != null and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_B:
		_cycle_boost(_active)
		get_viewport().set_input_as_handled()
		return
	if _menu_open and _cancel_ok and event.is_action_pressed(&"ui_cancel"):
		_finish_menu(null)
		get_viewport().set_input_as_handled()
		return
	if _picking:
		if event.is_action_pressed(&"ui_left") or event.is_action_pressed(&"ui_up"):
			_move_pick(-1)
		elif event.is_action_pressed(&"ui_right") or event.is_action_pressed(&"ui_down"):
			_move_pick(1)
		elif event.is_action_pressed(&"ui_accept"):
			_confirm_pick()
		elif event.is_action_pressed(&"ui_cancel"):
			_picking = false
			_picked.emit(null)
		else:
			return
		get_viewport().set_input_as_handled()
		return
	if _confirm_wait and (event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"ui_cancel") or (event is InputEventMouseButton and event.pressed)):
		_confirm_wait = false
		_confirmed.emit()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- průběžná aktualizace UI

func _process(delta: float) -> void:
	_time += delta
	if _tags.is_empty():
		return
	for u in _enemies:
		var t: Dictionary = _tags[u]
		var label: Label = t["label"]
		var bg: ColorRect = t["bg"]
		var fill: ColorRect = t["fill"]
		var shown := u.alive()
		label.visible = shown
		bg.visible = shown
		if shown:
			label.text = _tag_text(u)
			fill.size = Vector2(78.0 * float(u.hp()) / float(maxi(1, u.max_hp())), 5.0)
	_update_party()
	if _picking and not _pick_list.is_empty():
		var target := _pick_list[_pick_idx]
		_cursor.visible = true
		_cursor.position = target.home + Vector2(0.0, -SCALE * 64.0 - 70.0 + sin(_time * 8.0) * 5.0)


func _tag_text(u: BattleUnit3) -> String:
	var weak := PackedStringArray()
	for w in u.weaknesses:
		var name: String = String(BattleUnit3.TYPE_NAMES.get(w, "?")) if w in u.revealed else "?"
		weak.append("[%s]" % name if w in u.locked else name)
	var title := u.display_name
	if u.rank == &"elite":
		title += "  [ELITA]"
	elif u.rank == &"boss":
		title += "  [BOSS]"
	var line := "ZLOMEN" if u.broken else "Štít %d" % u.shield
	var st := _status_text(u)
	return "%s\n%s   %s\n%s · Morálka %d%s" % [title, line, " ".join(weak), "přední" if u.row == 0 else "zadní", maxi(0, u.morale), (" · " + st) if st != "" else ""]


func _update_party() -> void:
	for i in _party_rows.size():
		var row: Dictionary = _party_rows[i]
		var label: Label = row["label"]
		var hp_bar: ProgressBar = row["hp"]
		var mp_bar: ProgressBar = row["mp"]
		var shown := i < _party.size()
		label.visible = shown
		hp_bar.visible = shown
		mp_bar.visible = shown
		if not shown:
			continue
		var u := _party[i]
		var bp_left := u.bp - (_boost if u == _active else 0)
		var stt := _status_text(u)
		label.text = "%s  %d/%d HP  %d MP  BP %d%s" % [u.display_name, u.hp(), u.max_hp(), int(u.source.mana), bp_left, (" · " + stt) if stt != "" else ""]
		label.add_theme_color_override("font_color", GOLD if u == _active else (Color(0.6, 0.6, 0.65) if not u.alive() else Color.WHITE))
		hp_bar.max_value = u.max_hp()
		hp_bar.value = u.hp()
		mp_bar.max_value = maxi(1, u.source.max_mana())
		mp_bar.value = u.source.mana


func _refresh_timeline(order: Array[BattleUnit3], idx: int) -> void:
	for c in _timeline.get_children():
		_timeline.remove_child(c)
		c.queue_free()
	var queue: Array = []
	for i in range(idx, order.size()):
		if order[i].alive():
			queue.append(order[i])
	queue.append_array(_round_order())  # další kolo
	for i in mini(queue.size(), 7):
		_timeline.add_child(_chip(queue[i], i == 0))


# ---------------------------------------------------------------- stavba scény

func _build_ui(bg: Texture2D) -> void:
	var base := ColorRect.new()
	base.color = Color(0.05, 0.09, 0.05)
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(base)
	var tint := Color(0, 0, 0, 0)
	if use_arena:   # 3D bojiště; obrázek pozadí slouží jako kulisa v dálce
		var arena := BattleArena3D.new()
		arena.backdrop = bg
		arena.hour = float(_env.get("hour", 12.0))
		arena.weather = String(_env.get("weather", "jasno"))
		arena.mood = String(_env.get("mood", "forest"))
		add_child(arena)
	elif bg != null:
		var pic := TextureRect.new()
		pic.texture = bg
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(pic)
	tint = _env_tint() if not use_arena else tint
	if tint.a > 0.0:
		var shade := ColorRect.new()
		shade.color = tint
		shade.set_anchors_preset(Control.PRESET_FULL_RECT)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(shade)
	_stage = Node2D.new()
	add_child(_stage)
	var kind := "rain" if _rain else ("snow" if String(_env.get("weather", "")) == "sníh" else "")
	if kind != "":
		var wl := WeatherLayer.new()
		wl.kind = kind
		wl.area = _size
		wl.z_index = 2500
		add_child(wl)
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.z_index = 3000   # UI vždy nad postavami (ty mají z_index podle y)
	add_child(_ui)
	_build_timeline()
	_build_banner()
	_build_command_panel()
	_build_party_panel()
	var hint := _label("Šipky výběr · Enter potvrdit · Esc zpět · B boost", 13, Color(0.85, 0.85, 0.9, 0.8))
	hint.position = Vector2(_size.x * 0.5 - 170.0, _size.y - 24.0)
	_ui.add_child(hint)
	_cursor = Polygon2D.new()
	_cursor.polygon = PackedVector2Array([Vector2(-14, -14), Vector2(14, -14), Vector2(0, 10)])
	_cursor.color = GOLD
	_cursor.visible = false
	_ui.add_child(_cursor)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_flash)


func _build_timeline() -> void:
	_timeline = HBoxContainer.new()
	_timeline.add_theme_constant_override("separation", 4)
	_timeline.position = Vector2(12, 10)
	_ui.add_child(_timeline)


func _build_banner() -> void:
	_banner = PanelContainer.new()
	_banner.add_theme_stylebox_override("panel", _panel_style())
	_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_banner.offset_left = 140.0
	_banner.offset_right = -140.0
	_banner.offset_top = 52.0
	_banner.visible = false
	_banner_label = _label("", 24, Color.WHITE)
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_child(_banner_label)
	_ui.add_child(_banner)


func _build_command_panel() -> void:
	_cmd_panel = PanelContainer.new()
	_cmd_panel.add_theme_stylebox_override("panel", _panel_style())
	_cmd_panel.position = Vector2(14.0, _size.y - 222.0)
	_cmd_panel.custom_minimum_size = Vector2(250, 206)
	_cmd_panel.visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_cmd_panel.add_child(box)
	_cmd_title = _label("", 18, GOLD)
	box.add_child(_cmd_title)
	_cmd_list = VBoxContainer.new()
	_cmd_list.add_theme_constant_override("separation", 0)
	box.add_child(_cmd_list)
	_ui.add_child(_cmd_panel)


func _build_party_panel() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.position = Vector2(_size.x - 344.0, _size.y - 214.0)
	panel.custom_minimum_size = Vector2(330, 198)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	panel.add_child(box)
	for i in 3:
		var label := _label("", 16, Color.WHITE)
		box.add_child(label)
		var hp_bar := _bar(box, Color(0.85, 0.2, 0.2))
		hp_bar.custom_minimum_size = Vector2(0, 6)
		var mp_bar := _bar(box, Color(0.25, 0.45, 1.0))
		mp_bar.custom_minimum_size = Vector2(0, 4)
		_party_rows.append({"label": label, "hp": hp_bar, "mp": mp_bar})
	_p_pass = _label("", 13, Color(0.8, 0.9, 1.0))
	_p_pass.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_p_pass.custom_minimum_size.x = 306
	box.add_child(_p_pass)
	_ui.add_child(panel)


func _build_units(enemies: Array[Character], allies: Array = []) -> void:
	var spots := [Vector2(0.80, 0.58), Vector2(0.91, 0.43), Vector2(0.70, 0.69)]
	var members: Array[Character] = [_hero]
	for a in allies:
		if members.size() < 3:
			members.append(a)
	for i in members.size():
		var pu := BattleUnit3.from_character(members[i], true)
		pu.bp = 1 + int(pu.passive("bp_start"))
		pu.home = Vector2(_size.x * spots[i].x, _size.y * spots[i].y)
		_add_unit(pu, _party)
	_p_pass.text = "%s: %s" % [_hero.display_name, _party[0].passive_text()]
	var units: Array[BattleUnit3] = []
	for c in enemies:
		units.append(BattleUnit3.from_character(c, false))
	for r in 2:   # přední řada blíž k hrdinovi, zadní dál
		var rowu: Array[BattleUnit3] = []
		for u in units:
			if u.row == r:
				rowu.append(u)
		for j in rowu.size():
			var yy := 0.58 + (0.02 if r == 0 else 0.0) + 0.10 * (float(j) - float(rowu.size() - 1) / 2.0)
			rowu[j].home = Vector2(_size.x * (0.36 if r == 0 else 0.20), _size.y * yy)
	for u in units:
		_add_unit(u, _enemies)
	var counts := {}
	for u in _enemies:
		counts[u.display_name] = int(counts.get(u.display_name, 0)) + 1
	var seen := {}
	for u in _enemies:
		if int(counts[u.display_name]) > 1:
			var k := int(seen.get(u.display_name, 0))
			seen[u.display_name] = k + 1
			u.display_name += " " + char(65 + k)
	for u in _enemies:
		_make_tag(u)


func _enemy_home(i: int, n: int) -> Vector2:
	if n == 1:
		return Vector2(_size.x * 0.27, _size.y * 0.62)
	return Vector2(_size.x * (0.36 - 0.10 * float(i)), _size.y * (0.54 + 0.07 * float(i)))


func _add_unit(u: BattleUnit3, list: Array[BattleUnit3]) -> void:
	u.index = _next_index
	_next_index += 1
	list.append(u)
	u.holder = Node2D.new()
	u.holder.position = u.home
	u.holder.scale = Vector2.ONE * SCALE
	u.holder.z_index = int(u.home.y)
	_stage.add_child(u.holder)
	var shadow := Polygon2D.new()   # stín pod nohama (kreslí se před postavou)
	shadow.polygon = _ellipse(20.0, 6.0)
	shadow.color = Color(0, 0, 0, 0.35)
	u.holder.add_child(shadow)
	var vis := CharacterVisual.new()
	vis.body_sheet = u.source.visual.body_sheet
	vis.hair_sheet = u.source.visual.hair_sheet
	vis.modulate = u.source.tint
	u.holder.add_child(vis)   # _ready (vytvoření vrstev) proběhne až teď, bind je tedy až po něm
	vis.bind(u.source.equipment)
	vis.play(&"combat", u.dir, true)
	u.visual = vis


## Jméno, štít, slabiny a ukazatel zdraví u nepřítele + neviditelné tlačítko pro výběr myší.
func _make_tag(u: BattleUnit3) -> void:
	var label := _label("", 15, Color.WHITE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(160, 0)
	label.add_theme_font_size_override("font_size", 13)
	label.position = u.home + Vector2(-80.0, -SCALE * 64.0 - 70.0)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	_ui.add_child(label)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.7)
	bg.position = u.home + Vector2(-40.0, 10.0)
	bg.size = Vector2(80, 7)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(bg)
	var fill := ColorRect.new()
	fill.color = Color(0.85, 0.2, 0.2)
	fill.position = Vector2(1, 1)
	fill.size = Vector2(78, 5)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(fill)
	var click := Button.new()
	click.flat = true
	click.focus_mode = Control.FOCUS_NONE
	click.position = u.home + Vector2(-60.0, -190.0)
	click.size = Vector2(120, 200)
	click.mouse_filter = Control.MOUSE_FILTER_IGNORE   # zapíná se jen při výběru cíle
	for style in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		click.add_theme_stylebox_override(style, StyleBoxEmpty.new())
	click.pressed.connect(_on_enemy_clicked.bind(u))
	_ui.add_child(click)
	_tags[u] = {"label": label, "bg": bg, "fill": fill, "click": click}


# ---------------------------------------------------------------- prostředí

func _env_tint() -> Color:
	var hour := float(_env.get("hour", 12.0))
	var weather := String(_env.get("weather", "jasno"))
	if _night:
		return Color(0.04, 0.07, 0.28, 0.55)
	if weather == "mlha":
		return Color(0.85, 0.88, 0.9, 0.38)
	if _rain:
		return Color(0.1, 0.12, 0.18, 0.28)
	if weather == "zataženo":
		return Color(0.3, 0.32, 0.35, 0.2)
	if hour >= 17.5:
		return Color(0.95, 0.5, 0.2, 0.2)
	return Color(0, 0, 0, 0)


func _ensure_items() -> Dictionary:
	return consumables_of(_hero)


static func consumables_of(hero: Character) -> Dictionary:
	if not hero.has_meta(&"consumables"):
		hero.set_meta(&"consumables", {&"potion": 3, &"ether": 2, &"bomb": 2, &"antidote": 1, &"smoke": 1})
	return hero.get_meta(&"consumables")


# ---------------------------------------------------------------- drobné UI pomůcky

func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = PANEL_EDGE
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(12)
	return sb


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _bar(parent: Control, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 10)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("fill", fill)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0, 0, 0, 0.55)
	bar.add_theme_stylebox_override("background", back)
	parent.add_child(bar)
	return bar


func _chip(u: BattleUnit3, first: bool) -> Control:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.15, 0.3, 0.8, 0.92) if u.is_party else Color(0.65, 0.15, 0.15, 0.92)
	sb.border_color = GOLD if first else Color(1, 1, 1, 0.4)
	sb.set_border_width_all(3 if first else 1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(4)
	panel.add_theme_stylebox_override("panel", sb)
	panel.add_child(_label(u.display_name, 15 if first else 12, Color.WHITE))
	return panel


func _style_button(b: Button) -> void:
	var none := StyleBoxEmpty.new()
	none.set_content_margin_all(3)
	var sel := StyleBoxFlat.new()
	sel.bg_color = Color(0.25, 0.35, 0.85, 0.85)
	sel.set_corner_radius_all(3)
	sel.set_content_margin_all(3)
	b.add_theme_stylebox_override("normal", none)
	b.add_theme_stylebox_override("hover", sel)
	b.add_theme_stylebox_override("pressed", sel)
	b.add_theme_stylebox_override("focus", sel)
	b.add_theme_stylebox_override("disabled", none)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", GOLD)
	b.add_theme_color_override("font_focus_color", GOLD)
	b.add_theme_color_override("font_pressed_color", GOLD)
	b.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.62))
	b.add_theme_font_size_override("font_size", 18)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT


func _seen_enemies() -> Array:
	var out := []
	for u in _enemies:
		if u.source is TurnEnemy3:
			out.append({"id": String((u.source as TurnEnemy3).template_id), "revealed": u.revealed.map(func(w: StringName) -> String: return String(w))})
	return out
