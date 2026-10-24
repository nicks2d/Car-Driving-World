class_name Navigation
extends Node
## Navi: plant eine Route über das Straßennetz zu einem Ziel und sagt die Abbiegungen an.
##
## Straßen sind nur in der Nähe des Autos berechnet (ca. 3 km). Welche Orte es gibt und
## welche verbunden sind, steht aber ohne Wegsuche fest (RoadNetwork). Deshalb wird über
## diesen Orts-Graphen geplant (A*): Berechnete Abschnitte zählen mit ihrer echten Länge,
## noch unbekannte mit Luftlinie mal unknown_length_factor. Sobald unterwegs Abschnitte
## fertig werden, wird die Route verfeinert. Fällt ein Abschnitt weg (zu steil, Überlappung)
## oder fährt man von der Route ab, wird neu geplant.
##
## Die Autobahn steckt mit im Graphen: Knoten sind ihre Stützpunkte, je Fahrtrichtung einer
## (Vector4i: Achse, Linie, k, Richtung +1/-1). Orte mit Anschlussstelle haben Auffahrten
## dorthin, Stützpunkte mit Anschlussstelle Ausfahrten zum Ort. Gezählt wird die Fahrzeit,
## deshalb nimmt das Navi die Autobahn, wenn sie schneller ist.

## Wird gesendet, wenn sich die Route geändert hat (neu geplant oder verfeinert)
signal route_changed
## Wird gesendet, wenn das Ziel erreicht ist
signal arrived

@export var roads: RoadNetwork
@export var car: Car
## Ab so viel Abstand zur Route (Meter) für off_route_time Sekunden wird neu geplant
@export var off_route_distance: float = 40.0
@export var off_route_time: float = 3.0
## So nah am Ziel gilt es als erreicht (Meter)
@export var arrive_distance: float = 30.0
## Für die geschätzte Fahrzeit und die Wahl zwischen Landstraße und Autobahn
@export var average_speed_kmh: float = 70.0
@export var highway_speed_kmh: float = 130.0
## Noch nicht berechnete Abschnitte sind so viel länger als die Luftlinie (Schätzung)
@export var unknown_length_factor: float = 1.35
## Klickt man so nah an eine fertige Straße, liegt das Ziel genau dort (sonst am nächsten Ort)
@export var snap_to_road_distance: float = 80.0

var has_target: bool = false
var target: Vector3 = Vector3.ZERO
## Die Route als Linie und pro Punkt: 1 = Straße schon berechnet, 0 = geschätzt (Luftlinie)
var route_points := PackedVector3Array()
var route_known := PackedByteArray()
## Kurze Meldung (z. B. „Ziel erreicht“), die das HUD anzeigt
var message: String = ""
var message_timer: float = 0.0
## Fahrt seit dem Setzen des Ziels (für „Ziel erreicht · 14,4 km in 11:48 min“)
var _trip_distance: float = 0.0
var _trip_seconds: float = 0.0

## Abstand vom Routenanfang bis zu jedem Punkt und geschätzte Fahrzeit bis dorthin (Sekunden)
var _route_distance := PackedFloat32Array()
var _route_time := PackedFloat32Array()
var _route_speed := PackedFloat32Array()
## Abbiegungen: [Index in route_points, Richtung (-3..3, positiv = links), Text, Zusatz]
## (Text leer = normale Abbiegung, sonst z. B. „Ausfahrt 14 nehmen“ mit Ortsname als Zusatz)
var _turns: Array = []
## Schritte: [Schlüssel, vorwärts, von, bis]. von/bis: Punkt-Nummer, Lage (Vector2, nächster
## Punkt) oder -1 (Ende des Abschnitts). Oder für eine Luftlinie: [null, Startpunkt, Zielpunkt]
var _steps: Array = []
## Orte mit Anschlussstelle: Vector2i -> Array von Vector3i (Achse, Linie, k)
var _interchange_cache: Dictionary = {}
var _progress: int = 0
var _off_route_timer: float = 0.0
var _refresh_timer: float = 0.0
var _known_steps: int = 0

const GOAL := Vector2i(2147483647, 2147483647)


