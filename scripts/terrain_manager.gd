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
## So oft (Sekunden) wird geprüft, welche Kacheln gebraucht werden (und sofort, wenn eine
## Kachel fertig wurde). Jedes Bild wäre unnötig teuer.
@export var update_interval: float = 0.1
## Höchstens so viele wartende Kacheln fragen pro Prüfung, ob ihre Straßen fertig sind
@export var road_checks_per_update: int = 6

@export_group("Laden bei hohem Tempo")
## Kacheln vor dem Auto zuerst berechnen: Bezugspunkt so viele Sekunden Fahrweg voraus
@export var lookahead_seconds: float = 3.0
## ... aber höchstens so viele Meter voraus
@export var max_lookahead: float = 400.0
## Ab diesem Tempo (km/h) dürfen mehr Kacheln gleichzeitig berechnet werden
@export var fast_speed_kmh: float = 150.0
@export var fast_parallel_jobs: int = 8

@export_group("Vegetation")
## Material für Bäume und Büsche (foliage.gdshader) und für Felsen
@export var foliage_material: Material
@export var rock_material: Material
## Kahle Laubbäume im Winter (foliage_bare.gdshader)
@export var bare_tree_material: Material
## Bis zu dieser Detailstufe gibt es Bäume (0 = nur ganz nah, 2 = bis ca. 1,5 km)
@export_range(0, 3) var vegetation_max_lod: int = 2
## Abstand der möglichen Baumplätze in Metern (kleiner = dichterer Wald, langsamer)
@export var tree_spacing: float = 7.0
## Abstand der möglichen Felsplätze in Metern
@export var rock_spacing: float = 22.0
## Bis zu dieser Detailstufe werfen Bäume Schatten (0 = nur die nächsten Kacheln)
@export_range(0, 3) var vegetation_shadow_lod: int = 0
## Bäume in drei Stufen: sehr detailliert bis zu dieser Entfernung (Mitte einer 128-m-Zelle, Meter),
## dahinter die mittlere Version, ab Detailstufe 2 Impostoren (Bilder). Übergang gerastert über so viele Meter.
@export var near_tree_distance: float = 170.0
@export var near_tree_fade: float = 35.0
## Ferne Bäume als Impostoren (aus: einfache Modelle wie früher; zum Vergleichen der Leistung)
@export var use_impostors: bool = true
## So lange (Sekunden) blenden Gelände und Pflanzen beim Wechsel der Detailstufe über
@export var lod_fade_time: float = 0.6

var world_gen: WorldGen
var target: Node3D
var roads: RoadNetwork
var _chunks: Dictionary = {}  # Vector2i -> Chunk
var _running_jobs: int = 0
## Stand der Einstellungen: Kacheln mit älterem Stand werden nach und nach neu gebaut
var _generation: int = 0
var _base_lod_distances := PackedFloat32Array()
var _base_tree_spacing: float = 0.0
var _update_timer: float = 0.0
## Pflanzen-Modelle: Art -> [nah, mittel/fern] (Bäume zusätzlich in _near_tree_meshes: sehr detailliert)
var _veg_meshes: Dictionary = {}
var _near_tree_meshes: Dictionary = {}
## Ferne Bäume als Bilder (TreeImpostors) und ihre Materialien: Art -> [normal, Ausblenden]
var _impostors: TreeImpostors
var _impostor_materials: Dictionary = {}
## Beim Wechsel der Detailstufe: alte Kacheln und Pflanzen blenden aus [Knoten, Zeit]
var _fading: Array = []
## Ausblende-Varianten der Materialien (Original -> Variante)
var _fade_materials: Dictionary = {}
## Höhenbereich der Pflanzen der Kachel, die gerade eingebaut wird (für die Kiste der MultiMeshes)
var _veg_height_range := Vector2.ZERO
## Laubbäume und Büsche: wie foliage_material, aber mit Herbstfarben (deciduous = true)
var _deciduous_material: Material
var _bare_trees: bool = false
## Karte der fertigen Kacheln (1 Pixel = 1 Kachel, weiß = Kachel da), für den Horizont-Ring:
## Nur dort versinkt er unter dem Boden. Sie liegt um das Auto und wandert mit.
var chunk_mask: ImageTexture
var mask_origin: Vector2 = Vector2.ZERO
var mask_size: float = 1.0
const MASK_CELLS: int = 32
const MASK_HALF: int = 16
var _mask_image: Image
var _mask_center := Vector2i(1 << 30, 0)
var _mask_dirty: bool = true
## Geschwindigkeit des Ziels (x/z, Meter pro Sekunde), für das Laden in Fahrtrichtung
var _velocity := Vector2.ZERO
var _last_target := Vector2.ZERO
var _trunk_shape := CylinderShape3D.new()
var _rock_shape := SphereShape3D.new()


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
	## Höhen für die Kollision, mit NaN an Tunnelportalen (leer = wie heights)
	var collision_heights: PackedFloat32Array
	var grid_size: int = 0
	## Mit welchem Stand der Einstellungen gebaut (siehe set_detail)
	var generation: int = 0
	var pending_generation: int = 0
	## Bäume und Felsen: Art -> Array der MultiMeshInstance3D (Bäume nah: mehrere Zellen und Stufen)
	var veg_instances: Dictionary = {}
	## Stämme und große Felsen (x, y, z, Radius) und ihre Kollisionskörper
	var colliders: PackedFloat32Array
	var veg_bodies: Array[RID] = []


