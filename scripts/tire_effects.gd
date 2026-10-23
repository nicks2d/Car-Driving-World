extends Node3D
## Reifenspuren und Rauch, wenn die Räder rutschen (Driften, Vollbremsung, Handbremse).
## Spuren: viele kleine dunkle Streifen in einem MultiMesh. Ist der Vorrat aufgebraucht,
## wird der älteste Streifen wiederverwendet, so bleibt die Rechenzeit immer gleich.
## Rauch: ein Partikelsystem an jedem Hinterrad.

## So viele Spur-Stücke gibt es höchstens (je ca. 0,4 m lang)
@export var max_marks: int = 3000
## Ab so viel Rutschen (0 bis 1, siehe car.gd wheel_slip) entsteht eine Spur
@export_range(0.0, 1.0) var mark_threshold: float = 0.25
## Breite und Deckkraft der Spur
@export var mark_width: float = 0.24
@export_range(0.0, 1.0) var mark_opacity: float = 0.75
## Ab so viel Rutschen raucht es an den Hinterrädern
@export_range(0.0, 1.0) var smoke_threshold: float = 0.45

const MARK_STEP: float = 0.4

var _car: Car
var _wheels: Array[VehicleWheel3D] = []
## Letzter Spurpunkt pro Rad (Vector3) oder null, wenn die Spur gerade unterbrochen ist
var _last_points: Array = []
var _marks: MultiMesh
var _next_mark: int = 0
var _smokes: Array[GPUParticles3D] = []


func _ready() -> void:
	_car = get_parent() as Car
	for child in _car.get_children():
		if child is VehicleWheel3D:
			_wheels.append(child)
			_last_points.append(null)
	_create_marks()
	for wheel in _wheels:
		if wheel.use_as_traction:
			_smokes.append(_create_smoke(wheel))


func _physics_process(_delta: float) -> void:
	var smoke_index := 0
	for i in _wheels.size():
		var wheel := _wheels[i]
		var slip := _car.wheel_slip(wheel)
		_update_mark(i, wheel, slip)
		if wheel.use_as_traction:
			var smoke := _smokes[smoke_index]
			smoke_index += 1
			smoke.emitting = slip > smoke_threshold
			smoke.amount_ratio = clampf((slip - smoke_threshold) / (1.0 - smoke_threshold) + 0.3, 0.0, 1.0)


## Spur verlängern: alle MARK_STEP Meter ein neues Stück vom letzten Punkt bis hierher
func _update_mark(i: int, wheel: VehicleWheel3D, slip: float) -> void:
	if slip < mark_threshold:
		_last_points[i] = null
		return
	var normal := wheel.get_contact_normal()
	# 2 cm über dem Boden, damit die Spur nicht mit der Straße flackert
	var point := wheel.get_contact_point() + normal * 0.02
	if _last_points[i] == null:
		_last_points[i] = point
		return
	var last: Vector3 = _last_points[i]
	var along := point - last
	if along.length() < MARK_STEP:
		return
	if along.length() > 3.0:
		# Zu großer Sprung (z. B. nach einem Reset): neu anfangen
		_last_points[i] = point
		return
	var side := normal.cross(along).normalized() * mark_width
	var mark_basis := Basis(side, normal, along)
	_marks.set_instance_transform(_next_mark, Transform3D(mark_basis, (last + point) * 0.5))
	_marks.set_instance_color(_next_mark, Color(1.0, 1.0, 1.0, mark_opacity * clampf(slip * 1.5, 0.4, 1.0)))
	_next_mark = (_next_mark + 1) % max_marks
	_last_points[i] = point


func _create_marks() -> void:
	# Ein flaches Viereck 1 x 1 m; Breite und Länge kommen aus der Transform jedes Stücks
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.orientation = PlaneMesh.FACE_Y
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.02, 0.02, 0.02)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.9
	quad.material = material
	_marks = MultiMesh.new()
	_marks.transform_format = MultiMesh.TRANSFORM_3D
	_marks.use_colors = true
	_marks.mesh = quad
	_marks.instance_count = max_marks
	# Alle Stücke erst einmal unsichtbar (Größe 0)
	for i in max_marks:
		_marks.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = _marks
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Die Spuren liegen fest in der Welt und fahren nicht mit dem Auto mit
	instance.top_level = true
	instance.global_transform = Transform3D.IDENTITY
	# Die Spuren können überall liegen: nie wegen der Sichtbarkeitsbox ausblenden
	instance.custom_aabb = AABB(Vector3(-1e6, -1e4, -1e6), Vector3(2e6, 2e4, 2e6))
	add_child(instance)


## Weißgrauer Rauch, der hinter dem Rad aufsteigt, größer wird und verblasst
func _create_smoke(wheel: VehicleWheel3D) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = 90
	particles.lifetime = 2.2
	particles.emitting = false
	# Partikel bleiben in der Welt stehen, wenn das Auto weiterfährt
	particles.local_coords = false
	particles.position = wheel.position + Vector3(0.0, -0.2, -0.1)
	particles.visibility_aabb = AABB(Vector3(-20, -5, -20), Vector3(40, 15, 40))
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0.0, 1.0, -0.5)
	process.spread = 35.0
	process.initial_velocity_min = 0.8
	process.initial_velocity_max = 2.0
	process.gravity = Vector3(0.0, 0.6, 0.0)
	process.damping_min = 1.0
	process.damping_max = 2.0
	process.scale_min = 0.6
	process.scale_max = 1.0
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.6))
	grow.add_point(Vector2(1.0, 3.4))
	var grow_texture := CurveTexture.new()
	grow_texture.curve = grow
	process.scale_curve = grow_texture
	var fade := Gradient.new()
	fade.set_color(0, Color(0.85, 0.85, 0.85, 0.3))
	fade.set_color(1, Color(0.85, 0.85, 0.85, 0.0))
	var fade_texture := GradientTexture1D.new()
	fade_texture.gradient = fade
	process.color_ramp = fade_texture
	particles.process_material = process
	# Ein weicher, runder Fleck als Bild für jedes Rauch-Partikel
	var puff := Gradient.new()
	puff.set_color(0, Color(1, 1, 1, 1))
	puff.set_color(1, Color(1, 1, 1, 0))
	var puff_texture := GradientTexture2D.new()
	puff_texture.gradient = puff
	puff_texture.fill = GradientTexture2D.FILL_RADIAL
	puff_texture.fill_from = Vector2(0.5, 0.5)
	puff_texture.fill_to = Vector2(0.5, 0.0)
	puff_texture.width = 64
	puff_texture.height = 64
	var material := StandardMaterial3D.new()
	material.albedo_texture = puff_texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.material = material
	particles.draw_pass_1 = quad
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_car.add_child.call_deferred(particles)
	return particles