## Ziel setzen (Weltposition, z. B. Klick auf der Karte) und Route planen
func set_target(world_position: Vector3) -> void:
	target = _snap_target(world_position)
	has_target = true
	_trip_distance = 0.0
	_trip_seconds = 0.0
	_plan()


func clear_target() -> void:
	has_target = false
	route_points = PackedVector3Array()
	route_known = PackedByteArray()
	_route_distance = PackedFloat32Array()
	_route_time = PackedFloat32Array()
	_turns.clear()
	_steps.clear()
	route_changed.emit()


## Restliche Strecke in Metern
func remaining_distance() -> float:
	if route_points.is_empty():
		return 0.0
	var here := car.global_position
	return _route_distance[_route_distance.size() - 1] - _route_distance[_progress] \
		+ Vector2(here.x - route_points[_progress].x, here.z - route_points[_progress].z).length()


## Geschätzte Fahrzeit in Minuten (Autobahn schneller als Landstraße)
func remaining_minutes() -> float:
	if route_points.is_empty():
		return 0.0
	var here := car.global_position
	var to_route := Vector2(here.x - route_points[_progress].x, here.z - route_points[_progress].z).length()
	var seconds := _route_time[_route_time.size() - 1] - _route_time[_progress] + to_route / (average_speed_kmh / 3.6)
	return seconds / 60.0


## Nächste Abbiegung: {"direction": -3..3 (positiv = links), "distance": Meter, "text": eigene
## Ansage oder leer, "detail": Zusatz (Ortsname)} oder leer
func next_turn() -> Dictionary:
	for turn: Array in _turns:
		if turn[0] > _progress:
			return {"direction": turn[1], "distance": _route_distance[turn[0]] - _route_distance[_progress],
				"text": turn[2], "detail": turn[3]}
	return {}


## Was nach der nächsten Abbiegung kommt: {"direction": ..., "distance": Meter ab dieser
## Abbiegung bis zur übernächsten}. Kommt keine mehr: direction 0, Strecke bis zum Ziel.
## Leer, wenn es gar keine Abbiegung mehr gibt.
func turn_after_next() -> Dictionary:
	var first := -1
	for turn: Array in _turns:
		if turn[0] <= _progress:
			continue
		if first == -1:
			first = turn[0]
			continue
		return {"direction": turn[1], "distance": _route_distance[turn[0]] - _route_distance[first]}
	if first == -1:
		return {}
	return {"direction": 0, "distance": _route_distance[_route_distance.size() - 1] - _route_distance[first]}


func _process(delta: float) -> void:
	message_timer = maxf(message_timer - delta, 0.0)
	if not has_target or route_points.is_empty() or car == null:
		return
	_update_progress()
	_trip_seconds += delta
	_trip_distance += car.linear_velocity.length() * delta
	if remaining_distance() < arrive_distance:
		message = "Ziel erreicht"
		message_timer = 4.0
		var average := _trip_distance / maxf(_trip_seconds, 1.0) * 3.6
		Toasts.post(get_tree(), "check", "Ziel erreicht", "%s in %d:%02d min · Ø %d km/h" % [
			format_distance(_trip_distance), floori(_trip_seconds / 60.0), int(_trip_seconds) % 60, roundi(average)])
		clear_target()
		arrived.emit()
		return
	# Von der Route abgekommen? (nur wenn das Auto fährt)
	var here := car.global_position
	var off := Vector2(here.x - route_points[_progress].x, here.z - route_points[_progress].z).length()
	if off > off_route_distance and car.linear_velocity.length() > 2.0:
		_off_route_timer += delta
		if _off_route_timer > off_route_time:
			_off_route_timer = 0.0
			_plan()
			return
	else:
		_off_route_timer = 0.0
	# Jede Sekunde: Ist ein Abschnitt weggefallen? Sind neue fertig geworden?
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = 1.0
		var known := 0
		for step: Array in _steps:
			if step[0] == null:
				continue
			var status := roads.edge_status(step[0])
			if status == 2:
				_plan()
				return
			if status == 1:
				known += 1
		if known != _known_steps:
			_build_route()
			_progress = 0
			_update_progress(true)