## Wird vom Spiel aufgerufen, sobald die Welt-Formel bereit ist
func start(gen: WorldGen, follow: Node3D, road_network: RoadNetwork) -> void:
	world_gen = gen
	target = follow
	roads = road_network
	_veg_meshes = {
		"conifer": [VegetationMeshes.conifer(true), VegetationMeshes.conifer(false)],
		"broadleaf": [VegetationMeshes.broadleaf(true), VegetationMeshes.broadleaf(false)],
		"bush": [VegetationMeshes.bush(), VegetationMeshes.bush()],
		"reed": [VegetationMeshes.reed(), VegetationMeshes.reed()],
		"rock0": [VegetationMeshes.rock(3), VegetationMeshes.rock(3)],
		"rock1": [VegetationMeshes.rock(8), VegetationMeshes.rock(8)],
		"rock2": [VegetationMeshes.rock(15), VegetationMeshes.rock(15)],
	}
	_near_tree_meshes = {"conifer": VegetationMeshes.conifer_near(), "broadleaf": VegetationMeshes.broadleaf_near()}
	_deciduous_material = foliage_material.duplicate()
	(_deciduous_material as ShaderMaterial).set_shader_parameter("deciduous", true)
	# Impostoren im Hintergrund backen; bis dahin haben ferne Kacheln die einfachen Bäume
	_impostors = TreeImpostors.new()
	add_child(_impostors)
	_impostors.baked.connect(_on_impostors_baked)
	var noise: Texture2D = (foliage_material as ShaderMaterial).get_shader_parameter("leaf_noise")
	_impostors.bake.call_deferred(_near_tree_meshes, noise)
	_trunk_shape.radius = 0.4
	_trunk_shape.height = 6.0
	_rock_shape.radius = 1.0


func _process(delta: float) -> void:
	var started := Time.get_ticks_usec()
	_timed_process(delta)
	FrameCosts.add("Gelände", started)


func _timed_process(delta: float) -> void:
	if world_gen == null or target == null:
		return
	# Tempo messen (weich, ein Sprung zählt nicht)
	var here := Vector2(target.global_position.x, target.global_position.z)
	if delta > 0.0:
		var moved := here - _last_target
		var now := moved / delta if moved.length() < 100.0 else Vector2.ZERO
		_velocity = _velocity.lerp(now, clampf(delta * 3.0, 0.0, 1.0))
	_last_target = here
	_update_fading(delta)
	_update_timer -= delta
	if _collect_finished_jobs() > 0 or _update_timer <= 0.0:
		_update_timer = update_interval
		_update_chunks()


