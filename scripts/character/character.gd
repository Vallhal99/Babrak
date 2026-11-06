class_name Character
extends CharacterBody2D
## Základ každé postavy (hrdina, nepřítel, NPC): staty, vybavení, pohyb, útok, zranění.
## Potomci přepisují jen _think() (vstup hráče / AI). Vzhled řeší CharacterVisual.

signal hp_changed(hp: int, max_hp: int)
signal died
signal mana_changed(mana: int, max_mana: int)
signal xp_changed(xp: int, needed: int)
signal level_up(level: int)
signal skills_changed
signal gold_changed(gold: int)

const DIR_VECTORS: Array[Vector2] = [Vector2.UP, Vector2.LEFT, Vector2.DOWN, Vector2.RIGHT]
const POINTS_PER_LEVEL := 5
## Atributy: klíč -> [název, popis efektu na bod]. Efekty viz max_hp/max_mana/attack_power/speed_mult.
const ATTRIBUTES := {
	&"strength": ["Síla", "+1 útok"],
	&"vitality": ["Vitalita", "+4 zdraví"],
	&"spirit": ["Duch", "+3 many"],
	&"agility": ["Obratnost", "+3 % rychlosti"],
}
const BODY_CENTER := Vector2(0, -22)  # střed těla vůči patám (pro zásahy)

@export var display_name := "Hrdina"
@export var team: StringName = &"hero"
@export var level := 1
@export var tint := Color.WHITE
@export var invulnerable := false  # NPC: nedá se zranit ani zacílit
@export var base_max_hp := 30
@export var base_attack := 2
@export var base_defense := 0
@export var base_max_mana := 20
@export var mana_regen := 2.0  # za sekundu
@export var gold := 0
@export var gold_reward := 0  # kolik zlata dostane ten, kdo ho zabije
@export var xp_reward := 0  # kolik XP dostane ten, kdo ho zabije
@export var walk_speed := 90.0
@export var run_speed := 150.0
@export var combat_stance_time := 2.0
@export var attack_reach := 22.0  # střed zásahu před postavou
@export var attack_radius := 28.0
## Vybavení nasazené při startu (test / nepřátelé).
@export var start_items: Array[ItemData] = []
## Naučená kouzla; první je výchozí aktivní.
@export var spells: Array[SpellData] = []

var inventory := Inventory.new()
var equipment := Equipment.new()
var hp := 0
var dead := false
var mana := 0.0
var skill_points := 0
var attributes := {&"strength": 0, &"vitality": 0, &"spirit": 0, &"agility": 0}
var xp := 0
var active_spell: SpellData
var facing: int = AnimCatalog.Dir.DOWN

# Výstup _think():
var move_input := Vector2.ZERO
var run_input := false
var attack_input := false
var cast_input := false

var _attacking := false
var _stance_timer := 0.0
var _knockback := Vector2.ZERO
var _pending_spell: SpellData
var _last_attacker: Character
var _mana_shown := 0

@onready var visual: CharacterVisual = $Visual
@onready var _light: PointLight2D = get_node_or_null("Light")


func _ready() -> void:
	add_to_group(&"characters")
	visual.modulate = tint
	visual.bind(equipment)
	visual.finished.connect(_on_anim_finished)
	visual.frame_changed.connect(_on_frame_changed)
	equipment.slot_changed.connect(_on_equipment_changed)
	for item in start_items:
		inventory.add(item.id)
		equipment.equip(item, inventory)
	hp = max_hp()
	mana = float(max_mana())
	active_spell = spells[0] if spells else null
	_setup_light()
	_on_equipment_changed(0)


# --- staty (základ + vybavení) ---
func max_hp() -> int:
	return base_max_hp + 4 * attributes[&"vitality"] + equipment.sum_of(&"max_hp")


func max_mana() -> int:
	return base_max_mana + 3 * attributes[&"spirit"] + equipment.sum_of(&"max_mana")


func xp_needed() -> int:
	return 20 * level


