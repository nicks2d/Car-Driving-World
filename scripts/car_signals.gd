extends Node3D
## Blinker, Warnblinker und Hupe des eigenen Autos.
## Q/E blinken links/rechts (noch mal drücken = aus; nach einer Kurve geht der Blinker von
## selbst aus, wenn das Lenkrad zurückgeht), X Warnblinker, H Hupe (solange gedrückt).
## Orange Leuchten vorne, hinten und an den Spiegeln (Lage im Profil: indicator_points),
## Takt 1,5 Hz, nachts mit kleinem Lichtschein. Die Leuchten sind nur zu sehen, solange sie
## leuchten (aus: sieht man das Modell). Klicken und Hupe entstehen im Code.
## Bei einer Vollbremsung über 100 km/h geht der Warnblinker an und nach dem
## Wiederanfahren wieder aus (wie bei BMW).

## Blinktakt (Hz) und Größe einer Leuchte (Meter)
@export var blink_hz: float = 1.5
@export var lamp_size: Vector3 = Vector3(0.09, 0.045, 0.03)
## Lichtschein nachts: Helligkeit und Reichweite (Meter), ohne Schatten
@export var light_energy: float = 0.9
@export var light_range: float = 2.6
## Vollbremsung: ab diesem Tempo (km/h), Bremspedal mindestens so weit
@export var emergency_speed_kmh: float = 100.0
@export_range(0.0, 1.0) var emergency_brake: float = 0.8
## Lautstärke von Klicken und Hupe (dB)
@export var click_volume_db: float = -16.0
@export var horn_volume_db: float = -8.0
## Lenkrad ab diesem Einschlag = abgebogen; zurück unter diesen Wert = Blinker aus
@export var cancel_turned: float = 0.35
@export var cancel_back: float = 0.08

const MIX_RATE: float = 22050.0
const ORANGE := Color(1.0, 0.48, 0.05)

var _car: Car
## Je Seite (0 = links, 1 = rechts) ein Material und die Lichter (vorne, hinten)
var _materials: Array[StandardMaterial3D] = []
var _lamps: Array[MeshInstance3D] = []
var _lights: Array[OmniLight3D] = []
var _time: float = 0.0
var _was_lit: bool = false
var _turned: bool = false
var _auto_hazard: bool = false
var _stopped: bool = false
var _click: AudioStreamPlayer
var _tick: AudioStreamWAV
var _tock: AudioStreamWAV
var _horn_playback: AudioStreamGeneratorPlayback
var _horn_level: float = 0.0
var _horn_phase := Vector2.ZERO
var _day_night: DayNight


func _ready() -> void:
	_car = get_parent() as Car
	for side in 2:
		var material := StandardMaterial3D.new()
		material.albedo_color = ORANGE.darkened(0.5)
		material.emission_enabled = true
		material.emission = ORANGE
		material.emission_energy_multiplier = 0.0
		_materials.append(material)
	_car.profile_changed.connect(_build)
	if _car.profile:
		_build(_car.profile)
	# Klicken: zwei kurze Geräusche (an/aus), im Code erzeugt
	_tick = _make_click(1900.0, 0.012)
	_tock = _make_click(1300.0, 0.009)
	_click = AudioStreamPlayer.new()
	_click.volume_db = click_volume_db
	add_child(_click)
	# Hupe: zwei Töne, laufend berechnet (wie der Motor)
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = MIX_RATE
	stream.buffer_length = 0.08
	var horn := AudioStreamPlayer.new()
	horn.stream = stream
	horn.volume_db = horn_volume_db
	add_child(horn)
	horn.play()
	_horn_playback = horn.get_stream_playback() as AudioStreamGeneratorPlayback


## Leuchten an die Stellen aus dem Profil setzen (links gemessen, rechts gespiegelt)
func _build(profile: CarProfile) -> void:
	for node in _lamps:
		node.queue_free()
	for node in _lights:
		node.queue_free()
	_lamps.clear()
	_lights.clear()
	var points := profile.indicator_points
	if points.is_empty():
		# Ohne gemessene Punkte: Ecken der Platzhalter-Karosserie
		var half := profile.body_size * 0.5
		points = PackedVector3Array([profile.body_center + Vector3(half.x - 0.1, 0.0, half.z),
			profile.body_center + Vector3(half.x - 0.1, 0.05, -half.z),
			profile.body_center + Vector3(half.x + 0.05, half.y + 0.1, half.z * 0.3)])
	for side in 2:
		var mirror := 1.0 if side == 0 else -1.0
		for k in points.size():
			var p := points[k] * Vector3(mirror, 1.0, 1.0)
			var lamp := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = lamp_size if k != 2 else Vector3(lamp_size.z, lamp_size.y, lamp_size.x * 1.2)
			box.material = _materials[side]
			lamp.mesh = box
			lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# Etwas nach außen, damit die Leuchte nicht im Scheinwerfer- bzw. Spiegelgehäuse steckt
			var outward := [Vector3(0.0, 0.0, 0.015), Vector3(0.0, 0.0, -0.015), Vector3(mirror * 0.02, 0.0, 0.0)]
			lamp.position = p + outward[k]
			lamp.visible = false
			lamp.set_meta("side", side)
			add_child(lamp)
			_lamps.append(lamp)
			# Lichtschein nur vorne und hinten (Spiegel ohne)
			if k < 2:
				var light := OmniLight3D.new()
				light.light_color = ORANGE
				light.omni_range = light_range
				light.light_energy = 0.0
				light.shadow_enabled = false
				light.visible = false
				light.position = p + Vector3(mirror * 0.15, 0.0, 0.25 if k == 0 else -0.25)
				light.set_meta("side", side)
				add_child(light)
				_lights.append(light)


