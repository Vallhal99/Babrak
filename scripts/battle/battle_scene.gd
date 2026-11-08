class_name BattleScene
extends CanvasLayer
## Tahový souboj ve stylu Final Fantasy / Octopath Traveler.
##
## Hrdina stojí vpravo, nepřátelé vlevo před pozadím (les). Tahy jdou podle rychlosti,
## pořadí je vidět nahoře. Příkazy: Útok, Kouzla, Obrana, Boost, Útěk.
## Octopath prvky: Boost Points (BP) zvyšují počet zásahů / sílu kouzla, nepřátelé mají
## štít a slabiny (zásah do slabiny ubírá štít, na nule se nepřítel zlomí = ztratí tah a
## dostává víc zranění).
##
## Zdraví, mana, staty i vybavení se berou z postav ze světa (viz BattleUnit), animace
## z existujících sheetů (AnimCatalog). Co postava nemá (např. animaci), se prostě přeskočí.
##
## Použití: add_child(BattleScene.new()) -> start(hero, nepřátelé, pozadí) -> await finished.
## Výsledek: {"outcome": &"victory" | &"defeat" | &"fled", "xp", "gold", "loot", "leveled"}.

signal finished(result: Dictionary)
signal _menu_done(id: Variant)
signal _picked(unit: Variant)
signal _confirmed

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

## Pro testy a ladění: hrdina hraje sám (1. tah kouzlo, pak útok, při 2+ BP s Boostem).
var autoplay := false

var _hero: Hero
var _size := Vector2(960, 720)
var _party: Array[BattleUnit] = []
var _enemies: Array[BattleUnit] = []
var _state: StringName = &""        # prázdné = souboj běží; jinak victory / defeat / fled
var _result := {}
var _boost := 0
var _turn_no := 0
var _active: BattleUnit
var _time := 0.0
var _next_index := 0

var _menu_open := false
var _cancel_ok := false
var _menu_title := ""
var _menu_memory := {}
var _menu_buttons: Array[Button] = []
var _picking := false
var _pick_list: Array[BattleUnit] = []
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
var _tags: Dictionary = {}          # BattleUnit -> {label, bg, fill, click}


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


func start(hero: Hero, enemies: Array[Character], bg: Texture2D) -> void:
	_hero = hero
	_size = get_viewport().get_visible_rect().size
	_build_ui(bg)
	_build_units(enemies)
	_run()


# ---------------------------------------------------------------- hlavní smyčka

func _run() -> void:
	await _intro()
	while _state == &"":
		var order := _round_order()
		for i in order.size():
			var u: BattleUnit = order[i]
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


func _take_turn(u: BattleUnit) -> void:
	if u.is_party:
		await _party_turn(u)
	else:
		await _enemy_turn(u)


## Pořadí tahů v kole: rychlejší první, při shodě podle pořadí vzniku.
func _round_order() -> Array[BattleUnit]:
	var all: Array[BattleUnit] = []
	for u in _party + _enemies:
		if u.alive():
			all.append(u)
	all.sort_custom(_by_speed)
	return all


static func _by_speed(a: BattleUnit, b: BattleUnit) -> bool:
	if a.speed != b.speed:
		return a.speed > b.speed
	return a.index < b.index


func _outcome() -> StringName:
	if _alive(_enemies).is_empty():
		return &"victory"
	if _alive(_party).is_empty():
		return &"defeat"
	return &""


func _alive(list: Array[BattleUnit]) -> Array[BattleUnit]:
	var out: Array[BattleUnit] = []
	for u in list:
		if u.alive():
			out.append(u)
	return out


# ---------------------------------------------------------------- tahy

func _party_turn(u: BattleUnit) -> void:
	_turn_no += 1
	if _turn_no > 1:
		u.bp = mini(MAX_BP, u.bp + 1)     # +1 BP na začátku každého dalšího tahu
	u.defending = false
	u.visual.modulate = _rest_color(u)
	_boost = 0
	_active = u
	var act: Dictionary = await _choose_action(u)
	_active = null
	await _execute(u, act)
	_boost = 0


