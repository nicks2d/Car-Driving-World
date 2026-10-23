class_name RoadNetwork
extends Node3D
## Das Straßennetz. Die Welt ist in Zellen (cell_size) eingeteilt, in jeder liegt höchstens
## ein „Ort“ (Knoten), bevorzugt flach und im Tal. Benachbarte Orte werden mit einer
## Straße verbunden (nach rechts und nach vorne). Jeder Abschnitt hängt nur von seinen
## zwei Orten ab: Deshalb ist das Netz endlos, nahtlos und bei gleichem Seed immer gleich.
##
## Jeder Abschnitt durchläuft im Hintergrund drei Schritte:
##  1. berechnen (RoadSegment.build): Weg, Kurven, Höhenprofil
##  2. prüfen: Kommt er außerhalb der Kreuzungen einer anderen Straße zu nahe (kreuzen,
##     überlappen), fällt der Abschnitt mit dem größeren Hash-Wert weg. Das hängt nur von
##     den beiden Abschnitten ab, ist also immer gleich, egal in welcher Reihenfolge
##     gerechnet wird.
##  3. Mesh bauen: erst wenn an beiden Orten feststeht, welche Straßen dort ankommen.
##     Die Straße endet am Rand der Kreuzung, die Kreuzung (RoadJunction) bekommt eine
##     eigene Fläche.

## Material der Fahrbahn (road.gdshader)
@export var road_material: Material
## Material für Brücken (Beton)
@export var bridge_material: Material
## Material für Leitplanken (Metall)
@export var rail_material: Material
## Größe einer Zelle mit höchstens einem Ort (Meter)
@export var cell_size: float = 1200.0
## Wahrscheinlichkeit, dass zwei benachbarte Orte verbunden sind
@export_range(0.0, 1.0) var connection_chance: float = 0.8
## Breite der Fahrbahn (zwei Spuren) und des Banketts daneben.
## Alles andere (Markierungen, Brücken, Böschungen, Bäume) passt sich daran an.
@export var road_width: float = 9.0
@export var shoulder_width: float = 1.5
## Höchste Steigung (0.10 = 10 %)
@export var max_grade: float = 0.10
## Wunschradius normaler Kurven und kleinster Radius in engen Kehren (Meter)
@export var curve_radius: float = 60.0
@export var min_curve_radius: float = 20.0
## Querneigung in Kurven (0.05 = 5 %)
@export var max_bank: float = 0.05
## Rasterabstand der Wegsuche (kleiner = genauer, aber langsamer)
@export var grid_step: float = 18.0
## So weit vor der Kreuzungsmitte enden die Straßen mindestens (Meter).
## Laufen zwei Straßen spitz zusammen, wird es automatisch mehr.
@export var junction_radius: float = 14.0
## Bis zu dieser Entfernung werden Straßen vorab berechnet
@export var prefetch_distance: float = 2800.0
## Bis zu dieser Entfernung sind Straßen sichtbar
@export var mesh_distance: float = 2300.0
## Bis zu dieser Entfernung haben Straßen eine Kollision
@export var collision_distance: float = 600.0
## So viele Aufträge laufen gleichzeitig im Hintergrund
@export var max_parallel_jobs: int = 4
## So oft (Sekunden) wird das Netz rund ums Auto aktualisiert (und sofort, wenn ein
## Auftrag fertig wurde). Jedes Bild wäre unnötig teuer.
@export var update_interval: float = 0.1

## Die Schritte eines Abschnitts (in dieser Reihenfolge)
enum State { BUILDING, BUILT, CHECKING, CHECKED, MESHING, READY }

## Rund um gemeinsame Orte dürfen sich Straßen so nahe kommen (dort ist die Kreuzung)
const JUNCTION_CLEARANCE: float = 20.0
## So weit liegen die Abfahrtsrichtungen der Straßen eines Orts mindestens auseinander
const MIN_DEPARTURE_ANGLE: float = deg_to_rad(80.0)
## Ab dieser Entfernung wird ein Abschnitt ganz vergessen (wird bei Bedarf neu berechnet)
const FORGET_DISTANCE: float = 5300.0