## Strecke wie ein Navi: „80 m“, „350 m“, „1,2 km“
static func format_distance(meters: float) -> String:
	if meters < 100.0:
		return "%d m" % (roundi(meters / 10.0) * 10)
	if meters < 1000.0:
		return "%d m" % (roundi(meters / 50.0) * 50)
	return ("%.1f km" % (meters / 1000.0)).replace(".", ",")


## Fortschritt: welcher Routenpunkt ist dem Auto am nächsten? (nur ein Stück voraus suchen)
func _update_progress(full: bool = false) -> void:
	var here := car.global_position
	var best := INF
	var start := 0 if full else maxi(_progress - 3, 0)
	var stop := route_points.size() if full else mini(_progress + 60, route_points.size())
	for i in range(start, stop):
		var d := Vector2(here.x - route_points[i].x, here.z - route_points[i].z).length_squared()
		if d < best:
			best = d
			_progress = i


# ---------------------------------------------------------------------------
# Planen
# ---------------------------------------------------------------------------

## Das Ziel auf die nächste fertige Landstraße setzen (wenn nah genug), sonst auf den nächsten Ort
func _snap_target(p: Vector3) -> Vector3:
	var hit := _nearest_road_point(p, snap_to_road_distance, true)
	if not hit.is_empty():
		return hit["point"]
	var cell := _cell_of(p)
	var best := p
	var best_distance := INF
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var node: Variant = roads.node_at(cell + Vector2i(dx, dz))
			# Nur Orte, zu denen noch eine Straße führen kann (sonst wäre das Ziel unerreichbar)
			if node == null or roads.edges_at(cell + Vector2i(dx, dz)).is_empty():
				continue
			if (node as Vector3).distance_to(p) < best_distance:
				best_distance = (node as Vector3).distance_to(p)
				best = node
	return best


func _cell_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / roads.cell_size), floori(p.z / roads.cell_size))


## Nächster Punkt auf einer fertigen Straße: {"key", "index", "point"} oder leer.
## only_roads: nur Landstraßen (keine Autobahn, Rampen, Zubringer)
func _nearest_road_point(p: Vector3, max_distance: float, only_roads: bool = false) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := max_distance
	var rect := Rect2(p.x - max_distance, p.z - max_distance, max_distance * 2.0, max_distance * 2.0)
	for pair: Array in roads.loaded_segments(rect):
		if only_roads and not RoadNetwork.is_road_key(pair[0]):
			continue
		var points := (pair[1] as RoadSegment).points
		for i in range(0, points.size(), 2):
			var d := Vector2(points[i].x - p.x, points[i].z - p.z).length()
			if d < best_distance:
				best_distance = d
				best = {"key": pair[0], "index": i, "point": points[i]}
	return best


## Route vom Auto zum Ziel suchen (A* über Orte und Autobahn-Stützpunkte)
func _plan() -> void:
	_steps.clear()
	var here := car.global_position
	var slow := average_speed_kmh / 3.6
	# Startmöglichkeiten: [Knoten, Sekunden bis dorthin, Schritte]
	var starts: Array = []
	var on_road := _nearest_road_point(here, 30.0)
	if not on_road.is_empty():
		starts = _starts_on(on_road["key"], on_road["index"])
	else:
		var cell := _cell_of(here)
		var node: Variant = roads.node_at(cell)
		if node == null:
			return
		starts.append([cell, here.distance_to(node) / slow, [[null, here, node]]])
	# Zielmöglichkeiten: [Ort, Sekunden von dort, letzte Schritte]
	var goals: Array = []
	var at_goal := _nearest_road_point(target, 5.0, true)
	if not at_goal.is_empty():
		var key: Vector3i = at_goal["key"]
		var n := roads.edge_segment(key).points.size()
		var i: int = at_goal["index"]
		goals.append([Vector2i(key.x, key.y), i * RoadSegment.POINT_SPACING / slow, [[key, true, 0, i]]])
		goals.append([roads.edge_end_cell(key), (n - 1 - i) * RoadSegment.POINT_SPACING / slow, [[key, false, n - 1, i]]])
		# Start und Ziel auf demselben Abschnitt: direkt hinfahren
		if not on_road.is_empty() and on_road["key"] == key:
			var from: int = on_road["index"]
			_steps.append([key, i >= from, from, i])
			_build_route()
			return
	else:
		goals.append([_cell_of(target), 0.0, []])
	var result := _search(starts, goals)
	if result.is_empty():
		message = "Keine Route gefunden"
		message_timer = 4.0
		Toasts.post(get_tree(), "warning", "Keine Route gefunden", "Dorthin führt (noch) keine Straße")
		clear_target()
		return
	_steps = result
	# Ein Autobahn-Abschnitt vor einer Ausfahrt endet dort, wo die Ausfahrt beginnt
	for k in range(1, _steps.size()):
		var step: Array = _steps[k]
		var before: Array = _steps[k - 1]
		if step[0] == null or before[0] == null or not RoadNetwork.is_highway_key(before[0]):
			continue
		var key: Vector3i = step[0]
		if RoadNetwork.is_interchange_key(key) and _is_exit(key):
			before[3] = roads.ramp_ends(RoadNetwork.highway_axis(key), key.y, key.x, RoadNetwork.interchange_part(key))[0]
	_build_route()


