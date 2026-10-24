class_name Garage
extends CanvasLayer
## Die Garage (Entwurf „Glas“): Das Spiel pausiert, eine Kamera kreist langsam um das Auto an
## seiner Stelle in der Welt, das HUD ist aus. Links ein Glas-Panel mit den Daten (Balken im
## Vergleich zum stärksten Auto), Lack, HUD-Farbe, Sportauspuff, Welt (Tageszeit, Wetter,
## Jahreszeit – die Vorschau ändert sich sofort) und „Losfahren“. Unten rechts die Autos als
## Karten. Auto, Lack und Einstellungen werden in user:// gespeichert.
##
## Bedienung: Maus, ← → Auto, C Lack, Enter losfahren, Esc zurück (ohne Autowechsel).

## Wird gesendet, wenn die Garage geschlossen wurde
signal closed

@export var car: Car
## Alle Autos (Profile), in dieser Reihenfolge als Karten
@export var cars: Array[CarProfile] = []
@export var hud: CanvasLayer
@export var day_night: DayNight
@export var weather: Weather

@export_group("Kamera")
## Abstand der Kamera vom Auto (mal Radstand) und Höhe über dem Auto
@export var orbit_distance_factor: float = 2.6
@export var orbit_height: float = 1.6
## So schnell kreist die Kamera (Bogenmaß pro Sekunde)
@export var orbit_speed: float = 0.12
## Bildmitte nach links schieben, damit das Auto rechts neben dem Panel steht
@export var camera_shift: float = -1.5
@export var camera_fov: float = 50.0

const SETTINGS_PATH := "user://einstellungen.cfg"
const TIMES: Array[float] = [7.5, 13.0, 19.5, 23.5]
const TIME_NAMES: Array[String] = ["Morgen", "Mittag", "Abend", "Nacht"]
const WEATHER_MODES: Array[int] = [-1, Weather.Kind.CLEAR, Weather.Kind.RAIN, Weather.Kind.FOG, Weather.Kind.SNOW]
const WEATHER_NAMES: Array[String] = ["Auto", "Klar", "Regen", "Nebel", "Schnee"]
const PANEL_RECT := Rect2(40.0, 36.0, 500.0, 832.0)
const DARK_TEXT := Color("#0B1530")

var is_open: bool = false
## Wurde schon einmal losgefahren? (Beim Start gibt es kein „Zurück“)
var _has_driven: bool = false
var _selected: int = 0
var _paint: int = 0
var _open_selected: int = 0
var _open_paint: int = 0
var _accent_index: int = 0
## Sportauspuff an (für Pops und Flammen, siehe Car.sport_exhaust)
var sport_exhaust: bool = true
var _camera: Camera3D
var _orbit_angle: float = 0.6
var _dragging: bool = false
var _hud_was_visible: bool = true

# Oberfläche
var _root: Control
var _name_label: Label
var _subtitle_label: Label
var _bars: Array = []  # [Name-Label, Wert-Label, Bar]
var _paint_row: HBoxContainer
var _accent_row: HBoxContainer
var _exhaust_toggle: Toggle
var _time_buttons: Array[Button] = []
var _weather_buttons: Array[Button] = []
var _season_buttons: Array[Button] = []
var _drive_button: Button
var _cards: Array[CarCard] = []
var _credits: Control
var _collection: Control
## Liste in der Sammlung (füllt fill_collection)
var collection_list: VBoxContainer


# ---------------------------------------------------------------------------
# Kleine Bausteine der Oberfläche
# ---------------------------------------------------------------------------

## Balken (Anteil 0 bis 1) in Akzentfarbe auf heller Spur
class Bar extends Control:
	var ratio: float = 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(0.0, 4.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		UiStyle.draw_box(self, Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.12), 2)
		if ratio > 0.0:
			UiStyle.draw_box(self, Rect2(Vector2.ZERO, Vector2(size.x * clampf(ratio, 0.0, 1.0), size.y)), UiStyle.accent, 2)


