class_name Garage
extends CanvasLayer
## Die Garage: Auto auswählen, Lackfarbe, Daten, 3D-Vorschau in einem kleinen Showroom.
## Öffnet beim Spielstart und mit G. Solange sie offen ist, pausiert das Spiel (die Welt
## lädt im Hintergrund weiter). Auto und Farbe werden in user:// gespeichert.
##
## Bedienung: Maus, oder Pfeil hoch/runter = Auto, links/rechts = Farbe,
## Enter = Losfahren, Esc = zurück ohne Wechsel.

## Wird gesendet, wenn die Garage geschlossen wurde
signal closed

## Das Auto in der Welt
@export var car: Car
## Alle Autos (Profile), in dieser Reihenfolge in der Liste
@export var cars: Array[CarProfile] = []
## Umdrehungen pro Minute der Drehscheibe in der Vorschau
@export var turntable_rpm: float = 2.5

const SETTINGS_PATH := "user://einstellungen.cfg"

var is_open: bool = false
## Wurde schon einmal losgefahren? (Beim Start gibt es kein „Zurück“)
var _has_driven: bool = false
var _selected: int = 0
var _paint: int = 0
var _list: ItemList
var _preview_root: Node3D
var _preview_model: CarModel
var _turntable: Node3D
var _name_label: Label
var _subtitle_label: Label
var _loading_label: Label
var _data_grid: GridContainer
var _colors: HBoxContainer
var _credits: PanelContainer
var _drive_button: Button
var _extra_row: HBoxContainer
var _drag_speed: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_build_ui()
	visible = false
	_load_settings()


## Gespeicherte Wahl gleich aufs Auto anwenden (auch wenn die Garage beim Start nicht aufgeht)
func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	var id: String = config.get_value("garage", "car", "")
	for i in cars.size():
		if cars[i].id == id and CarModel.is_available(cars[i]):
			_selected = i
	_paint = config.get_value("garage", "paint", 0)
	if car and cars.size() > 0 and car.profile != cars[_selected]:
		car.apply_profile(cars[_selected])
	_apply_paint_to_car()


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("garage", "car", cars[_selected].id)
	config.set_value("garage", "paint", _paint)
	config.save(SETTINGS_PATH)


## Weitere Einstellungen (z. B. Wetter) können sich hier anhängen
func add_setting_row(control: Control) -> void:
	_extra_row.add_child(control)


func open() -> void:
	if is_open:
		return
	is_open = true
	visible = true
	get_tree().paused = true
	# Das Auto vorauswählen, das gerade fährt
	for i in cars.size():
		if car and cars[i] == car.profile:
			_selected = i
	_list.select(_selected)
	_list.ensure_current_is_visible()
	_list.grab_focus()
	_show_selected()


## Garage schließen. drive = true: gewähltes Auto übernehmen
func close(drive: bool) -> void:
	if not is_open:
		return
	if drive:
		_take_car()
	is_open = false
	visible = false
	_has_driven = true
	# Das Vorschau-Auto freigeben: Nur das gefahrene Auto bleibt geladen
	_preview_model.clear()
	get_tree().paused = false
	closed.emit()


func _take_car() -> void:
	var profile := cars[_selected]
	if car.profile != profile:
		# Gleiche Stelle, aufrecht und etwas angehoben: dort steht das neue Auto
		var spot := Transform3D(Basis(Vector3.UP, atan2(car.global_basis.z.x, car.global_basis.z.z)),
			car.global_position + Vector3.UP * 0.6)
		car.apply_profile(profile)
		car.teleport(spot)
	_apply_paint_to_car()
	_save_settings()


func _apply_paint_to_car() -> void:
	var model := car.get_node_or_null("Model") as CarModel if car else null
	if model:
		model.set_paint(_paint)