## Wie es von einer Stelle auf einem Abschnitt weitergeht: [[Knoten, Sekunden, Schritte], ...].
## Auf Landstraßen in beide Richtungen (wenden geht), auf Autobahn und Rampen nur vorwärts.
func _starts_on(key: Vector3i, i: int) -> Array:
	var slow := average_speed_kmh / 3.6
	var fast := highway_speed_kmh / 3.6
	var spacing := RoadSegment.POINT_SPACING
	var n := roads.edge_segment(key).points.size()
	if RoadNetwork.is_road_key(key):
		return [[roads.edge_end_cell(key), (n - 1 - i) * spacing / slow, [[key, true, i, n - 1]]],
			[Vector2i(key.x, key.y), i * spacing / slow, [[key, false, i, 0]]]]
	var axis := RoadNetwork.highway_axis(key)
	if RoadNetwork.is_highway_key(key):
		if roads.edge_segment(key).direction_at(i).dot(_car_forward()) >= 0.0:
			return [[Vector4i(axis, key.y, key.x + 1, 1), (n - 1 - i) * spacing / fast, [[key, true, i, n - 1]]]]
		return [[Vector4i(axis, key.y, key.x, -1), i * spacing / fast, [[key, false, i, 0]]]]
	var part := RoadNetwork.interchange_part(key)
	var interchange := roads.highways.interchange_at(axis, key.y, key.x)
	var connector := RoadNetwork.interchange_key(axis, key.y, key.x, 0)
	if part == 0:
		# Zubringer: zurück zum Ort oder auf eine der beiden Auffahrten
		var result: Array = [[interchange["cell"], i * spacing / slow, [[key, false, i, 0]]]]
		for dir: int in [1, -1]:
			var entry := _entry_steps(axis, key.y, key.x, dir, i)
			if not entry.is_empty():
				result.append([Vector4i(axis, key.y, key.x + dir, dir), entry[0], entry[1]])
		return result
	var dir := 1 if part >= 3 else -1
	var rest := (n - 1 - i) * spacing / slow
	var ends := roads.ramp_ends(axis, key.y, key.x, part)
	if not _is_exit(key):
		# Auffahrt: weiter auf der Autobahn
		var pair := _highway_step_key(axis, key.y, key.x, dir)
		return [[Vector4i(axis, key.y, key.x + dir, dir), rest + _length(pair[0]) / fast,
			[[key, true, i, n - 1], [pair[0], pair[1], ends[1], -1]]]]
	# Ausfahrt: über den Zubringer zum Ort
	return [[interchange["cell"], rest, [[key, true, i, n - 1], [connector, false, ends[1], 0]]]]


## Fahrtrichtung des Autos (flach)
func _car_forward() -> Vector3:
	var forward := car.linear_velocity if car.linear_velocity.length() > 2.0 else car.global_basis.z
	forward.y = 0.0
	return forward.normalized()