var world_gen: WorldGen
var target: Node3D
var _nodes: Dictionary = {}  # Vector2i -> Vector3 (Ort) oder null (kein Ort in der Zelle)
var _entries: Dictionary = {}  # Vector3i (Zelle x, Zelle z, Richtung) -> Entry
## Abschnitte, die berechnet werden sollen: 1 = nur berechnen, 2 = auch prüfen
var _wanted: Dictionary = {}  # Vector3i -> int
var _edge_cache: Dictionary = {}  # Vector3i -> bool (gibt es diese Verbindung?)
var _junctions: Dictionary = {}  # Vector2i -> RoadJunction
var _departures: Dictionary = {}  # Vector2i -> Dictionary (Nachbarzelle -> Richtung)
var _running: int = 0
var _update_timer: float = 0.0


## Ein Straßenabschnitt und was dazu in der Szene steht
class Entry:
	var segment: RoadSegment
	var state: int = State.BUILDING
	var task_id: int = -1
	## Wird der Abschnitt gebraucht (nicht nur als Nachbar beim Prüfen)? Dann auch prüfen.
	var needed: bool = false
	## Bleibt der Abschnitt im Netz? (gültig und keine Überlappung mit einem wichtigeren)
	var kept: bool = false
	## Abschnitte, denen dieser nahe kommen könnte (wird einmal ausgerechnet)
	var neighbors: Array[Vector3i] = []
	var has_neighbors: bool = false
	var check: OverlapCheck
	var mesh_instance: MeshInstance3D
	var body: StaticBody3D


## Hintergrund-Auftrag: Kommt ein Abschnitt einem wichtigeren Abschnitt zu nahe?
class OverlapCheck:
	var segment: RoadSegment
	var others: Array = []  # RoadSegments mit kleinerem Hash-Wert
	var distance: float
	var overlaps: bool = false

	func run() -> void:
		for other: RoadSegment in others:
			if segment.comes_close(other, distance, JUNCTION_CLEARANCE):
				overlaps = true
				return


func start(gen: WorldGen, follow: Node3D) -> void:
	world_gen = gen
	target = follow
	# Der Straßen-Shader braucht die Breite, damit die Markierungen an der richtigen Stelle sitzen
	if road_material is ShaderMaterial:
		(road_material as ShaderMaterial).set_shader_parameter("road_width", road_width)


func _process(delta: float) -> void:
	if world_gen == null or target == null:
		return
	_update_timer -= delta
	if _collect_finished() == 0 and _update_timer > 0.0:
		return
	_update_timer = update_interval
	_prefetch()
	_advance()
	_dispatch()
	_update_visuals()


func _exit_tree() -> void:
	for entry: Entry in _entries.values():
		if entry.task_id != -1:
			WorkerThreadPool.wait_for_task_completion(entry.task_id)
			entry.task_id = -1


# ---------------------------------------------------------------------------
# Orte und Verbindungen
# ---------------------------------------------------------------------------

