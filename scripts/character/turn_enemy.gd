class_name TurnEnemy
extends Enemy
## Nepřítel na mapě pro tahový režim ("Nová hra tah").
## Pronásleduje hrdinu jako obyčejný Enemy, ale při dotyku neútočí v reálném čase:
## vyšle `contact` a hra přepne do tahového souboje (BattleScene).

signal contact(enemy: TurnEnemy)

## Štít (Octopath): kolik zásahů do slabiny nepřítele zlomí (Break).
@export var shield_points := 3
## Slabiny = typy útoku (viz BattleUnit.TYPE_NAMES). Hráč je odhalí, až když do nich trefí.
@export var weaknesses: Array[StringName] = [&"blunt", &"fire"]
## Rychlost v souboji (kdo je na tahu dřív).
@export var battle_speed := 8

## Po útěku hrdiny chvíli nespouští souboj (sekundy).
var grace := 0.0
var _triggered := false


func _think(delta: float) -> void:
	grace = maxf(0.0, grace - delta)
	if _triggered:
		return
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
		var player := _target as Hero
		# souboj nezačne, dokud hráč nemá ovládání (inventář, obchod) nebo běží ochranná doba po útěku
		if grace <= 0.0 and (player == null or player.controls_enabled):
			_triggered = true
			contact.emit(self)


## Povolí nepříteli spustit souboj znovu (po zrušeném nebo uteklém souboji).
func release() -> void:
	_triggered = false