## Ausfahrt-Rampe? (Teil 1 und 3; 2 und 4 sind Einfahrten)
static func _is_exit(key: Vector3i) -> bool:
	var part := RoadNetwork.interchange_part(key)
	return part == 1 or part == 3


## Autobahn-Abschnitt ab Stützpunkt k in Fahrtrichtung dir: [Schlüssel, vorwärts]
static func _highway_step_key(axis: int, line: int, k: int, dir: int) -> Array:
	if dir > 0:
		return [Vector3i(k, line, 2 + axis), true]
	return [Vector3i(k - 1, line, 2 + axis), false]


## Lage eines Knotens: Ort (Vector2i) oder Autobahn-Stützpunkt (Vector4i)
func _position(node: Variant) -> Vector3:
	if node is Vector4i:
		var h: Vector4i = node
		return roads.highways.control_point(h.x, h.y, h.z)
	return roads.node_at(node)


## Länge eines Abschnitts: berechnet oder geschätzt (Luftlinie mal unknown_length_factor)
func _length(key: Vector3i) -> float:
	var segment := roads.edge_segment(key)
	if segment:
		return segment.total_length()
	var ends := _fallback_ends(key)
	return (ends[0] as Vector3).distance_to(ends[1]) * unknown_length_factor


## Anfang und Ende eines (noch nicht berechneten) Abschnitts, für die geschätzte Linie
func _fallback_ends(key: Vector3i) -> Array:
	if RoadNetwork.is_road_key(key):
		return [roads.node_at(Vector2i(key.x, key.y)), roads.node_at(roads.edge_end_cell(key))]
	var axis := RoadNetwork.highway_axis(key)
	if RoadNetwork.is_highway_key(key):
		return [roads.highways.control_point(axis, key.y, key.x), roads.highways.control_point(axis, key.y, key.x + 1)]
	var interchange := roads.highways.interchange_at(axis, key.y, key.x)
	var point: Vector3 = interchange["point"]
	var part := RoadNetwork.interchange_part(key)
	if part == 0:
		return [interchange["place"], point]
	var ends := roads.ramp_ends(axis, key.y, key.x, part)
	return [Vector3(ends[0].x, point.y, ends[0].y), Vector3(ends[1].x, point.y, ends[1].y)]


## Auffahrt an der Anschlussstelle k in Fahrtrichtung dir bis zum nächsten Stützpunkt:
## [Sekunden, Schritte] oder leer. from = Startpunkt auf dem Zubringer (-1 = am Ort).
func _entry_steps(axis: int, line: int, k: int, dir: int, from: int) -> Array:
	var connector := RoadNetwork.interchange_key(axis, line, k, 0)
	var part := 4 if dir > 0 else 2
	var ramp := RoadNetwork.interchange_key(axis, line, k, part)
	var pair := _highway_step_key(axis, line, k, dir)
	if roads.edge_status(connector) == 2 or roads.edge_status(ramp) == 2 or roads.edge_status(pair[0]) == 2:
		return []
	var ends := roads.ramp_ends(axis, line, k, part)
	var place: Vector3 = roads.highways.interchange_at(axis, line, k)["place"]
	var on_connector := Vector2(place.x, place.z).distance_to(ends[0])
	var seconds := (on_connector + _length(ramp)) / (average_speed_kmh / 3.6) \
		+ maxf(_length(pair[0]) - RoadNetwork.RAMP_LENGTH, 0.0) / (highway_speed_kmh / 3.6)
	return [seconds, [[connector, true, maxi(from, 0), ends[0]], [ramp, true, -1, -1], [pair[0], pair[1], ends[1], -1]]]


## Ausfahrt am Stützpunkt k (Fahrtrichtung dir) bis zum Ort: [Sekunden, Schritte] oder leer
func _exit_steps(axis: int, line: int, k: int, dir: int) -> Array:
	var connector := RoadNetwork.interchange_key(axis, line, k, 0)
	var part := 3 if dir > 0 else 1
	var ramp := RoadNetwork.interchange_key(axis, line, k, part)
	if roads.edge_status(connector) == 2 or roads.edge_status(ramp) == 2:
		return []
	var ends := roads.ramp_ends(axis, line, k, part)
	var place: Vector3 = roads.highways.interchange_at(axis, line, k)["place"]
	var seconds := (_length(ramp) + Vector2(place.x, place.z).distance_to(ends[1])) / (average_speed_kmh / 3.6)
	return [seconds, [[ramp, true, -1, -1], [connector, false, ends[1], 0]]]