## Der Ort in einer Zelle (Vector3) oder null, wenn dort keiner liegt
func node_at(cell: Vector2i) -> Variant:
	if _nodes.has(cell):
		return _nodes[cell]
	var rng := RandomNumberGenerator.new()
	rng.seed = world_gen.hash_cell(cell.x, cell.y, 202)
	var margin := cell_size * 0.15
	var best: Variant = null
	var best_score := INF
	# Mehrere Zufallsstellen probieren und die flachste, tiefste nehmen
	for i in 8:
		var p := Vector2(cell.x * cell_size + rng.randf_range(margin, cell_size - margin),
			cell.y * cell_size + rng.randf_range(margin, cell_size - margin))
		var lakes: Array = world_gen.lakes_near(Rect2(p.x - 60.0, p.y - 60.0, 120.0, 120.0))
		if world_gen.water_level_at(p.x, p.y, lakes) > WorldGen.NO_WATER:
			continue
		var too_close_to_lake := false
		for lake: WorldGen.Lake in lakes:
			if p.distance_to(lake.center) < lake.radius + 50.0:
				too_close_to_lake = true
		if too_close_to_lake:
			continue
		var h := world_gen.terrain_height(p.x, p.y, lakes)
		var relief := h - world_gen.ground_level(p.x, p.y)
		var slope := (absf(world_gen.terrain_height(p.x + 20.0, p.y, lakes) - h)
			+ absf(world_gen.terrain_height(p.x, p.y + 20.0, lakes) - h)) / 20.0
		var score := relief + slope * 400.0
		if relief < 300.0 and score < best_score:
			best_score = score
			best = Vector3(p.x, h, p.y)
	_nodes[cell] = best
	return best


## Gibt es eine Straße von dieser Zelle nach rechts (dir 0) bzw. nach vorne (dir 1)?
func _edge_exists(cell: Vector2i, dir: int) -> bool:
	var key := Vector3i(cell.x, cell.y, dir)
	if _edge_cache.has(key):
		return _edge_cache[key]
	var other := cell + (Vector2i(1, 0) if dir == 0 else Vector2i(0, 1))
	var exists := false
	if node_at(cell) != null and node_at(other) != null:
		var rng := RandomNumberGenerator.new()
		rng.seed = world_gen.hash_cell(cell.x, cell.y, 303 + dir)
		exists = rng.randf() < connection_chance
	_edge_cache[key] = exists
	return exists


func _edge_nodes(key: Vector3i) -> Array:
	return [node_at(Vector2i(key.x, key.y)), node_at(_end_cell(key))]


## Zelle des Orts, an dem der Abschnitt endet
func _end_cell(key: Vector3i) -> Vector2i:
	return Vector2i(key.x, key.y) + (Vector2i(1, 0) if key.z == 0 else Vector2i(0, 1))


## Die (bis zu) vier Abschnitte an einem Ort: [Schlüssel, true = beginnt hier]
func _arm_keys(cell: Vector2i) -> Array:
	return [[Vector3i(cell.x, cell.y, 0), true], [Vector3i(cell.x, cell.y, 1), true],
		[Vector3i(cell.x - 1, cell.y, 0), false], [Vector3i(cell.x, cell.y - 1, 1), false]]


## Richtung, in der die Straße zur Nachbarzelle den Ort in cell verlässt.
## Wie die Luftlinie, aber die Straßen eines Orts liegen mindestens MIN_DEPARTURE_ANGLE
## auseinander. Hängt nur vom Ort und seinen Nachbarn ab, ist also immer gleich.
func _departure(cell: Vector2i, toward: Vector2i) -> Vector2:
	if not _departures.has(cell):
		var center: Vector3 = node_at(cell)
		var others: Array[Vector2i] = []
		var angles: Array[float] = []
		for option: Array in _arm_keys(cell):
			var key: Vector3i = option[0]
			if not _edge_exists(Vector2i(key.x, key.y), key.z):
				continue
			var other_cell := _end_cell(key) if option[1] else Vector2i(key.x, key.y)
			var other: Vector3 = node_at(other_cell)
			others.append(other_cell)
			angles.append(atan2(other.z - center.z, other.x - center.x))
		# Zu eng beieinander liegende Richtungen ein Stück auseinanderdrehen
		for attempt in 30:
			for a in angles.size():
				for b in range(a + 1, angles.size()):
					var diff := angle_difference(angles[a], angles[b])
					if absf(diff) < MIN_DEPARTURE_ANGLE:
						var push := (MIN_DEPARTURE_ANGLE - absf(diff)) * 0.5 * (1.0 if diff >= 0.0 else -1.0)
						angles[a] -= push
						angles[b] += push
		var result := {}
		for i in others.size():
			result[others[i]] = Vector2.from_angle(angles[i])
		_departures[cell] = result
	return _departures[cell].get(toward, Vector2.ZERO)


