class_name SaveSlots
extends CenterContainer
## Výběr slotu pro uložení / načtení hry (pauza i hlavní menu).

const GAME := "res://scenes/main_turn3.tscn"
signal closed

var _save := true
var _host: Node
var _box: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_box = VBoxContainer.new()
	_box.custom_minimum_size.x = 440
	_box.add_theme_constant_override("separation", 8)
	add_child(_box)


## save = true: ukládá (host = herní scéna s metodou save_game); false: načítá.
func open(save: bool, host: Node = null) -> void:
	_save = save
	_host = host
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	var title := Label.new()
	title.text = "Uložit hru" if save else "Načíst hru"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	_box.add_child(title)
	for slot in range(1, SaveGame.SLOTS + 1):
		var b := Button.new()
		b.custom_minimum_size.y = 46
		b.text = "Slot %d: %s" % [slot, SaveGame.summary(slot)]
		b.disabled = not save and not SaveGame.exists(slot)
		b.pressed.connect(_pick.bind(slot))
		_box.add_child(b)
	var back := Button.new()
	back.text = "Zpět"
	back.pressed.connect(close)
	_box.add_child(back)
	visible = true
	(_box.get_child(1) as Button).grab_focus()


func close() -> void:
	visible = false
	closed.emit()


func _pick(slot: int) -> void:
	if _save:
		var ok: bool = _host.save_game(slot)
		open(true, _host)   # obnoví popisky slotů
		(_box.get_child(0) as Label).text = "Uloženo do slotu %d" % slot if ok else "Uložení se nepodařilo"
	else:
		Session.pending_load = slot
		get_tree().paused = false
		if _host != null:
			get_tree().reload_current_scene()
		else:
			get_tree().change_scene_to_file(GAME)