func _enemy_turn(u: BattleUnit) -> void:
	if u.broken:  # zlomený nepřítel ztratí tah, pak se probere a obnoví štít
		u.broken = false
		u.shield = u.max_shield
		u.visual.modulate = _rest_color(u)
		_popup(u, "Probral se", Color.WHITE, 24)
		await _wait(0.8)
		return
	var targets := _alive(_party)
	if targets.is_empty():
		return
	var target: BattleUnit = targets[randi() % targets.size()]
	var heavy := randf() < 0.2
	if heavy:
		await _say("%s: Zuřivý úder!" % u.display_name, 0.8)
	await _attack(u, target, 0, 1.5 if heavy else 1.0)


## Výběr příkazu hrdiny; vrací {"kind", "target", "spell"}.
func _choose_action(u: BattleUnit) -> Dictionary:
	if autoplay:
		return _auto_action(u)
	while true:
		var items: Array[Dictionary] = [
			{"id": &"attack", "label": "Útok"},
			{"id": &"spell", "label": "Kouzla", "disabled": u.source.spells.is_empty()},
			{"id": &"defend", "label": "Obrana"},
			{"id": &"boost", "label": _boost_label()},
			{"id": &"flee", "label": "Útěk"},
		]
		var id: Variant = await _menu(items, false, u.display_name)
		match id:
			&"boost":
				_cycle_boost(u)
			&"attack":
				var target := await _pick_enemy()
				if target != null:
					return {"kind": &"attack", "target": target}
			&"spell":
				var act := await _spell_choice(u)
				if not act.is_empty():
					return act
			&"defend":
				return {"kind": &"defend"}
			&"flee":
				return {"kind": &"flee"}
	return {}


func _spell_choice(u: BattleUnit) -> Dictionary:
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
		return {"kind": &"spell", "spell": spell, "target": u}
	var target := await _pick_enemy()
	if target == null:
		return {}
	return {"kind": &"spell", "spell": spell, "target": target}


func _auto_action(u: BattleUnit) -> Dictionary:
	var foes := _alive(_enemies)
	if _turn_no == 1 and not u.source.spells.is_empty():
		var sp: SpellData = u.source.spells[0]
		if sp.effect == SpellData.Effect.PROJECTILE and int(u.source.mana) >= sp.mana_cost:
			return {"kind": &"spell", "spell": sp, "target": foes[0]}
	if u.bp >= 2:
		_boost = 1
	return {"kind": &"attack", "target": foes[0]}


func _execute(u: BattleUnit, act: Dictionary) -> void:
	var boost := mini(_boost, u.bp)
	match act["kind"]:
		&"attack":
			u.bp -= boost
			_boost = 0
			await _attack(u, act["target"], boost)
		&"spell":
			u.bp -= boost
			_boost = 0
			await _cast(u, act["spell"], act["target"], boost)
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


func _cycle_boost(u: BattleUnit) -> void:
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
func _attack(a: BattleUnit, t: BattleUnit, boost := 0, mult := 1.0) -> void:
	var weapon := a.weapon()
	var wtype := BattleUnit.weapon_type(weapon)
	var anim: StringName = weapon.attack_anim if weapon else &"thrust"
	var hits := 1 + boost
	if boost > 0:
		_popup(a, "Boost %d" % boost, GOLD, 26)
	a.holder.z_index = 1000
	if weapon and weapon.ranged:
		for i in hits:
			if not t.alive():
				break
			await _anim(a, anim, a.dir, _fire_at.bind(a, t, wtype, mult))
			await _wait(0.3)
	else:
		await _move(a, _stop_point(a, t), &"run", a.dir)
		for i in hits:
			if not t.alive():
				break
			await _anim(a, anim, a.dir, _strike.bind(a, t, mult, wtype, -1.0, 1))
		await _move(a, a.home, &"run", a.back_dir())
	a.holder.z_index = int(a.home.y)
	_idle(a)