## Fester Zufallswert pro Abschnitt: Überlappen sich zwei, fällt der mit dem größeren weg
func _priority(key: Vector3i) -> int:
	return world_gen.hash_cell(key.x * 2 + key.z, key.y, 404)


## Abschnitt anfordern: level 1 = nur berechnen, 2 = auch prüfen (wird wirklich gebraucht)
func _want(key: Vector3i, level: int) -> void:
	var entry: Entry = _entries.get(key)
	if entry:
		if level >= 2:
			entry.needed = true
	else:
		_wanted[key] = maxi(_wanted.get(key, 0), level)


## Bereich, den ein Abschnitt höchstens beeinflussen kann (bevor er berechnet ist)
func _edge_area(key: Vector3i) -> Rect2:
	var ends := _edge_nodes(key)
	var a: Vector3 = ends[0]
	var b: Vector3 = ends[1]
	var length := Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
	var rect := Rect2(a.x, a.z, 0.0, 0.0).expand(Vector2(b.x, b.z))
	return rect.grow(RoadSegment.corridor_half_width(length) + 150.0 + road_width + RoadSegment.MAX_BANK)


## Alle Verbindungen, die einen Bereich beeinflussen könnten
func _edges_touching(rect: Rect2) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var reach := 700.0
	var x0 := floori((rect.position.x - reach) / cell_size) - 1
	var x1 := floori((rect.end.x + reach) / cell_size)
	var z0 := floori((rect.position.y - reach) / cell_size) - 1
	var z1 := floori((rect.end.y + reach) / cell_size)
	for cz in range(z0, z1 + 1):
		for cx in range(x0, x1 + 1):
			for dir in 2:
				var cell := Vector2i(cx, cz)
				if _edge_exists(cell, dir) and _edge_area(Vector3i(cx, cz, dir)).intersects(rect):
					result.append(Vector3i(cx, cz, dir))
	return result


# ---------------------------------------------------------------------------
# Abfragen für Gelände, Spiel und Autopilot
# ---------------------------------------------------------------------------

## Fertige Straßen für einen Bereich: {"segments": [RoadSegment], "pads": PackedVector4Array}
## pads sind die Kreuzungen (Mitte x, y, z und Radius). Leeres Dictionary = noch nicht fertig.
func segments_for_rect(rect: Rect2) -> Dictionary:
	var segments: Array = []
	var cells := {}
	var complete := true
	for key in _edges_touching(rect):
		var entry: Entry = _entries.get(key)
		_want(key, 2)
		if entry == null or entry.state < State.CHECKED:
			complete = false
			continue
		if entry.kept and entry.segment.bounds.intersects(rect):
			segments.append(entry.segment)
			cells[Vector2i(key.x, key.y)] = true
			cells[_end_cell(key)] = true
	if not complete:
		return {}
	var pads := PackedVector4Array()
	for cell: Vector2i in cells:
		var junction := _junction(cell)
		if junction == null:
			complete = false
			continue
		# Etwas größer als die Kreuzungsfläche, damit das Gelände rundherum flach bleibt
		pads.append(Vector4(junction.center.x, junction.center.y, junction.center.z, junction.radius + 4.0))
	if not complete:
		return {}
	return {"segments": segments, "pads": pads}


## Sind alle Straßen rund um diesen Punkt fertig (inklusive Mesh und Kollision)?
func is_area_ready(center: Vector2, radius: float) -> bool:
	var rect := Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
	if segments_for_rect(rect).is_empty():
		return false
	for key in _edges_touching(rect):
		var entry: Entry = _entries[key]
		if entry.kept and entry.state != State.READY and _distance_to_rect(center, entry.segment.bounds) < radius:
			return false
	return true


