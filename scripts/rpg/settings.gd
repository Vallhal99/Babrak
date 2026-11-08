class_name Settings
extends RefCounted
## Uživatelské nastavení (user://settings.cfg): hlasitost, celá obrazovka, vsync, 3D bojiště, rychlost textu.

const PATH := "user://settings.cfg"
const DEFAULTS := {"volume": 0.8, "fullscreen": false, "vsync": true, "arena3d": true, "text_speed": 1.0}

static var values := DEFAULTS.duplicate()
static var _loaded := false
static var text_speed := 1.0   ## násobič psaní dialogů


static func load_and_apply() -> void:
	if not _loaded:
		_loaded = true
		var cfg := ConfigFile.new()
		if cfg.load(PATH) == OK:
			for k in DEFAULTS:
				values[k] = cfg.get_value("game", k, DEFAULTS[k])
	apply()


static func set_value(key: String, v: Variant) -> void:
	values[key] = v
	apply()
	var cfg := ConfigFile.new()
	for k in values:
		cfg.set_value("game", k, values[k])
	cfg.save(PATH)


static func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, float(values["volume"]))))
	var win := DisplayServer.WINDOW_MODE_FULLSCREEN if values["fullscreen"] else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != win:
		DisplayServer.window_set_mode(win)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if values["vsync"] else DisplayServer.VSYNC_DISABLED)
	BattleScene3.use_arena = bool(values["arena3d"])
	text_speed = float(values["text_speed"])
