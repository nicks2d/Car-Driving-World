class_name PauseMenu
extends CanvasLayer
## Pausemenü (Esc) im Glas-Stil: Weiterfahren, Garage, Karte, Fotomodus, Einstellungen,
## Spiel beenden. Die Einstellungen haben fünf Reiter (Grafik, Anzeige, Steuerung, Audio,
## Spiel); jede Änderung wirkt sofort und wird gespeichert (GameSettings). Das Spiel ist
## angehalten, deshalb darf das Glas hier echt weichzeichnen.

@export var settings: GameSettings
@export var garage: Garage
@export var big_map: BigMap
@export var photo_mode: PhotoMode
@export var hud: CanvasLayer
@export var weather: Weather

const MAIN_SIZE := Vector2(440.0, 600.0)
const SETTINGS_SIZE := Vector2(1200.0, 800.0)
const TABS: Array[String] = ["Grafik", "Anzeige", "Steuerung", "Audio", "Spiel"]
const SECTIONS: Array[String] = ["grafik", "anzeige", "steuerung", "audio", "spiel"]
const RESOLUTIONS: Array[String] = ["1280x720", "1600x900", "1920x1080", "2560x1440"]
const FPS_LIMITS: Array[int] = [30, 60, 120, 0]

var is_open: bool = false
var _root: Control
var _main: Control
var _settings_panel: Control
var _tab: int = 0
var _tab_buttons: Array[Button] = []
var _scroll: ScrollContainer
var _content: VBoxContainer
var _quit_button: Button
var _quit_armed: bool = false
var _quality_buttons: Array[Button] = []
var _quality_note: Label
## Tastenbelegung: Aktion, die auf eine Taste wartet (leer = keine)
var _waiting_action: String = ""
var _hud_was_visible: bool = true
var _knob: Texture2D
## Knöpfe in Akzentfarbe (bekommen beim Öffnen die aktuelle HUD-Farbe)
var _primary_buttons: Array[Button] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 30
	_knob = _make_knob()
	_build()
	visible = false
	if settings:
		settings.changed.connect(_on_settings_changed)


func open() -> void:
	if is_open:
		return
	is_open = true
	visible = true
	get_tree().paused = true
	if hud:
		_hud_was_visible = hud.visible
		hud.visible = false
	_quit_armed = false
	_quit_button.text = "Spiel beenden"
	for button in _primary_buttons:
		_style_big_button(button, true)
	_show_main()


func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	_waiting_action = ""
	get_tree().paused = false
	if hud:
		hud.visible = _hud_was_visible


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if not is_open:
		# Etwas anderes (Garage, Karte, Fotomodus) hat angehalten: das schließt selbst
		if not get_tree().paused:
			open()
			get_viewport().set_input_as_handled()
		return
	if _settings_panel.visible:
		_show_main()
	else:
		close()
	get_viewport().set_input_as_handled()


## Tastenbelegung: die nächste Taste gehört der wartenden Aktion (Esc bricht ab)
func _input(event: InputEvent) -> void:
	if _waiting_action == "" or not is_open:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	get_viewport().set_input_as_handled()
	if key.keycode != KEY_ESCAPE:
		var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
		settings.rebind(_waiting_action, code)
	_waiting_action = ""
	_show_tab(_tab)


func _show_main() -> void:
	_waiting_action = ""
	_main.visible = true
	_settings_panel.visible = false


## Für Tests (--pause=N): Einstellungen mit diesem Reiter zeigen
func show_settings_tab(index: int) -> void:
	_tab = index
	_show_settings()


func _show_settings() -> void:
	_main.visible = false
	_settings_panel.visible = true
	_show_tab(_tab)


# ---------------------------------------------------------------------------
# Aufbau
# ---------------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.25)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	_build_main()
	_build_settings()


func _build_main() -> void:
	_main = _glass_window(MAIN_SIZE)
	var box := _window_box(_main, 36)
	box.add_child(UiStyle.label("PAUSE", 13, "semibold", UiStyle.TEXT_DIM, 3))
	box.add_child(UiStyle.label("Spiel angehalten", 30, "extrabold"))
	_spacer(box, 14)
	box.add_child(_big_button("Weiterfahren", true, close))
	box.add_child(_big_button("Garage", false, func() -> void:
		close()
		if garage:
			garage.open()))
	box.add_child(_big_button("Karte", false, func() -> void:
		close()
		if big_map:
			big_map.open()))
	box.add_child(_big_button("Fotomodus", false, func() -> void:
		close()
		if photo_mode:
			photo_mode.open()))
	box.add_child(_big_button("Einstellungen", false, _show_settings))
	_quit_button = _big_button("Spiel beenden", false, func() -> void:
		if _quit_armed:
			get_tree().quit()
		else:
			_quit_armed = true
			_quit_button.text = "Wirklich beenden? Noch mal klicken")
	_quit_button.add_theme_color_override("font_color", UiStyle.RED)
	_quit_button.add_theme_color_override("font_hover_color", UiStyle.RED)
	box.add_child(_quit_button)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	box.add_child(UiStyle.label("Esc  weiterfahren", 14, "medium", UiStyle.TEXT_FAINT))


