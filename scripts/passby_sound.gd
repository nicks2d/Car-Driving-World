class_name PassbySound
extends Node3D
## Vorbeifahrt-Geräusche der KI-Autos: Die nächsten max_voices Autos (bis max_distance) bekommen
## je einen räumlichen Lautsprecher (AudioStreamPlayer3D, Bus „Umgebung“) mit Doppler-Effekt
## (Kamera und Lautsprecher verfolgen ihre Bewegung pro Physik-Schritt). Die Klänge entstehen
## beim Start im Code (wie die Wetter-Geräusche): eine Schleife aus Motorbrummen, Reifenrauschen
## und Fahrtwind für Pkw, eine tiefere, lautere für Lkw. Tonhöhe und Lautstärke folgen dem Tempo.

@export var traffic: Traffic
@export var camera: Camera3D
@export var max_voices: int = 6
@export var max_distance: float = 220.0
## Lautstärke bei 100 km/h (dB), Lkw lauter
@export var car_volume_db: float = -6.0
@export var truck_volume_db: float = -1.0

const RATE: int = 22050
const LOOP_SECONDS: float = 2.0

var _car_loop: AudioStreamWAV
var _truck_loop: AudioStreamWAV
var _voices: Array[AudioStreamPlayer3D] = []
var _assigned: Array = []  # je Lautsprecher das Auto (oder null)
var _timer: float = 0.0


func _ready() -> void:
	_car_loop = _make_loop(92.0, 0.55, 0.35)
	_truck_loop = _make_loop(46.0, 0.8, 0.25)
	if camera:
		camera.doppler_tracking = Camera3D.DOPPLER_TRACKING_PHYSICS_STEP
	for k in max_voices:
		var voice := AudioStreamPlayer3D.new()
		voice.bus = "Umgebung"
		voice.max_distance = max_distance
		voice.unit_size = 14.0
		voice.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
		add_child(voice)
		_voices.append(voice)
		_assigned.append(null)


## Schleife: Grundton mit Obertönen (leicht schwankend wie ein Motor unter Last), dazu
## gefiltertes Rauschen für Reifen und Wind. Alle Frequenzen passen ganzzahlig in die Schleife,
## das Rauschen wird an den Enden überblendet (kein Knacken).
func _make_loop(fundamental: float, engine: float, noise: float) -> AudioStreamWAV:
	var count := int(RATE * LOOP_SECONDS)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(fundamental)
	var low := 0.0
	var lower := 0.0
	for i in count:
		var t := float(i) / RATE
		var wobble := 1.0 + 0.15 * sin(TAU * 3.0 * t)
		var hum := sin(TAU * fundamental * t) * 0.5 + sin(TAU * fundamental * 2.0 * t) * 0.3 \
			+ sin(TAU * fundamental * 3.0 * t) * 0.15 + sin(TAU * fundamental * 4.5 * t) * 0.05
		low += (rng.randf_range(-1.0, 1.0) - low) * 0.18
		lower += (low - lower) * 0.05
		samples[i] = hum * engine * wobble + (low * 0.7 + lower * 1.6) * noise
	# Überblenden: Ende in den Anfang
	var fade := int(RATE * 0.15)
	for i in fade:
		var w := float(i) / fade
		samples[i] = samples[i] * w + samples[count - fade + i] * (1.0 - w)
	var data := PackedByteArray()
	data.resize((count - fade) * 2)
	for i in count - fade:
		data.encode_s16(i * 2, int(clampf(samples[i] * 0.6, -1.0, 1.0) * 32000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = count - fade
	return stream


func _physics_process(delta: float) -> void:
	if traffic == null or camera == null:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = 0.25
		_assign()
	# Lautsprecher fahren mit ihren Autos (pro Physik-Schritt, so stimmt der Doppler)
	for k in _voices.size():
		var c: Traffic.TrafficCar = _assigned[k]
		var voice := _voices[k]
		if c == null or not traffic.is_alive(c):
			if voice.playing:
				voice.stop()
			_assigned[k] = null
			continue
		voice.global_position = c.position + Vector3.UP * 0.6
		var kmh := c.speed * 3.6
		voice.pitch_scale = clampf((0.55 if c.truck else 0.7) + kmh / (220.0 if c.truck else 160.0), 0.4, 2.2)
		var base := truck_volume_db if c.truck else car_volume_db
		voice.volume_db = base + clampf(20.0 * log(maxf(kmh, 5.0) / 100.0) / log(10.0), -18.0, 6.0)


## Die nächsten Autos bekommen einen Lautsprecher; wer schon einen hat, behält ihn
func _assign() -> void:
	var wanted := traffic.nearest_cars(camera.global_position, _voices.size(), max_distance)
	for k in _voices.size():
		if _assigned[k] != null and not wanted.has(_assigned[k]):
			_assigned[k] = null
			_voices[k].stop()
	for c in wanted:
		if _assigned.has(c):
			continue
		for k in _voices.size():
			if _assigned[k] == null:
				_assigned[k] = c
				_voices[k].stream = _truck_loop if c.truck else _car_loop
				_voices[k].global_position = c.position
				_voices[k].play(randf() * LOOP_SECONDS * 0.8)
				break
