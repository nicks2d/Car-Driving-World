class_name GrassManager
extends Node3D
## Gras rund um das Auto. Die Umgebung ist in kleine Felder (patch_size) eingeteilt.
## Für jedes Feld in der Nähe werden im Hintergrund viele Grasbüschel verteilt
## (nicht auf Straßen, im Wasser, an steilen Hängen oder im Schnee) und als MultiMesh
## angezeigt. Ferne Felder werden wieder entfernt.

@export var grass_material: Material
## Bis zu dieser Entfernung wächst Gras (passend zu fade_end im grass.gdshader)
@export var radius: float = 56.0
## Kantenlänge eines Gras-Felds in Metern (muss die Kachelgröße glatt teilen)
@export var patch_size: float = 16.0
## Grasbüschel pro Quadratmeter (mehr = dichter, aber langsamer)
@export var density: float = 3.0
@export var max_parallel_jobs: int = 3

var world_gen: WorldGen
var target: Node3D
var terrain: TerrainManager
var roads: RoadNetwork
var _patches: Dictionary = {}  # Vector2i -> Patch
var _running: int = 0
var _mesh: ArrayMesh


class Patch:
	var instance: MultiMeshInstance3D
	var job: GrassJob
	var task_id: int = -1
	var removed: bool = false


## Hintergrund-Auftrag: Grasbüschel eines Felds verteilen
class GrassJob:
	var world_gen: WorldGen
	var patch: Vector2i
	var patch_size: float
	var density: float
	var chunk_origin: Vector2
	var heights: PackedFloat32Array
	var grid_size: int
	var spacing: float
	var road_segments: Array
	var road_pads: PackedVector4Array
	var buffer := PackedFloat32Array()

	func run() -> void:
		var origin := Vector2(patch.x * patch_size, patch.y * patch_size)
		var rect := Rect2(origin, Vector2(patch_size, patch_size))
		var roads := RoadQuery.new(road_segments, road_pads, rect)
		var lakes: Array = world_gen.lakes_near(rect)
		var rng := RandomNumberGenerator.new()
		rng.seed = world_gen.hash_cell(patch.x, patch.y, 505)
		var count := int(patch_size * patch_size * density)
		var snow := world_gen.snow_height - 150.0
		for i in count:
			var x := origin.x + rng.randf() * patch_size
			var z := origin.y + rng.randf() * patch_size
			var angle := rng.randf() * TAU
			var size := rng.randf()
			var bright := rng.randf()
			var lx := x - chunk_origin.x
			var lz := z - chunk_origin.y
			var h := _height(lx, lz)
			var gx := (_height(lx + spacing, lz) - _height(lx - spacing, lz)) / (2.0 * spacing)
			var gz := (_height(lx, lz + spacing) - _height(lx, lz - spacing)) / (2.0 * spacing)
			# Nicht an steilen Hängen, nicht im Schnee, nicht auf der Straße, nicht im Wasser
			if gx * gx + gz * gz > 0.36 or h > snow:
				continue
			if not roads.is_empty() and roads.is_on_road(x, z, 0.8):
				continue
			var level := world_gen.water_level_at(x, z, lakes)
			if level > WorldGen.NO_WATER and h < level + 0.5:
				continue
			var height := lerpf(0.28, 0.6, size)
			var width := lerpf(1.0, 1.6, size)
			var c := cos(angle)
			var s := sin(angle)
			var dryness := world_gen.variation(x, z) * 0.5 + 0.5
			buffer.append_array([c * width, 0.0, s * width, x - origin.x, 0.0, height, 0.0, h - 0.05,
				-s * width, 0.0, c * width, z - origin.y, bright, dryness, 0.0, 0.0])

	## Höhe aus dem feinen Raster der Kachel, genau wie im Mesh (zwei Dreiecke pro Quadrat)
	func _height(lx: float, lz: float) -> float:
		var fx := clampf(lx / spacing, 0.0, grid_size - 1.001)
		var fz := clampf(lz / spacing, 0.0, grid_size - 1.001)
		var ix := floori(fx)
		var iz := floori(fz)
		var tx := fx - ix
		var tz := fz - iz
		var h00 := heights[iz * grid_size + ix]
		var h10 := heights[iz * grid_size + ix + 1]
		var h01 := heights[(iz + 1) * grid_size + ix]
		var h11 := heights[(iz + 1) * grid_size + ix + 1]
		if tx + tz <= 1.0:
			return h00 + (h10 - h00) * tx + (h01 - h00) * tz
		return h11 + (h01 - h11) * (1.0 - tx) + (h10 - h11) * (1.0 - tz)