## Runder Farbknopf, der gewählte mit Ring in Akzentfarbe
class Swatch extends Control:
	signal pressed
	var color: Color = Color.WHITE
	var selected: bool = false
	var diameter: float = 40.0

	func _init(swatch_color: Color, size_px: float) -> void:
		color = swatch_color
		diameter = size_px
		custom_minimum_size = Vector2(size_px + 8.0, size_px + 8.0)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _draw() -> void:
		var center := size * 0.5
		if selected:
			draw_arc(center, diameter * 0.5 + 3.0, 0.0, TAU, 48, UiStyle.accent, 2.5, true)
		draw_circle(center, diameter * 0.5 - (2.0 if selected else 0.0), color)
		draw_arc(center, diameter * 0.5 - (2.0 if selected else 0.0), 0.0, TAU, 48, Color(1, 1, 1, 0.25), 1.0, true)

	func _gui_input(event: InputEvent) -> void:
		var mouse := event as InputEventMouseButton
		if mouse and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			pressed.emit()


## Schalter (an/aus) wie bei einem Handy
class Toggle extends Control:
	signal toggled(on: bool)
	var on: bool = true

	func _init() -> void:
		custom_minimum_size = Vector2(46.0, 26.0)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _draw() -> void:
		var rect := Rect2(Vector2(0.0, (size.y - 26.0) * 0.5), Vector2(46.0, 26.0))
		UiStyle.draw_box(self, rect, UiStyle.accent if on else Color(1, 1, 1, 0.16), 13)
		var knob_x := rect.position.x + (33.0 if on else 13.0)
		draw_circle(Vector2(knob_x, rect.get_center().y), 10.0, Color.WHITE)

	func _gui_input(event: InputEvent) -> void:
		var mouse := event as InputEventMouseButton
		if mouse and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			on = not on
			queue_redraw()
			toggled.emit(on)


## Karte eines Autos unten rechts
class CarCard extends Control:
	signal pressed
	var title: String = ""
	var subtitle: String = ""
	var selected: bool = false
	var available: bool = true

	func _init() -> void:
		custom_minimum_size = Vector2(184.0, 94.0)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var glass := GlassPanel.new()
		glass.radius = 18.0
		glass.set_anchors_preset(Control.PRESET_FULL_RECT)
		glass.show_behind_parent = true
		add_child(glass)

	func _draw() -> void:
		var alpha := 1.0 if available else 0.4
		if selected:
			UiStyle.draw_box(self, Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0), 18, UiStyle.accent, 2)
		UiStyle.draw_text(self, title, Vector2(18.0, 52.0), 18, "semibold", Color(1, 1, 1, alpha))
		UiStyle.draw_text(self, subtitle if available else "Modell fehlt", Vector2(18.0, 74.0), 14, "regular",
			Color(1, 1, 1, 0.62 * alpha))

	func _gui_input(event: InputEvent) -> void:
		var mouse := event as InputEventMouseButton
		if mouse and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			pressed.emit()


# ---------------------------------------------------------------------------
# Öffnen, schließen, Einstellungen
# ---------------------------------------------------------------------------

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_camera = Camera3D.new()
	_camera.fov = camera_fov
	_camera.far = 30000.0
	_camera.near = 0.1
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_camera)
	# Das Automodell muss auch bei angehaltenem Spiel laden können
	if car and car.has_node("Model"):
		car.get_node("Model").process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false
	_load_settings()


## Gespeicherte Wahl gleich aufs Auto anwenden (auch wenn die Garage beim Start nicht aufgeht)
func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		var id: String = config.get_value("garage", "car", "")
		for i in cars.size():
			if cars[i].id == id and CarModel.is_available(cars[i]):
				_selected = i
		_paint = config.get_value("garage", "paint", 0)
		_accent_index = clampi(config.get_value("hud", "akzent", 0), 0, UiStyle.ACCENTS.size() - 1)
		sport_exhaust = config.get_value("auto", "sportauspuff", true)
	UiStyle.accent = UiStyle.ACCENTS[_accent_index]
	if car:
		car.sport_exhaust = sport_exhaust
		if cars.size() > 0 and car.profile != cars[_selected]:
			car.apply_profile(cars[_selected])
	_apply_paint_to_car()


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("garage", "car", cars[_selected].id)
	config.set_value("garage", "paint", _paint)
	config.set_value("hud", "akzent", _accent_index)
	config.set_value("auto", "sportauspuff", sport_exhaust)
	config.save(SETTINGS_PATH)