func _exit_tree() -> void:
	# Laufende Hintergrund-Aufträge sauber beenden lassen
	for chunk: Chunk in _chunks.values():
		if chunk.task_id != -1:
			WorkerThreadPool.wait_for_task_completion(chunk.task_id)
			chunk.task_id = -1
		_free_vegetation_collision(chunk)


func _update_chunks() -> void:
	var center := Vector2(target.global_position.x, target.global_position.z)
	var reach := ceili(view_distance / chunk_size)
	var center_coord := Vector2i(floori(center.x / chunk_size), floori(center.y / chunk_size))
	var todo: Array = []
	# Bezugspunkt für die Reihenfolge: ein Stück voraus in Fahrtrichtung
	var focus := center + (_velocity * lookahead_seconds).limit_length(max_lookahead)

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
			if (chunk.lod != wanted_lod or chunk.generation != _generation) and chunk.task_id == -1:
				# Fehlende Kacheln vor feineren Detailstufen, alles vom Bezugspunkt aus gesehen
				var key := _distance_to_chunk(focus, coord) * (1.0 if chunk.lod == -1 else 1.5)
				todo.append([key, chunk, wanted_lod])
			_update_collision(chunk, distance)

	# Kacheln, die weit genug weg sind, wieder löschen (mit etwas Puffer)
	for coord: Vector2i in _chunks.keys():
		if _distance_to_chunk(center, coord) > view_distance + 200.0:
			_remove_chunk(_chunks[coord])

	_update_mask(center_coord)

	# Die nächsten Kacheln zuerst berechnen
	todo.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var road_checks := 0
	var job_limit := fast_parallel_jobs if _velocity.length() * 3.6 > fast_speed_kmh else max_parallel_jobs
	for entry: Array in todo:
		if _running_jobs >= job_limit or road_checks >= road_checks_per_update:
			break
		road_checks += 1
		var chunk: Chunk = entry[1]
		# Erst bauen, wenn alle Straßen in der Nähe fertig berechnet sind
		var road_data := roads.segments_for_rect(_chunk_rect(chunk.coord))
		if road_data.is_empty():
			continue
		_start_job(chunk, entry[2], road_data)


## Karte der fertigen Kacheln neu zeichnen, wenn sich etwas geändert hat oder das Auto
## zu weit von ihrer Mitte weg ist
func _update_mask(center_coord: Vector2i) -> void:
	if absi(center_coord.x - _mask_center.x) > 4 or absi(center_coord.y - _mask_center.y) > 4:
		_mask_center = center_coord
		_mask_dirty = true
	if not _mask_dirty:
		return
	_mask_dirty = false
	if _mask_image == null:
		_mask_image = Image.create(MASK_CELLS, MASK_CELLS, false, Image.FORMAT_R8)
	var first := _mask_center - Vector2i(MASK_HALF, MASK_HALF)
	for y in MASK_CELLS:
		for x in MASK_CELLS:
			var chunk: Chunk = _chunks.get(first + Vector2i(x, y))
			var loaded := chunk != null and not chunk.removed and chunk.mesh_instance != null
			_mask_image.set_pixel(x, y, Color.WHITE if loaded else Color.BLACK)
	if chunk_mask == null:
		chunk_mask = ImageTexture.create_from_image(_mask_image)
	else:
		chunk_mask.update(_mask_image)
	mask_origin = Vector2(first) * chunk_size
	mask_size = MASK_CELLS * chunk_size


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
	job.with_vegetation = lod <= vegetation_max_lod
	job.tree_spacing = tree_spacing
	job.rock_spacing = rock_spacing
	chunk.pending_generation = _generation
	chunk.job = job
	chunk.task_id = WorkerThreadPool.add_task(job.run, false, "Gelände-Kachel")
	_running_jobs += 1


## Fertige Hintergrund-Aufträge einbauen. Gibt zurück, wie viele es waren.
func _collect_finished_jobs() -> int:
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
	return uploads


