class_name RoadNetwork
extends Node3D
## Das Straßennetz. Die Welt ist in Zellen (cell_size) eingeteilt, in jeder liegt höchstens
## ein „Ort“ (Knoten), bevorzugt flach und im Tal. Benachbarte Orte werden mit einer
## Straße verbunden (nach rechts und nach vorne). Jeder Abschnitt hängt nur von seinen
## zwei Orten ab: Deshalb ist das Netz endlos, nahtlos und bei gleichem Seed immer gleich.
## Die Abschnitte werden im Hintergrund berechnet (RoadSegment.build).

## Material der Fahrbahn (road.gdshader)
@export var road_material: Material
## Größe einer Zelle mit höchstens einem Ort (Meter)
@export var cell_size: float = 1200.0
## Wahrscheinlichkeit, dass zwei benachbarte Orte verbunden sind
@export_range(0.0, 1.0) var connection_chance: float = 0.8
## Breite der Fahrbahn (zwei Spuren) und des Banketts daneben
@export var road_width: float = 7.0
@export var shoulder_width: float = 1.2
## Höchste Steigung (0.10 = 10 %)
@export var max_grade: float = 0.10
## Rasterabstand der Wegsuche (kleiner = genauer, aber langsamer)
@export var grid_step: float = 18.0
## Radius der runden Kreuzungsfläche an einem Ort
@export var pad_radius: float = 11.0
## Bis zu dieser Entfernung werden Straßen vorab berechnet
@export var prefetch_distance: float = 2800.0
## Bis zu dieser Entfernung sind Straßen sichtbar
@export var mesh_distance: float = 2300.0
## Bis zu dieser Entfernung haben Straßen eine Kollision
@export var collision_distance: float = 600.0
## So viele Abschnitte werden gleichzeitig im Hintergrund berechnet
@export var max_parallel_jobs: int = 4

var world_gen: WorldGen
var target: Node3D
var _nodes: Dictionary = {}  # Vector2i -> Vector3 (Ort) oder null (kein Ort in der Zelle)
var _entries: Dictionary = {}  # Vector3i (Zelle x, Zelle z, Richtung) -> Entry
var _wanted: Dictionary = {}  # Vector3i -> true (soll berechnet werden)
var _edge_cache: Dictionary = {}  # Vector3i -> bool (gibt es diese Verbindung?)
var _running: int = 0
var _pads: Dictionary = {}  # Vector2i -> MeshInstance3D
var _pad_mesh: ArrayMesh


## Ein Straßenabschnitt und was dazu in der Szene steht
class Entry:
	var segment: RoadSegment
	var task_id: int = -1
	var done: bool = false
	var mesh_instance: MeshInstance3D
	var body: StaticBody3D


func start(gen: WorldGen, follow: Node3D) -> void:
	world_gen = gen
	target = follow
	_pad_mesh = _make_pad_mesh()


func _process(_delta: float) -> void:
	if world_gen == null or target == null:
		return
	_collect_finished()
	_prefetch()
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
	var cell := Vector2i(key.x, key.y)
	var other := cell + (Vector2i(1, 0) if key.z == 0 else Vector2i(0, 1))
	return [node_at(cell), node_at(other)]


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

## Fertige Straßen für einen Bereich. Leeres Dictionary = noch nicht alle berechnet.
func segments_for_rect(rect: Rect2) -> Dictionary:
	var segments: Array = []
	var pads := PackedVector3Array()
	var ready := true
	for key in _edges_touching(rect):
		var entry: Entry = _entries.get(key)
		if entry == null or not entry.done:
			_wanted[key] = true
			ready = false
			continue
		if entry.segment.valid and entry.segment.bounds.intersects(rect):
			segments.append(entry.segment)
			pads.append(entry.segment.start)
			pads.append(entry.segment.end)
	if not ready:
		return {}
	return {"segments": segments, "pads": pads}


## Sind alle Straßen rund um diesen Punkt fertig berechnet?
func is_area_ready(center: Vector2, radius: float) -> bool:
	return not segments_for_rect(Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0)).is_empty()


## Nächste Stelle auf einer Straße. preferred_forward wählt die passende Fahrtrichtung.
## Ergebnis: {"found": bool, "transform": Transform3D}
func nearest_road_transform(near: Vector3, preferred_forward: Vector3 = Vector3.ZERO) -> Dictionary:
	var best_segment: RoadSegment = null
	var best_index := -1
	var best_distance := INF
	for entry: Entry in _entries.values():
		if not entry.done or not entry.segment.valid:
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
		if not entry.done or not entry.segment.valid:
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
		var end_cell := Vector2i(key.x, key.y)
		if going_forward:
			end_cell += Vector2i(1, 0) if key.z == 0 else Vector2i(0, 1)
		var next := _next_segment_at(end_cell, visited)
		if next.is_empty():
			break
		key = next["key"]
		segment = _entries[key].segment
		going_forward = next["forward"]
		best_index = 1 if going_forward else segment.points.size() - 2
	return route


func _next_segment_at(cell: Vector2i, visited: Dictionary) -> Dictionary:
	# Straßen, die an diesem Ort beginnen (vorwärts) oder enden (rückwärts)
	var options := [
		[Vector3i(cell.x, cell.y, 0), true], [Vector3i(cell.x, cell.y, 1), true],
		[Vector3i(cell.x - 1, cell.y, 0), false], [Vector3i(cell.x, cell.y - 1, 1), false]]
	for option: Array in options:
		var key: Vector3i = option[0]
		if visited.has(key):
			continue
		var entry: Entry = _entries.get(key)
		if entry and entry.done and entry.segment.valid:
			return {"key": key, "forward": option[1]}
	return {}