## Nächste Stelle auf einer Straße. preferred_forward wählt die passende Fahrtrichtung.
## Ergebnis: {"found": bool, "transform": Transform3D}
func nearest_road_transform(near: Vector3, preferred_forward: Vector3 = Vector3.ZERO) -> Dictionary:
	var best_segment: RoadSegment = null
	var best_index := -1
	var best_distance := INF
	for entry: Entry in _entries.values():
		if entry.state != State.READY or not entry.kept:
			continue
		var points := entry.segment.points
		# Nicht direkt auf einer Kreuzung starten
		for i in range(6, points.size() - 6):
			var d := Vector2(points[i].x - near.x, points[i].z - near.z).length_squared()
			if d < best_distance:
				best_distance = d
				best_segment = entry.segment
				best_index = i
	if best_segment == null:
		return {"found": false}
	var p := best_segment.points[best_index]
	var forward := best_segment.direction_at(best_index)
	if preferred_forward != Vector3.ZERO and forward.dot(preferred_forward) < 0.0:
		forward = -forward
	var yaw := atan2(forward.x, forward.z)
	return {"found": true, "transform": Transform3D(Basis(Vector3.UP, yaw), p + Vector3.UP * 1.0)}


## Ein Fahrweg ab dem nächsten Straßenpunkt in Blickrichtung, über Kreuzungen hinweg.
## Für den Autopiloten im Benchmark.
func route_from(near: Vector3, forward: Vector3, min_length: float) -> PackedVector3Array:
	var route := PackedVector3Array()
	var best_key := Vector3i.ZERO
	var best_index := -1
	var best_distance := INF
	for key: Vector3i in _entries.keys():
		var entry: Entry = _entries[key]
		if entry.state < State.CHECKED or not entry.kept:
			continue
		var points := entry.segment.points
		for i in points.size():
			var d := points[i].distance_squared_to(near)
			if d < best_distance:
				best_distance = d
				best_key = key
				best_index = i
	if best_index == -1:
		return route
	var segment: RoadSegment = _entries[best_key].segment
	var going_forward := segment.direction_at(best_index).dot(forward) >= 0.0
	var key := best_key
	var visited := {}
	while true:
		visited[key] = true
		var points := segment.points
		if going_forward:
			for i in range(best_index, points.size()):
				route.append(points[i])
		else:
			for i in range(best_index, -1, -1):
				route.append(points[i])
		if (route.size() - 1) * RoadSegment.POINT_SPACING > min_length:
			break
		# Am Ende angekommen: an diesem Ort eine andere, noch nicht befahrene Straße nehmen
		var end_cell := _end_cell(key) if going_forward else Vector2i(key.x, key.y)
		var arriving := route[route.size() - 1] - route[maxi(route.size() - 7, 0)]
		arriving.y = 0.0
		var next := _next_segment_at(end_cell, visited, arriving.normalized())
		if next.is_empty():
			break
		key = next["key"]
		segment = _entries[key].segment
		going_forward = next["forward"]
		best_index = 1 if going_forward else segment.points.size() - 2
	return route


func _next_segment_at(cell: Vector2i, visited: Dictionary, arriving: Vector3) -> Dictionary:
	# Straßen, die an diesem Ort beginnen (vorwärts) oder enden (rückwärts).
	# Genommen wird die, bei der man am wenigsten abbiegen muss.
	var options := _arm_keys(cell)
	var best: Dictionary = {}
	var best_dot := -2.0
	for option: Array in options:
		var key: Vector3i = option[0]
		if visited.has(key):
			continue
		var entry: Entry = _entries.get(key)
		if entry == null or entry.state < State.CHECKED or not entry.kept:
			continue
		var points := entry.segment.points
		var leaving: Vector3 = points[mini(6, points.size() - 1)] - points[0] if option[1] \
			else points[maxi(points.size() - 7, 0)] - points[points.size() - 1]
		leaving.y = 0.0
		var dot := leaving.normalized().dot(arriving)
		if dot > best_dot:
			best_dot = dot
			best = {"key": key, "forward": option[1]}
	return best