func _cast(u: BattleUnit, spell: SpellData, t: BattleUnit, boost: int) -> void:
	u.source.mana = maxf(0.0, u.source.mana - float(spell.mana_cost))
	u.source._emit_mana()
	await _say(spell.display_name, 0.6)
	var power := float(spell.power + u.source.level) * (1.0 + 0.6 * float(boost))
	if boost > 0:
		_popup(u, "Boost %d" % boost, GOLD, 26)
	match spell.effect:
		SpellData.Effect.HEAL:
			await _anim(u, spell.cast_anim, u.dir, _heal.bind(u, roundi(power), spell.color))
			await _wait(0.5)
		_:
			var wtype: StringName = BattleUnit.SPELL_TYPES.get(spell.id, &"magic")
			await _anim(u, spell.cast_anim, u.dir, _fire_spell.bind(u, t, spell.color, power, wtype, 1 + boost))
			await _wait(0.45)
	_idle(u)


func _fire_at(a: BattleUnit, t: BattleUnit, wtype: StringName, mult: float) -> void:
	_launch(a.center(), t.center(), Color(0.85, 0.7, 0.45), true, _strike.bind(a, t, mult, wtype, -1.0, 1))


func _fire_spell(u: BattleUnit, t: BattleUnit, color: Color, power: float, wtype: StringName, shield_hits: int) -> void:
	_launch(u.center(), t.center(), color, false, _strike.bind(u, t, 1.0, wtype, power, shield_hits))


## Jeden zásah. base_override >= 0 = kouzlo (ignoruje obranu); jinak fyzický útok.
func _strike(a: BattleUnit, t: BattleUnit, mult: float, wtype: StringName, base_override: float, shield_hits: int) -> void:
	if not t.alive():
		return
	var base := base_override
	if base < 0.0:
		base = float(a.attack()) * 1.6 - float(t.defense()) * 0.8
	var value := base * mult * randf_range(0.9, 1.1)
	var weak := wtype in t.weaknesses
	if weak:
		value *= WEAK_BONUS
	if t.broken:
		value *= BREAK_BONUS
	if t.defending:
		value *= 0.5
	var dmg := maxi(1, roundi(value))
	t.set_hp(t.hp() - dmg)
	var color := Color(1.0, 0.5, 0.5) if t.is_party else (GOLD if weak else Color.WHITE)
	_popup(t, str(dmg), color, 36 if weak else 30)
	_hit_fx(t)
	if weak and not t.broken:
		if not (wtype in t.revealed):
			t.revealed.append(wtype)
		_popup(t, "Slabost!", GOLD, 20, -36.0)
		t.shield = maxi(0, t.shield - shield_hits)
		if t.shield == 0 and t.max_shield > 0 and t.alive():
			_break(t)
	if not t.alive():
		_kill(t)


func _break(t: BattleUnit) -> void:
	t.broken = true
	if t.flash_tween:
		t.flash_tween.kill()
	t.visual.modulate = _rest_color(t)
	_popup(t, "BREAK!", Color(1.0, 0.6, 0.1), 42, -72.0)
	_screen_flash(Color(1, 1, 1, 0.55), 0.3)


func _heal(u: BattleUnit, amount: int, color: Color) -> void:
	var before := u.hp()
	u.set_hp(before + amount)
	_popup(u, "+%d" % (u.hp() - before), Color(0.5, 1.0, 0.6), 32)
	if u.flash_tween:
		u.flash_tween.kill()
	u.visual.modulate = color.lightened(0.5)
	u.flash_tween = create_tween()
	u.flash_tween.tween_property(u.visual, "modulate", _rest_color(u), 0.5)


## Smrt: animace pádu (hurt). Nepřítel pak zmizí, hrdina zůstane ležet.
func _kill(u: BattleUnit) -> void:
	if u.flash_tween:
		u.flash_tween.kill()
	u.visual.position = Vector2.ZERO
	u.visual.modulate = u.source.tint
	u.visual.play(&"hurt", u.dir, true)
	if u.is_party:
		return
	await _wait(0.9)
	var tw := create_tween()
	tw.tween_property(u.visual, "modulate:a", 0.0, 0.5)
	await tw.finished
	u.holder.visible = false


func _hit_fx(t: BattleUnit) -> void:
	if t.flash_tween:
		t.flash_tween.kill()
	t.visual.modulate = Color(1.0, 0.35, 0.35)
	t.flash_tween = create_tween()
	t.flash_tween.tween_property(t.visual, "modulate", _rest_color(t), 0.3)
	var shake := create_tween()
	shake.tween_property(t.visual, "position", Vector2(5, 0), 0.04)
	shake.tween_property(t.visual, "position", Vector2(-5, 0), 0.06)
	shake.tween_property(t.visual, "position", Vector2.ZERO, 0.05)


