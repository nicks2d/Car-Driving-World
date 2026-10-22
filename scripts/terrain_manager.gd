class_name TerrainManager
extends Node3D
## Lädt Gelände-Kacheln (Chunks) rund um das Auto und entfernt ferne wieder.
## Nahe Kacheln sind fein (viele Punkte), ferne grob. Berechnet wird im Hintergrund
## (WorkerThreadPool), eingebaut werden pro Bild nur wenige fertige Kacheln.

## Material für das Gelände (terrain.gdshader)
@export var terrain_material: Material
## Material für Flüsse (water.gdshader)
@export var water_material: Material
## Kantenlänge einer Kachel in Metern
@export var chunk_size: float = 256.0
## Bis zu dieser Entfernung gibt es detailliertes Gelände (dahinter: Horizont-Ring)
@export var view_distance: float = 2000.0
## Ab diesen Entfernungen wird die nächst gröbere Detailstufe benutzt
@export var lod_distances: PackedFloat32Array = PackedFloat32Array([450.0, 900.0, 1500.0])
## Abstand der Rasterpunkte pro Detailstufe (Meter). Muss chunk_size glatt teilen.
@export var lod_spacings: PackedFloat32Array = PackedFloat32Array([2.0, 4.0, 8.0, 16.0])
## Bis zu dieser Entfernung bekommen Kacheln eine Kollision
@export var collision_distance: float = 320.0
## So viele Kacheln werden gleichzeitig im Hintergrund berechnet
@export var max_parallel_jobs: int = 6
## So viele fertige Kacheln werden pro Bild eingebaut (mehr = schneller, aber Ruckelgefahr)
@export var max_uploads_per_frame: int = 2

var world_gen: WorldGen
var target: Node3D
var roads: RoadNetwork
var _chunks: Dictionary = {}  # Vector2i -> Chunk
var _running_jobs: int = 0


## Alles, was zu einer Kachel gehört
class Chunk:
	var coord: Vector2i
	var lod: int = -1
	var mesh_instance: MeshInstance3D
	var water_instance: MeshInstance3D
	var body: StaticBody3D
	var job: TerrainChunkJob
	var task_id: int = -1
	var removed: bool = false
	## Feine Höhen (Detailstufe 0), für Kollision und Vegetation
	var heights: PackedFloat32Array
	var grid_size: int = 0


## Wird vom Spiel aufgerufen, sobald die Welt-Formel bereit ist
func start(gen: WorldGen, follow: Node3D, road_network: RoadNetwork) -> void:
	world_gen = gen
	target = follow
	roads = road_network


func _process(_delta: float) -> void:
	if world_gen == null or target == null:
		return
	_collect_finished_jobs()
	_update_chunks()


func _exit_tree() -> void:
	# Laufende Hintergrund-Aufträge sauber beenden lassen
	for chunk: Chunk in _chunks.values():
		if chunk.task_id != -1:
			WorkerThreadPool.wait_for_task_completion(chunk.task_id)
			chunk.task_id = -1


func _update_chunks() -> void:
	var center := Vector2(target.global_position.x, target.global_position.z)
	var reach := ceili(view_distance / chunk_size)
	var center_coord := Vector2i(floori(center.x / chunk_size), floori(center.y / chunk_size))
	var todo: Array = []

	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var coord := center_coord + Vector2i(dx, dz)
			var distance := _distance_to_chunk(center, coord)
			if distance > view_distance:
				continue
			var chunk: Chunk = _chunks.get(coord)
			if chunk == null:
				chunk = Chunk.new()
				chunk.coord = coord
				_chunks[coord] = chunk
			var wanted_lod := _lod_for_distance(distance)
			if chunk.lod != wanted_lod and chunk.task_id == -1:
				todo.append([distance, chunk, wanted_lod])
			_update_collision(chunk, distance)

	# Kacheln, die weit genug weg sind, wieder löschen (mit etwas Puffer)
	for coord: Vector2i in _chunks.keys():
		if _distance_to_chunk(center, coord) > view_distance + 200.0:
			_remove_chunk(_chunks[coord])

	# Die nächsten Kacheln zuerst berechnen
	todo.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for entry: Array in todo:
		if _running_jobs >= max_parallel_jobs:
			break
		var chunk: Chunk = entry[1]
		# Erst bauen, wenn alle Straßen in der Nähe fertig berechnet sind
		var road_data := roads.segments_for_rect(_chunk_rect(chunk.coord))
		if road_data.is_empty():
			continue
		_start_job(chunk, entry[2], road_data)


func _chunk_rect(coord: Vector2i) -> Rect2:
	return Rect2(coord.x * chunk_size, coord.y * chunk_size, chunk_size, chunk_size)


func _start_job(chunk: Chunk, lod: int, road_data: Dictionary) -> void:
	var job := TerrainChunkJob.new()
	job.world_gen = world_gen
	job.coord = chunk.coord
	job.lod = lod
	job.spacing = lod_spacings[lod]
	job.chunk_size = chunk_size
	job.road_segments = road_data["segments"]
	job.road_pads = road_data["pads"]
	job.pad_radius = roads.pad_radius
	chunk.job = job
	chunk.task_id = WorkerThreadPool.add_task(job.run, false, "Gelände-Kachel")
	_running_jobs += 1


