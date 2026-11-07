class_name LightingLab
extends CanvasLayer
## Ladicí panel osvětlení (F2 ve hře). Vybereš klíčový snímek (denní dobu), táhneš posuvníky a vidíš výsledek hned;
## „Uložit“ zapíše data/lighting.json. Časová osa + cyklus dne ukáže plynulé přechody, výběr místa přenese hrdinu.
## Screenshot (F12) uloží PNG bez panelu do user://shots/.

const SPOTS := {"Tábor": Vector2(420, 460), "Osada": Vector2(830, 800), "Kostel a hřbitov": Vector2(200, 850), "Chata": Vector2(885, 440),
	"Les": Vector2(300, 400), "Palouček": Vector2(160, 480), "Řeka": Vector2(120, 520), "Okraj hor": Vector2(870, 305), "Vchod do dungeonu": Vector2(590, 235)}
const SKETCH_S := 6.0
const SKETCH_ORIGIN := Vector2(-93, -76)      # počátek skici v dlaždicích (generate_map.py: -W//2, -H//2)

var world: Hd2dWorld
var hero: Node2D
var _key := 0
var _widgets: Dictionary = {}
var _time_slider: HSlider
var _time_label: Label
var _key_pick: OptionButton
var _panel: PanelContainer
var _updating := false


## Poloha na nákresu (px původního obrázku) → souřadnice světa.
static func spot_position(sketch_px: Vector2) -> Vector2:
	return ((Vector2(sketch_px.x + 20.0, sketch_px.y - 80.0) / SKETCH_S) + SKETCH_ORIGIN) * 24.0


func setup(w: Hd2dWorld, h: Node2D) -> void:
	world = w
	hero = h
	layer = 80
	_panel = PanelContainer.new()
	_panel.position = Vector2(8, 8)
	_panel.custom_minimum_size = Vector2(350, 0)
	add_child(_panel)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(350, 690)
	_panel.add_child(sc)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(330, 0)
	sc.add_child(box)
	_build_top(box)
	var group := ""
	for p in LightingProfile.PARAMS:
		if p[2] != group:
			group = p[2]
			var l := Label.new()
			l.text = "— %s —" % group
			l.add_theme_color_override("font_color", Color(1, 0.85, 0.5))
			box.add_child(l)
		box.add_child(_param_row(p))
	_build_quality(box)
	_select_key(world.profile.key_index_near(world.hour))


func _build_top(box: VBoxContainer) -> void:
	var t := Label.new()
	t.text = "OSVĚTLENÍ  (F2 zavřít, F12 screenshot)"
	box.add_child(t)
	_time_label = Label.new()
	box.add_child(_time_label)
	_time_slider = HSlider.new()
	_time_slider.min_value = 0.0
	_time_slider.max_value = 24.0
	_time_slider.step = 0.05
	_time_slider.value = world.hour
	_time_slider.value_changed.connect(func(v: float) -> void:
		if not _updating:
			world.day_length = 0.0
			world.set_time(v))
	box.add_child(_time_slider)
	var row := HBoxContainer.new()
	box.add_child(row)
	_key_pick = OptionButton.new()
	_key_pick.item_selected.connect(_select_key)
	row.add_child(_key_pick)
	row.add_child(_button("Nový", _new_key))
	row.add_child(_button("Smazat", _delete_key))
	var row2 := HBoxContainer.new()
	box.add_child(row2)
	row2.add_child(_button("Cyklus dne", func() -> void: world.day_length = 0.0 if world.day_length > 0.0 else 90.0))
	row2.add_child(_button("Uložit", _save))
	row2.add_child(_button("Načíst", _reload))
	var spots := OptionButton.new()
	for k in SPOTS:
		spots.add_item(k)
	spots.item_selected.connect(func(i: int) -> void: teleport(spots.get_item_text(i)))
	box.add_child(spots)


func _build_quality(box: VBoxContainer) -> void:
	var l := Label.new()
	l.text = "— Kvalita (Forward+/Mobile) —"
	l.add_theme_color_override("font_color", Color(1, 0.85, 0.5))
	box.add_child(l)
	var presets := HBoxContainer.new()
	for pn in LightingProfile.PRESETS:
		presets.add_child(_button(pn, func() -> void:
			world.profile.quality.merge(LightingProfile.PRESETS[pn], true)
			world.apply_quality()
			_rebuild_panel()))
	box.add_child(presets)
	var wl := Label.new()
	wl.text = "Počasí (F3 přepíná):"
	box.add_child(wl)
	var wrow := HFlowContainer.new()
	for wn in WorldFx.WEATHER_ORDER:
		wrow.add_child(_button(wn, func() -> void: world.fx.set_weather(wn)))
	box.add_child(wrow)
	for q in [["ssao", "SSAO (okluze)"], ["ssil", "SSIL (odražené světlo)"], ["dof", "Hloubka ostrosti"], ["volumetric_fog", "Objemová mlha"],
			["contact_shadows", "Kontaktní stíny props"], ["shafts", "Světelné paprsky"], ["sway", "Vítr na rostlinách"],
			["ambient_life", "Ptáci, motýli, listí, kouř"], ["foreground", "Listí v popředí"]]:
		var c := CheckBox.new()
		c.text = q[1]
		c.button_pressed = world.profile.quality[q[0]]
		c.toggled.connect(func(on: bool) -> void:
			world.profile.quality[q[0]] = on
			world.apply_quality())
		box.add_child(c)
	for q in [["ssao_intensity", "SSAO síla", 0.0, 6.0], ["shadow_distance", "Dosah stínů", 20.0, 120.0], ["dof_amount", "DOF síla", 0.0, 0.4], ["volumetric_density", "Hustota objemové mlhy", 0.0, 0.1]]:
		box.add_child(_slider_row(q[1], q[2], q[3], (q[3] - q[2]) / 200.0, float(world.profile.quality[q[0]]), func(v: float) -> void:
			world.profile.quality[q[0]] = v
			world.apply_quality()))


