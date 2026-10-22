class_name WaterManager
extends Node3D
## Seen und alles, was das Auto im Wasser betrifft.
## - Für jeden See in der Nähe liegt eine flache, runde Wasserfläche auf Wasserhöhe.
##   (Flüsse baut der TerrainManager pro Kachel, siehe terrain_chunk_job.gd.)
## - Fährt das Auto ins Wasser, wird es stark gebremst und nach ein paar Sekunden
##   auf die nächste Straße gesetzt. Die Fahrphysik des Autos selbst bleibt unverändert.

@export var water_material: Material
## Bis zu dieser Entfernung werden Seen angezeigt
@export var lake_distance: float = 3500.0
## Bremskraft im Wasser (Newton pro m/s Geschwindigkeit)
@export var water_drag: float = 2500.0
## Nach so vielen Sekunden im Wasser geht es zurück auf die Straße
@export var reset_after_seconds: float = 3.0

var world_gen: WorldGen
var car: VehicleBody3D
var roads: RoadNetwork
var _lakes: Dictionary = {}  # Mittelpunkt (Vector2) -> MeshInstance3D
var _disc_mesh: ArrayMesh
var _update_timer: float = 0.0
var _time_in_water: float = 0.0


func start(gen: WorldGen, the_car: VehicleBody3D, road_network: RoadNetwork) -> void:
	world_gen = gen
	car = the_car
	roads = road_network
	_disc_mesh = _make_disc_mesh()


func _process(delta: float) -> void:
	if world_gen == null:
		return
	_update_timer -= delta
	if _update_timer > 0.0:
		return
	_update_timer = 0.5
	var p := Vector2(car.global_position.x, car.global_position.z)
	var area := Rect2(p - Vector2.ONE * lake_distance, Vector2.ONE * lake_distance * 2.0)
	var wanted := {}
	for lake: WorldGen.Lake in world_gen.lakes_near(area):
		wanted[lake.center] = lake
	for center: Vector2 in _lakes.keys():
		if not wanted.has(center):
			_lakes[center].queue_free()
			_lakes.erase(center)
	for center: Vector2 in wanted:
		if _lakes.has(center):
			continue
		var lake: WorldGen.Lake = wanted[center]
		var surface := MeshInstance3D.new()
		surface.mesh = _disc_mesh
		surface.material_override = water_material
		surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Etwas kleiner als der See: am Rand liegt das Ufer genau auf Wasserhöhe
		var radius := lake.radius - 1.0
		surface.position = Vector3(center.x, lake.level, center.y)
		surface.scale = Vector3(radius, 1.0, radius)
		add_child(surface)
		_lakes[center] = surface


func _physics_process(delta: float) -> void:
	if world_gen == null or car.freeze:
		return
	var p := car.global_position
	var lakes: Array = world_gen.lakes_near(Rect2(p.x - 1.0, p.z - 1.0, 2.0, 2.0))
	var level := world_gen.water_level_at(p.x, p.z, lakes)
	if level > WorldGen.NO_WATER and p.y < level + 0.2:
		# Im Wasser: kräftig abbremsen
		car.apply_central_force(-car.linear_velocity * water_drag)
		_time_in_water += delta
		if _time_in_water > reset_after_seconds:
			_time_in_water = 0.0
			var result := roads.nearest_road_transform(p, car.global_basis.z)
			if result["found"]:
				car.teleport(result["transform"])
	else:
		_time_in_water = 0.0


## Kreisscheibe mit Radius 1 (wird pro See skaliert)
func _make_disc_mesh() -> ArrayMesh:
	var verts := PackedVector3Array([Vector3.ZERO])
	var normals := PackedVector3Array([Vector3.UP])
	var uvs := PackedVector2Array([Vector2.ZERO])
	var indices := PackedInt32Array()
	var steps := 96
	for i in steps:
		var angle := TAU * i / steps
		verts.append(Vector3(cos(angle), 0.0, sin(angle)))
		normals.append(Vector3.UP)
		uvs.append(Vector2.ZERO)
	for i in steps:
		indices.append_array([0, i + 1, (i + 1) % steps + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
