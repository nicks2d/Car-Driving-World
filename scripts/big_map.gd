class_name BigMap
extends CanvasLayer
## Große Karte (Taste M). Das Spiel pausiert, solange sie offen ist.
## Mausrad = zoomen (um den Mauszeiger), linke Maustaste ziehen = verschieben,
## Linksklick = Ziel setzen, Rechtsklick = Ziel löschen, M oder Esc = schließen.

@export var car: Car
@export var roads: RoadNetwork
@export var navigation: Navigation
@export var tiles: MapTiles
## Start-Maßstab und Grenzen (Meter pro Pixel)
@export var start_meters_per_pixel: float = 6.0
@export var min_meters_per_pixel: float = 1.0
@export var max_meters_per_pixel: float = 48.0

var is_open: bool = false
var _map: MapView
var _info: Label
var _dragging: bool = false
var _drag_distance: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 15
	var catcher := Control.new()
	catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	catcher.gui_input.connect(_on_map_input)
	add_child(catcher)
	_map = MapView.new()
	_map.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map.car = car
	_map.roads = roads
	_map.tiles = tiles
	_map.show_unknown = true
	if navigation:
		_map.set_navigation(navigation)
	catcher.add_child(_map)
	_info = Label.new()
	_info.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_info.position = Vector2(24, -60)
	_info.add_theme_font_size_override("font_size", 17)
	_info.add_theme_color_override("font_outline_color", Color.BLACK)
	_info.add_theme_constant_override("outline_size", 6)
	add_child(_info)
	visible = false


func open() -> void:
	is_open = true
	visible = true
	get_tree().paused = true
	_map.center = Vector2(car.global_position.x, car.global_position.z)
	_map.meters_per_pixel = start_meters_per_pixel


func close() -> void:
	is_open = false
	visible = false
	get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_map"):
		if is_open:
			close()
		elif not get_tree().paused:
			open()
		get_viewport().set_input_as_handled()
	elif is_open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not is_open:
		return
	_map.queue_redraw()
	var text := "Linksklick: Ziel setzen   Rechtsklick: Ziel löschen   Mausrad: zoomen   Ziehen: verschieben   M: schließen"
	if navigation.has_target and not navigation.route_points.is_empty():
		text = "Ziel: %s, ca. %d min      " % [("%.1f km" % (navigation.remaining_distance() / 1000.0)).replace(".", ","),
			maxi(roundi(navigation.remaining_minutes()), 1)] + text
	text += "\nGestrichelt: Verbindungen, die noch nicht berechnet sind (werden beim Hinfahren genau)"
	_info.text = text


func _on_map_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse:
		if mouse.button_index == MOUSE_BUTTON_WHEEL_UP or mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mouse.pressed:
				_zoom_at(mouse.position, 0.85 if mouse.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 0.85)
		elif mouse.button_index == MOUSE_BUTTON_LEFT:
			if mouse.pressed:
				_dragging = true
				_drag_distance = 0.0
			else:
				_dragging = false
				# Kaum bewegt: das war ein Klick, kein Verschieben
				if _drag_distance < 5.0:
					var p := _map.screen_to_world(mouse.position)
					navigation.set_target(Vector3(p.x, 0.0, p.y))
		elif mouse.button_index == MOUSE_BUTTON_RIGHT and mouse.pressed:
			navigation.clear_target()
	var motion := event as InputEventMouseMotion
	if motion and _dragging:
		_drag_distance += motion.relative.length()
		_map.center -= motion.relative * _map.meters_per_pixel


## Zoomen, ohne dass sich der Punkt unter der Maus bewegt
func _zoom_at(screen_position: Vector2, factor: float) -> void:
	var before := _map.screen_to_world(screen_position)
	_map.meters_per_pixel = clampf(_map.meters_per_pixel * factor, min_meters_per_pixel, max_meters_per_pixel)
	var after := _map.screen_to_world(screen_position)
	_map.center += before - after