func _unhandled_input(event: InputEvent) -> void:
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
		if _credits.visible:
			_credits.visible = false
		else:
			close(not _has_driven)
	elif event.is_action_pressed("ui_left"):
		_set_paint(_paint - 1)
	elif event.is_action_pressed("ui_right"):
		_set_paint(_paint + 1)
	else:
		return
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not is_open:
		return
	# Drehscheibe: langsam von selbst, mit der Maus schneller (klingt dann aus)
	_drag_speed = move_toward(_drag_speed, 0.0, delta * 3.0)
	_turntable.rotate_y((turntable_rpm / 60.0 * TAU + _drag_speed) * delta)
	_loading_label.visible = _preview_model.is_loading()


func _on_item_selected(index: int) -> void:
	if not CarModel.is_available(cars[index]):
		_list.select(_selected)
		return
	_selected = index
	_paint = 0
	_show_selected()


func _show_selected() -> void:
	var profile := cars[_selected]
	_paint = clampi(_paint, 0, maxi(profile.paint_colors.size() - 1, 0))
	_preview_model.show_profile(profile)
	# Die Reifen sollen genau auf dem Boden stehen
	var rest := Car.resting_wheel_center(profile, 0)
	_preview_root.position.y = profile.wheel_radius - rest.y
	_name_label.text = profile.display_name
	_subtitle_label.text = profile.subtitle
	_fill_data(profile)
	_fill_colors(profile)


func _on_preview_ready() -> void:
	_preview_model.set_paint(_paint)


func _set_paint(index: int) -> void:
	var count := cars[_selected].paint_colors.size()
	if count == 0:
		return
	_paint = wrapi(index, 0, count)
	_preview_model.set_paint(_paint)
	_fill_colors(cars[_selected])


# ---------------------------------------------------------------------------
# Daten und Farben
# ---------------------------------------------------------------------------

func _fill_data(p: CarProfile) -> void:
	for child in _data_grid.get_children():
		child.queue_free()
	var rows := [
		["Leistung", "%d PS (%d kW)" % [p.power_ps, roundi(p.max_power_kw)]],
		["Drehmoment", "%d Nm" % roundi(p.max_torque_nm)],
		["Gewicht", "%s kg" % _thousands(roundi(p.mass))],
		["Antrieb", p.drive_text],
		["Motor", p.engine_text],
		["Getriebe", p.gearbox_text],
		["0–100 km/h", ("%.1f s" % p.measured_0_100).replace(".", ",") if p.measured_0_100 > 0.0 else "–"],
		["Spitze", "%d km/h" % roundi(p.measured_top_kmh if p.measured_top_kmh > 0.0 else p.top_speed_kmh)],
		["Bremsweg 100–0", ("%.0f m" % p.measured_braking_m) if p.measured_braking_m > 0.0 else "–"],
	]
	for row: Array in rows:
		var key := Label.new()
		key.text = row[0]
		key.add_theme_color_override("font_color", Color(0.65, 0.68, 0.72))
		key.add_theme_font_size_override("font_size", 16)
		_data_grid.add_child(key)
		var value := Label.new()
		value.text = row[1]
		value.add_theme_font_size_override("font_size", 18)
		_data_grid.add_child(value)


func _thousands(value: int) -> String:
	var text := str(value)
	return text if text.length() <= 3 else text.substr(0, text.length() - 3) + "." + text.substr(text.length() - 3)


func _fill_colors(p: CarProfile) -> void:
	for child in _colors.get_children():
		if child is Button:
			child.queue_free()
	for i in p.paint_colors.size():
		var button := Button.new()
		button.custom_minimum_size = Vector2(38, 38)
		button.focus_mode = Control.FOCUS_NONE
		var style := StyleBoxFlat.new()
		style.bg_color = p.paint_colors[i]
		style.set_corner_radius_all(19)
		style.set_border_width_all(3 if i == _paint else 1)
		style.border_color = Color.WHITE if i == _paint else Color(1, 1, 1, 0.3)
		for state in ["normal", "hover", "pressed", "focus"]:
			button.add_theme_stylebox_override(state, style)
		button.pressed.connect(_set_paint.bind(i))
		_colors.add_child(button)