func _collect_finished_jobs() -> void:
	var uploads := 0
	for chunk: Chunk in _chunks.values():
		if chunk.task_id == -1 or not WorkerThreadPool.is_task_completed(chunk.task_id):
			continue
		if uploads >= max_uploads_per_frame:
			break
		WorkerThreadPool.wait_for_task_completion(chunk.task_id)
		chunk.task_id = -1
		_running_jobs -= 1
		if chunk.removed:
			continue
		_apply_job(chunk)
		uploads += 1
	# Gelöschte Kacheln endgültig vergessen, sobald ihr Auftrag fertig ist
	for coord: Vector2i in _chunks.keys():
		var chunk: Chunk = _chunks[coord]
		if chunk.removed and chunk.task_id == -1:
			_chunks.erase(coord)


func _apply_job(chunk: Chunk) -> void:
	var job := chunk.job
	chunk.job = null
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, job.arrays)
	if chunk.mesh_instance == null:
		chunk.mesh_instance = MeshInstance3D.new()
		chunk.mesh_instance.material_override = terrain_material
		chunk.mesh_instance.position = Vector3(chunk.coord.x * chunk_size, 0.0, chunk.coord.y * chunk_size)
		add_child(chunk.mesh_instance)
	chunk.mesh_instance.mesh = mesh
	_apply_water(chunk, job)
	chunk.lod = job.lod
	if job.lod == 0:
		chunk.heights = job.heights
		chunk.grid_size = job.grid_size


func _apply_water(chunk: Chunk, job: TerrainChunkJob) -> void:
	if job.water_arrays.is_empty():
		if chunk.water_instance:
			chunk.water_instance.queue_free()
			chunk.water_instance = null
		return
	var water_mesh := ArrayMesh.new()
	water_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, job.water_arrays)
	if chunk.water_instance == null:
		chunk.water_instance = MeshInstance3D.new()
		chunk.water_instance.material_override = water_material
		chunk.water_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		chunk.water_instance.position = chunk.mesh_instance.position
		add_child(chunk.water_instance)
	chunk.water_instance.mesh = water_mesh


func _update_collision(chunk: Chunk, distance: float) -> void:
	if distance < collision_distance and chunk.body == null and chunk.grid_size > 0:
		_create_collision(chunk)
	elif distance > collision_distance + 80.0 and chunk.body != null:
		chunk.body.queue_free()
		chunk.body = null


func _create_collision(chunk: Chunk) -> void:
	# Höhenfeld: sehr effizient für Gelände. Es liegt mittig um seinen Ursprung,
	# deshalb wird es in die Mitte der Kachel gesetzt und auf den Punktabstand skaliert.
	var shape := HeightMapShape3D.new()
	shape.map_width = chunk.grid_size
	shape.map_depth = chunk.grid_size
	shape.map_data = chunk.heights
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.scale = Vector3(lod_spacings[0], 1.0, lod_spacings[0])
	collision.position = Vector3(chunk_size * 0.5, 0.0, chunk_size * 0.5)
	chunk.body = StaticBody3D.new()
	chunk.body.position = Vector3(chunk.coord.x * chunk_size, 0.0, chunk.coord.y * chunk_size)
	chunk.body.add_child(collision)
	add_child(chunk.body)


func _remove_chunk(chunk: Chunk) -> void:
	if chunk.removed:
		return
	chunk.removed = true
	if chunk.mesh_instance:
		chunk.mesh_instance.queue_free()
		chunk.mesh_instance = null
	if chunk.water_instance:
		chunk.water_instance.queue_free()
		chunk.water_instance = null
	if chunk.body:
		chunk.body.queue_free()
		chunk.body = null


## Kürzeste Entfernung vom Punkt zur Kachel (0, wenn der Punkt darin liegt)
func _distance_to_chunk(point: Vector2, coord: Vector2i) -> float:
	var low := Vector2(coord.x * chunk_size, coord.y * chunk_size)
	var high := low + Vector2(chunk_size, chunk_size)
	var nearest := point.clamp(low, high)
	return point.distance_to(nearest)


func _lod_for_distance(distance: float) -> int:
	for i in lod_distances.size():
		if distance < lod_distances[i]:
			return i
	return lod_spacings.size() - 1


## Ist rund um die Position alles mit Kollision geladen? (Zum Freigeben des Autos)
func is_area_ready(position_3d: Vector3) -> bool:
	if world_gen == null:
		return false
	var center := Vector2(position_3d.x, position_3d.z)
	var reach := ceili(collision_distance / chunk_size)
	var center_coord := Vector2i(floori(center.x / chunk_size), floori(center.y / chunk_size))
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var coord := center_coord + Vector2i(dx, dz)
			if _distance_to_chunk(center, coord) > collision_distance * 0.5:
				continue
			var chunk: Chunk = _chunks.get(coord)
			if chunk == null or chunk.body == null:
				return false
	return true


## Wie viele Kacheln noch auf ihre (neue) Detailstufe warten
func pending_count() -> int:
	if target == null:
		return 0
	var center := Vector2(target.global_position.x, target.global_position.z)
	var count := 0
	for chunk: Chunk in _chunks.values():
		if chunk.removed:
			continue
		var distance := _distance_to_chunk(center, chunk.coord)
		if distance <= view_distance and (chunk.task_id != -1 or chunk.lod != _lod_for_distance(distance)):
			count += 1
	return count


func chunk_count() -> int:
	return _chunks.size()