func _process(delta: float) -> void:
	if _car == null or _car.profile == null:
		return
	_handle_input()
	_update_auto_hazard()
	_update_auto_cancel()
	# Takt: in der ersten Hälfte jeder Periode leuchtet es
	var active := _car.turn_signal != 0 or _car.hazard
	if active:
		_time += delta
	else:
		_time = 0.0
	var lit := active and fmod(_time, 1.0 / blink_hz) < 0.5 / blink_hz
	_car.signal_lit = lit
	if lit != _was_lit:
		_click.stream = _tick if lit else _tock
		_click.play()
		_was_lit = lit
	var night := _is_night()
	for side in 2:
		var on := lit and (_car.hazard or _car.turn_signal == (1 if side == 0 else -1))
		_materials[side].emission_energy_multiplier = 4.0 if on else 0.0
		_materials[side].albedo_color = ORANGE if on else ORANGE.darkened(0.5)
		for lamp in _lamps:
			if lamp.get_meta("side") == side:
				lamp.visible = on
	for light in _lights:
		var side: int = light.get_meta("side")
		var on := night and lit and (_car.hazard or _car.turn_signal == (1 if side == 0 else -1))
		light.visible = on
		light.light_energy = light_energy if on else 0.0
	_update_horn(delta)


func _handle_input() -> void:
	if not _car.throttle_enabled:
		return
	if Input.is_action_just_pressed("blink_left"):
		_set_turn(0 if _car.turn_signal == 1 else 1)
	elif Input.is_action_just_pressed("blink_right"):
		_set_turn(0 if _car.turn_signal == -1 else -1)
	if Input.is_action_just_pressed("hazard"):
		_car.hazard = not _car.hazard
		_auto_hazard = false


func _set_turn(direction: int) -> void:
	_car.turn_signal = direction
	_turned = false
	_time = 0.0


## Blinker geht aus, wenn nach dem Abbiegen das Lenkrad wieder zurückgeht
func _update_auto_cancel() -> void:
	if _car.turn_signal == 0:
		return
	var steer := _car.steer_amount() * float(_car.turn_signal)
	if steer > cancel_turned:
		_turned = true
	elif _turned and steer < cancel_back:
		_car.turn_signal = 0
		_turned = false


## Vollbremsung über 100 km/h: Warnblinker an. Aus, sobald das Auto (fast) gestanden hat und
## wieder anfährt.
func _update_auto_hazard() -> void:
	var kmh := _car.linear_velocity.length() * 3.6
	if not _car.hazard and kmh > emergency_speed_kmh and Input.get_action_strength("brake") >= emergency_brake \
			and _car.throttle_enabled:
		_car.hazard = true
		_auto_hazard = true
		_stopped = false
	if not _auto_hazard:
		return
	if kmh < 10.0:
		_stopped = true
	elif _stopped and kmh > 20.0 and _car.throttle_input > 0.2:
		_car.hazard = false
		_auto_hazard = false


func _is_night() -> bool:
	if _day_night == null:
		_day_night = get_tree().get_first_node_in_group("day_night") as DayNight
	return _day_night != null and _day_night.daylight < 0.4


## Hupe: zwei Töne mit Obertönen, weich ein- und ausgeblendet
func _update_horn(_delta: float) -> void:
	if _horn_playback == null:
		return
	var frames := _horn_playback.get_frames_available()
	if frames <= 0:
		return
	var pressed := Input.is_action_pressed("horn") and _car.throttle_enabled
	var tones := _car.profile.horn_tones
	var buffer := PackedVector2Array()
	buffer.resize(frames)
	var attack := 1.0 / (0.03 * MIX_RATE)
	for i in frames:
		_horn_level = move_toward(_horn_level, 1.0 if pressed else 0.0, attack)
		var sample := 0.0
		if _horn_level > 0.0:
			_horn_phase = Vector2(fmod(_horn_phase.x + tones.x / MIX_RATE, 1.0), fmod(_horn_phase.y + tones.y / MIX_RATE, 1.0))
			for k in 2:
				var phase := _horn_phase[k]
				# Etwas rau wie eine echte Hupe: Grundton plus abnehmende Obertöne
				sample += sin(phase * TAU) + 0.45 * sin(phase * TAU * 2.0) + 0.25 * sin(phase * TAU * 3.0) \
					+ 0.12 * sin(phase * TAU * 5.0)
			sample *= 0.25 * _horn_level
			sample = sample / (1.0 + absf(sample))
		buffer[i] = Vector2(sample, sample)
	_horn_playback.push_buffer(buffer)


## Kurzes Klicken: ein Ton, der sehr schnell abklingt, mit etwas Rauschen
func _make_click(frequency: float, seconds: float) -> AudioStreamWAV:
	var count := int(seconds * MIX_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(frequency)
	for i in count:
		var t := float(i) / MIX_RATE
		var envelope := exp(-t / (seconds * 0.3))
		var value := (sin(TAU * frequency * t) * 0.7 + rng.randf_range(-1.0, 1.0) * 0.3) * envelope
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 30000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = int(MIX_RATE)
	wav.stereo = false
	wav.data = data
	return wav