func _build_settings() -> void:
	_settings_panel = _glass_window(SETTINGS_SIZE)
	var box := _window_box(_settings_panel, 32)
	box.add_theme_constant_override("separation", 14)
	var header := HBoxContainer.new()
	box.add_child(header)
	var title := UiStyle.label("Einstellungen", 28, "extrabold")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(UiStyle.label("Änderungen wirken sofort und werden gespeichert", 14, "medium", UiStyle.TEXT_DIM))
	_tab_buttons = _segmented(box, TABS, _show_tab)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 8)
	_scroll.add_child(_content)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	box.add_child(footer)
	footer.add_child(_outline_button("Zurücksetzen", func() -> void:
		settings.reset_section(SECTIONS[_tab])
		_show_tab(_tab)))
	var space := Control.new()
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(space)
	var back := _big_button("Zurück", true, _show_main)
	back.custom_minimum_size = Vector2(180.0, 46.0)
	footer.add_child(back)


## Inhalt eines Reiters neu aufbauen (Scroll-Position bleibt, wenn es derselbe ist)
func _show_tab(index: int) -> void:
	var keep_scroll := index == _tab
	var scroll := _scroll.scroll_vertical
	_tab = index
	_select_segment(_tab_buttons, index)
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_quality_buttons.clear()
	_quality_note = null
	match index:
		0:
			_fill_graphics()
		1:
			_fill_display()
		2:
			_fill_controls()
		3:
			_fill_audio()
		4:
			_fill_game()
	if keep_scroll:
		await get_tree().process_frame
		_scroll.scroll_vertical = scroll
	else:
		_scroll.scroll_vertical = 0


func _on_settings_changed() -> void:
	# Qualitätsstufe zeigt „Eigene“, sobald ein Regler davon abweicht
	if _quality_buttons.is_empty() or _quality_note == null:
		return
	var quality: String = settings.get_value("grafik", "qualitaet")
	_select_segment(_quality_buttons, GameSettings.QUALITY_NAMES.find(quality))
	_quality_note.text = "Eigene Einstellung" if quality == "eigene" else ""


# ---------------------------------------------------------------------------
# Reiter
# ---------------------------------------------------------------------------

func _fill_graphics() -> void:
	var row := _row("Qualität", "Setzt alle Regler darunter. Hoch ist der Standard.")
	var quality: String = settings.get_value("grafik", "qualitaet")
	var holder := VBoxContainer.new()
	holder.custom_minimum_size = Vector2(500.0, 0.0)
	row.add_child(holder)
	_quality_buttons = _segmented(holder, ["Niedrig", "Mittel", "Hoch", "Ultra"], func(i: int) -> void:
		settings.set_quality(GameSettings.QUALITY_NAMES[i])
		_show_tab(_tab))
	_select_segment(_quality_buttons, GameSettings.QUALITY_NAMES.find(quality))
	_quality_note = UiStyle.label("Eigene Einstellung" if quality == "eigene" else "", 13, "medium", UiStyle.TEXT_DIM)
	holder.add_child(_quality_note)
	_slider_row("Render-Auflösung", "Anteil der Bildpunkte, MetalFX rechnet hoch", "grafik", "render_scale",
		0.5, 1.0, 0.05, func(v: float) -> String: return "%d %%" % roundi(v * 100.0))
	_slider_row("Sichtweite", "Wie weit Gelände in voller Form geladen wird", "grafik", "sichtweite",
		1000.0, 3000.0, 100.0, func(v: float) -> String: return ("%.1f km" % (v / 1000.0)).replace(".", ","))
	_choice_row("Schatten", "", "grafik", "schatten", ["Aus", "Niedrig", "Mittel", "Hoch"], [0, 1, 2, 3])
	_slider_row("Vegetation", "Dichte der Bäume, Büsche und Felsen", "grafik", "vegetation",
		0.4, 1.0, 0.1, func(v: float) -> String: return "%d %%" % roundi(v * 100.0))
	_choice_row("Gras", "", "grafik", "gras", ["Aus", "Wenig", "Normal", "Viel"], [0, 1, 2, 3])
	_toggle_row("Umgebungsverdeckung (SSAO)", "Weiche Schatten in Ecken und unter Bäumen", "grafik", "ssao")
	_toggle_row("Spiegelungen bei Regen", "Nasse Straßen spiegeln (kostet ~2,5 ms)", "grafik", "spiegelungen")
	_toggle_row("Volumetrischer Nebel", "Lichtstrahlen im Dunst (teuer)", "grafik", "volumennebel")
	_toggle_row("Wolkenschatten", "Schatten ziehender Wolken auf dem Land", "grafik", "wolkenschatten")
	_choice_row("Verkehr", "KI-Autos auf Landstraßen und Autobahnen", "grafik", "verkehr", ["Aus", "Wenig", "Normal"],
		[0.0, 0.5, 1.0])