# ---------------------------------------------------------------------------
# Oberfläche bauen
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var background := PanelContainer.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.06, 0.065, 0.075, 0.97)
	background.add_theme_stylebox_override("panel", bg_style)
	add_child(background)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	background.add_child(margin)
	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 16)
	margin.add_child(main)
	# Kopfzeile
	var header := HBoxContainer.new()
	main.add_child(header)
	var title := Label.new()
	title.text = "Garage"
	title.add_theme_font_size_override("font_size", 36)
	header.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var credits_button := Button.new()
	credits_button.text = "Credits"
	credits_button.focus_mode = Control.FOCUS_NONE
	credits_button.pressed.connect(func() -> void: _credits.visible = not _credits.visible)
	header.add_child(credits_button)
	# Inhalt: links Liste, rechts Vorschau und Daten
	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 24)
	main.add_child(content)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 300
	content.add_child(left)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.add_theme_font_size_override("font_size", 20)
	_list.add_theme_constant_override("v_separation", 14)
	for profile in cars:
		var available := CarModel.is_available(profile)
		var index := _list.add_item(profile.display_name if available else "%s (Modell fehlt)" % profile.display_name)
		_list.set_item_tooltip(index, profile.subtitle)
		_list.set_item_disabled(index, not available)
		if not available:
			_list.set_item_custom_fg_color(index, Color(1, 1, 1, 0.35))
	_list.item_selected.connect(_on_item_selected)
	left.add_child(_list)
	var hint := Label.new()
	hint.text = "↑ ↓ Auto   ← → Farbe\nEnter losfahren   Esc zurück"
	hint.add_theme_color_override("font_color", Color(0.6, 0.62, 0.66))
	left.add_child(hint)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 12)
	content.add_child(right)
	right.add_child(_build_showroom())
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 16)
	right.add_child(name_row)
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 30)
	name_row.add_child(_name_label)
	_subtitle_label = Label.new()
	_subtitle_label.add_theme_color_override("font_color", Color(0.65, 0.68, 0.72))
	_subtitle_label.add_theme_font_size_override("font_size", 18)
	_subtitle_label.size_flags_vertical = Control.SIZE_SHRINK_END
	name_row.add_child(_subtitle_label)
	_data_grid = GridContainer.new()
	_data_grid.columns = 6
	_data_grid.add_theme_constant_override("h_separation", 18)
	_data_grid.add_theme_constant_override("v_separation", 6)
	right.add_child(_data_grid)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	right.add_child(bottom)
	_colors = HBoxContainer.new()
	_colors.add_theme_constant_override("separation", 8)
	var paint_label := Label.new()
	paint_label.text = "Lack"
	_colors.add_child(paint_label)
	bottom.add_child(_colors)
	_extra_row = HBoxContainer.new()
	_extra_row.add_theme_constant_override("separation", 10)
	_extra_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_extra_row.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_child(_extra_row)
	_drive_button = Button.new()
	_drive_button.text = "  Losfahren  "
	_drive_button.add_theme_font_size_override("font_size", 24)
	_drive_button.focus_mode = Control.FOCUS_NONE
	_drive_button.pressed.connect(close.bind(true))
	bottom.add_child(_drive_button)
	_build_credits(background)