func open() -> void:
	if is_open:
		return
	is_open = true
	visible = true
	get_tree().paused = true
	if hud:
		_hud_was_visible = hud.visible
		hud.visible = false
	_camera.current = true
	for i in cars.size():
		if car and cars[i] == car.profile:
			_selected = i
	_open_selected = _selected
	_open_paint = _paint
	_rest_wheels()
	_credits.visible = false
	_collection.visible = false
	_refresh_all()


## Garage schließen. drive = true: gewähltes Auto behalten, sonst zurück zum vorherigen
func close(drive: bool) -> void:
	if not is_open:
		return
	if not drive and (_selected != _open_selected or _paint != _open_paint):
		_selected = _open_selected
		_paint = _open_paint
		car.apply_profile(cars[_selected])
		_apply_paint_to_car()
	is_open = false
	visible = false
	_has_driven = true
	_camera.current = false
	if hud:
		hud.visible = _hud_was_visible
	# Neues Auto: aufrecht und etwas angehoben an derselben Stelle absetzen
	if _selected != _open_selected:
		var spot := Transform3D(Basis(Vector3.UP, atan2(car.global_basis.z.x, car.global_basis.z.z)),
			car.global_position + Vector3.UP * 0.6)
		car.teleport(spot)
	_save_settings()
	get_tree().paused = false
	closed.emit()


## Räder in Ruhelage setzen. Solange das Auto beim Laden eingefroren war, hat die Physik
## ihre Lage verstellt; im angehaltenen Spiel korrigiert sie das nicht von selbst.
func _rest_wheels() -> void:
	if car == null or car.profile == null:
		return
	var wheels := car.corner_wheels()
	for i in wheels.size():
		wheels[i].transform = Transform3D(Basis(), Car.resting_wheel_center(car.profile, i))


func _apply_paint_to_car() -> void:
	var model := car.get_node_or_null("Model") as CarModel if car else null
	if model:
		model.set_paint(_paint)


func _unhandled_input(event: InputEvent) -> void:
	# Etwas anderes (z. B. die große Karte) hat das Spiel angehalten: dann nicht stören
	if not is_open and get_tree().paused:
		return
	if event.is_action_pressed("open_garage"):
		if is_open:
			close(true)
		else:
			open()
		get_viewport().set_input_as_handled()
		return
	if not is_open:
		return
	if event.is_action_pressed("ui_accept"):
		close(true)
	elif event.is_action_pressed("ui_cancel"):
		if _credits.visible or _collection.visible:
			_credits.visible = false
			_collection.visible = false
		else:
			close(not _has_driven)
	elif event.is_action_pressed("ui_left"):
		_step_car(-1)
	elif event.is_action_pressed("ui_right"):
		_step_car(1)
	elif event.is_action_pressed("cycle_paint"):
		_set_paint(_paint + 1)
	else:
		return
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not is_open or car == null:
		return
	if not _dragging:
		_orbit_angle += orbit_speed * delta
	# Kamera kreist um das Auto, bleibt aber über dem Gelände
	var target := car.global_position + Vector3.UP * 0.55
	var distance := car.profile.wheelbase * orbit_distance_factor if car.profile else 7.0
	var eye := target + Vector3(sin(_orbit_angle), 0.0, cos(_orbit_angle)) * distance + Vector3.UP * orbit_height
	var space := car.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(eye + Vector3.UP * 80.0, eye - Vector3.UP * 80.0)
	query.exclude = [car.get_rid()]
	var hit := space.intersect_ray(query)
	if not hit.is_empty() and eye.y < hit["position"].y + 1.0:
		eye.y = hit["position"].y + 1.0
	_camera.global_transform = Transform3D(Basis.looking_at(target - eye), eye)
	_camera.h_offset = camera_shift


