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
## Für die geschätzte Fahrzeit
@export var average_speed_kmh: float = 70.0
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

## Abstand vom Routenanfang bis zu jedem Punkt
var _route_distance := PackedFloat32Array()
## Abbiegungen: [Index in route_points, Richtung (-3..3, positiv = links)]
var _turns: Array = []
## Schritte: [Schlüssel, vorwärts, von Punkt, bis Punkt] (-1 = ganzer Abschnitt),
## oder für eine Luftlinie vom Auto zum Ort: [null, Startpunkt, Zielpunkt]
var _steps: Array = []
## Orte, an denen zwei Schritte zusammenstoßen (für die Abbiege-Hinweise)
var _step_cells: Array[Vector2i] = []
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


## Geschätzte Fahrzeit in Minuten
func remaining_minutes() -> float:
	return remaining_distance() / (average_speed_kmh / 3.6) / 60.0


## Nächste Abbiegung: {"direction": -3..3 (positiv = links), "distance": Meter} oder leer
func next_turn() -> Dictionary:
	for turn: Array in _turns:
		if turn[0] > _progress:
			return {"direction": turn[1], "distance": _route_distance[turn[0]] - _route_distance[_progress]}
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

## Das Ziel auf die nächste fertige Straße setzen (wenn nah genug), sonst auf den nächsten Ort
func _snap_target(p: Vector3) -> Vector3:
	var hit := _nearest_road_point(p, snap_to_road_distance)
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


## Nächster Punkt auf einer fertigen Straße: {"key", "index", "point"} oder leer
func _nearest_road_point(p: Vector3, max_distance: float) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := max_distance
	var rect := Rect2(p.x - max_distance, p.z - max_distance, max_distance * 2.0, max_distance * 2.0)
	for pair: Array in roads.loaded_segments(rect):
		var points := (pair[1] as RoadSegment).points
		for i in range(0, points.size(), 2):
			var d := Vector2(points[i].x - p.x, points[i].z - p.z).length()
			if d < best_distance:
				best_distance = d
				best = {"key": pair[0], "index": i, "point": points[i]}
	return best


## Route vom Auto zum Ziel suchen (A* über die Orte)
func _plan() -> void:
	_steps.clear()
	_step_cells.clear()
	var here := car.global_position
	# Startmöglichkeiten: [Ort, Kosten bis dorthin, erster Schritt]
	var starts: Array = []
	var on_road := _nearest_road_point(here, 30.0)
	if not on_road.is_empty():
		var key: Vector3i = on_road["key"]
		var n := roads.edge_segment(key).points.size()
		var i: int = on_road["index"]
		starts.append([roads.edge_end_cell(key), (n - 1 - i) * RoadSegment.POINT_SPACING, [key, true, i, n - 1]])
		starts.append([Vector2i(key.x, key.y), i * RoadSegment.POINT_SPACING, [key, false, i, 0]])
	else:
		var cell := _cell_of(here)
		var node: Variant = roads.node_at(cell)
		if node == null:
			return
		starts.append([cell, here.distance_to(node), [null, here, node]])
	# Zielmöglichkeiten: [Ort, Kosten von dort, letzter Schritt]
	var goals: Array = []
	var at_goal := _nearest_road_point(target, 5.0)
	if not at_goal.is_empty():
		var key: Vector3i = at_goal["key"]
		var n := roads.edge_segment(key).points.size()
		var i: int = at_goal["index"]
		goals.append([Vector2i(key.x, key.y), i * RoadSegment.POINT_SPACING, [key, true, 0, i]])
		goals.append([roads.edge_end_cell(key), (n - 1 - i) * RoadSegment.POINT_SPACING, [key, false, n - 1, i]])
		# Start und Ziel auf demselben Abschnitt: direkt hinfahren
		if not on_road.is_empty() and on_road["key"] == key:
			var from: int = on_road["index"]
			_steps.append([key, i >= from, from, i])
			_build_route()
			return
	else:
		goals.append([_cell_of(target), 0.0, null])
	var result := _search(starts, goals)
	if result.is_empty():
		message = "Keine Route gefunden"
		message_timer = 4.0
		Toasts.post(get_tree(), "warning", "Keine Route gefunden", "Dorthin führt (noch) keine Straße")
		clear_target()
		return
	_steps = result
	_build_route()


