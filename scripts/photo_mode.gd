class_name PhotoMode
extends CanvasLayer
## Fotomodus (Taste P): Das Spiel hält an, das HUD verschwindet, eine freie Kamera fliegt
## rund ums Auto (höchstens max_distance Meter weit, nicht durchs Gelände). Einstellbar:
## Zoom, Schärfe aufs Auto, Belichtung, Tageszeit und Filter. Die Leertaste speichert ein
## PNG in user://fotos, „O“ öffnet den Ordner im Finder.

@export var car: Car
@export var hud: CanvasLayer
## Meldungen (Toasts): beim Fotografieren kurz ausblenden
@export var messages: CanvasLayer
@export var day_night: DayNight
@export var viewpoints: Viewpoints
## Höchstens so weit darf die Kamera vom Auto weg (Meter)
@export var max_distance: float = 30.0
## Tempo der Kamera (m/s) und Mausempfindlichkeit
@export var move_speed: float = 8.0
@export var look_sensitivity: float = 0.005

const FILTERS: Array[String] = ["Neutral", "Warm", "Kühl", "S/W"]
const FOLDER := "user://fotos"
const PANEL_SIZE := Vector2(1100.0, 128.0)

var is_open: bool = false
var _camera: Camera3D
var _attributes: CameraAttributesPractical
var _filter_rect: ColorRect
var _panel: Control
var _yaw: float = 0.0
var _pitch: float = 0.0
var _filter: int = 0
var _exposure: float = 1.0
var _focus: bool = true
var _time_before: float = 12.0
var _hud_was_visible: bool = true
var _dragging: bool = false
var _photo_msec: int = -100000


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 25
	_camera = Camera3D.new()
	_camera.near = 0.05
	_camera.far = 30000.0
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_attributes = CameraAttributesPractical.new()
	_camera.attributes = _attributes
	add_child(_camera)
	# Filter: liest das fertige Bild und färbt es um
	_filter_rect = ColorRect.new()
	_filter_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_filter_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/photo_filter.gdshader")
	_filter_rect.material = material
	add_child(_filter_rect)
	# Bedienfeld unten in der Mitte (Glas, darf unscharf sein: das Spiel steht ja)
	_panel = Control.new()
	_panel.size = PANEL_SIZE
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_KEEP_SIZE, 36)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.draw.connect(_draw_panel)
	add_child(_panel)
	var glass := GlassPanel.new()
	glass.radius = 24.0
	glass.set_anchors_preset(Control.PRESET_FULL_RECT)
	glass.show_behind_parent = true
	_panel.add_child(glass)
	visible = false


func open() -> void:
	if is_open:
		return
	is_open = true
	visible = true
	get_tree().paused = true
	if hud:
		_hud_was_visible = hud.visible
		hud.visible = false
	# Start dort, wo die Fahrkamera gerade ist
	var current := get_viewport().get_camera_3d()
	if current:
		_camera.global_transform = current.global_transform
		_camera.fov = current.fov
	var euler := _camera.global_basis.get_euler()
	_pitch = euler.x
	_yaw = euler.y
	_camera.current = true
	_time_before = day_night.time_of_day if day_night else 12.0
	_exposure = 1.0
	_apply_settings()


## Filter wählen (0 = neutral, 1 = warm, 2 = kühl, 3 = schwarz-weiß)
func set_filter(index: int) -> void:
	_filter = clampi(index, 0, FILTERS.size() - 1)
	_apply_settings()