# ---------------------------------------------------------------------------
# Auswahl
# ---------------------------------------------------------------------------

func _step_car(step: int) -> void:
	for k in range(1, cars.size()):
		var index := posmod(_selected + step * k, cars.size())
		if CarModel.is_available(cars[index]):
			_pick_car(index)
			return


func _pick_car(index: int) -> void:
	if index == _selected or not CarModel.is_available(cars[index]):
		return
	_selected = index
	_paint = 0
	car.apply_profile(cars[index])
	_rest_wheels()
	_apply_paint_to_car()
	_refresh_all()


func _set_paint(index: int) -> void:
	var count := cars[_selected].paint_colors.size()
	if count == 0:
		return
	_paint = wrapi(index, 0, count)
	_apply_paint_to_car()
	_fill_paint()


func _set_accent(index: int) -> void:
	_accent_index = index
	UiStyle.accent = UiStyle.ACCENTS[index]
	_refresh_all()


func _set_time(index: int) -> void:
	if day_night:
		day_night.set_time(TIMES[index])
	_select_segment(_time_buttons, index)


func _set_weather(index: int) -> void:
	if weather:
		weather.set_mode(WEATHER_MODES[index], true)
	if day_night:
		day_night.refresh()
	_select_segment(_weather_buttons, index)


func _set_season(index: int) -> void:
	if weather:
		weather.set_season(index, true)
	if day_night:
		day_night.refresh()
	_select_segment(_season_buttons, index)


func _refresh_all() -> void:
	var p := cars[_selected]
	_name_label.text = p.display_name
	_subtitle_label.text = p.subtitle
	_fill_bars(p)
	_fill_paint()
	_fill_accents()
	_exhaust_toggle.on = sport_exhaust
	_exhaust_toggle.queue_redraw()
	# Welt: was gerade eingestellt ist
	if day_night:
		var hour := day_night.time_of_day
		var time_index := 3
		if hour >= 5.0 and hour < 10.5:
			time_index = 0
		elif hour >= 10.5 and hour < 16.5:
			time_index = 1
		elif hour >= 16.5 and hour < 21.5:
			time_index = 2
		_select_segment(_time_buttons, time_index)
	if weather:
		var weather_index := WEATHER_MODES.find(weather.mode)
		_select_segment(_weather_buttons, weather_index)
		_select_segment(_season_buttons, weather.season)
	_drive_button.add_theme_stylebox_override("normal", UiStyle.box(UiStyle.accent, 16))
	_drive_button.add_theme_stylebox_override("hover", UiStyle.box(UiStyle.accent.lightened(0.12), 16))
	_drive_button.add_theme_stylebox_override("pressed", UiStyle.box(UiStyle.accent.darkened(0.1), 16))
	for i in _cards.size():
		_cards[i].selected = i == _selected
		_cards[i].queue_redraw()
	for bar: Array in _bars:
		(bar[2] as Bar).queue_redraw()