# ---------------------------------------------------------------------------
# Hintergrund-Aufträge
# ---------------------------------------------------------------------------

func _prefetch() -> void:
	var p := Vector2(target.global_position.x, target.global_position.z)
	for key in _edges_touching(Rect2(p - Vector2.ONE * prefetch_distance, Vector2.ONE * prefetch_distance * 2.0)):
		if not _entries.has(key):
			_wanted[key] = true


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
		_wanted.erase(key)
		if _entries.has(key):
			continue
		var ends := _edge_nodes(key)
		var segment := RoadSegment.new()
		segment.world_gen = world_gen
		segment.key = key
		segment.start = ends[0]
		segment.end = ends[1]
		segment.road_width = road_width
		segment.shoulder_width = shoulder_width
		segment.max_grade = max_grade
		segment.grid_step = grid_step
		var entry := Entry.new()
		entry.segment = segment
		entry.task_id = WorkerThreadPool.add_task(segment.build, false, "Straße")
		_entries[key] = entry
		_running += 1


func _collect_finished() -> void:
	for entry: Entry in _entries.values():
		if entry.task_id != -1 and WorkerThreadPool.is_task_completed(entry.task_id):
			WorkerThreadPool.wait_for_task_completion(entry.task_id)
			entry.task_id = -1
			entry.done = true
			_running -= 1


# ---------------------------------------------------------------------------
# Sichtbare Straßen, Kollision, Kreuzungsflächen
# ---------------------------------------------------------------------------

func _update_visuals() -> void:
	var p := Vector2(target.global_position.x, target.global_position.z)
	var pad_cells := {}
	for key: Vector3i in _entries.keys():
		var entry: Entry = _entries[key]
		if not entry.done:
			continue
		var segment := entry.segment
		# Sehr weit weg: ganz vergessen (wird bei Bedarf neu berechnet).
		# Auch ungültige Abschnitte bleiben gemerkt, sonst würden sie ständig neu berechnet.
		if _distance_to_rect(p, _edge_area(key)) > prefetch_distance + 1500.0:
			_free_visuals(entry)
			_entries.erase(key)
			continue
		if not segment.valid:
			continue
		var distance := _distance_to_rect(p, segment.bounds)
		if distance < mesh_distance:
			if entry.mesh_instance == null:
				var mesh := ArrayMesh.new()
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, segment.mesh_arrays)
				entry.mesh_instance = MeshInstance3D.new()
				entry.mesh_instance.mesh = mesh
				entry.mesh_instance.material_override = road_material
				entry.mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				entry.mesh_instance.position = segment.origin
				add_child(entry.mesh_instance)
			pad_cells[Vector2i(key.x, key.y)] = segment.start
			var other := Vector2i(key.x, key.y) + (Vector2i(1, 0) if key.z == 0 else Vector2i(0, 1))
			pad_cells[other] = segment.end
		elif entry.mesh_instance:
			entry.mesh_instance.queue_free()
			entry.mesh_instance = null
		if distance < collision_distance and entry.body == null:
			var shape := ConcavePolygonShape3D.new()
			shape.backface_collision = true
			shape.set_faces(segment.collision_faces)
			var collision := CollisionShape3D.new()
			collision.shape = shape
			entry.body = StaticBody3D.new()
			entry.body.add_child(collision)
			add_child(entry.body)
		elif distance > collision_distance + 100.0 and entry.body:
			entry.body.queue_free()
			entry.body = null
	# Runde Kreuzungsflächen an den Orten
	for cell: Vector2i in _pads.keys():
		if not pad_cells.has(cell):
			_pads[cell].queue_free()
			_pads.erase(cell)
	for cell: Vector2i in pad_cells:
		if not _pads.has(cell):
			var pad := MeshInstance3D.new()
			pad.mesh = _pad_mesh
			pad.material_override = road_material
			pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			pad.position = pad_cells[cell] + Vector3(0.0, 0.03, 0.0)
			add_child(pad)
			_pads[cell] = pad


func _free_visuals(entry: Entry) -> void:
	if entry.mesh_instance:
		entry.mesh_instance.queue_free()
		entry.mesh_instance = null
	if entry.body:
		entry.body.queue_free()
		entry.body = null


func _distance_to_rect(point: Vector2, rect: Rect2) -> float:
	return point.distance_to(point.clamp(rect.position, rect.end))


## Flache runde Scheibe für Kreuzungen (ohne Fahrbahnmarkierung)
func _make_pad_mesh() -> ArrayMesh:
	var verts := PackedVector3Array([Vector3.ZERO])
	var normals := PackedVector3Array([Vector3.UP])
	var uvs := PackedVector2Array([Vector2(0.3, 0.0)])
	var tangents := PackedFloat32Array([1.0, 0.0, 0.0, 1.0])
	var indices := PackedInt32Array()
	var steps := 32
	for i in steps:
		var angle := TAU * i / steps
		verts.append(Vector3(cos(angle), 0.0, sin(angle)) * pad_radius)
		normals.append(Vector3.UP)
		uvs.append(Vector2(0.3, 0.0))
		tangents.append_array([1.0, 0.0, 0.0, 1.0])
	for i in steps:
		var a := i + 1
		var b := (i + 1) % steps + 1
		# Mitte, aktueller, nächster: so zeigt die Vorderseite nach oben
		indices.append_array([0, a, b])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