func _apply_job(chunk: Chunk) -> void:
	var started := Time.get_ticks_usec()
	var job := chunk.job
	chunk.job = null
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, job.arrays)
	# Wechsel der Detailstufe: die alte Kachel blendet kurz gerastert aus (kein sichtbares Aufploppen)
	if chunk.mesh_instance and chunk.mesh_instance.mesh and chunk.lod >= 0 and chunk.lod != job.lod:
		var old := MeshInstance3D.new()
		old.mesh = chunk.mesh_instance.mesh
		old.position = chunk.mesh_instance.position
		old.cast_shadow = chunk.mesh_instance.cast_shadow
		add_child(old)
		_start_fade(old, terrain_material)
	if chunk.mesh_instance == null:
		chunk.mesh_instance = MeshInstance3D.new()
		chunk.mesh_instance.material_override = terrain_material
		chunk.mesh_instance.position = Vector3(chunk.coord.x * chunk_size, 0.0, chunk.coord.y * chunk_size)
		add_child(chunk.mesh_instance)
	chunk.mesh_instance.mesh = mesh
	_mask_dirty = true
	_apply_water(chunk, job)
	FrameCosts.add("Gelände: Mesh", started)
	started = Time.get_ticks_usec()
	_apply_vegetation(chunk, job)
	FrameCosts.add("Gelände: Pflanzen", started)
	started = Time.get_ticks_usec()
	chunk.lod = job.lod
	var rebuilt := chunk.generation != chunk.pending_generation
	chunk.generation = chunk.pending_generation
	if job.lod == 0:
		chunk.heights = job.heights
		chunk.collision_heights = job.collision_heights
		chunk.grid_size = job.grid_size
		chunk.colliders = job.colliders
		# Neu gebaut mit anderer Vegetation: Stämme und Felsen neu
		if rebuilt and chunk.body != null:
			_free_vegetation_collision(chunk)
			_create_vegetation_collision(chunk)


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


func _apply_vegetation(chunk: Chunk, job: TerrainChunkJob) -> void:
	_veg_height_range = job.vegetation_height_range if job.vegetation_height_range.x <= job.vegetation_height_range.y \
		else Vector2(0.0, 2000.0)
	# Alte Pflanzen: beim Wechsel der Detailstufe kurz gerastert ausblenden, sonst gleich weg
	var lod_changed := chunk.lod >= 0 and chunk.lod != job.lod
	for nodes: Array in chunk.veg_instances.values():
		for node: GeometryInstance3D in nodes:
			if lod_changed and node.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
				_start_fade(node, node.material_override)
			else:
				node.queue_free()
	chunk.veg_instances.clear()
	for kind: String in job.vegetation:
		var buffer: PackedFloat32Array = job.vegetation[kind]
		if buffer.is_empty():
			continue
		var tree := kind == "conifer" or kind == "broadleaf"
		# Büsche und Schilf nur in der Nähe, in der Ferne sieht man sie ohnehin nicht
		if (kind == "bush" or kind == "reed") and job.lod > 1:
			continue
		var nodes: Array = []
		if tree and job.lod == 0 and near_tree_distance > 0.0:
			nodes = _near_trees(chunk, kind, buffer, job.tree_quarters.get(kind, []))
		elif tree and job.lod >= 2 and _impostors.ready_to_use and use_impostors:
			nodes = [_veg_instance(chunk, buffer, _impostors.quad_mesh(), _impostor_material(kind, false))]
		else:
			var mesh: Mesh = _veg_meshes[kind][0 if job.lod <= 1 else 1]
			var instance := _veg_instance(chunk, buffer, mesh, _material_for(kind))
			# Schatten nur bei den nächsten Kacheln (Büsche, Felsen)
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if job.lod <= vegetation_shadow_lod \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			nodes = [instance]
		chunk.veg_instances[kind] = nodes


