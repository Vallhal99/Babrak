class_name Companion
extends Npc
## Společník: stojí na mapě a čeká na rozhovor (E). Po přijetí do družiny (dialog akce "recruit")
## chodí za hrdinou a bojuje v tahovém souboji. Neměnný (invulnerable), takže ho nepřátelé na mapě neberou jako cíl.
## Definice společníků: COMPANIONS (třída, jméno, barva, dialog).

const COMPANIONS := {
	&"mira": {"name": "Mira", "class": &"mage", "tint": Color(0.85, 1.0, 0.9), "dialogue": "mira"},
	&"borek": {"name": "Bořek", "class": &"warrior", "tint": Color(1.0, 0.9, 0.7), "dialogue": "borek"},
}

var companion_id: StringName = &""
var dialogue_id := ""
var joined := false
var leader: Character


func setup_companion(id: StringName) -> void:
	var d: Dictionary = COMPANIONS[id]
	companion_id = id
	display_name = d["name"]
	tint = d["tint"]
	dialogue_id = d["dialogue"]
	set_meta(&"companion_id", id)


func _ready() -> void:
	super()
	ClassDefs.apply(self, COMPANIONS[companion_id]["class"])
	set_meta(&"companion_id", companion_id)


func _think(_delta: float) -> void:
	if joined and leader != null:
		var to := leader.global_position - global_position
		if to.length() > 70.0:
			move_input = to.normalized()
			run_input = to.length() > 220.0


func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-40, -68), display_name, HORIZONTAL_ALIGNMENT_CENTER, 80, 12, Color(0.6, 1.0, 0.7) if joined else Color(1, 0.9, 0.5))
	if _hero_near and not joined:
		draw_string(font, Vector2(-50, -80), "[E] Mluvit", HORIZONTAL_ALIGNMENT_CENTER, 100, 11, Color.WHITE)
