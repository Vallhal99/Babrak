extends Node
## Registruje vstupní akce v kódu. Nové klávesy se přidávají jen sem.

const ACTIONS := {
	&"move_left": [KEY_A, KEY_LEFT],
	&"move_right": [KEY_D, KEY_RIGHT],
	&"move_up": [KEY_W, KEY_UP],
	&"move_down": [KEY_S, KEY_DOWN],
	&"run": [KEY_SHIFT],
	&"attack": [KEY_SPACE, KEY_J],
	&"inventory": [KEY_I, KEY_TAB],
	&"cast": [KEY_Q],
	&"interact": [KEY_E],
	&"pause": [KEY_ESCAPE],
	&"toggle_night": [KEY_N],
}


func _init() -> void:
	for action in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in ACTIONS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)