## Bäume in der nächsten Detailstufe: pro 128-m-Zelle die sehr detaillierte Version (nah) und die mittlere
## (dahinter), gerastert übergeblendet (Sichtweiten mit Übergang). Schatten wirft ein eigener, unsichtbarer
## Satz mit der mittleren Version für die ganze Kachel: so kosten die Schatten nicht mehr als vorher.
func _near_trees(chunk: Chunk, kind: String, buffer: PackedFloat32Array, quarters: Array) -> Array:
	var nodes: Array = []
	var material := _material_for(kind)
	for part: PackedFloat32Array in quarters:
		if part.is_empty():
			continue
		var near := _veg_instance(chunk, part, _near_tree_meshes[kind], material)
		near.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		near.visibility_range_end = near_tree_distance
		near.visibility_range_end_margin = near_tree_fade
		near.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		var mid := _veg_instance(chunk, part, _veg_meshes[kind][0], material)
		mid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mid.visibility_range_begin = near_tree_distance
		mid.visibility_range_begin_margin = near_tree_fade
		mid.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		nodes.append_array([near, mid])
	if vegetation_shadow_lod >= 0:
		var shadow := _veg_instance(chunk, buffer, _veg_meshes[kind][0], material)
		shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		nodes.append(shadow)
	return nodes


## Ein MultiMesh für diese Pflanzen (16 Werte pro Exemplar: Lage und Zufallswerte)
func _veg_instance(chunk: Chunk, buffer: PackedFloat32Array, mesh: Mesh, material: Material) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	# Kiste vorgeben: Sonst rechnet Godot sie beim Einbauen aus allen Exemplaren aus und wartet dafür auf den
	# Render-Thread (gemessen bis 19 ms pro MultiMesh). Kachelfläche mit Rand, Höhe aus dem Auftrag plus
	# höchster Baum.
	var range := _veg_height_range
	multimesh.custom_aabb = AABB(Vector3(-25.0, range.x - 6.0, -25.0), Vector3(chunk_size + 50.0, range.y - range.x + 40.0,
		chunk_size + 50.0))
	multimesh.instance_count = int(buffer.size() / 16.0)
	multimesh.buffer = buffer
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.position = chunk.mesh_instance.position
	add_child(instance)
	return instance


## Impostor-Material einer Baumart (fade = Variante zum Ausblenden)
func _impostor_material(kind: String, fade: bool) -> ShaderMaterial:
	if not _impostor_materials.has(kind):
		var noise: Texture2D = (foliage_material as ShaderMaterial).get_shader_parameter("leaf_noise")
		var normal := _impostors.material_for(kind, kind == "broadleaf", noise, false)
		var fading := _impostors.material_for(kind, kind == "broadleaf", noise, true)
		_impostor_materials[kind] = [normal, fading]
		_fade_materials[normal] = fading
		for material: ShaderMaterial in [normal, fading]:
			material.set_shader_parameter("bare", kind == "broadleaf" and _bare_trees)
	return _impostor_materials[kind][1 if fade else 0]


## Impostoren fertig: ferne Kacheln bekommen sie sofort (statt der einfachen Bäume)
func _on_impostors_baked() -> void:
	for chunk: Chunk in _chunks.values():
		if chunk.lod < 2:
			continue
		for kind: String in ["conifer", "broadleaf"]:
			for node: MultiMeshInstance3D in chunk.veg_instances.get(kind, []):
				node.multimesh.mesh = _impostors.quad_mesh()
				node.material_override = _impostor_material(kind, false)


## Knoten gerastert ausblenden (über lod_fade_time), dann freigeben. material = sein Material; ohne passende
## Ausblende-Variante wird er gleich freigegeben.
func _start_fade(node: GeometryInstance3D, material: Material) -> void:
	var fade_material := _fade_material(material)
	if fade_material == null:
		node.queue_free()
		return
	node.material_override = fade_material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.set_instance_shader_parameter("fade_out", 1.0)
	_fading.append([node, 0.0])


func _fade_material(material: Material) -> Material:
	if material == null:
		return null
	if _fade_materials.has(material):
		return _fade_materials[material]
	var shader_material := material as ShaderMaterial
	if shader_material == null:
		return null
	var variant: Shader = null
	if shader_material.shader.resource_path == "res://shaders/foliage.gdshader":
		variant = preload("res://shaders/foliage_fade.gdshader")
	elif shader_material.shader.resource_path == "res://shaders/terrain.gdshader":
		variant = preload("res://shaders/terrain_fade.gdshader")
	if variant == null:
		return null
	var copy := shader_material.duplicate() as ShaderMaterial
	copy.shader = variant
	_fade_materials[material] = copy
	return copy