# ---------------------------------------------------------------------------
# Kreuzungen
# ---------------------------------------------------------------------------

## Kreuzung an einem Ort. null = noch nicht alle Straßen dort geprüft.
func _junction(cell: Vector2i) -> RoadJunction:
	if _junctions.has(cell):
		return _junctions[cell]
	var arms: Array = []
	var complete := true
	for option: Array in _arm_keys(cell):
		var key: Vector3i = option[0]
		if not _edge_exists(Vector2i(key.x, key.y), key.z):
			continue
		var entry: Entry = _entries.get(key)
		_want(key, 2)
		if entry == null or entry.state < State.CHECKED:
			complete = false
			continue
		if entry.kept:
			arms.append([entry.segment, option[1]])
	if not complete:
		return null
	var junction := RoadJunction.new()
	junction.center = node_at(cell)
	junction.arms = arms
	junction.radius = _junction_size(arms)
	_junctions[cell] = junction
	return junction


## Wie weit die Straßen vor der Mitte enden: Je spitzer zwei Straßen aufeinander zulaufen,
## desto weiter draußen, sonst würden sich ihre Ränder schon vorher überlappen.
func _junction_size(arms: Array) -> float:
	var size := junction_radius
	var half := road_width * 0.5 + shoulder_width + RoadSegment.VERGE_WIDTH
	for a in arms.size():
		for b in range(a + 1, arms.size()):
			var angle := _arm_direction(arms[a]).angle_to(_arm_direction(arms[b]))
			size = maxf(size, half / tan(maxf(angle, 0.1) * 0.5) + 1.0)
	# Mehr geht nicht: dort ist die Straße schon nicht mehr flach
	return minf(size, RoadSegment.JUNCTION_FLAT * RoadSegment.POINT_SPACING)


## Richtung, in die eine Straße den Ort verlässt
func _arm_direction(arm: Array) -> Vector3:
	var points := (arm[0] as RoadSegment).points
	var n := points.size()
	var d: Vector3 = points[6] - points[0] if arm[1] else points[n - 7] - points[n - 1]
	d.y = 0.0
	return d.normalized()


# ---------------------------------------------------------------------------
# Hintergrund-Aufträge
# ---------------------------------------------------------------------------

func _prefetch() -> void:
	var p := Vector2(target.global_position.x, target.global_position.z)
	for key in _edges_touching(Rect2(p - Vector2.ONE * prefetch_distance, Vector2.ONE * prefetch_distance * 2.0)):
		_want(key, 2)


## Neue Abschnitte berechnen (die nächsten zuerst)
func _dispatch() -> void:
	if _wanted.is_empty() or _running >= max_parallel_jobs:
		return
	var p := Vector2(target.global_position.x, target.global_position.z)
	var keys: Array = _wanted.keys()
	keys.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return _edge_area(a).get_center().distance_squared_to(p) < _edge_area(b).get_center().distance_squared_to(p))
	for key: Vector3i in keys:
		if _running >= max_parallel_jobs:
			break
		var level: int = _wanted[key]
		_wanted.erase(key)
		if _entries.has(key):
			continue
		var ends := _edge_nodes(key)
		var segment := RoadSegment.new()
		segment.world_gen = world_gen
		segment.key = key
		segment.start = ends[0]
		segment.end = ends[1]
		segment.start_direction = _departure(Vector2i(key.x, key.y), _end_cell(key))
		segment.end_direction = _departure(_end_cell(key), Vector2i(key.x, key.y))
		segment.road_width = road_width
		segment.shoulder_width = shoulder_width
		segment.max_grade = max_grade
		segment.grid_step = grid_step
		segment.curve_radius = curve_radius
		segment.min_curve_radius = min_curve_radius
		segment.max_bank = max_bank
		var entry := Entry.new()
		entry.segment = segment
		entry.needed = level >= 2
		entry.task_id = WorkerThreadPool.add_task(segment.build, false, "Straße")
		_entries[key] = entry
		_running += 1