func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	_dragging = false
	_camera.current = false
	if day_night:
		day_night.set_time(_time_before)
	if hud:
		hud.visible = _hud_was_visible
	get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("photo_mode"):
		# Etwas anderes (Garage, große Karte) hat das Spiel angehalten: dann nicht
		if is_open:
			close()
		elif not get_tree().paused:
			open()
		get_viewport().set_input_as_handled()
		return
	var key := event as InputEventKey
	# „O“ öffnet den Foto-Ordner, auch kurz nach dem Verlassen des Fotomodus
	if key and key.pressed and not key.echo and key.physical_keycode == KEY_O \
			and (is_open or Time.get_ticks_msec() - _photo_msec < 8000):
		OS.shell_open(ProjectSettings.globalize_path(FOLDER))
		get_viewport().set_input_as_handled()
		return
	if not is_open:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT or button.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = button.pressed
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera.fov = maxf(_camera.fov - 3.0, 12.0)
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera.fov = minf(_camera.fov + 3.0, 90.0)
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		_yaw -= motion.relative.x * look_sensitivity
		_pitch = clampf(_pitch - motion.relative.y * look_sensitivity, -1.45, 1.45)
	elif key and key.pressed and not key.echo:
		match key.physical_keycode:
			KEY_1, KEY_2, KEY_3, KEY_4:
				_filter = key.physical_keycode - KEY_1
			KEY_F:
				_focus = not _focus
			KEY_SPACE:
				_take_photo()
			_:
				return
	else:
		return
	_apply_settings()
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not is_open or car == null:
		return
	# Bewegen: W/S vor und zurück in Blickrichtung, A/D seitlich, Q/E runter und rauf
	var basis := Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	var move := Vector3.ZERO
	move += -basis.z * (_axis(KEY_W, KEY_S))
	move += basis.x * (_axis(KEY_D, KEY_A))
	move += Vector3.UP * (_axis(KEY_E, KEY_Q))
	var target := _camera.global_position + move * move_speed * delta
	_camera.global_transform = Transform3D(basis, _constrain(target))
	# Pfeiltasten: Tageszeit (← →, 2 Stunden pro Sekunde) und Belichtung (↑ ↓)
	var time_step := _axis(KEY_RIGHT, KEY_LEFT)
	if time_step != 0.0 and day_night:
		day_night.set_time(day_night.time_of_day + time_step * 2.0 * delta)
	var exposure_step := _axis(KEY_UP, KEY_DOWN)
	if exposure_step != 0.0:
		_exposure = clampf(_exposure * pow(2.0, exposure_step * 1.5 * delta), 0.25, 4.0)
	_apply_settings()


func _axis(positive: Key, negative: Key) -> float:
	return (1.0 if Input.is_physical_key_pressed(positive) else 0.0) \
		- (1.0 if Input.is_physical_key_pressed(negative) else 0.0)


## Kamera höchstens max_distance vom Auto weg, nicht hinter Gelände oder Wänden und nicht
## unter dem Boden
func _constrain(target: Vector3) -> Vector3:
	var anchor := car.global_position + Vector3.UP * 0.8
	if target.distance_to(anchor) > max_distance:
		target = anchor + (target - anchor).normalized() * max_distance
	var space := car.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(anchor, target)
	query.exclude = [car.get_rid()]
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		target = (hit["position"] as Vector3) + (anchor - target).normalized() * 0.4
	var down := PhysicsRayQueryParameters3D.create(target + Vector3.UP * 30.0, target + Vector3.DOWN * 30.0)
	down.exclude = [car.get_rid()]
	var ground := space.intersect_ray(down)
	if not ground.is_empty():
		target.y = maxf(target.y, (ground["position"] as Vector3).y + 0.3)
	return target


## Schärfe, Belichtung und Filter auf Kamera und Filterfläche übertragen
func _apply_settings() -> void:
	var distance := _camera.global_position.distance_to(car.global_position) if car else 6.0
	_attributes.dof_blur_far_enabled = _focus
	_attributes.dof_blur_near_enabled = _focus
	_attributes.dof_blur_far_distance = distance + 3.0
	_attributes.dof_blur_far_transition = maxf(distance, 6.0)
	_attributes.dof_blur_near_distance = maxf(distance - 3.0, 0.3)
	_attributes.dof_blur_near_transition = 1.5
	_attributes.dof_blur_amount = 0.08
	_attributes.exposure_multiplier = _exposure
	_filter_rect.visible = _filter != 0
	(_filter_rect.material as ShaderMaterial).set_shader_parameter("mode", _filter)
	_panel.queue_redraw()