func _rebuild_panel() -> void:
	_panel.queue_free()
	setup(world, hero)


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b


func _slider_row(label: String, lo: float, hi: float, step: float, val: float, cb: Callable, store := "") -> Control:
	var row := VBoxContainer.new()
	var l := Label.new()
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = val
	var upd := func(v: float) -> void: l.text = "%s: %s" % [label, snappedf(v, step)]
	upd.call(val)
	s.value_changed.connect(func(v: float) -> void:
		upd.call(v)
		if not _updating:
			cb.call(v))
	row.add_child(s)
	if store != "":
		_widgets[store] = [s, upd]
	return row


func _param_row(p: Array) -> Control:
	var key: String = p[0]
	if p[3] is String:
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = p[1]
		l.custom_minimum_size = Vector2(190, 0)
		row.add_child(l)
		var cp := ColorPickerButton.new()
		cp.custom_minimum_size = Vector2(80, 24)
		cp.edit_alpha = false
		cp.color_changed.connect(func(c: Color) -> void:
			if not _updating:
				_edit(key, "#" + c.to_html(false)))
		row.add_child(cp)
		_widgets[key] = [cp, null]
		return row
	return _slider_row(p[1], p[3], p[4], p[5], 0.0, func(v: float) -> void: _edit(key, v), key)


func _edit(key: String, v: Variant) -> void:
	world.profile.keys[_key][key] = v
	world.day_length = 0.0
	world.set_time(float(world.profile.keys[_key].hour))


func _select_key(i: int) -> void:
	_key = clampi(i, 0, world.profile.keys.size() - 1)
	_refresh_keys()
	var k: Dictionary = world.profile.keys[_key]
	world.day_length = 0.0
	world.set_time(float(k.hour))
	_updating = true
	_time_slider.value = float(k.hour)
	for p in LightingProfile.PARAMS:
		var w: Array = _widgets[p[0]]
		if p[3] is String:
			(w[0] as ColorPickerButton).color = Color.html(String(k[p[0]]))
		else:
			(w[0] as HSlider).value = float(k[p[0]])
			w[1].call(float(k[p[0]]))
	_updating = false


func _refresh_keys() -> void:
	_key_pick.clear()
	for k in world.profile.keys:
		_key_pick.add_item("%s (%s h)" % [k.name, k.hour])
	_key_pick.select(_key)


func _new_key() -> void:
	var k: Dictionary = world.profile.keys[_key].duplicate()
	k.hour = fposmod(float(k.hour) + 1.0, 24.0)
	k.name = "Nový"
	world.profile.keys.append(k)
	world.profile.keys.sort_custom(func(a, b): return float(a.hour) < float(b.hour))
	_select_key(world.profile.keys.find(k))


func _delete_key() -> void:
	if world.profile.keys.size() > 2:
		world.profile.keys.remove_at(_key)
		_select_key(0)


func _save() -> void:
	world.profile.keys.sort_custom(func(a, b): return float(a.hour) < float(b.hour))
	var path := LightingProfile.PATH if OS.has_feature("editor") else "user://lighting.json"
	world.profile.save_file(path)
	print("Osvětlení uloženo: ", ProjectSettings.globalize_path(path))


func _reload() -> void:
	world.profile = LightingProfile.load_file()
	world.apply_quality()
	_select_key(0)


func teleport(spot: String) -> void:
	hero.global_position = spot_position(SPOTS[spot])
	world.snap_camera()


func _process(_d: float) -> void:
	if world == null:
		return
	_time_label.text = "Čas: %02d:%02d%s" % [int(world.hour), int(fposmod(world.hour, 1.0) * 60.0), "  ▶" if world.day_length > 0.0 else ""]
	if world.day_length > 0.0:
		_updating = true
		_time_slider.value = world.hour
		_updating = false


func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_F12:
			screenshot()


func screenshot() -> String:
	var was := _panel.visible
	_panel.visible = false
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("user://shots")
	var path := "user://shots/%s.png" % Time.get_datetime_string_from_system().replace(":", "-")
	get_viewport().get_texture().get_image().save_png(path)
	_panel.visible = was
	print("Screenshot: ", ProjectSettings.globalize_path(path))
	return path