## Anschlussstellen, deren Zubringer an diesem Ort beginnt: [Vector3i(Achse, Linie, k), ...]
func _interchanges_of(cell: Vector2i) -> Array:
	if _interchange_cache.has(cell):
		return _interchange_cache[cell]
	var result: Array = []
	var node: Vector3 = roads.node_at(cell)
	var area := Rect2(node.x - 1000.0, node.z - 1000.0, 2000.0, 2000.0)
	for section: Array in roads.highways.sections_touching(area):
		for k: int in [section[2], section[2] + 1]:
			var id := Vector3i(section[0], section[1], k)
			if result.has(id):
				continue
			var interchange := roads.highways.interchange_at(id.x, id.y, id.z)
			if not interchange.is_empty() and interchange["cell"] == cell:
				result.append(id)
	_interchange_cache[cell] = result
	return result


## Verbindungen eines Knotens: [[Nachbar, Sekunden, Schritte], ...]
func _links(node: Variant) -> Array:
	var result: Array = []
	if node is Vector4i:
		var h: Vector4i = node
		# Weiter auf der Autobahn bis zum nächsten Stützpunkt
		var pair := _highway_step_key(h.x, h.y, h.z, h.w)
		if roads.edge_status(pair[0]) != 2:
			result.append([Vector4i(h.x, h.y, h.z + h.w, h.w), _length(pair[0]) / (highway_speed_kmh / 3.6),
				[[pair[0], pair[1], -1, -1]]])
		# Ausfahrt an diesem Stützpunkt
		if not roads.highways.interchange_at(h.x, h.y, h.z).is_empty():
			var leave := _exit_steps(h.x, h.y, h.z, h.w)
			if not leave.is_empty():
				result.append([roads.highways.interchange_at(h.x, h.y, h.z)["cell"], leave[0], leave[1]])
		return result
	var cell: Vector2i = node
	for option: Array in roads.edges_at(cell):
		var key: Vector3i = option[0]
		if roads.edge_status(key) == 2:
			continue
		var other := roads.edge_end_cell(key) if option[1] else Vector2i(key.x, key.y)
		result.append([other, _length(key) / (average_speed_kmh / 3.6), [[key, option[1], -1, -1]]])
	# Auffahrten an diesem Ort, in beide Richtungen
	for id: Vector3i in _interchanges_of(cell):
		for dir: int in [1, -1]:
			var entry := _entry_steps(id.x, id.y, id.z, dir, -1)
			if not entry.is_empty():
				result.append([Vector4i(id.x, id.y, id.z + dir, dir), entry[0], entry[1]])
	return result