func _rest_color(u: BattleUnit) -> Color:
	if u.broken:
		return Color(1.0, 0.9, 0.35)
	if u.defending:
		return Color(0.7, 0.85, 1.0)
	return u.source.tint


func _stop_point(a: BattleUnit, t: BattleUnit) -> Vector2:
	return t.home + Vector2(REACH if a.is_party else -REACH, 0.0)


# ---------------------------------------------------------------- animace a efekty

## Přehraje animaci jednotky; ve snímku zásahu zavolá on_hit, vrátí se po doběhnutí animace.
func _anim(u: BattleUnit, anim: StringName, dir: int, on_hit := Callable()) -> void:
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


func _move(u: BattleUnit, to: Vector2, anim: StringName, dir: int) -> void:
	var dist := u.holder.position.distance_to(to)
	if dist < 2.0:
		return
	u.visual.play(anim, dir, true)
	var tw := create_tween()
	tw.tween_property(u.holder, "position", to, dist / RUN_SPEED)
	await tw.finished


func _idle(u: BattleUnit) -> void:
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
func _popup(u: BattleUnit, text: String, color: Color, font_size := 30, dy := 0.0) -> void:
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
	var all: Array[BattleUnit] = _party + _enemies
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


func _outro() -> void:
	match _state:
		&"victory":
			await _victory()
		&"defeat":
			await _say("Hrdina padl...", 1.6)
		&"fled":
			await _fled()
	_flash.color = Color(0, 0, 0, 0)
	var tw := create_tween()
	tw.tween_property(_flash, "color:a", 1.0, 0.45)
	await tw.finished


func _victory() -> void:
	await _wait(1.6)  # doběhne animace pádu posledního nepřítele
	var hero := _party[0]
	var xp := 0
	var gold := 0
	var loot: Array[String] = []
	for u in _enemies:
		xp += u.source.xp_reward
		gold += u.source.gold_reward
		var e := u.source as Enemy
		if e:
			for entry in e.loot:
				if entry.item and randf() < entry.chance:
					_hero.inventory.add(entry.item.id)
					loot.append(entry.item.display_name)
	var level_before := _hero.level
	_hero.gain_xp(xp)
	_hero.add_gold(gold)
	var leveled := _hero.level > level_before
	_result = {"xp": xp, "gold": gold, "loot": loot, "leveled": leveled}
	var tw := create_tween()
	tw.set_loops(2)
	tw.tween_property(hero.holder, "position:y", hero.home.y - 34.0, 0.16)
	tw.tween_property(hero.holder, "position:y", hero.home.y, 0.16)
	var wrap := _show_rewards(xp, gold, loot, leveled)
	await _wait_confirm()
	wrap.queue_free()


func _fled() -> void:
	var hero := _party[0]
	_popup(hero, "Útěk!", Color.WHITE, 30)
	hero.visual.play(&"run", AnimCatalog.Dir.RIGHT, true)
	var tw := create_tween()
	tw.tween_property(hero.holder, "position:x", _size.x + 220.0, 0.8)
	await tw.finished


