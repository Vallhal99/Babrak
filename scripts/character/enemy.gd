class_name Enemy
extends Character
## Jednoduchý nepřítel: hlídá, pronásleduje nejbližšího nepřítele svého týmu a útočí.

@export var sight := 200.0
@export var attack_range := 30.0
@export var attack_cooldown := 1.2
## Co po smrti může spadnout (každá položka se hází zvlášť).
@export var loot: Array[LootEntry] = []

var _target: Character
var _cooldown := 0.0


func _ready() -> void:
	super()
	died.connect(_on_died)


func _think(delta: float) -> void:
	_cooldown -= delta
	if _target == null or _target.dead:
		_target = _find_target()
	if _target == null:
		return
	var to := _target.global_position - global_position
	if to.length() > sight * 1.5:
		_target = null
	elif to.length() > attack_range:
		move_input = to.normalized()
	else:
		facing = dir_from(to)
		if _cooldown <= 0.0:
			attack_input = true
			_cooldown = attack_cooldown


func _find_target() -> Character:
	var best: Character
	var best_dist := sight
	for node in get_tree().get_nodes_in_group(&"characters"):
		var other := node as Character
		if other.dead or other.invulnerable or other.team == team:
			continue
		var d := global_position.distance_to(other.global_position)
		if d < best_dist:
			best = other
			best_dist = d
	return best


func _on_died() -> void:
	for entry in loot:
		if randf() < entry.chance:
			var pickup := Pickup.new()
			pickup.item = entry.item
			pickup.position = position + Vector2(0, -4)
			get_parent().add_child(pickup)
	var tween := create_tween()
	tween.tween_interval(2.5)
	tween.tween_property(self, "modulate:a", 0.0, 0.6)
	tween.tween_callback(queue_free)