func _take_photo() -> void:
	# Ein Bild ohne Bedienfeld und Meldungen rendern lassen, dann speichern
	_panel.visible = false
	if messages:
		messages.visible = false
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	_panel.visible = true
	if messages:
		messages.visible = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOLDER))
	var t := Time.get_datetime_dict_from_system()
	var path := "%s/foto_%04d-%02d-%02d_%02d-%02d-%02d.png" % [FOLDER, t.year, t.month, t.day, t.hour, t.minute, t.second]
	var number := 2
	while FileAccess.file_exists(path):
		path = "%s/foto_%04d-%02d-%02d_%02d-%02d-%02d_%d.png" % [FOLDER, t.year, t.month, t.day, t.hour, t.minute,
			t.second, number]
		number += 1
	image.save_png(path)
	_photo_msec = Time.get_ticks_msec()
	if viewpoints:
		viewpoints.photo_saved(path, car.global_position)
	Toasts.post(get_tree(), "camera", "Foto gespeichert", path.get_file(), "O", "Ordner öffnen")


## Brennweite wie bei einer Kleinbildkamera (aus dem senkrechten Bildwinkel)
func _focal_length() -> float:
	return 12.0 / tan(deg_to_rad(_camera.fov) * 0.5)


func _draw_panel() -> void:
	var y_title := 34.0
	var y_value := 66.0
	# Filter als Segmente
	var x := 28.0
	UiStyle.draw_text(_panel, "FILTER  1–4", Vector2(x, y_title), 12, "semibold", UiStyle.TEXT_DIM, 0.0, 1)
	for i in FILTERS.size():
		var width := UiStyle.text_width(FILTERS[i], 15, "medium") + 24.0
		var rect := Rect2(x, y_value - 22.0, width, 32.0)
		if i == _filter:
			UiStyle.draw_box(_panel, rect, UiStyle.accent, 9)
		else:
			UiStyle.draw_box(_panel, rect, Color(1, 1, 1, 0.06), 9, Color(1, 1, 1, 0.14), 1)
		UiStyle.draw_text(_panel, FILTERS[i], Vector2(rect.get_center().x, y_value), 15, "medium", UiStyle.TEXT, 0.5)
		x += width + 8.0
	# Werte mit Tasten
	var hour := day_night.time_of_day if day_night else 12.0
	var minutes := roundi(hour * 60.0) % (24 * 60)
	var columns := [
		["BELICHTUNG  ↑ ↓", ("%+.1f EV" % (log(_exposure) / log(2.0))).replace(".", ",")],
		["TAGESZEIT  ← →", "%02d:%02d" % [floori(minutes / 60.0), minutes % 60]],
		["SCHÄRFE  F", "Auf das Auto" if _focus else "Aus"],
		["ZOOM  Mausrad", "%d mm" % roundi(_focal_length())],
	]
	x += 28.0
	for column: Array in columns:
		UiStyle.draw_text(_panel, column[0], Vector2(x, y_title), 12, "semibold", UiStyle.TEXT_DIM, 0.0, 1)
		UiStyle.draw_text(_panel, column[1], Vector2(x, y_value), 19, "semibold", UiStyle.TEXT)
		x += 170.0
	# Hinweise unten
	_panel.draw_line(Vector2(24.0, 88.0), Vector2(PANEL_SIZE.x - 24.0, 88.0), Color(1, 1, 1, 0.12), 1.0)
	UiStyle.draw_text(_panel, "Maus ziehen: schwenken   ·   W A S D, Q E: bewegen   ·   Leertaste: Foto   ·   O: Ordner   ·   P / Esc: zurück",
		Vector2(PANEL_SIZE.x * 0.5, 114.0), 14, "regular", UiStyle.TEXT_DIM, 0.5)