func _update_fading(delta: float) -> void:
	for k in range(_fading.size() - 1, -1, -1):
		var entry: Array = _fading[k]
		var node: GeometryInstance3D = entry[0]
		entry[1] = float(entry[1]) + delta
		if not is_instance_valid(node) or float(entry[1]) >= lod_fade_time:
			if is_instance_valid(node):
				node.queue_free()
			_fading.remove_at(k)
			continue
		node.set_instance_shader_parameter("fade_out", 1.0 - float(entry[1]) / lod_fade_time)


func _material_for(kind: String) -> Material:
	if kind.begins_with("rock"):
		return rock_material
	if kind == "broadleaf" and _bare_trees and bare_tree_material:
		return bare_tree_material
	if kind == "broadleaf" or kind == "bush":
		return _deciduous_material
	return foliage_material


## Winter: Laubbäume ohne Blätter (eigenes Material, das Löcher in die Krone schneidet).
## Nur im Winter, weil so ein Material mehr Rechenzeit kostet.
func set_bare_trees(bare: bool) -> void:
	if bare == _bare_trees or _deciduous_material == null:
		return
	_bare_trees = bare
	if _impostor_materials.has("broadleaf"):
		for material: ShaderMaterial in _impostor_materials["broadleaf"]:
			material.set_shader_parameter("bare", bare)
	for chunk: Chunk in _chunks.values():
		for instance: MultiMeshInstance3D in chunk.veg_instances.get("broadleaf", []):
			if instance.multimesh.mesh != _impostors.quad_mesh():
				instance.material_override = _material_for("broadleaf")


## Kollision für Baumstämme und große Felsen, direkt im PhysicsServer (ohne Tausende Nodes).
## Wichtig: pro Körper nur wenige Formen. Jede neue Form lässt den Körper seine Formen neu
## zusammenbauen; 1000 Formen an einem Körper dauerten über 30 ms (sichtbarer Ruckler).
## Deshalb ein Körper pro 64 × 64 m.
func _create_vegetation_collision(chunk: Chunk) -> void:
	if chunk.colliders.is_empty():
		return
	var cell := 64.0
	var bodies := {}  # Vector2i -> RID
	var chunk_origin := Vector3(chunk.coord.x * chunk_size, 0.0, chunk.coord.y * chunk_size)
	for i in range(0, chunk.colliders.size(), 4):
		var p := Vector3(chunk.colliders[i], chunk.colliders[i + 1], chunk.colliders[i + 2])
		var radius := chunk.colliders[i + 3]
		var group := Vector2i(floori(p.x / cell), floori(p.z / cell))
		if not bodies.has(group):
			var new_body := PhysicsServer3D.body_create()
			PhysicsServer3D.body_set_mode(new_body, PhysicsServer3D.BODY_MODE_STATIC)
			PhysicsServer3D.body_set_space(new_body, get_world_3d().space)
			PhysicsServer3D.body_set_state(new_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), chunk_origin))
			bodies[group] = new_body
			chunk.veg_bodies.append(new_body)
		var body: RID = bodies[group]
		if radius < 0.5:
			PhysicsServer3D.body_add_shape(body, _trunk_shape.get_rid(), Transform3D(Basis(), p + Vector3.UP * 3.0))
		else:
			PhysicsServer3D.body_add_shape(body, _rock_shape.get_rid(),
				Transform3D(Basis().scaled(Vector3.ONE * radius), p + Vector3.UP * radius * 0.3))


func _free_vegetation_collision(chunk: Chunk) -> void:
	for body in chunk.veg_bodies:
		PhysicsServer3D.free_rid(body)
	chunk.veg_bodies.clear()


func _update_collision(chunk: Chunk, distance: float) -> void:
	if distance < collision_distance and chunk.body == null and chunk.grid_size > 0:
		var started := Time.get_ticks_usec()
		_create_collision(chunk)
		FrameCosts.add("Gelände: Kollision", started)
	elif distance > collision_distance + 80.0 and chunk.body != null:
		chunk.body.queue_free()
		chunk.body = null
		_free_vegetation_collision(chunk)