## A*: Liefert die Schritte vom Auto zum Ziel (leer = nichts gefunden). Kosten = Fahrzeit.
func _search(starts: Array, goals: Array) -> Array:
	var goal_position: Vector3 = target
	var ids := {}  # Knoten (Vector2i oder Vector4i) -> int
	var nodes: Array = []
	# Achtung: normale Arrays, keine Packed-Arrays: Die kleine Funktion id_of unten bekommt
	# Packed-Arrays nur als Kopie und würde dann ins Leere schreiben
	var cost: Array = []
	var came_from: Array = []  # pro id: [vorherige id, Schritte]
	var heap := RoadSegment.MinHeap.new()
	var id_of := func(node: Variant) -> int:
		if not ids.has(node):
			ids[node] = nodes.size()
			nodes.append(node)
			cost.append(INF)
			came_from.append(null)
		return ids[node]
	# Schätzung der Restzeit: Luftlinie mit Autobahn-Tempo (nie zu hoch, sonst findet A* nicht
	# den schnellsten Weg)
	var fast := highway_speed_kmh / 3.6
	var goal_extra := {}  # Ziel-Ort -> [Sekunden, letzte Schritte]
	for goal: Array in goals:
		goal_extra[goal[0]] = [goal[1], goal[2]]
	var goal_id: int = id_of.call(GOAL)
	for start: Array in starts:
		var id: int = id_of.call(start[0])
		if start[1] < cost[id]:
			cost[id] = start[1]
			came_from[id] = [-1, start[2]]
			heap.push(start[1] + _position(start[0]).distance_to(goal_position) / fast, id)
	# Nicht beliebig weit suchen: höchstens doppelte Luftlinie plus 5 km Umweg
	var start_position: Vector3 = car.global_position
	var max_detour := start_position.distance_to(goal_position) * 2.0 + 5000.0
	var expanded := 0
	var closed := {}
	while not heap.is_empty() and expanded < 4000:
		var current := heap.pop()
		if current == goal_id:
			break
		if closed.has(current):
			continue
		closed[current] = true
		expanded += 1
		var node: Variant = nodes[current]
		var here := _position(node)
		if here.distance_to(start_position) + here.distance_to(goal_position) > max_detour:
			continue
		if goal_extra.has(node):
			var total: float = cost[current] + goal_extra[node][0]
			if total < cost[goal_id]:
				cost[goal_id] = total
				came_from[goal_id] = [current, goal_extra[node][1]]
				heap.push(total, goal_id)
		for link: Array in _links(node):
			var id: int = id_of.call(link[0])
			var new_cost: float = cost[current] + link[1]
			if new_cost < cost[id]:
				cost[id] = new_cost
				came_from[id] = [current, link[2]]
				heap.push(new_cost + _position(link[0]).distance_to(goal_position) / fast, id)
	if came_from[goal_id] == null:
		return []
	# Rückwärts einsammeln (Kopien, weil die Schritte danach noch angepasst werden)
	var steps: Array = []
	var at := goal_id
	while at != -1:
		var entry: Array = came_from[at]
		var part: Array = entry[1]
		for k in range(part.size() - 1, -1, -1):
			steps.push_front((part[k] as Array).duplicate())
		at = entry[0]
	return steps


## Aus den Schritten eine Linie bauen (echte Straßenpunkte oder Luftlinie) und Abbiegungen finden
func _build_route() -> void:
	route_points = PackedVector3Array()
	route_known = PackedByteArray()
	_route_speed = PackedFloat32Array()
	_turns.clear()
	_known_steps = 0
	var slow := average_speed_kmh / 3.6
	var joints: Array = []  # [Punkt, Schritt danach]
	for step: Array in _steps:
		if not route_points.is_empty():
			joints.append([route_points.size() - 1, step])
		if step[0] == null:
			_append_line(step[1], step[2], 0, slow)
			continue
		var key: Vector3i = step[0]
		var speed := highway_speed_kmh / 3.6 if RoadNetwork.is_highway_key(key) else slow
		var segment := roads.edge_segment(key)
		if segment == null:
			var ends := _fallback_ends(key)
			var a: Vector3 = ends[0] if step[1] else ends[1]
			var b: Vector3 = ends[1] if step[1] else ends[0]
			if step[2] is Vector2:
				a = Vector3(step[2].x, a.y, step[2].y)
			if step[3] is Vector2:
				b = Vector3(step[3].x, b.y, step[3].y)
			_append_line(a, b, 0, speed)
			continue
		_known_steps += 1
		var points := segment.points
		var from := _resolve(points, step[2], 0 if step[1] else points.size() - 1)
		var to := _resolve(points, step[3], points.size() - 1 if step[1] else 0)
		var direction := 1 if to >= from else -1
		var i := from
		while true:
			_append_point(points[i], 1, speed)
			if i == to:
				break
			i += direction
	# Strecke und Fahrzeit bis zu jedem Punkt
	_route_distance = PackedFloat32Array()
	_route_distance.resize(route_points.size())
	_route_time = PackedFloat32Array()
	_route_time.resize(route_points.size())
	for i in range(1, route_points.size()):
		var length := route_points[i].distance_to(route_points[i - 1])
		_route_distance[i] = _route_distance[i - 1] + length
		_route_time[i] = _route_time[i - 1] + length / _route_speed[i]
	# Abbiegungen an den Stellen, an denen zwei Schritte zusammenstoßen
	for joint: Array in joints:
		var turn := _joint_turn(joint[0], joint[1])
		if not turn.is_empty():
			_turns.append(turn)
	route_changed.emit()


