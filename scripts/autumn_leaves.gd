class_name AutumnLeaves
extends GPUParticles3D
## Herbstlaub: Hinter dem Auto wirbeln Blätter auf, wo Laubbäume an der Straße stehen. Wie viele,
## hängt vom Herbst-Gewicht (Weather.autumn_weight), vom Laubwald an der Stelle
## (gleiche Formel wie die Bäume der Kacheln) und vom Tempo ab. Die Blätter werden vom Sog hinter
## dem Auto mitgerissen (starten mit gut der Hälfte des Tempos), werden schnell langsamer, wirbeln
## und taumeln zu Boden (local_coords aus: sie bleiben in der Welt).

@export var car: Car
@export var world_gen: WorldGen
@export var weather: Weather
## So viele Blätter höchstens gleichzeitig, ab diesem Tempo (km/h) die volle Menge
@export var max_leaves: int = 240
@export var full_speed_kmh: float = 110.0

var _timer: float = 0.0


func _ready() -> void:
	amount = max_leaves
	lifetime = 3.0
	local_coords = false
	emitting = false
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(1.0, 0.1, 0.6)
	# Richtung im Auto: nach vorne (+Z, mit dem Sog) und etwas nach oben
	process.direction = Vector3(0.0, 0.45, 1.0)
	process.spread = 35.0
	process.initial_velocity_min = 1.5
	process.initial_velocity_max = 4.5
	process.gravity = Vector3(0.0, -2.5, 0.0)
	process.damping_min = 7.0
	process.damping_max = 13.0
	process.angular_velocity_min = -360.0
	process.angular_velocity_max = 360.0
	process.scale_min = 0.7
	process.scale_max = 1.3
	var colors := Gradient.new()
	colors.set_color(0, Color(0.85, 0.45, 0.08))
	colors.set_color(1, Color(0.55, 0.12, 0.05))
	colors.add_point(0.5, Color(0.9, 0.7, 0.15))
	var ramp := GradientTexture1D.new()
	ramp.gradient = colors
	process.color_initial_ramp = ramp
	process_material = process
	var leaf := QuadMesh.new()
	leaf.size = Vector2(0.12, 0.08)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 0.8
	# Blattform: Ellipse (runder Verlauf, hart abgeschnitten)
	var shape := Gradient.new()
	shape.set_color(0, Color(1, 1, 1, 1))
	shape.set_color(1, Color(1, 1, 1, 0))
	shape.add_point(0.85, Color(1, 1, 1, 1))
	var shape_texture := GradientTexture2D.new()
	shape_texture.gradient = shape
	shape_texture.fill = GradientTexture2D.FILL_RADIAL
	shape_texture.fill_from = Vector2(0.5, 0.5)
	shape_texture.fill_to = Vector2(1.0, 0.5)
	shape_texture.width = 32
	shape_texture.height = 32
	material.albedo_texture = shape_texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.5
	# Direkt vor der Kamera unsichtbar (sonst fliegen dort große Flächen durchs Bild)
	material.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
	material.distance_fade_min_distance = 1.5
	material.distance_fade_max_distance = 4.0
	leaf.material = material
	draw_pass_1 = leaf


func _physics_process(delta: float) -> void:
	if car == null or world_gen == null or weather == null:
		return
	# Hinter dem Auto, auf Höhe der Hinterräder, ausgerichtet wie das Auto
	global_transform = Transform3D(car.global_basis.orthonormalized(),
		car.global_position - car.global_basis.z * 2.2 + Vector3.UP * 0.2)
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.3
	var autumn := weather.autumn_weight()
	var kmh := car.linear_velocity.length() * 3.6
	var ratio := autumn * clampf(kmh / full_speed_kmh, 0.0, 1.0) * _broadleaf_density(car.global_position)
	emitting = ratio > 0.03
	amount_ratio = clampf(ratio * 2.5, 0.0, 1.0)
	# Mitgerissen: gut die Hälfte des eigenen Tempos
	var speed := car.linear_velocity.length()
	var process := process_material as ParticleProcessMaterial
	process.initial_velocity_min = speed * 0.4
	process.initial_velocity_max = speed * 0.75


## Laubwald an der Stelle: Walddichte (wie im Gelände) mal Anteil der Laubbäume (im Tal mehr)
func _broadleaf_density(p: Vector3) -> float:
	var h := world_gen.natural_height(p.x, p.z)
	var forest := world_gen.forest_density(p.x, p.z, h, 0.1)
	var conifer_share := clampf(0.4 + (h - 250.0) / 500.0 + world_gen.variation(p.x, p.z) * 0.3, 0.1, 0.95)
	return clampf(forest * (1.0 - conifer_share) * 2.0, 0.0, 1.0)