## A*: Liefert die Schritte vom Auto zum Ziel (leer = nichts gefunden)
func _search(starts: Array, goals: Array) -> Array:
	var goal_position: Vector3 = target
	var ids := {}  # Vector2i -> int
	var cells: Array[Vector2i] = []
	# Achtung: normale Arrays, keine Packed-Arrays: Die kleine Funktion id_of unten bekommt
	# Packed-Arrays nur als Kopie und würde dann ins Leere schreiben
	var cost: Array = []
	var came_from: Array = []  # pro id: [vorherige id, Schritt]
	var heap := RoadSegment.MinHeap.new()
	var id_of := func(cell: Vector2i) -> int:
		if not ids.has(cell):
			ids[cell] = cells.size()
			cells.append(cell)
			cost.append(INF)
			came_from.append(null)
		return ids[cell]
	var goal_extra := {}  # Ziel-Ort -> [Kosten, letzter Schritt]
	for goal: Array in goals:
		goal_extra[goal[0]] = [goal[1], goal[2]]
	var goal_id: int = id_of.call(GOAL)
	for start: Array in starts:
		var id: int = id_of.call(start[0])
		if start[1] < cost[id]:
			cost[id] = start[1]
			came_from[id] = [-1, start[2]]
			heap.push(start[1] + (roads.node_at(start[0]) as Vector3).distance_to(goal_position), id)
	# Nicht beliebig weit suchen: höchstens doppelte Luftlinie plus 5 km Umweg
	var start_position: Vector3 = car.global_position
	var max_detour := start_position.distance_to(goal_position) * 2.0 + 5000.0
	var expanded := 0
	while not heap.is_empty() and expanded < 4000:
		var current := heap.pop()
		if current == goal_id:
			break
		expanded += 1
		var cell := cells[current]
		var here: Vector3 = roads.node_at(cell)
		if here.distance_to(start_position) + here.distance_to(goal_position) > max_detour:
			continue
		if goal_extra.has(cell):
			var total: float = cost[current] + goal_extra[cell][0]
			if total < cost[goal_id]:
				cost[goal_id] = total
				came_from[goal_id] = [current, goal_extra[cell][1]]
				heap.push(total, goal_id)
		for option: Array in roads.edges_at(cell):
			var key: Vector3i = option[0]
			var forward: bool = option[1]
			var status := roads.edge_status(key)
			if status == 2:
				continue
			var other := roads.edge_end_cell(key) if forward else Vector2i(key.x, key.y)
			var there: Vector3 = roads.node_at(other)
			var length := here.distance_to(there) * unknown_length_factor
			var segment := roads.edge_segment(key)
			if segment:
				length = segment.total_length()
			var id: int = id_of.call(other)
			var new_cost: float = cost[current] + length
			if new_cost < cost[id]:
				cost[id] = new_cost
				came_from[id] = [current, [key, forward, -1, -1]]
				heap.push(new_cost + there.distance_to(goal_position), id)
	if came_from[goal_id] == null:
		return []
	# Rückwärts einsammeln
	var steps: Array = []
	var node := goal_id
	while node != -1:
		var entry: Array = came_from[node]
		if entry[1] != null:
			steps.push_front(entry[1])
		node = entry[0]
	return steps


## Aus den Schritten eine Linie bauen (echte Straßenpunkte oder Luftlinie) und Abbiegungen finden
func _build_route() -> void:
	route_points = PackedVector3Array()
	route_known = PackedByteArray()
	_turns.clear()
	_known_steps = 0
	var joints: Array[int] = []
	for step: Array in _steps:
		if not route_points.is_empty():
			joints.append(route_points.size() - 1)
		if step[0] == null:
			_append_line(step[1], step[2], 0)
			continue
		var segment := roads.edge_segment(step[0])
		if segment == null:
			var key: Vector3i = step[0]
			var a: Vector3 = roads.node_at(Vector2i(key.x, key.y))
			var b: Vector3 = roads.node_at(roads.edge_end_cell(key))
			if step[1]:
				_append_line(a, b, 0)
			else:
				_append_line(b, a, 0)
			continue
		_known_steps += 1
		var points := segment.points
		var from: int = step[2] if step[2] >= 0 else (0 if step[1] else points.size() - 1)
		var to: int = step[3] if step[3] >= 0 else (points.size() - 1 if step[1] else 0)
		var direction := 1 if to >= from else -1
		var i := from
		while true:
			_append_point(points[i], 1)
			if i == to:
				break
			i += direction
	# Strecke bis zu jedem Punkt
	_route_distance = PackedFloat32Array()
	_route_distance.resize(route_points.size())
	for i in range(1, route_points.size()):
		_route_distance[i] = _route_distance[i - 1] + route_points[i].distance_to(route_points[i - 1])
	# Abbiegungen an den Stellen, an denen zwei Schritte zusammenstoßen
	for joint in joints:
		var direction := _turn_at(joint)
		if direction != 0:
			_turns.append([joint, direction])
	route_changed.emit()


func _append_point(p: Vector3, known: int) -> void:
	if not route_points.is_empty() and route_points[route_points.size() - 1].distance_to(p) < 0.5:
		return
	route_points.append(p)
	route_known.append(known)


## Gerade Linie mit einem Punkt alle 40 m (damit Abstände und Fortschritt stimmen)
func _append_line(a: Vector3, b: Vector3, known: int) -> void:
	var steps := maxi(ceili(a.distance_to(b) / 40.0), 1)
	for i in steps + 1:
		_append_point(a.lerp(b, float(i) / steps), known)


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