func start(gen: WorldGen, follow: Node3D, terrain_manager: TerrainManager, road_network: RoadNetwork) -> void:
	world_gen = gen
	target = follow
	terrain = terrain_manager
	roads = road_network
	_mesh = VegetationMeshes.grass_clump()


func _process(_delta: float) -> void:
	if world_gen == null:
		return
	_collect_finished()
	var p := Vector2(target.global_position.x, target.global_position.z)
	var reach := ceili(radius / patch_size)
	var center := Vector2i(floori(p.x / patch_size), floori(p.y / patch_size))
	var todo: Array = []
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var coord := center + Vector2i(dx, dz)
			var distance := _distance_to_patch(p, coord)
			if distance > radius or _patches.has(coord):
				continue
			todo.append([distance, coord])
	todo.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for entry: Array in todo:
		if _running >= max_parallel_jobs:
			break
		_start_job(entry[1])
	for coord: Vector2i in _patches.keys():
		if _distance_to_patch(p, coord) > radius + 24.0:
			_remove(coord)


func _exit_tree() -> void:
	for patch: Patch in _patches.values():
		if patch.task_id != -1:
			WorkerThreadPool.wait_for_task_completion(patch.task_id)
			patch.task_id = -1


func _start_job(coord: Vector2i) -> void:
	var origin := Vector2(coord.x * patch_size, coord.y * patch_size)
	var chunk_coord := Vector2i(floori(origin.x / terrain.chunk_size), floori(origin.y / terrain.chunk_size))
	var fine := terrain.fine_heights(chunk_coord)
	if fine.is_empty():
		return
	var road_data := roads.segments_for_rect(Rect2(origin, Vector2(patch_size, patch_size)))
	if road_data.is_empty():
		return
	var job := GrassJob.new()
	job.world_gen = world_gen
	job.patch = coord
	job.patch_size = patch_size
	job.density = density
	job.chunk_origin = Vector2(chunk_coord.x * terrain.chunk_size, chunk_coord.y * terrain.chunk_size)
	job.heights = fine["heights"]
	job.grid_size = fine["grid_size"]
	job.spacing = fine["spacing"]
	job.road_segments = road_data["segments"]
	job.road_pads = road_data["pads"]
	var patch := Patch.new()
	patch.job = job
	patch.task_id = WorkerThreadPool.add_task(job.run, false, "Gras")
	_patches[coord] = patch
	_running += 1


func _collect_finished() -> void:
	for coord: Vector2i in _patches.keys():
		var patch: Patch = _patches[coord]
		if patch.task_id == -1 or not WorkerThreadPool.is_task_completed(patch.task_id):
			continue
		WorkerThreadPool.wait_for_task_completion(patch.task_id)
		patch.task_id = -1
		_running -= 1
		if patch.removed:
			_patches.erase(coord)
			continue
		var buffer := patch.job.buffer
		patch.job = null
		if buffer.is_empty():
			continue
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_custom_data = true
		multimesh.mesh = _mesh
		multimesh.instance_count = int(buffer.size() / 16.0)
		multimesh.buffer = buffer
		patch.instance = MultiMeshInstance3D.new()
		patch.instance.multimesh = multimesh
		patch.instance.material_override = grass_material
		patch.instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		patch.instance.position = Vector3(coord.x * patch_size, 0.0, coord.y * patch_size)
		add_child(patch.instance)


func _remove(coord: Vector2i) -> void:
	var patch: Patch = _patches[coord]
	if patch.instance:
		patch.instance.queue_free()
		patch.instance = null
	if patch.task_id != -1:
		patch.removed = true
	else:
		_patches.erase(coord)


func _distance_to_patch(point: Vector2, coord: Vector2i) -> float:
	var low := Vector2(coord.x * patch_size, coord.y * patch_size)
	return point.distance_to(point.clamp(low, low + Vector2(patch_size, patch_size)))