## Zkušenosti: každá úroveň dá POINTS_PER_LEVEL bodů k rozdání (spend_point) a doplní zdraví i manu.
func gain_xp(amount: int) -> void:
	xp += amount
	while xp >= xp_needed():
		xp -= xp_needed()
		level += 1
		skill_points += POINTS_PER_LEVEL
		hp = max_hp()
		mana = float(max_mana())
		hp_changed.emit(hp, max_hp())
		level_up.emit(level)
	xp_changed.emit(xp, xp_needed())
	skills_changed.emit()
	queue_redraw()


func add_gold(amount: int) -> void:
	gold += amount
	gold_changed.emit(gold)


func spend_gold(amount: int) -> bool:
	if gold < amount:
		return false
	gold -= amount
	gold_changed.emit(gold)
	return true


func speed_mult() -> float:
	return 1.0 + 0.03 * attributes[&"agility"]


## Utratí jeden dovednostní bod za atribut. Zdraví/mana se zvednou o stejnou hodnotu jako maximum.
func spend_point(attribute: StringName) -> bool:
	if skill_points <= 0 or not attributes.has(attribute):
		return false
	skill_points -= 1
	attributes[attribute] += 1
	if attribute == &"vitality":
		hp += 4
		hp_changed.emit(hp, max_hp())
	elif attribute == &"spirit":
		mana += 3.0
		_emit_mana()
	skills_changed.emit()
	queue_redraw()
	return true


func attack_power() -> int:
	return base_attack + attributes[&"strength"] + equipment.sum_of(&"damage")


func defense() -> int:
	return base_defense + equipment.sum_of(&"defense")


# --- smyčka ---
func _think(_delta: float) -> void:
	pass  # virtuální: nastaví move_input / run_input / attack_input


func _physics_process(delta: float) -> void:
	_stance_timer = maxf(0.0, _stance_timer - delta)
	move_input = Vector2.ZERO
	run_input = false
	attack_input = false
	cast_input = false
	if not dead:
		_regen_mana(delta)
		_think(delta)
		if attack_input and not _attacking:
			_start_attack()
		elif cast_input and not _attacking:
			cast(active_spell)
	var input := Vector2.ZERO if (_attacking or dead) else move_input
	velocity = input * (run_speed if run_input else walk_speed) * speed_mult() + _knockback
	_knockback = _knockback.move_toward(Vector2.ZERO, 700.0 * delta)
	move_and_slide()
	if not (_attacking or dead):
		_animate(input)


func _process(delta: float) -> void:
	if _light and _light.enabled:  # plápolání
		_light.energy = lerpf(_light.energy, randf_range(0.85, 1.25), 10.0 * delta)


func _animate(input: Vector2) -> void:
	if input != Vector2.ZERO:
		facing = dir_from(input)
		var move := loco(&"run" if run_input else &"walk")
		visual.play(move, AnimCatalog.dir8(input) if AnimCatalog.DIAG.has(move) else facing)
		return
	var idle := loco(&"idle")
	if idle == &"idle" and _stance_timer > 0.0:
		idle = &"combat"
	visual.play(idle, facing)


## Animace pohybu podle držené věci (pochodeň: idle -> torch_idle ...).
func loco(kind: StringName) -> StringName:
	var off := equipment.get_item(ItemData.Slot.OFFHAND)
	if off and off.stance != &"":
		var name := StringName("%s_%s" % [off.stance, kind])
		if AnimCatalog.ANIMS.has(name):
			return name
	return kind


# --- boj ---
func _start_attack() -> void:
	var weapon := equipment.get_item(ItemData.Slot.WEAPON)
	_attacking = true
	_stance_timer = combat_stance_time
	visual.play(weapon.attack_anim if weapon else &"thrust", facing, true)


func _on_frame_changed(anim: StringName, frame: int) -> void:
	if not _attacking or frame != AnimCatalog.hit_frame(anim):
		return
	if _pending_spell:
		_release_spell()
	else:
		_strike()


# --- kouzla ---
func cast(spell: SpellData) -> bool:
	if spell == null or dead or _attacking or mana < spell.mana_cost:
		return false
	mana -= spell.mana_cost
	_pending_spell = spell
	_attacking = true
	_stance_timer = combat_stance_time
	visual.play(spell.cast_anim, facing, true)
	_emit_mana()
	return true