func _create_collision(chunk: Chunk) -> void:
	# Höhenfeld: sehr effizient für Gelände. Es liegt mittig um seinen Ursprung,
	# deshalb wird es in die Mitte der Kachel gesetzt und auf den Punktabstand skaliert.
	var shape := HeightMapShape3D.new()
	shape.map_width = chunk.grid_size
	shape.map_depth = chunk.grid_size
	shape.map_data = chunk.heights if chunk.collision_heights.is_empty() else chunk.collision_heights
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.scale = Vector3(lod_spacings[0], 1.0, lod_spacings[0])
	collision.position = Vector3(chunk_size * 0.5, 0.0, chunk_size * 0.5)
	chunk.body = StaticBody3D.new()
	chunk.body.position = Vector3(chunk.coord.x * chunk_size, 0.0, chunk.coord.y * chunk_size)
	chunk.body.add_child(collision)
	add_child(chunk.body)
	_create_vegetation_collision(chunk)


func _remove_chunk(chunk: Chunk) -> void:
	if chunk.removed:
		return
	chunk.removed = true
	_mask_dirty = true
	if chunk.mesh_instance:
		chunk.mesh_instance.queue_free()
		chunk.mesh_instance = null
	if chunk.water_instance:
		chunk.water_instance.queue_free()
		chunk.water_instance = null
	for nodes: Array in chunk.veg_instances.values():
		for instance: MultiMeshInstance3D in nodes:
			instance.queue_free()
	chunk.veg_instances.clear()
	_free_vegetation_collision(chunk)
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
## Einstellungen: Sichtweite (Meter), Baumdichte (1 = normal) und bis zu welcher Detailstufe
## es Bäume gibt. Geänderte Vegetation: alle Kacheln werden nach und nach neu gebaut (die alten
## bleiben sichtbar, bis die neuen fertig sind).
func set_detail(sight: float, vegetation_density: float, max_vegetation_lod: int) -> void:
	if _base_lod_distances.is_empty():
		_base_lod_distances = lod_distances.duplicate()
		_base_tree_spacing = tree_spacing
	view_distance = sight
	var factor := clampf(sight / 2000.0, 0.65, 1.3)
	for i in lod_distances.size():
		lod_distances[i] = _base_lod_distances[i] * factor
	var spacing := _base_tree_spacing / sqrt(maxf(vegetation_density, 0.1))
	if not is_equal_approx(spacing, tree_spacing) or max_vegetation_lod != vegetation_max_lod:
		tree_spacing = spacing
		vegetation_max_lod = max_vegetation_lod
		_generation += 1
	_update_timer = 0.0


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


## Anteil der Kacheln rund um eine Stelle, die schon mit Kollision fertig sind (0–1), für den Ladebalken
func area_progress(position_3d: Vector3) -> float:
	if world_gen == null:
		return 0.0
	var center := Vector2(position_3d.x, position_3d.z)
	var reach := ceili(collision_distance / chunk_size)
	var center_coord := Vector2i(floori(center.x / chunk_size), floori(center.y / chunk_size))
	var total := 0
	var done := 0
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var coord := center_coord + Vector2i(dx, dz)
			if _distance_to_chunk(center, coord) > collision_distance * 0.5:
				continue
			total += 1
			var chunk: Chunk = _chunks.get(coord)
			if chunk != null and chunk.body != null:
				done += 1
	return float(done) / total if total > 0 else 1.0


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


## Feine Höhen einer Kachel (für das Gras). Leeres Dictionary, wenn noch nicht da.
func fine_heights(coord: Vector2i) -> Dictionary:
	var chunk: Chunk = _chunks.get(coord)
	if chunk == null or chunk.removed or chunk.grid_size == 0:
		return {}
	return {"heights": chunk.heights, "grid_size": chunk.grid_size, "spacing": lod_spacings[0]}


func chunk_count() -> int:
	return _chunks.size()