## Fünf Balken, jeweils im Vergleich zum stärksten Auto (beim Gewicht zum schwersten,
## bei 0–100 zum schnellsten)
func _fill_bars(p: CarProfile) -> void:
	var max_power := 1.0
	var max_torque := 1.0
	var max_mass := 1.0
	var max_top := 1.0
	var best_sprint := 99.0
	for other in cars:
		max_power = maxf(max_power, other.power_ps)
		max_torque = maxf(max_torque, other.max_torque_nm)
		max_mass = maxf(max_mass, other.mass)
		max_top = maxf(max_top, _top_speed(other))
		if other.measured_0_100 > 0.0:
			best_sprint = minf(best_sprint, other.measured_0_100)
	var sprint := p.measured_0_100
	var rows := [
		["Leistung", "%d PS" % p.power_ps, p.power_ps / max_power],
		["Drehmoment", "%d Nm" % roundi(p.max_torque_nm), p.max_torque_nm / max_torque],
		["Gewicht", "%s kg · %s" % [_thousands(roundi(p.mass)), _short_drive(p)], p.mass / max_mass],
		["0–100 km/h", ("%.1f s" % sprint).replace(".", ",") if sprint > 0.0 else "–",
			best_sprint / sprint if sprint > 0.0 else 0.0],
		["Spitze", "%d km/h" % roundi(_top_speed(p)), _top_speed(p) / max_top],
	]
	for i in rows.size():
		(_bars[i][0] as Label).text = rows[i][0]
		(_bars[i][1] as Label).text = rows[i][1]
		(_bars[i][2] as Bar).ratio = rows[i][2]
		(_bars[i][2] as Bar).queue_redraw()


## „Allrad (M xDrive, heckbetont)“ → „Allrad“
func _short_drive(p: CarProfile) -> String:
	return p.drive_text.get_slice(" (", 0)


func _top_speed(p: CarProfile) -> float:
	return p.measured_top_kmh if p.measured_top_kmh > 0.0 else p.top_speed_kmh


func _thousands(value: int) -> String:
	var text := str(value)
	return text if text.length() <= 3 else text.substr(0, text.length() - 3) + "." + text.substr(text.length() - 3)


func _fill_paint() -> void:
	for child in _paint_row.get_children():
		child.queue_free()
	var p := cars[_selected]
	for i in p.paint_colors.size():
		var swatch := Swatch.new(p.paint_colors[i], 40.0)
		swatch.selected = i == _paint
		swatch.pressed.connect(_set_paint.bind(i))
		_paint_row.add_child(swatch)


func _fill_accents() -> void:
	for child in _accent_row.get_children():
		child.queue_free()
	for i in UiStyle.ACCENTS.size():
		var swatch := Swatch.new(UiStyle.ACCENTS[i], 24.0)
		swatch.selected = i == _accent_index
		swatch.pressed.connect(_set_accent.bind(i))
		_accent_row.add_child(swatch)


func _select_segment(buttons: Array[Button], index: int) -> void:
	for i in buttons.size():
		var chosen := i == index
		var style := UiStyle.box(Color.WHITE if chosen else Color(0, 0, 0, 0), 11)
		for state in ["normal", "hover", "pressed", "focus"]:
			buttons[i].add_theme_stylebox_override(state, style if chosen or state == "normal" or state == "focus"
				else UiStyle.box(Color(1, 1, 1, 0.08), 11))
		buttons[i].add_theme_color_override("font_color", DARK_TEXT if chosen else Color(1, 1, 1, 0.8))
		buttons[i].add_theme_color_override("font_hover_color", DARK_TEXT if chosen else Color.WHITE)
		buttons[i].add_theme_color_override("font_pressed_color", DARK_TEXT)
		buttons[i].add_theme_font_override("font", UiStyle.font("semibold" if chosen else "medium"))


# ---------------------------------------------------------------------------
# Oberfläche bauen
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Ziehen mit der Maus im freien Bereich dreht die Kamera
	_root.mouse_filter = Control.MOUSE_FILTER_PASS
	_root.gui_input.connect(_on_background_input)
	add_child(_root)
	_build_panel()
	_build_cards()
	_credits = _build_overlay("Credits")
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.add_theme_font_override("normal_font", UiStyle.font("regular"))
	text.add_theme_font_override("bold_font", UiStyle.font("semibold"))
	text.add_theme_font_size_override("normal_font_size", 15)
	text.add_theme_font_size_override("bold_font_size", 15)
	var credits := "Automodelle (von Sketchfab, für das Spiel verändert: skaliert, Räder getrennt, Teile ausgeblendet, eigene Materialien):\n\n"
	for profile in cars:
		credits += "[b]%s[/b] (%s)\n%s\n\n" % [profile.display_name, profile.subtitle, profile.credit]
	credits += "Schrift: Inter von Rasmus Andersson und The Inter Project Authors (SIL Open Font License 1.1).\n"
	credits += "Texturen: Poly Haven (CC0). Alles andere: im Spiel selbst erzeugt."
	text.text = credits
	_credits.get_meta("content").add_child(text)
	_collection = _build_overlay("Sammlung")
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_collection.get_meta("content").add_child(scroll)
	collection_list = VBoxContainer.new()
	collection_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	collection_list.add_theme_constant_override("separation", 12)
	scroll.add_child(collection_list)
	collection_list.add_child(UiStyle.label("Noch keine Aussichtspunkte entdeckt. Halte an einem an (Schild „Aussichtspunkt“).",
		15, "regular", UiStyle.TEXT_DIM))


