extends Control
## Minimap unten links (Entwurf „Glas“): dunkle Karte in einem Glas-Panel mit runden Ecken.
## Sie dreht sich mit dem Auto (Fahrtrichtung oben), das Auto sitzt etwas unterhalb der Mitte,
## damit man mehr vom Weg voraus sieht. Je schneller, desto weiter zoomt sie heraus.
## Die „N“-Plakette am Rand zeigt nach Norden. Darunter Strecke und Zeit bis zum Ziel.

@export var car: Car
@export var roads: RoadNetwork
@export var navigation: Navigation
@export var tiles: MapTiles
@export var viewpoints: Viewpoints
## Maßstab im Stand und bei hohem Tempo (Meter pro Pixel)
@export var slow_meters_per_pixel: float = 1.6
@export var fast_meters_per_pixel: float = 5.0
## Ab diesem Tempo ist ganz herausgezoomt
@export var full_zoom_speed_kmh: float = 180.0
## Das Auto sitzt so weit unten in der Karte (0,5 = Mitte)
@export var car_height: float = 0.72

const MAP_RECT := Rect2(8.0, 8.0, 296.0, 250.0)
const MAP_RADIUS: int = 20

var _map: MapView
var _overlay: Control
var _meters_per_pixel: float = 1.6
var _info: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glass := GlassPanel.new()
	glass.radius = 28.0
	glass.blur = 0.0
	glass.set_anchors_preset(Control.PRESET_FULL_RECT)
	glass.show_behind_parent = true
	add_child(glass)
	# Runde Ecken: ein Panel mit abgerundeter Form schneidet die Karte zu
	var mask := Panel.new()
	mask.position = MAP_RECT.position
	mask.size = MAP_RECT.size
	mask.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mask.add_theme_stylebox_override("panel", UiStyle.box(Color.WHITE, MAP_RADIUS))
	add_child(mask)
	_map = MapView.new()
	_map.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map.car = car
	_map.roads = roads
	_map.tiles = tiles
	_map.viewpoints = viewpoints
	if navigation:
		_map.set_navigation(navigation)
	mask.add_child(_map)
	# Die N-Plakette liegt über der Karte
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)


func _process(delta: float) -> void:
	if car == null:
		return
	# Zoom nach Tempo, weich nachgeführt
	var t := clampf(car.linear_velocity.length() * 3.6 / full_zoom_speed_kmh, 0.0, 1.0)
	_meters_per_pixel = lerpf(_meters_per_pixel, lerpf(slow_meters_per_pixel, fast_meters_per_pixel, t),
		clampf(delta * 1.5, 0.0, 1.0))
	var forward := Vector2(car.global_basis.z.x, car.global_basis.z.z).normalized()
	# Mitte der Karte ein Stück vor dem Auto, damit das Auto unten sitzt
	var ahead := (car_height - 0.5) * MAP_RECT.size.y * _meters_per_pixel
	_map.center = Vector2(car.global_position.x, car.global_position.z) + forward * ahead
	_map.meters_per_pixel = _meters_per_pixel
	# Fahrtrichtung zeigt nach oben
	_map.rotation_angle = -PI * 0.5 - forward.angle()
	_map.queue_redraw()
	_overlay.queue_redraw()
	var info := "Ziel auf der Karte setzen"
	if navigation and navigation.has_target and not navigation.route_points.is_empty():
		var minutes := maxi(roundi(navigation.remaining_minutes()), 1)
		var time := "%d min" % minutes if minutes < 60 else "%d h %02d min" % [floori(minutes / 60.0), minutes % 60]
		info = "%s · %s" % [Navigation.format_distance(navigation.remaining_distance()), time]
	if info != _info:
		_info = info
		queue_redraw()


func _draw() -> void:
	var has_route := not _info.begins_with("Ziel auf")
	UiStyle.draw_text(self, _info, Vector2(18.0, 286.0), 15 if has_route else 13,
		"semibold" if has_route else "medium", UiStyle.TEXT if has_route else UiStyle.TEXT_DIM)
	UiStyle.draw_text(self, "M Karte", Vector2(size.x - 18.0, 286.0), 13, "medium", UiStyle.TEXT_DIM, 1.0)


## „N“-Plakette am Kartenrand, in Richtung Norden (-z)
func _draw_overlay() -> void:
	var north := Vector2(0.0, -1.0).rotated(_map.rotation_angle)
	var half := MAP_RECT.size * 0.5 - Vector2(22.0, 22.0)
	var reach := minf(half.x / maxf(absf(north.x), 0.001), half.y / maxf(absf(north.y), 0.001))
	var pos := MAP_RECT.get_center() + north * reach
	_overlay.draw_circle(pos, 14.0, Color(0.06, 0.08, 0.11, 0.92))
	_overlay.draw_arc(pos, 14.0, 0.0, TAU, 24, Color(1, 1, 1, 0.25), 1.0, true)
	UiStyle.draw_text(_overlay, "N", pos + Vector2(0.0, 5.0), 14, "semibold", UiStyle.TEXT, 0.5)