func _show_rewards(xp: int, gold: int, loot: Array[String], leveled: bool) -> Control:
	var wrap := CenterContainer.new()
	wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.custom_minimum_size = Vector2(340, 0)
	wrap.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var title := _label("Vítězství!", 32, GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	box.add_child(_label("Zkušenosti: +%d" % xp, 20, Color.WHITE))
	box.add_child(_label("Zlato: +%d" % gold, 20, Color.WHITE))
	if leveled:
		box.add_child(_label("Nová úroveň: %d  (+%d bodů)" % [_hero.level, Character.POINTS_PER_LEVEL], 20, Color(0.5, 1.0, 0.6)))
	if not loot.is_empty():
		box.add_child(_label("Kořist: %s" % ", ".join(loot), 18, Color(0.85, 0.9, 1.0)))
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
func _pick_enemy() -> BattleUnit:
	var foes := _alive(_enemies)
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
	return r as BattleUnit


func _move_pick(step: int) -> void:
	_pick_idx = posmod(_pick_idx + step, _pick_list.size())


func _confirm_pick() -> void:
	if not _picking:
		return
	_picking = false
	_picked.emit(_pick_list[_pick_idx])


func _on_enemy_clicked(u: BattleUnit) -> void:
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


func _tag_text(u: BattleUnit) -> String:
	var weak := PackedStringArray()
	for w in u.weaknesses:
		weak.append(String(BattleUnit.TYPE_NAMES.get(w, "?")) if w in u.revealed else "?")
	var line := "ZLOMEN" if u.broken else "Štít %d" % u.shield
	return "%s\n%s   %s" % [u.display_name, line, " ".join(weak)]


func _update_party() -> void:
	if _party.is_empty():
		return
	var u := _party[0]
	_p_name.text = "%s   Úr. %d" % [u.display_name, u.source.level]
	_p_hp.text = "HP  %d / %d" % [u.hp(), u.max_hp()]
	_p_hp_bar.max_value = u.max_hp()
	_p_hp_bar.value = u.hp()
	_p_mp.text = "MP  %d / %d" % [int(u.source.mana), u.source.max_mana()]
	_p_mp_bar.max_value = u.source.max_mana()
	_p_mp_bar.value = u.source.mana
	for i in MAX_BP:
		if i < u.bp - _boost:
			_pips[i].color = GOLD
		elif i < u.bp:
			_pips[i].color = Color(1.0, 0.4, 0.15)   # BP, které se právě chystáš utratit
		else:
			_pips[i].color = Color(0.25, 0.25, 0.38)


func _refresh_timeline(order: Array[BattleUnit], idx: int) -> void:
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
	if bg != null:
		var pic := TextureRect.new()
		pic.texture = bg
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(pic)
	_stage = Node2D.new()
	add_child(_stage)
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
	panel.position = Vector2(_size.x - 344.0, _size.y - 160.0)
	panel.custom_minimum_size = Vector2(330, 144)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)
	_p_name = _label("", 20, GOLD)
	box.add_child(_p_name)
	_p_hp = _label("", 18, Color.WHITE)
	box.add_child(_p_hp)
	_p_hp_bar = _bar(box, Color(0.85, 0.2, 0.2))
	_p_mp = _label("", 18, Color.WHITE)
	box.add_child(_p_mp)
	_p_mp_bar = _bar(box, Color(0.25, 0.45, 1.0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(_label("BP", 18, Color.WHITE))
	for i in MAX_BP:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(14, 14)
		pip.pivot_offset = Vector2(7, 7)
		pip.rotation = PI / 4.0   # kosočtverec
		row.add_child(pip)
		_pips.append(pip)
	box.add_child(row)
	_ui.add_child(panel)


func _build_units(enemies: Array[Character]) -> void:
	var hero_unit := BattleUnit.from_character(_hero, true)
	hero_unit.bp = 1
	hero_unit.home = Vector2(_size.x * 0.78, _size.y * 0.64)
	_add_unit(hero_unit, _party)
	var n := enemies.size()
	for i in n:
		var u := BattleUnit.from_character(enemies[i], false)
		u.home = _enemy_home(i, n)
		_add_unit(u, _enemies)
	var counts := {}
	for u in _enemies:
		counts[u.display_name] = int(counts.get(u.display_name, 0)) + 1
	var seen := {}
	for u in _enemies:   # stejná jména dostanou písmeno: Zbojník A, Zbojník B
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


func _add_unit(u: BattleUnit, list: Array[BattleUnit]) -> void:
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
func _make_tag(u: BattleUnit) -> void:
	var label := _label("", 15, Color.WHITE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(220, 0)
	label.position = u.home + Vector2(-110.0, -SCALE * 64.0 - 52.0)
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


func _chip(u: BattleUnit, first: bool) -> Control:
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
	none.set_content_margin_all(5)
	var sel := StyleBoxFlat.new()
	sel.bg_color = Color(0.25, 0.35, 0.85, 0.85)
	sel.set_corner_radius_all(3)
	sel.set_content_margin_all(5)
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
	b.add_theme_font_size_override("font_size", 20)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