func _build_panel() -> void:
	var panel := Control.new()
	panel.position = PANEL_RECT.position
	panel.size = PANEL_RECT.size
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(panel)
	var glass := GlassPanel.new()
	glass.radius = 28.0
	glass.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(glass)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 33)
	margin.add_theme_constant_override("margin_top", 34)
	margin.add_theme_constant_override("margin_bottom", 28)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	margin.add_child(box)

	var heading := UiStyle.label("GARAGE", 13, "semibold", UiStyle.accent, 2)
	box.add_child(heading)
	_name_label = UiStyle.label("", 38, "extrabold")
	box.add_child(_name_label)
	_subtitle_label = UiStyle.label("", 17, "regular", UiStyle.TEXT_DIM)
	box.add_child(_subtitle_label)
	_spacer(box, 14)
	for i in 5:
		var row := HBoxContainer.new()
		var name_label := UiStyle.label("", 16, "regular", Color(1, 1, 1, 0.85))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var value_label := UiStyle.label("", 16, "semibold")
		row.add_child(value_label)
		box.add_child(row)
		_spacer(box, 6)
		var bar := Bar.new()
		box.add_child(bar)
		_spacer(box, 12)
		_bars.append([name_label, value_label, bar])
	_spacer(box, 4)
	box.add_child(UiStyle.label("LACK", 13, "semibold", UiStyle.TEXT_DIM, 2))
	_spacer(box, 6)
	_paint_row = HBoxContainer.new()
	_paint_row.add_theme_constant_override("separation", 8)
	box.add_child(_paint_row)
	_spacer(box, 12)
	# HUD-Farbe und Sportauspuff in einer Zeile
	var extras := HBoxContainer.new()
	box.add_child(extras)
	var accent_box := VBoxContainer.new()
	accent_box.add_theme_constant_override("separation", 4)
	accent_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	accent_box.add_child(UiStyle.label("HUD-FARBE", 13, "semibold", UiStyle.TEXT_DIM, 2))
	_accent_row = HBoxContainer.new()
	_accent_row.add_theme_constant_override("separation", 6)
	accent_box.add_child(_accent_row)
	extras.add_child(accent_box)
	var exhaust_box := VBoxContainer.new()
	exhaust_box.add_theme_constant_override("separation", 8)
	exhaust_box.add_child(UiStyle.label("SPORTAUSPUFF", 13, "semibold", UiStyle.TEXT_DIM, 2))
	_exhaust_toggle = Toggle.new()
	_exhaust_toggle.toggled.connect(func(on: bool) -> void:
		sport_exhaust = on
		if car:
			car.sport_exhaust = on)
	var toggle_row := HBoxContainer.new()
	toggle_row.alignment = BoxContainer.ALIGNMENT_END
	toggle_row.add_child(_exhaust_toggle)
	exhaust_box.add_child(toggle_row)
	extras.add_child(exhaust_box)
	_spacer(box, 14)
	box.add_child(UiStyle.label("WELT", 13, "semibold", UiStyle.TEXT_DIM, 2))
	_spacer(box, 8)
	_time_buttons = _segmented(box, TIME_NAMES, _set_time)
	_spacer(box, 8)
	_weather_buttons = _segmented(box, WEATHER_NAMES, _set_weather)
	_spacer(box, 8)
	_season_buttons = _segmented(box, Weather.SEASON_NAMES, _set_season)
	_spacer(box, 18)
	_drive_button = Button.new()
	_drive_button.text = "Losfahren  →"
	_drive_button.custom_minimum_size = Vector2(0.0, 56.0)
	_drive_button.focus_mode = Control.FOCUS_NONE
	_drive_button.add_theme_font_override("font", UiStyle.font("semibold"))
	_drive_button.add_theme_font_size_override("font_size", 20)
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		_drive_button.add_theme_color_override(state, DARK_TEXT)
	_drive_button.pressed.connect(close.bind(true))
	box.add_child(_drive_button)
	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(filler)
	# Unten: Credits, Sammlung, Tastenhinweise
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	box.add_child(bottom)
	bottom.add_child(_outline_button("Credits", func() -> void: _credits.visible = true))
	bottom.add_child(_outline_button("Sammlung", func() -> void: _collection.visible = true))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(gap)
	for hint: Array in [["Enter", "fahren"], ["Esc", "zurück"]]:
		var key := UiStyle.label(hint[0], 13, "semibold")
		key.add_theme_stylebox_override("normal", _key_style())
		key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bottom.add_child(key)
		var word := UiStyle.label(hint[1], 14, "regular", UiStyle.TEXT_DIM)
		word.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bottom.add_child(word)


