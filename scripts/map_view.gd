class_name MapView
extends Control
## Zeichnet die Karte: Gelände-Kacheln (MapTiles), Straßen, Route, Ziel und Auto.
## Wird von der Minimap (dreht sich mit dem Auto) und der großen Karte benutzt.
## Gezeichnet wird in Weltkoordinaten (Meter, x/z); eine Transform rechnet sie auf den
## Bildschirm um. So müssen die Straßenlinien nicht in jedem Bild umgerechnet werden.

var tiles: MapTiles
var roads: RoadNetwork
var navigation: Navigation
var car: Car
## Mitte der Ansicht (Welt x/z), Meter pro Pixel, Drehung der Karte (Bogenmaß)
var center: Vector2 = Vector2.ZERO
var meters_per_pixel: float = 2.0
var rotation_angle: float = 0.0
## Große Karte: Orte und noch nicht berechnete Verbindungen gestrichelt zeigen
var show_unknown: bool = false

const ROAD_COLOR := Color(0.93, 0.92, 0.88)
const ROAD_EDGE := Color(0.15, 0.15, 0.16)
const ROUTE_COLOR := Color(0.2, 0.6, 1.0)
const UNKNOWN_COLOR := Color(0.95, 0.95, 0.95, 0.55)
const TUNNEL_COLOR := Color(0.78, 0.76, 0.72)

## Ausgedünnte Straßenlinien pro Abschnitt (Welt x/z), aufgeteilt in Stücke:
## [[Linie, true = Tunnel], ...]
var _road_lines: Dictionary = {}  # RoadSegment -> Array
var _route_line := PackedVector2Array()
var _route_known := PackedByteArray()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_navigation(nav: Navigation) -> void:
	navigation = nav
	navigation.route_changed.connect(_on_route_changed)


func _on_route_changed() -> void:
	_route_line = PackedVector2Array()
	for p in navigation.route_points:
		_route_line.append(Vector2(p.x, p.z))
	_route_known = navigation.route_known


func world_to_screen(p: Vector2) -> Vector2:
	return size * 0.5 + (p - center).rotated(rotation_angle) / meters_per_pixel


func screen_to_world(s: Vector2) -> Vector2:
	return center + ((s - size * 0.5) * meters_per_pixel).rotated(-rotation_angle)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.16, 0.18, 0.16))
	if roads == null or tiles == null:
		return
	var view := Transform2D(rotation_angle, size * 0.5) * Transform2D().scaled(Vector2.ONE / meters_per_pixel) \
		* Transform2D(0.0, -center)
	draw_set_transform_matrix(view)
	var radius := size.length() * 0.5 * meters_per_pixel
	var view_rect := Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
	_draw_tiles(view_rect)
	if show_unknown:
		_draw_places(view_rect)
	_draw_roads(view_rect)
	_draw_route()
	draw_set_transform_matrix(Transform2D.IDENTITY)
	_draw_markers()


func _draw_tiles(view_rect: Rect2) -> void:
	var level := tiles.level_for(meters_per_pixel)
	var tile_size: float = tiles.level_sizes[level]
	for tz in range(floori(view_rect.position.y / tile_size), floori(view_rect.end.y / tile_size) + 1):
		for tx in range(floori(view_rect.position.x / tile_size), floori(view_rect.end.x / tile_size) + 1):
			var texture := tiles.get_tile(level, tx, tz)
			var rect := Rect2(tx * tile_size, tz * tile_size, tile_size, tile_size)
			if texture == null and level + 1 < tiles.level_sizes.size():
				# Noch nicht fertig: solange die gröbere Stufe zeigen
				var coarse_size: float = tiles.level_sizes[level + 1]
				var cx := floori(rect.position.x / coarse_size)
				var cz := floori(rect.position.y / coarse_size)
				var coarse := tiles.get_tile(level + 1, cx, cz)
				if coarse:
					var region := Rect2((rect.position - Vector2(cx, cz) * coarse_size) / coarse_size * tiles.tile_pixels,
						Vector2.ONE * tile_size / coarse_size * tiles.tile_pixels)
					draw_texture_rect_region(coarse, rect, region)
				continue
			if texture:
				draw_texture_rect(texture, rect, false)


func _draw_roads(view_rect: Rect2) -> void:
	var width := maxf(9.0, 2.5 * meters_per_pixel)
	var lines: Array[PackedVector2Array] = []
	var tunnels: Array[PackedVector2Array] = []
	for pair: Array in roads.loaded_segments(view_rect):
		var segment: RoadSegment = pair[1]
		if not _road_lines.has(segment):
			_road_lines[segment] = _split_line(segment)
		for part: Array in _road_lines[segment]:
			if part[1]:
				tunnels.append(part[0])
			else:
				lines.append(part[0])
	# Erst alle dunklen Ränder, dann alle hellen Fahrbahnen (sonst überdecken sich Kreuzungen)
	for line in lines:
		draw_polyline(line, ROAD_EDGE, width * 1.6, true)
	for line in lines:
		draw_polyline(line, ROAD_COLOR, width, true)
	# Tunnel gestrichelt
	var dash := maxf(25.0, 7.0 * meters_per_pixel)
	for line in tunnels:
		_draw_dashed_polyline(line, ROAD_EDGE, width * 1.6, dash)
		_draw_dashed_polyline(line, TUNNEL_COLOR, width, dash)
	# Gemerkte Linien von Abschnitten, die es nicht mehr gibt, vergessen
	if _road_lines.size() > lines.size() + 200:
		_road_lines.clear()


