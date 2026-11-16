class_name CollisionEffects
extends Node3D
## Was bei Berührungen passiert (Leitplanke, Wand, Haus, Verkehrsautos, aufsetzender Unterboden):
##  - Funken an der Berührstelle: ein kurzer Schauer beim Aufprall, ein Strom beim Entlangschrammen
##  - Schleifgeräusch, solange das Auto an etwas entlangschrammt (lauter und heller mit dem Tempo)
##  - dumpfer Schlag beim Aufprall, laut nach Wucht
##  - Signal hit: die Kamera ruckt kurz (FollowCamera)
## Gelände und Bäume sind weich: dort nur der Schlag (leiser), keine Funken und kein Schleifen.
## Die Geräusche werden beim Start berechnet (keine Sounddateien), wie der Motorsound.

## Aufprall: Stärke 0–1 und Richtung, aus der er kam (Auto-Koordinaten)
signal hit(strength: float, direction: Vector3)

@export_group("Erkennen")
## Ab dieser Geschwindigkeitsänderung (m/s) zählt eine Berührung als Aufprall, bei dieser ist er voll
@export var hit_min_delta_v: float = 0.8
@export var hit_full_delta_v: float = 9.0
## Ab so viel Rutschen an der Berührstelle (m/s) schrammt das Auto
@export var scrape_min_speed: float = 1.5
## Mindestabstand zwischen zwei Aufprall-Geräuschen (Sekunden)
@export var hit_cooldown: float = 0.18

@export_group("Funken")
@export var spark_amount: int = 240
@export var spark_lifetime: float = 0.45
@export var spark_speed: float = 6.0
@export var spark_glow: float = 7.0

@export_group("Geräusche")
@export var thud_volume_db: float = 2.0
@export var scrape_volume_db: float = -3.0

var _car: Car
var _sparks: GPUParticles3D
var _spark_material: ParticleProcessMaterial
var _thud: AudioStreamPlayer3D
var _scrape: AudioStreamPlayer3D
var _cooldown: float = 0.0
var _spark_timer: float = 0.0
var _scrape_level: float = 0.0


func _ready() -> void:
	_car = get_parent() as Car
	_car.contact_monitor = true
	_car.max_contacts_reported = 6
	_sparks = _make_sparks()
	add_child(_sparks)
	_thud = AudioStreamPlayer3D.new()
	_thud.stream = _make_thud()
	_thud.bus = &"Motor"
	_thud.unit_size = 6.0
	add_child(_thud)
	_scrape = AudioStreamPlayer3D.new()
	_scrape.stream = _make_scrape()
	_scrape.bus = &"Motor"
	_scrape.unit_size = 6.0
	_scrape.volume_db = -80.0
	add_child(_scrape)


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_spark_timer = maxf(_spark_timer - delta, 0.0)
	var state := PhysicsServer3D.body_get_direct_state(_car.get_rid())
	var scrape_speed := 0.0
	var scrape_point := Vector3.ZERO
	var scrape_normal := Vector3.UP
	var scrape_slide := Vector3.ZERO
	var strongest := 0.0
	var hit_point := Vector3.ZERO
	var hit_normal := Vector3.UP
	var soft_hit := false
	if state:
		for i in state.get_contact_count():
			var soft := _is_soft(state.get_contact_collider_object(i))
			var normal := state.get_contact_local_normal(i)
			var point := state.get_contact_local_position(i)
			var relative := state.get_contact_local_velocity_at_position(i) - state.get_contact_collider_velocity_at_position(i)
			var slide := relative - normal * relative.dot(normal)
			var delta_v := state.get_contact_impulse(i).length() / _car.mass
			if delta_v > strongest:
				strongest = delta_v
				hit_point = point
				hit_normal = normal
				soft_hit = soft
			if not soft and slide.length() > scrape_speed:
				scrape_speed = slide.length()
				scrape_point = point
				scrape_normal = normal
				scrape_slide = slide
	# Aufprall: Schlag, Funkenschauer, Kamera-Ruck
	if strongest > hit_min_delta_v and _cooldown <= 0.0:
		_cooldown = hit_cooldown
		var strength := clampf((strongest - hit_min_delta_v) / (hit_full_delta_v - hit_min_delta_v), 0.0, 1.0)
		_thud.global_position = hit_point
		_thud.volume_db = thud_volume_db + linear_to_db(lerpf(0.25, 1.0, strength) * (0.5 if soft_hit else 1.0))
		_thud.pitch_scale = lerpf(1.15, 0.8, strength) * randf_range(0.95, 1.05)
		_thud.play()
		if not soft_hit:
			_spray(hit_point, hit_normal, Vector3.ZERO, 0.08 + strength * 0.15)
		hit.emit(strength, _car.global_basis.inverse() * -hit_normal)
	# Schrammen: Funkenstrom und Schleifgeräusch
	var scraping := scrape_speed > scrape_min_speed
	if scraping:
		_spray(scrape_point, scrape_normal, scrape_slide, 0.05)
	var target := clampf((scrape_speed - scrape_min_speed) / 20.0, 0.0, 1.0) if scraping else 0.0
	_scrape_level = move_toward(_scrape_level, target, delta * (8.0 if target > _scrape_level else 4.0))
	if _scrape_level > 0.01:
		if not _scrape.playing:
			_scrape.play(randf() * 0.9)
		_scrape.global_position = scrape_point if scraping else _scrape.global_position
		_scrape.volume_db = scrape_volume_db + linear_to_db(lerpf(0.3, 1.0, _scrape_level)) - (1.0 - minf(_scrape_level * 6.0, 1.0)) * 30.0
		_scrape.pitch_scale = lerpf(0.8, 1.3, _scrape_level)
	elif _scrape.playing:
		_scrape.stop()
	_sparks.emitting = _spark_timer > 0.0