func _fill_display() -> void:
	_choice_row("Modus", "", "anzeige", "vollbild", ["Fenster", "Vollbild"], [false, true])
	_choice_row("Auflösung (Fenster)", "Fenstergröße; im Vollbild gilt die des Bildschirms", "anzeige", "aufloesung",
		["1280 × 720", "1600 × 900", "1920 × 1080", "2560 × 1440"], RESOLUTIONS)
	_toggle_row("V-Sync", "Gegen Bildrisse. Im Fenster lässt macOS es nicht abschalten.", "anzeige", "vsync")
	_choice_row("FPS-Begrenzung", "", "anzeige", "fps_limit", ["30", "60", "120", "Unbegrenzt"], FPS_LIMITS)
	_toggle_row("FPS-Anzeige", "Auch mit F3 umschaltbar", "anzeige", "fps_anzeige")


func _fill_controls() -> void:
	_choice_row("Grip-Stufe", "Komfort = sehr viel Halt, Drift = Heck kommt leicht", "steuerung", "grip",
		["Komfort", "Sport", "Drift"], ["komfort", "sport", "drift"])
	_slider_row("Lenkempfindlichkeit", "Wie schnell die Lenkung einschlägt", "steuerung", "lenkung",
		0.5, 1.5, 0.05, func(v: float) -> String: return "%d %%" % roundi(v * 100.0))
	_toggle_row("Tempolimits übernehmen", "Der Tempomat stellt sich auf erkannte Schilder ein", "steuerung", "tempolimit")
	_spacer(_content, 6)
	_content.add_child(UiStyle.label("TASTEN", 13, "semibold", UiStyle.TEXT_DIM, 2))
	_content.add_child(UiStyle.label("Klicken, dann die neue Taste drücken (Esc bricht ab).", 14, "regular",
		UiStyle.TEXT_DIM))
	for entry: Array in GameSettings.ACTIONS:
		var action: String = entry[0]
		var twins := settings.duplicates_of(action)
		var row := _row(entry[1], ("Doppelt belegt: " + ", ".join(PackedStringArray(twins))) if not twins.is_empty() else "",
			not twins.is_empty())
		var waiting := _waiting_action == action
		var button := _outline_button("Taste drücken …" if waiting else GameSettings.key_name(settings.key_of(action)),
			func() -> void:
				_waiting_action = action
				_show_tab(_tab))
		button.custom_minimum_size = Vector2(200.0, 40.0)
		if waiting:
			button.add_theme_stylebox_override("normal", UiStyle.box(Color(UiStyle.accent, 0.3), 12, UiStyle.accent, 1))
		row.add_child(button)


func _fill_audio() -> void:
	var percent := func(v: float) -> String: return "%d %%" % roundi(v * 100.0)
	_slider_row("Gesamt", "", "audio", "gesamt", 0.0, 1.0, 0.05, percent)
	_slider_row("Motor", "Motor, Reifen, Blinker, Hupe", "audio", "motor", 0.0, 1.0, 0.05, percent)
	_slider_row("Umgebung", "Regen, Wind, Donner", "audio", "umgebung", 0.0, 1.0, 0.05, percent)
	_slider_row("Musik", "Noch keine Musik im Spiel (vorbereitet)", "audio", "musik", 0.0, 1.0, 0.05, percent)