## Fertige Hintergrund-Aufträge übernehmen. Gibt zurück, wie viele es waren.
func _collect_finished() -> int:
	var finished := 0
	for entry: Entry in _entries.values():
		if entry.task_id == -1 or not WorkerThreadPool.is_task_completed(entry.task_id):
			continue
		WorkerThreadPool.wait_for_task_completion(entry.task_id)
		entry.task_id = -1
		_running -= 1
		finished += 1
		match entry.state:
			State.BUILDING:
				entry.state = State.BUILT
			State.CHECKING:
				entry.kept = not entry.check.overlaps
				entry.check = null
				entry.state = State.CHECKED
			State.MESHING:
				entry.state = State.READY
	return finished


## Berechnete Abschnitte prüfen und geprüfte (in Sichtweite) zu Meshes machen
func _advance() -> void:
	var p := Vector2(target.global_position.x, target.global_position.z)
	for key: Vector3i in _entries.keys():
		if _running >= max_parallel_jobs:
			return
		var entry: Entry = _entries[key]
		if entry.state == State.BUILT and entry.needed:
			_start_check(key, entry)
		elif entry.state == State.CHECKED and entry.kept \
				and _distance_to_rect(p, entry.segment.bounds) < mesh_distance + 200.0:
			_start_mesh(key, entry)


func _start_check(key: Vector3i, entry: Entry) -> void:
	if not entry.segment.valid:
		entry.kept = false
		entry.state = State.CHECKED
		return
	if not entry.has_neighbors:
		for other_key in _edges_touching(entry.segment.bounds):
			if other_key != key:
				entry.neighbors.append(other_key)
		entry.has_neighbors = true
	# Alle Nachbarn müssen berechnet sein. Wichtig sind nur die mit kleinerem Hash-Wert:
	# Überlappt dieser Abschnitt einen davon, fällt er weg.
	var others: Array = []
	var complete := true
	for other_key in entry.neighbors:
		var other: Entry = _entries.get(other_key)
		if other == null or other.state == State.BUILDING:
			_want(other_key, 1)
			complete = false
			continue
		if other.segment.valid and _priority(other_key) < _priority(key):
			others.append(other.segment)
	if not complete:
		return
	var check := OverlapCheck.new()
	check.segment = entry.segment
	check.others = others
	check.distance = road_width + 2.0 * (shoulder_width + RoadSegment.VERGE_WIDTH) + 2.0
	entry.check = check
	entry.task_id = WorkerThreadPool.add_task(check.run, false, "Straße prüfen")
	entry.state = State.CHECKING
	_running += 1


func _start_mesh(key: Vector3i, entry: Entry) -> void:
	var at_start := _junction(Vector2i(key.x, key.y))
	var at_end := _junction(_end_cell(key))
	if at_start == null or at_end == null:
		return
	var first := at_start.mouth_steps()
	var last := entry.segment.points.size() - 1 - at_end.mouth_steps()
	entry.task_id = WorkerThreadPool.add_task(entry.segment.build_mesh.bind(first, last), false, "Straßen-Mesh")
	entry.state = State.MESHING
	_running += 1


# ---------------------------------------------------------------------------
# Sichtbare Straßen, Kreuzungen, Kollision
# ---------------------------------------------------------------------------