func _release_spell() -> void:
	var spell := _pending_spell
	_pending_spell = null
	match spell.effect:
		SpellData.Effect.HEAL:
			heal(spell.power + level)
		SpellData.Effect.PROJECTILE:
			_fire(spell.power + level, spell.color)


## Vystřelí projektil ve směru pohledu (kouzlo nebo šíp).
func _fire(damage: int, color: Color) -> void:
	var shot := Projectile.new()
	shot.direction = DIR_VECTORS[facing]
	shot.damage = damage
	shot.team = team
	shot.caster = self
	shot.color = color
	get_parent().add_child(shot)
	shot.global_position = global_position + BODY_CENTER + shot.direction * 18.0


func heal(amount: int) -> void:
	hp = mini(max_hp(), hp + amount)
	hp_changed.emit(hp, max_hp())
	queue_redraw()
	visual.modulate = Color(0.5, 1.0, 0.6)
	create_tween().tween_property(visual, "modulate", tint, 0.4)


func _regen_mana(delta: float) -> void:
	if mana < max_mana():
		mana = minf(float(max_mana()), mana + mana_regen * delta)
		_emit_mana()


func _emit_mana() -> void:
	if int(mana) != _mana_shown:
		_mana_shown = int(mana)
		mana_changed.emit(_mana_shown, max_mana())


func _strike() -> void:
	var weapon := equipment.get_item(ItemData.Slot.WEAPON)
	if weapon and weapon.ranged:
		_fire(attack_power(), Color(0.85, 0.7, 0.45))
		return
	var center := global_position + DIR_VECTORS[facing] * attack_reach + BODY_CENTER
	for node in get_tree().get_nodes_in_group(&"characters"):
		var other := node as Character
		if other == self or other.dead or other.invulnerable or other.team == team:
			continue
		if center.distance_to(other.global_position + BODY_CENTER) <= attack_radius:
			other.take_damage(maxi(1, attack_power() - other.defense()), self)


func take_damage(amount: int, source: Node2D = null) -> void:
	if dead or invulnerable:
		return
	hp = maxi(0, hp - amount)
	_last_attacker = source as Character
	hp_changed.emit(hp, max_hp())
	queue_redraw()
	if source:
		_knockback = (global_position - source.global_position).normalized() * 160.0
	visual.modulate = Color(1.0, 0.35, 0.35)
	create_tween().tween_property(visual, "modulate", tint, 0.25)
	if hp == 0:
		_die()


func _die() -> void:
	dead = true
	_attacking = false
	$Collision.set_deferred("disabled", true)
	_pending_spell = null
	visual.play(&"hurt", facing, true)
	if _last_attacker and xp_reward > 0:
		_last_attacker.gain_xp(xp_reward)
		_last_attacker.add_gold(gold_reward)
	died.emit()


func _on_anim_finished(_anim: StringName) -> void:
	_attacking = false


func _draw() -> void:
	if hp < max_hp() and not dead:  # malý ukazatel zdraví nad hlavou
		draw_rect(Rect2(-14, -62, 28, 3), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(-14, -62, 28.0 * hp / max_hp(), 3), Color(0.85, 0.15, 0.15))


# --- světlo (pochodeň) ---
func _setup_light() -> void:
	if _light == null:
		return
	var gradient := Gradient.new()
	gradient.set_color(0, Color.WHITE)
	gradient.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	_light.texture = tex


func _on_equipment_changed(_slot: int) -> void:
	hp = mini(hp, max_hp())
	mana = minf(mana, float(max_mana()))
	queue_redraw()
	if _light == null:
		return
	var off := equipment.get_item(ItemData.Slot.OFFHAND)
	_light.enabled = off != null and off.light > 0.0
	if _light.enabled:
		_light.texture_scale = off.light / 64.0


static func dir_from(v: Vector2) -> int:
	if absf(v.x) > absf(v.y):
		return AnimCatalog.Dir.RIGHT if v.x > 0.0 else AnimCatalog.Dir.LEFT
	return AnimCatalog.Dir.DOWN if v.y > 0.0 else AnimCatalog.Dir.UP