func _fill_game() -> void:
	var row := _row("HUD-Farbe", "Akzentfarbe von Tacho, Navi und Menüs")
	var swatches := HBoxContainer.new()
	swatches.add_theme_constant_override("separation", 6)
	row.add_child(swatches)
	for i in UiStyle.ACCENTS.size():
		var swatch := Garage.Swatch.new(UiStyle.ACCENTS[i], 34.0)
		swatch.selected = garage != null and garage.accent_index() == i
		swatch.pressed.connect(func() -> void:
			garage.set_accent(i)
			_show_tab(_tab))
		swatches.add_child(swatch)
	var exhaust_row := _row("Sportauspuff", "Knallen und Flammen beim Gaswegnehmen")
	var exhaust := Garage.Toggle.new()
	exhaust.on = garage != null and garage.sport_exhaust
	exhaust.toggled.connect(func(on: bool) -> void: garage.set_sport_exhaust(on))
	exhaust_row.add_child(exhaust)
	_choice_row("Tempo-Anzeige", "", "spiel", "einheit", ["km/h", "mph"], ["kmh", "mph"])
	var weather_row := _row("Automatisches Wetter", "Wechselt alle paar Minuten; aus = aktuelles Wetter bleibt (F5)")
	var auto := Garage.Toggle.new()
	auto.on = weather != null and weather.mode < 0
	auto.toggled.connect(func(on: bool) -> void:
		if weather:
			weather.set_mode(-1 if on else weather.kind, false))
	weather_row.add_child(auto)
	_slider_row("Tageslänge", "Echtzeit für 24 Stunden im Spiel", "spiel", "tageslaenge", 4.0, 60.0, 1.0,
		func(v: float) -> String: return "%d min" % roundi(v))


# ---------------------------------------------------------------------------
# Zeilen und Bedienelemente
# ---------------------------------------------------------------------------

## Zeile: links Titel (und Hinweis), rechts das Bedienelement (wird an die Zeile angehängt)
func _row(title: String, hint: String, warning: bool = false) -> HBoxContainer:
	var panel := PanelContainer.new()
	var style := UiStyle.box(Color(1, 1, 1, 0.05), 14)
	style.content_margin_left = 18
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	_content.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.add_theme_constant_override("separation", 2)
	row.add_child(texts)
	texts.add_child(UiStyle.label(title, 17, "semibold"))
	if hint != "":
		texts.add_child(UiStyle.label(hint, 13, "medium" if warning else "regular",
			UiStyle.RED if warning else UiStyle.TEXT_DIM))
	return row


func _choice_row(title: String, hint: String, section: String, key: String, names: Array, values: Array) -> void:
	var row := _row(title, hint)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(500.0, 46.0)
	row.add_child(holder)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(box)
	# Die Knöpfe kommen nachträglich in dasselbe Array (das Lambda kennt es schon)
	var buttons: Array[Button] = []
	buttons.append_array(_segmented(box, names, func(i: int) -> void:
		settings.set_value(section, key, values[i])
		_select_segment(buttons, i)))
	var current: Variant = settings.get_value(section, key)
	var chosen := -1
	for i in values.size():
		if typeof(values[i]) in [TYPE_INT, TYPE_FLOAT] and typeof(current) in [TYPE_INT, TYPE_FLOAT]:
			if is_equal_approx(float(values[i]), float(current)):
				chosen = i
		elif values[i] == current:
			chosen = i
	_select_segment(buttons, chosen)


func _toggle_row(title: String, hint: String, section: String, key: String) -> void:
	var row := _row(title, hint)
	var toggle := Garage.Toggle.new()
	toggle.on = settings.get_value(section, key)
	toggle.toggled.connect(func(on: bool) -> void: settings.set_value(section, key, on))
	row.add_child(toggle)