## Linie eines Abschnitts (jeder dritte Punkt), in Stücke geteilt: draußen und im Tunnel
func _split_line(segment: RoadSegment) -> Array:
	var parts: Array = []
	var line := PackedVector2Array()
	var in_tunnel := false
	var n := segment.points.size()
	var i := 0
	while i < n:
		var here := segment.tunnel[i] == 1
		if here != in_tunnel and not line.is_empty():
			line.append(Vector2(segment.points[i].x, segment.points[i].z))
			parts.append([line, in_tunnel])
			line = PackedVector2Array()
		in_tunnel = here
		line.append(Vector2(segment.points[i].x, segment.points[i].z))
		# Normal jeden dritten Punkt, aber kein Tunnelanfang oder -ende überspringen
		var next := mini(i + 3, n - 1) if i < n - 1 else n
		for k in range(i + 1, mini(next, n)):
			if (segment.tunnel[k] == 1) != in_tunnel:
				next = k
				break
		i = next
	if line.size() >= 2:
		parts.append([line, in_tunnel])
	return parts


## Orte und noch nicht berechnete Verbindungen (große Karte)
func _draw_places(view_rect: Rect2) -> void:
	var cell_size := roads.cell_size
	var dash := maxf(20.0, 8.0 * meters_per_pixel)
	for cz in range(floori(view_rect.position.y / cell_size) - 1, floori(view_rect.end.y / cell_size) + 1):
		for cx in range(floori(view_rect.position.x / cell_size) - 1, floori(view_rect.end.x / cell_size) + 1):
			var cell := Vector2i(cx, cz)
			var node: Variant = roads.node_at(cell)
			if node == null:
				continue
			var p := Vector2((node as Vector3).x, (node as Vector3).z)
			for option: Array in roads.edges_at(cell):
				if not option[1]:
					continue
				var key: Vector3i = option[0]
				if roads.edge_status(key) != 0:
					continue
				var other: Vector3 = roads.node_at(roads.edge_end_cell(key))
				draw_dashed_line(p, Vector2(other.x, other.z), UNKNOWN_COLOR, 2.0 * meters_per_pixel, dash)
			draw_circle(p, 4.0 * meters_per_pixel, Color(1, 1, 1, 0.8))


func _draw_route() -> void:
	if navigation == null or not navigation.has_target or _route_line.size() < 2:
		return
	var width := maxf(6.0, 4.0 * meters_per_pixel)
	var dash := maxf(15.0, 6.0 * meters_per_pixel)
	# Berechnete Stücke durchgezogen, geschätzte (Luftlinie) gestrichelt
	var start := 0
	for i in range(1, _route_line.size()):
		var known := _route_known[i] == 1
		var end_of_run := i == _route_line.size() - 1 or (_route_known[i + 1] == 1) != known
		if not end_of_run:
			continue
		var part := _route_line.slice(start, i + 1)
		if known:
			draw_polyline(part, ROUTE_COLOR, width, true)
		else:
			_draw_dashed_polyline(part, ROUTE_COLOR, width, dash)
		start = i


## Gestrichelte Linie über viele Punkte: Striche und Lücken laufen über die Punkte hinweg
func _draw_dashed_polyline(points: PackedVector2Array, color: Color, width: float, dash: float) -> void:
	var travelled := 0.0
	for j in points.size() - 1:
		var a := points[j]
		var b := points[j + 1]
		var length := a.distance_to(b)
		var t := 0.0
		while t < length:
			# Wie weit bis zum nächsten Wechsel zwischen Strich und Lücke?
			var phase := fmod(travelled + t, dash * 2.0)
			var step := minf((dash - phase) if phase < dash else (dash * 2.0 - phase), length - t)
			if phase < dash:
				draw_line(a.lerp(b, t / length), a.lerp(b, (t + step) / length), color, width, true)
			t += maxf(step, 0.01)
		travelled += length


func _draw_markers() -> void:
	# Ziel
	if navigation and navigation.has_target:
		var t := world_to_screen(Vector2(navigation.target.x, navigation.target.z))
		draw_circle(t, 9.0, Color(0.9, 0.15, 0.15))
		draw_arc(t, 9.0, 0.0, TAU, 24, Color.WHITE, 2.0, true)
	# Auto als Pfeil in Fahrtrichtung
	if car:
		var p := world_to_screen(Vector2(car.global_position.x, car.global_position.z))
		var forward := Vector2(car.global_basis.z.x, car.global_basis.z.z).normalized().rotated(rotation_angle)
		var side := Vector2(-forward.y, forward.x)
		var arrow := PackedVector2Array([p + forward * 11.0, p - forward * 7.0 + side * 7.0,
			p - forward * 3.0, p - forward * 7.0 - side * 7.0])
		draw_colored_polygon(arrow, Color(1.0, 0.75, 0.1))
		draw_polyline(arrow + PackedVector2Array([arrow[0]]), Color(0.1, 0.1, 0.1), 1.5, true)
