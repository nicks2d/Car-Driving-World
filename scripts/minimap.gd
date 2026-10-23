extends Control
## Runde Minimap unten links. Die Karte dreht sich mit dem Auto (Fahrtrichtung oben),
## je schneller das Auto, desto weiter zoomt sie heraus. „N“ am Rand zeigt nach Norden.

@export var car: Car
@export var roads: RoadNetwork
@export var navigation: Navigation
@export var tiles: MapTiles
## Radius der Minimap in Pixeln
@export var radius_px: float = 115.0
## Maßstab im Stand und bei hohem Tempo (Meter pro Pixel)
@export var slow_meters_per_pixel: float = 1.3
@export var fast_meters_per_pixel: float = 4.0
## Ab diesem Tempo ist ganz herausgezoomt
@export var full_zoom_speed_kmh: float = 180.0

var _map: MapView
var _north: Label
var _meters_per_pixel: float = 1.3


func _ready() -> void:
	custom_minimum_size = Vector2.ONE * radius_px * 2.0
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Runde Maske: Ein Panel mit ganz runden Ecken, das seine Kinder auf seine Form beschneidet
	var mask := Panel.new()
	mask.set_anchors_preset(Control.PRESET_FULL_RECT)
	mask.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var circle := StyleBoxFlat.new()
	circle.bg_color = Color.WHITE
	circle.set_corner_radius_all(int(radius_px))
	mask.add_theme_stylebox_override("panel", circle)
	add_child(mask)
	_map = MapView.new()
	_map.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map.car = car
	_map.roads = roads
	_map.tiles = tiles
	if navigation:
		_map.set_navigation(navigation)
	mask.add_child(_map)
	# Rand
	var ring := Panel.new()
	ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var border := StyleBoxFlat.new()
	border.bg_color = Color(0, 0, 0, 0)
	border.border_color = Color(0.05, 0.05, 0.06, 0.9)
	border.set_border_width_all(4)
	border.set_corner_radius_all(int(radius_px))
	ring.add_theme_stylebox_override("panel", border)
	add_child(ring)
	_north = Label.new()
	_north.text = "N"
	_north.add_theme_font_size_override("font_size", 16)
	_north.add_theme_color_override("font_outline_color", Color.BLACK)
	_north.add_theme_constant_override("outline_size", 5)
	add_child(_north)


func _process(delta: float) -> void:
	if car == null:
		return
	# Zoom nach Tempo, weich nachgeführt
	var t := clampf(car.linear_velocity.length() * 3.6 / full_zoom_speed_kmh, 0.0, 1.0)
	_meters_per_pixel = lerpf(_meters_per_pixel, lerpf(slow_meters_per_pixel, fast_meters_per_pixel, t),
		clampf(delta * 1.5, 0.0, 1.0))
	var forward := Vector2(car.global_basis.z.x, car.global_basis.z.z)
	_map.center = Vector2(car.global_position.x, car.global_position.z)
	_map.meters_per_pixel = _meters_per_pixel
	# Fahrtrichtung zeigt nach oben
	_map.rotation_angle = -PI * 0.5 - forward.angle()
	_map.queue_redraw()
	# „N“ am Rand in Richtung Norden (-z)
	var north := Vector2(0.0, -1.0).rotated(_map.rotation_angle)
	_north.position = size * 0.5 + north * (radius_px - 14.0) - _north.size * 0.5
