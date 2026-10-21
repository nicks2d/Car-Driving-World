class_name HorizonRing
extends MeshInstance3D
## Grobes Gelände weit hinter der Sichtweite (bis ca. 25 km), damit am Horizont
## immer Berge zu sehen sind. Es ist ein Ring um das Auto, der aus derselben
## Welt-Formel berechnet wird. Fährt man weit genug, wird er im Hintergrund neu gebaut.
## Wo die normalen Kacheln liegen, versinkt der Ring im Shader unter dem Boden.

## Innerer Rand des Rings (sollte deutlich innerhalb der Kachel-Sichtweite liegen)
@export var inner_radius: float = 1200.0
## Äußerer Rand des Rings
@export var outer_radius: float = 26000.0
## Anzahl der Ringe von innen nach außen
@export var ring_count: int = 110
## Anzahl der Punkte pro Ring
@export var segment_count: int = 720
## Nach so vielen Metern Fahrt wird der Ring neu um das Auto gebaut
@export var rebuild_distance: float = 600.0

var world_gen: WorldGen
var target: Node3D
var _job: RingJob
var _task_id: int = -1


## Hintergrund-Auftrag: berechnet Punkte und Dreiecke des Rings
class RingJob:
	var world_gen: WorldGen
	var center: Vector2
	var inner_radius: float
	var outer_radius: float
	var rings: int
	var segments: int
	var arrays: Array = []

	func run() -> void:
		var count := rings * segments
		var verts := PackedVector3Array()
		verts.resize(count)
		var colors := PackedColorArray()
		colors.resize(count)
		var ratio := outer_radius / inner_radius
		for r in rings:
			# Ringe liegen innen dicht und werden nach außen immer weiter (geometrisch)
			var radius := inner_radius * pow(ratio, float(r) / (rings - 1))
			for s in segments:
				var angle := TAU * s / segments
				var x := center.x + cos(angle) * radius
				var z := center.y + sin(angle) * radius
				var h := world_gen.natural_height(x, z)
				var water := 0.0
				var lake: WorldGen.Lake = world_gen.lake_at(x, z)
				if lake and Vector2(x, z).distance_to(lake.center) < lake.radius:
					h = lake.level
					water = 1.0
				var i := r * segments + s
				verts[i] = Vector3(x - center.x, h, z - center.y)
				colors[i] = Color(world_gen.forest_density(x, z, h, 0.1), 0.0, water, 1.0)
		# Normalen aus den Nachbarpunkten (quer zum Ring und entlang des Rings)
		var normals := PackedVector3Array()
		normals.resize(count)
		for r in rings:
			for s in segments:
				var i := r * segments + s
				var inner := verts[maxi(r - 1, 0) * segments + s]
				var outer := verts[mini(r + 1, rings - 1) * segments + s]
				var left := verts[r * segments + (s + segments - 1) % segments]
				var right := verts[r * segments + (s + 1) % segments]
				var n := (right - left).cross(outer - inner).normalized()
				normals[i] = n if n.y > 0.0 else -n
		# Dreiecke zwischen Ring r und r+1
		var indices := PackedInt32Array()
		indices.resize((rings - 1) * segments * 6)
		var k := 0
		for r in rings - 1:
			for s in segments:
				var a := r * segments + s
				var b := r * segments + (s + 1) % segments
				var c := a + segments
				var d := b + segments
				indices[k] = a
				indices[k + 1] = c
				indices[k + 2] = b
				indices[k + 3] = b
				indices[k + 4] = c
				indices[k + 5] = d
				k += 6
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices


func start(gen: WorldGen, follow: Node3D) -> void:
	world_gen = gen
	target = follow
	_start_job()


func _process(_delta: float) -> void:
	if world_gen == null or target == null:
		return
	if _task_id != -1:
		if WorkerThreadPool.is_task_completed(_task_id):
			WorkerThreadPool.wait_for_task_completion(_task_id)
			_task_id = -1
			var ring_mesh := ArrayMesh.new()
			ring_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _job.arrays)
			mesh = ring_mesh
			global_position = Vector3(_job.center.x, 0.0, _job.center.y)
			# Der Ring springt an die neue Stelle, ohne Übergang
			reset_physics_interpolation()
		return
	var here := Vector2(target.global_position.x, target.global_position.z)
	var ring_center := Vector2(global_position.x, global_position.z)
	if here.distance_to(ring_center) > rebuild_distance:
		_start_job()


func _exit_tree() -> void:
	if _task_id != -1:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1


func _start_job() -> void:
	_job = RingJob.new()
	_job.world_gen = world_gen
	_job.center = Vector2(target.global_position.x, target.global_position.z)
	_job.inner_radius = inner_radius
	_job.outer_radius = outer_radius
	_job.rings = ring_count
	_job.segments = segment_count
	_task_id = WorkerThreadPool.add_task(_job.run, false, "Horizont-Ring")


## Ist der Ring schon einmal gebaut worden?
func is_ready() -> bool:
	return mesh != null