func _update_visuals() -> void:
	var p := Vector2(target.global_position.x, target.global_position.z)
	for key: Vector3i in _entries.keys():
		var entry: Entry = _entries[key]
		if entry.task_id != -1:
			continue
		# Sehr weit weg: ganz vergessen (wird bei Bedarf neu berechnet).
		# Auch ungültige Abschnitte bleiben gemerkt, sonst würden sie ständig neu berechnet.
		if _distance_to_rect(p, _edge_area(key)) > FORGET_DISTANCE:
			_free_visuals(entry)
			_entries.erase(key)
			continue
		if entry.state != State.READY:
			continue
		var segment := entry.segment
		var distance := _distance_to_rect(p, segment.bounds)
		if distance < mesh_distance:
			if entry.mesh_instance == null:
				var mesh := ArrayMesh.new()
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, segment.mesh_arrays)
				mesh.surface_set_material(0, road_material)
				if not segment.bridge_arrays.is_empty():
					mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, segment.bridge_arrays)
					mesh.surface_set_material(1, bridge_material)
				entry.mesh_instance = MeshInstance3D.new()
				entry.mesh_instance.mesh = mesh
				# Brücken werfen Schatten, flache Straßen brauchen das nicht
				entry.mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON \
					if not segment.bridge_arrays.is_empty() else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				entry.mesh_instance.position = segment.origin
				add_child(entry.mesh_instance)
				# Leitplanken als eigenes Mesh, damit nur sie (und Brücken) Schatten werfen
				if not segment.rail_arrays.is_empty():
					var rail_mesh := ArrayMesh.new()
					rail_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, segment.rail_arrays)
					var rails := MeshInstance3D.new()
					rails.mesh = rail_mesh
					rails.material_override = rail_material
					entry.mesh_instance.add_child(rails)
		elif entry.mesh_instance:
			entry.mesh_instance.queue_free()
			entry.mesh_instance = null
		if distance < collision_distance and entry.body == null:
			entry.body = _make_body(segment.collision_faces)
		elif distance > collision_distance + 100.0 and entry.body:
			entry.body.queue_free()
			entry.body = null
	for cell: Vector2i in _junctions.keys():
		var junction: RoadJunction = _junctions[cell]
		var distance := Vector2(junction.center.x - p.x, junction.center.z - p.y).length()
		if distance > FORGET_DISTANCE:
			_free_junction(junction)
			_junctions.erase(cell)
			continue
		if junction.arms.is_empty():
			continue
		if distance < mesh_distance:
			if junction.mesh_instance == null:
				if junction.mesh_arrays.is_empty():
					junction.build()
				var mesh := ArrayMesh.new()
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, junction.mesh_arrays)
				junction.mesh_instance = MeshInstance3D.new()
				junction.mesh_instance.mesh = mesh
				junction.mesh_instance.material_override = road_material
				junction.mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				junction.mesh_instance.position = junction.center
				add_child(junction.mesh_instance)
		elif junction.mesh_instance:
			junction.mesh_instance.queue_free()
			junction.mesh_instance = null
		if distance < collision_distance and junction.body == null:
			if junction.mesh_arrays.is_empty():
				junction.build()
			junction.body = _make_body(junction.collision_faces)
		elif distance > collision_distance + 100.0 and junction.body:
			junction.body.queue_free()
			junction.body = null


func _make_body(faces: PackedVector3Array) -> StaticBody3D:
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	var body := StaticBody3D.new()
	body.add_child(collision)
	add_child(body)
	return body


func _free_visuals(entry: Entry) -> void:
	if entry.mesh_instance:
		entry.mesh_instance.queue_free()
		entry.mesh_instance = null
	if entry.body:
		entry.body.queue_free()
		entry.body = null


func _free_junction(junction: RoadJunction) -> void:
	if junction.mesh_instance:
		junction.mesh_instance.queue_free()
		junction.mesh_instance = null
	if junction.body:
		junction.body.queue_free()
		junction.body = null


func _distance_to_rect(point: Vector2, rect: Rect2) -> float:
	return point.distance_to(point.clamp(rect.position, rect.end))