## Punkt-Nummer zu einem Anker: Nummer, Lage (x/z, nächster Punkt) oder -1 (fallback)
static func _resolve(points: PackedVector3Array, anchor: Variant, fallback: int) -> int:
	if anchor is int:
		return fallback if anchor < 0 else mini(anchor, points.size() - 1)
	var p: Vector2 = anchor
	var best := fallback
	var best_distance := INF
	for i in points.size():
		var d := Vector2(points[i].x - p.x, points[i].z - p.y).length_squared()
		if d < best_distance:
			best_distance = d
			best = i
	return best


## Hinweis an der Stelle, an der zwei Schritte zusammenstoßen: [Punkt, Richtung, Text, Zusatz]
## oder leer. Auffahrten und Ausfahrten bekommen eigene Ansagen, das Einfädeln auf die
## Autobahn und der Übergang zwischen Autobahn-Abschnitten keine.
func _joint_turn(index: int, after: Array) -> Array:
	if after[0] != null:
		var key: Vector3i = after[0]
		if RoadNetwork.is_interchange_key(key) and RoadNetwork.interchange_part(key) != 0:
			if _is_exit(key):
				var interchange := roads.highways.interchange_at(RoadNetwork.highway_axis(key), key.y, key.x)
				return [index, -1, "Ausfahrt %d nehmen" % interchange["number"], interchange["name"]]
			var onto := _turn_at(index)
			return [index, onto if onto != 0 else -1, "Auf die Autobahn", ""]
		if RoadNetwork.is_highway_key(key):
			return []
	var direction := _turn_at(index)
	return [index, direction, "", ""] if direction != 0 else []


## speed: Tempo (m/s) auf dem Stück bis zu diesem Punkt, für die Fahrzeit
func _append_point(p: Vector3, known: int, speed: float) -> void:
	if not route_points.is_empty() and route_points[route_points.size() - 1].distance_to(p) < 0.5:
		return
	route_points.append(p)
	route_known.append(known)
	_route_speed.append(speed)


## Gerade Linie mit einem Punkt alle 40 m (damit Abstände und Fortschritt stimmen)
func _append_line(a: Vector3, b: Vector3, known: int, speed: float) -> void:
	var steps := maxi(ceili(a.distance_to(b) / 40.0), 1)
	for i in steps + 1:
		_append_point(a.lerp(b, float(i) / steps), known, speed)


## Wie stark biegt die Route an diesem Punkt ab? 0 = geradeaus, 1 = leicht, 2 = normal,
## 3 = scharf; positiv = links, negativ = rechts
func _turn_at(index: int) -> int:
	var before := _point_at_distance(index, -25.0)
	var after := _point_at_distance(index, 25.0)
	var here := route_points[index]
	var incoming := Vector2(here.x - before.x, here.z - before.z)
	var outgoing := Vector2(after.x - here.x, after.z - here.z)
	if incoming.length() < 1.0 or outgoing.length() < 1.0:
		return 0
	var angle := rad_to_deg(absf(incoming.angle_to(outgoing)))
	# In der Welt zeigt „links“ dorthin, wohin sich der Weg bei positivem Kreuzprodukt
	# (Vector3, wie im Straßencode) dreht
	var left := Vector3(incoming.x, 0.0, incoming.y).cross(Vector3(outgoing.x, 0.0, outgoing.y)).y > 0.0
	var strength := 0
	if angle > 130.0:
		strength = 3
	elif angle > 55.0:
		strength = 2
	elif angle > 20.0:
		strength = 1
	return strength if left else -strength


## Punkt auf der Route, distance Meter vor (positiv) oder hinter (negativ) dem Punkt index
func _point_at_distance(index: int, distance: float) -> Vector3:
	var step := 1 if distance > 0.0 else -1
	var travelled := 0.0
	var i := index
	while i + step >= 0 and i + step < route_points.size() and travelled < absf(distance):
		travelled += route_points[i].distance_to(route_points[i + step])
		i += step
	return route_points[i]