## Gelände (Kacheln des TerrainManager) sowie Bäume und Felsen (Körper nur im Physik-Server, ohne Node):
## kein Metall, keine Funken
func _is_soft(collider: Object) -> bool:
	var node := collider as Node
	return node == null or node.get_parent() is TerrainManager


## Funken an dieser Stelle: weg von der Fläche und in Richtung des Rutschens, für seconds Sekunden
func _spray(point: Vector3, normal: Vector3, slide: Vector3, seconds: float) -> void:
	_sparks.global_position = point
	var direction := (normal + (-slide.normalized() * 1.5 if slide.length() > 0.1 else Vector3.ZERO) + Vector3.UP * 0.4).normalized()
	_spark_material.direction = direction
	_spark_timer = maxf(_spark_timer, seconds)


func _make_sparks() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = spark_amount
	particles.lifetime = spark_lifetime
	particles.emitting = false
	particles.local_coords = false
	particles.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
	_spark_material = ParticleProcessMaterial.new()
	_spark_material.direction = Vector3.UP
	_spark_material.spread = 35.0
	_spark_material.initial_velocity_min = spark_speed * 0.4
	_spark_material.initial_velocity_max = spark_speed
	_spark_material.gravity = Vector3(0, -9.8, 0)
	_spark_material.damping_min = 1.0
	_spark_material.damping_max = 3.0
	_spark_material.scale_min = 0.6
	_spark_material.scale_max = 1.2
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 0.85, 0.5))
	fade.set_color(1, Color(1.0, 0.25, 0.02, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	_spark_material.color_ramp = ramp
	particles.process_material = _spark_material
	var quad := QuadMesh.new()
	quad.size = Vector2(0.02, 0.1)
	# Leuchten über Emission (über der Glow-Schwelle, deshalb glühen die Funken); ausblenden über Alpha
	var look := StandardMaterial3D.new()
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.vertex_color_use_as_albedo = true
	look.albedo_color = Color(0.25, 0.12, 0.02)
	look.emission_enabled = true
	look.emission = Color(1.0, 0.55, 0.15)
	look.emission_energy_multiplier = spark_glow
	look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	look.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = look
	particles.draw_pass_1 = quad
	return particles


# ---------------------------------------------------------------------------
# Geräusche (beim Start berechnet)
# ---------------------------------------------------------------------------

const RATE: int = 22050


## Dumpfer Schlag: tiefer, schnell abklingender Ton, dazu ein Knirschen (Rauschen) und ein kurzes
## metallisches Klingen
func _make_thud() -> AudioStreamWAV:
	var length := int(RATE * 0.6)
	var samples := PackedFloat32Array()
	samples.resize(length)
	var low := 0.0
	for i in length:
		var t := float(i) / RATE
		var body := sin(TAU * (55.0 + 50.0 * exp(-t * 18.0)) * t) * exp(-t * 9.0)
		low = lerpf(low, randf_range(-1.0, 1.0), 0.18)
		var crunch := low * exp(-t * 14.0) * 0.8
		var ring := (sin(TAU * 820.0 * t) + 0.6 * sin(TAU * 1370.0 * t)) * exp(-t * 22.0) * 0.18
		samples[i] = body * 0.9 + crunch + ring
	return _to_wav(samples, false)


## Schleifen: gefiltertes Rauschen mit metallischen Resonanzen und Knacken, 1 s als Schleife
func _make_scrape() -> AudioStreamWAV:
	var length := RATE
	var samples := PackedFloat32Array()
	samples.resize(length)
	var band := 0.0
	var band2 := 0.0
	for i in length:
		var t := float(i) / RATE
		var noise := randf_range(-1.0, 1.0)
		band = lerpf(band, noise, 0.35)
		band2 = lerpf(band2, band, 0.5)
		var grind := (band - band2) * 2.2
		var squeal := sin(TAU * 1900.0 * t + sin(TAU * 7.0 * t) * 3.0) * 0.08
		var crackle := randf_range(-1.0, 1.0) * 0.9 if randf() < 0.004 else 0.0
		# An den Enden der Schleife weich überblenden, damit es nicht knackt
		var edge := clampf(minf(t, 1.0 - t) / 0.02, 0.0, 1.0)
		samples[i] = (grind + squeal + crackle) * edge
	return _to_wav(samples, true)


func _to_wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var peak := 0.001
	for v in samples:
		peak = maxf(peak, absf(v))
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i] / peak, -1.0, 1.0) * 30000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = samples.size()
	return wav