func _build_cards() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_root.add_child(row)
	for i in cars.size():
		var p := cars[i]
		var card := CarCard.new()
		card.title = p.display_name.trim_prefix("BMW ")
		card.subtitle = "%d PS · %s" % [p.power_ps, _short_drive(p)]
		card.available = CarModel.is_available(p)
		card.pressed.connect(_pick_car.bind(i))
		row.add_child(card)
		_cards.append(card)
	# Rechts unten ausrichten (40 Punkte Rand)
	row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 40)


## Umschalter mit mehreren Feldern nebeneinander; gibt die Knöpfe zurück
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


func _outline_button(text: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0.0, 42.0)
	button.add_theme_font_override("font", UiStyle.font("medium"))
	button.add_theme_font_size_override("font_size", 15)
	var normal := UiStyle.box(Color(0, 0, 0, 0), 12, Color(1, 1, 1, 0.22), 1)
	normal.set_content_margin_all(14)
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(1, 1, 1, 0.08)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_color_override("font_color", UiStyle.TEXT)
	button.pressed.connect(on_press)
	return button


func _key_style() -> StyleBoxFlat:
	var style := UiStyle.box(Color(1, 1, 1, 0.06), 6, Color(1, 1, 1, 0.3), 1)
	style.content_margin_left = 7
	style.content_margin_right = 7
	style.content_margin_top = 2
	style.content_margin_bottom = 3
	return style


func _spacer(parent: Control, height: float) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, height)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(spacer)


## Glas-Fenster in der Mitte (Credits, Sammlung) mit Titel und „Schließen“.
## Der Inhalt kommt in die VBox aus get_meta("content").
func _build_overlay(title: String) -> Control:
	var overlay := Control.new()
	overlay.size = Vector2(920.0, 600.0)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var glass := GlassPanel.new()
	glass.radius = 28.0
	glass.tint = Color(UiStyle.GLASS, 0.82)
	glass.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(glass)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	overlay.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	margin.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	var title_label := UiStyle.label(title, 26, "extrabold")
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)
	header.add_child(_outline_button("Schließen", func() -> void: overlay.visible = false))
	overlay.set_meta("content", box)
	overlay.visible = false
	add_child(overlay)
	return overlay


func _on_background_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse and mouse.button_index == MOUSE_BUTTON_LEFT:
		_dragging = mouse.pressed
	var motion := event as InputEventMouseMotion
	if motion and _dragging:
		_orbit_angle -= motion.relative.x * 0.008