## Kleiner Showroom: eigene 3D-Welt mit Boden, Licht und Drehscheibe
func _build_showroom() -> Control:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.gui_input.connect(_on_showroom_input)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.process_mode = Node.PROCESS_MODE_ALWAYS
	container.add_child(viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.035, 0.038, 0.045)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.58, 0.65)
	environment.ambient_light_energy = 0.7
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.glow_enabled = true
	# Spiegelungen auf dem glänzenden Boden (die Welt ist pausiert, das kostet hier nichts)
	environment.ssr_enabled = true
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	viewport.add_child(world_environment)
	# Boden: dunkel und glänzend
	var floor_mesh := CylinderMesh.new()
	floor_mesh.top_radius = 9.0
	floor_mesh.bottom_radius = 9.0
	floor_mesh.height = 0.05
	floor_mesh.radial_segments = 64
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.05, 0.05, 0.055)
	floor_material.roughness = 0.22
	floor_mesh.material = floor_material
	var floor_instance := MeshInstance3D.new()
	floor_instance.mesh = floor_mesh
	floor_instance.position.y = -0.025
	viewport.add_child(floor_instance)
	# Licht: weiches Hauptlicht von oben, zwei Kantenlichter
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-60, 30, 0)
	key.light_energy = 1.6
	key.shadow_enabled = true
	viewport.add_child(key)
	# Aufhelllicht von vorne (ohne Schatten), damit auch dunkle Lacke gut zu sehen sind
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 160, 0)
	fill.light_energy = 0.6
	fill.light_specular = 0.0
	viewport.add_child(fill)
	# Kantenlichter hoch über und hinter dem Auto (nicht im Bild, keine Flecken auf dem Boden)
	for setup: Array in [[Vector3(-6, 5, -5), Color(0.7, 0.8, 1.0)], [Vector3(6, 4.5, -3), Color(1.0, 0.9, 0.8)]]:
		var rim := OmniLight3D.new()
		rim.position = setup[0]
		rim.light_color = setup[1]
		rim.light_energy = 4.0
		rim.omni_range = 16.0
		# Keine Glanzpunkte: sonst spiegeln sich die Lampen als Flecken im Boden
		rim.light_specular = 0.0
		viewport.add_child(rim)
	var camera := Camera3D.new()
	camera.fov = 30.0
	var eye := Vector3(0, 1.9, 10.0)
	camera.transform = Transform3D(Basis.looking_at(Vector3(0, 0.6, 0) - eye), eye)
	viewport.add_child(camera)
	_turntable = Node3D.new()
	_turntable.rotation.y = deg_to_rad(-35)
	viewport.add_child(_turntable)
	_preview_root = Node3D.new()
	_turntable.add_child(_preview_root)
	_preview_model = CarModel.new()
	_preview_model.name = "Model"
	_preview_root.add_child(_preview_model)
	_preview_model.model_ready.connect(_on_preview_ready)
	_loading_label = Label.new()
	_loading_label.text = "Lädt …"
	_loading_label.position = Vector2(16, 12)
	container.add_child(_loading_label)
	return container


func _on_showroom_input(event: InputEvent) -> void:
	# Mit gedrückter Maustaste ziehen dreht das Auto
	if event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT:
		_turntable.rotate_y((event as InputEventMouseMotion).relative.x * 0.01)
		_drag_speed = 0.0


func _build_credits(parent: Control) -> void:
	_credits = PanelContainer.new()
	_credits.set_anchors_preset(Control.PRESET_CENTER)
	_credits.custom_minimum_size = Vector2(900, 520)
	_credits.position = -_credits.custom_minimum_size * 0.5
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.105, 0.12)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(24)
	_credits.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	_credits.add_child(box)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var credits := "[font_size=24]Credits[/font_size]\n\nAutomodelle (von Sketchfab, für das Spiel verändert: skaliert, Räder getrennt, Teile ausgeblendet, eigene Materialien):\n\n"
	for profile in cars:
		credits += "[b]%s[/b] (%s)\n%s\n\n" % [profile.display_name, profile.subtitle, profile.credit]
	credits += "Texturen: Poly Haven (CC0). Alles andere: im Spiel selbst erzeugt."
	text.text = credits
	box.add_child(text)
	var close_button := Button.new()
	close_button.text = "Schließen"
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	close_button.pressed.connect(func() -> void: _credits.visible = false)
	box.add_child(close_button)
	_credits.visible = false
	parent.add_child(_credits)