func _slider_row(title: String, hint: String, section: String, key: String, low: float, high: float, step: float,
		format: Callable) -> void:
	var row := _row(title, hint)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.value = settings.get_value(section, key)
	slider.custom_minimum_size = Vector2(380.0, 30.0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_NONE
	var track := UiStyle.box(Color(1, 1, 1, 0.14), 3)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	slider.add_theme_stylebox_override("slider", track)
	var filled := UiStyle.box(UiStyle.accent, 3)
	filled.content_margin_top = 3
	filled.content_margin_bottom = 3
	slider.add_theme_stylebox_override("grabber_area", filled)
	slider.add_theme_stylebox_override("grabber_area_highlight", filled)
	slider.add_theme_icon_override("grabber", _knob)
	slider.add_theme_icon_override("grabber_highlight", _knob)
	row.add_child(slider)
	var value_label := UiStyle.label(format.call(slider.value), 16, "semibold")
	value_label.custom_minimum_size = Vector2(90.0, 0.0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	slider.value_changed.connect(func(v: float) -> void:
		value_label.text = format.call(v)
		settings.set_value(section, key, v))


func _segmented(parent: Control, names: Array, on_pick: Callable) -> Array[Button]:
	var holder := PanelContainer.new()
	var style := UiStyle.box(Color(1, 1, 1, 0.06), 13)
	style.set_content_margin_all(4)
	holder.add_theme_stylebox_override("panel", style)
	parent.add_child(holder)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	holder.add_child(row)
	var buttons: Array[Button] = []
	for i in names.size():
		var button := Button.new()
		button.text = names[i]
		button.custom_minimum_size = Vector2(0.0, 38.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 15)
		button.pressed.connect(on_pick.bind(i))
		row.add_child(button)
		buttons.append(button)
	_select_segment(buttons, -1)
	return buttons


## Gewählter Knopf weiß mit dunkler Schrift (wie in der Garage)
func _select_segment(buttons: Array[Button], index: int) -> void:
	for i in buttons.size():
		var chosen := i == index
		var style := UiStyle.box(Color.WHITE if chosen else Color(0, 0, 0, 0), 11)
		for state: String in ["normal", "hover", "pressed", "focus"]:
			buttons[i].add_theme_stylebox_override(state, style if chosen or state == "normal" or state == "focus"
				else UiStyle.box(Color(1, 1, 1, 0.08), 11))
		buttons[i].add_theme_color_override("font_color", Garage.DARK_TEXT if chosen else Color(1, 1, 1, 0.8))
		buttons[i].add_theme_color_override("font_hover_color", Garage.DARK_TEXT if chosen else Color.WHITE)
		buttons[i].add_theme_color_override("font_pressed_color", Garage.DARK_TEXT)
		buttons[i].add_theme_font_override("font", UiStyle.font("semibold" if chosen else "medium"))


## Großer Knopf im Pausemenü: gefüllt (Akzentfarbe) oder dezent
func _big_button(text: String, primary: bool, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0.0, 52.0)
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER if primary else HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_override("font", UiStyle.font("semibold"))
	button.add_theme_font_size_override("font_size", 18)
	_style_big_button(button, primary)
	button.add_theme_color_override("font_color", UiStyle.TEXT)
	button.add_theme_color_override("font_hover_color", UiStyle.TEXT)
	button.pressed.connect(on_press)
	if primary:
		_primary_buttons.append(button)
	return button


func _style_big_button(button: Button, primary: bool) -> void:
	var normal := UiStyle.box(UiStyle.accent if primary else Color(1, 1, 1, 0.06), 14)
	normal.content_margin_left = 20
	normal.content_margin_right = 20
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = UiStyle.accent.lightened(0.12) if primary else Color(1, 1, 1, 0.13)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)


func _outline_button(text: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0.0, 46.0)
	button.add_theme_font_override("font", UiStyle.font("medium"))
	button.add_theme_font_size_override("font_size", 15)
	var normal := UiStyle.box(Color(0, 0, 0, 0), 12, Color(1, 1, 1, 0.22), 1)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(1, 1, 1, 0.08)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_color_override("font_color", UiStyle.TEXT)
	button.pressed.connect(on_press)
	return button


## Fenster mit weichgezeichnetem Glas in der Bildmitte
func _glass_window(window_size: Vector2) -> Control:
	var window := Control.new()
	window.size = window_size
	window.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	window.mouse_filter = Control.MOUSE_FILTER_STOP
	var glass := GlassPanel.new()
	glass.radius = 28.0
	glass.tint = Color(UiStyle.GLASS, 0.7)
	glass.set_anchors_preset(Control.PRESET_FULL_RECT)
	window.add_child(glass)
	_root.add_child(window)
	return window


func _window_box(window: Control, margin_px: int) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, margin_px)
	window.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	return box


func _spacer(parent: Control, height: float) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, height)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(spacer)


## Runder weißer Knopf für die Regler
func _make_knob() -> Texture2D:
	var size_px := 22
	var image := Image.create(size_px, size_px, false, Image.FORMAT_RGBA8)
	var center := Vector2(size_px, size_px) * 0.5
	for y in size_px:
		for x in size_px:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(center)
			var alpha := clampf(size_px * 0.5 - 1.0 - d + 0.5, 0.0, 1.0)
			image.set_pixel(x, y, Color(1, 1, 1, alpha))
	return ImageTexture.create_from_image(image)
