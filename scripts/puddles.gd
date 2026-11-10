class_name Puddles
extends Node3D
## Pfützen nach Regen: Der Straßen-Shader zeigt sie vor allem in Senken (RoadSegment.sag). Fährt
## das Auto auf nasser Straße schnell durch eine Senke, spritzt an den Vorderrädern eine
## Wasserfontäne, es platscht, und das Lenkrad zieht kurz (ein kleiner Ruck um die Hochachse).
## Pro Senke nur einmal, bis das Auto wieder herausgefahren ist.

@export var car: Car
@export var limits: SpeedLimits
## Ab dieser Nässe (Car.wetness) und diesem Tempo (km/h) spritzt es
@export var min_wetness: float = 0.4
@export var min_speed_kmh: float = 25.0
## Ab diesem Senken-Wert (0–1) steht dort eine Pfütze
@export var min_sag: float = 0.45
## Wie stark das Lenkrad zieht (Drehimpuls je Tonne bei 100 km/h)
@export var pull_strength: float = 900.0

var _fountains: Array[GPUParticles3D] = []
var _splash: AudioStreamPlayer3D
var _inside: bool = false
## So oft hat es gespritzt (für Tests)
var splash_count: int = 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 99
	# Weicher runder Tropfen (Verlauf von der Mitte nach außen durchsichtig)
	var dot := Gradient.new()
	dot.set_color(0, Color(1, 1, 1, 1))
	dot.set_color(1, Color(1, 1, 1, 0))
	var dot_texture := GradientTexture2D.new()
	dot_texture.gradient = dot
	dot_texture.fill = GradientTexture2D.FILL_RADIAL
	dot_texture.fill_from = Vector2(0.5, 0.5)
	dot_texture.fill_to = Vector2(1.0, 0.5)
	dot_texture.width = 32
	dot_texture.height = 32
	# Tropfen verblassen im Flug
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.9))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	var fade_texture := GradientTexture1D.new()
	fade_texture.gradient = fade
	for k in 2:
		var particles := GPUParticles3D.new()
		particles.one_shot = true
		particles.emitting = false
		particles.amount = 300
		particles.lifetime = 0.9
		particles.explosiveness = 0.8
		particles.local_coords = false
		var process := ParticleProcessMaterial.new()
		# Nach oben, zur Seite (vom Auto weg) und nach hinten
		var side := 1.0 if k == 0 else -1.0
		process.direction = Vector3(side * 0.9, 1.0, -0.6)
		process.spread = 28.0
		process.initial_velocity_min = 2.5
		process.initial_velocity_max = 7.0
		process.gravity = Vector3(0.0, -9.8, 0.0)
		process.scale_min = 0.3
		process.scale_max = 1.4
		process.color_ramp = fade_texture
		process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		process.emission_box_extents = Vector3(0.12, 0.05, 0.35)
		particles.process_material = process
		var drop := QuadMesh.new()
		drop.size = Vector2(0.05, 0.05)
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.vertex_color_use_as_albedo = true
		material.albedo_color = Color(0.82, 0.86, 0.9, 0.55)
		material.albedo_texture = dot_texture
		material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		drop.material = material
		particles.draw_pass_1 = drop
		add_child(particles)
		_fountains.append(particles)
	_splash = AudioStreamPlayer3D.new()
	_splash.stream = _splash_sound()
	_splash.bus = "Motor"
	_splash.unit_size = 8.0
	add_child(_splash)


## Platschen: Rauschen, das schnell abklingt, mit einem tiefen Schwall am Anfang (im Code erzeugt)
func _splash_sound() -> AudioStreamWAV:
	var rate := 22050
	var count := int(rate * 0.7)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var low := 0.0
	for i in count:
		var t := float(i) / rate
		low += (rng.randf_range(-1.0, 1.0) - low) * 0.3
		var sample := low * exp(-t * 6.0) * 1.6 + sin(TAU * 70.0 * t) * exp(-t * 18.0) * 0.5
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 30000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = data
	return stream


func _physics_process(_delta: float) -> void:
	if car == null or limits == null or car.freeze:
		return
	var segment := limits.place_segment()
	if segment == null or segment.sag.is_empty():
		_inside = false
		return
	var i := limits.place_index()
	var deep := segment.sag[i] >= min_sag
	if not deep:
		_inside = false
		return
	var kmh := car.linear_velocity.length() * 3.6
	if _inside or car.wetness < min_wetness or kmh < min_speed_kmh:
		return
	# Steht das Auto auf der Fahrbahn (nicht auf dem Bankett)?
	var p := segment.points[i]
	var left := Vector3.UP.cross(segment.direction_at(i)).normalized()
	if absf((car.global_position - p).dot(left)) > segment.road_width * 0.5:
		return
	_inside = true
	splash(kmh)


## Fontäne an beiden Vorderrädern, Platschen, kurzer Zug am Lenkrad
func splash(kmh: float) -> void:
	splash_count += 1
	var wheels := car.corner_wheels()
	for k in mini(2, wheels.size()):
		var fountain := _fountains[k]
		fountain.global_position = wheels[k].global_position - Vector3.UP * 0.25
		fountain.global_basis = car.global_basis
		(fountain.process_material as ParticleProcessMaterial).initial_velocity_max = 4.0 + kmh / 20.0
		fountain.restart()
	_splash.global_position = car.global_position
	_splash.volume_db = clampf(-12.0 + kmh / 10.0, -12.0, 4.0)
	_splash.play()
	var side := 1.0 if _rng.randf() < 0.5 else -1.0
	car.apply_torque_impulse(Vector3.UP * side * pull_strength * car.mass / 1000.0 * clampf(kmh / 100.0, 0.3, 1.5))
