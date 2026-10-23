extends Node
## Motorsound ohne Sounddateien: Der Klang wird laufend berechnet (AudioStreamGenerator).
##
## So funktioniert es: Ein Viertaktmotor zündet in jedem Zylinder einmal pro Arbeitsspiel
## (zwei Kurbelwellen-Umdrehungen), ein Sechszylinder also 6-mal, ein V8 8-mal. Eine solche
## Periode wird einmal als Tabelle berechnet: kurze Druckstöße, jeder Zylinder etwas anders
## laut und etwas früher oder später (beim V8 mit Kreuzwelle besonders: das Blubbern).
## Beim Abspielen läuft die Tabelle je nach Drehzahl schneller oder langsamer durch.
## Zylinderzahl, Klang und Turbo stehen im Profil des Autos (CarProfile).
## Unter Last klingt es härter (Tabelle mit spitzen Stößen), ohne Gas weicher.
## Dazu kommen Ansauggeräusch, Turbo-Pfeifen, Begrenzer-Stottern, ein „Krack“ beim
## Hochschalten unter Vollgas und Reifenquietschen, wenn die Räder rutschen.

## Gesamtlautstärke in Dezibel
@export var volume_db: float = -4.0
## Anteile der einzelnen Geräusche (0 bis 1)
@export_range(0.0, 1.0) var engine_volume: float = 0.6
@export_range(0.0, 1.0) var shift_volume: float = 0.5
@export_range(0.0, 1.0) var squeal_volume: float = 0.22
## Abtastrate: 22050 reicht für einen Motor und spart Rechenzeit
@export var mix_rate: float = 22050.0

const TABLE_SIZE: int = 2048

var _car: Car
var _wheels: Array[VehicleWheel3D] = []
var _playback: AudioStreamGeneratorPlayback
var _load_table := PackedFloat32Array()
var _coast_table := PackedFloat32Array()
var _phase: float = 0.0
var _turbo_phase: float = 0.0
var _squeal_phase: float = 0.0
var _vibrato_phase: float = 0.0
var _noise_low: float = 0.0
var _limiter_phase: float = 0.0
var _shift_crack: float = 0.0
# Werte vom letzten Puffer (dazwischen wird weich übergeblendet)
var _rpm: float = 900.0
var _load: float = 0.0
var _squeal: float = 0.0


func _ready() -> void:
	_car = get_parent() as Car
	for child in _car.get_children():
		if child is VehicleWheel3D:
			_wheels.append(child)
	_car.profile_changed.connect(_on_profile_changed)
	if _car.profile:
		_on_profile_changed(_car.profile)
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = mix_rate
	stream.buffer_length = 0.12
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	add_child(player)
	player.play()
	_playback = player.get_stream_playback() as AudioStreamGeneratorPlayback
	_car.gear_changed.connect(_on_gear_changed)


func _on_profile_changed(profile: CarProfile) -> void:
	_load_table = _make_table(profile, profile.sound_sharpness, 7.0)
	_coast_table = _make_table(profile, profile.sound_sharpness * 0.35, 3.0)


## Eine Periode (720° Kurbelwinkel) mit einer Zündung pro Zylinder. sharpness: wie spitz ein
## Druckstoß ansteigt, decay: wie schnell er abklingt (größer = härterer, hellerer Klang)
func _make_table(profile: CarProfile, sharpness: float, decay: float) -> PackedFloat32Array:
	var cylinders := maxi(profile.cylinders, 1)
	# Feste „Zufalls“-Werte pro Zylinder (bei jedem Start gleich): Lautstärke und Zeitpunkt
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * cylinders
	var gains := PackedFloat32Array()
	var starts := PackedFloat32Array()
	for c in cylinders:
		gains.append(1.0 + rng.randf_range(-1.0, 1.0) * (0.05 + 0.15 * profile.firing_unevenness))
		starts.append((c + rng.randf_range(-0.5, 0.5) * profile.firing_unevenness * 0.6) / cylinders)
	var table := PackedFloat32Array()
	table.resize(TABLE_SIZE)
	for i in TABLE_SIZE:
		var x := float(i) / TABLE_SIZE
		var value := 0.0
		for c in cylinders:
			# Zeit seit der Zündung dieses Zylinders, in „Zündabständen“
			var since := fposmod(x - starts[c], 1.0) * cylinders
			var pulse := (1.0 - exp(-since * sharpness)) * exp(-since * decay)
			# Etwas Nachschwingen im Auspuff
			pulse += 0.25 * sin(since * TAU * 2.0) * exp(-since * 4.0)
			value += pulse * gains[c]
		# Tiefer Anteil einmal pro Kurbelwellen-Umdrehung (V8-Bass)
		value += profile.sound_rumble * 2.0 * sin(x * TAU * 2.0)
		table[i] = value
	# Gleichanteil entfernen und auf -1..1 bringen
	var mean := 0.0
	for v in table:
		mean += v
	mean /= TABLE_SIZE
	var peak := 0.0
	for i in TABLE_SIZE:
		table[i] -= mean
		peak = maxf(peak, absf(table[i]))
	for i in TABLE_SIZE:
		table[i] /= peak
	return table


func _on_gear_changed(new_gear: int) -> void:
	# Beim schnellen Hochschalten unter Last knallt es kurz im Auspuff
	if new_gear > 1 and _car.throttle_input > 0.6:
		_shift_crack = 1.0


func _process(_delta: float) -> void:
	if _playback == null:
		return
	var frames := _playback.get_frames_available()
	if frames <= 0:
		return
	var redline := _car.profile.redline_rpm
	var intake_volume := _car.profile.intake_volume
	var turbo_volume := _car.profile.turbo_volume
	var target_rpm := _car.engine_rpm
	var target_load := _car.throttle_input
	var target_squeal := 0.0
	for wheel in _wheels:
		target_squeal = maxf(target_squeal, _car.wheel_slip(wheel))
	target_squeal *= clampf(_car.linear_velocity.length() / 8.0, 0.0, 1.0)
	var buffer := PackedVector2Array()
	buffer.resize(frames)
	var start_rpm := _rpm
	var start_load := _load
	var start_squeal := _squeal
	for i in frames:
		var t := float(i + 1) / frames
		var rpm := lerpf(start_rpm, target_rpm, t)
		var engine_load := lerpf(start_load, target_load, t)
		var squeal := lerpf(start_squeal, target_squeal, t)
		var rev := rpm / redline
		# Motor: Tabelle mit der Arbeitsspiel-Frequenz (Drehzahl / 120) abspielen
		_phase = fmod(_phase + rpm / 120.0 / mix_rate * TABLE_SIZE, TABLE_SIZE)
		var index := int(_phase)
		var frac := _phase - index
		var next := (index + 1) % TABLE_SIZE
		var hard := lerpf(_load_table[index], _load_table[next], frac)
		var soft := lerpf(_coast_table[index], _coast_table[next], frac)
		var engine := lerpf(soft, hard, engine_load) * (0.35 + 0.65 * engine_load) * (0.55 + 0.45 * rev)
		# Begrenzer: Zündung wird ganz schnell aus- und eingeschaltet
		if rpm > redline - 60.0 and engine_load > 0.5:
			_limiter_phase = fmod(_limiter_phase + 18.0 / mix_rate, 1.0)
			if _limiter_phase < 0.4:
				engine *= 0.25
		# Ansauggeräusch: gefiltertes Rauschen, lauter mit Gas und Drehzahl
		_noise_low = lerpf(_noise_low, randf_range(-1.0, 1.0), 0.08 + 0.25 * rev)
		var intake := _noise_low * engine_load * rev * rev
		# Turbo: leises Pfeifen, steigt mit der Drehzahl
		_turbo_phase = fmod(_turbo_phase + (900.0 + rev * 2600.0) / mix_rate, 1.0)
		var turbo := sin(_turbo_phase * TAU) * engine_load * rev
		# Schalt-Knall: kurzes Rauschen, klingt in ca. 60 ms ab
		var crack := 0.0
		if _shift_crack > 0.001:
			crack = randf_range(-1.0, 1.0) * _shift_crack
			_shift_crack *= 0.9985
		# Reifenquietschen: hoher Ton mit leichtem Zittern
		_vibrato_phase = fmod(_vibrato_phase + 7.0 / mix_rate, 1.0)
		_squeal_phase = fmod(_squeal_phase + (950.0 + sin(_vibrato_phase * TAU) * 45.0) / mix_rate, 1.0)
		var tire := (sin(_squeal_phase * TAU) + 0.35 * sin(_squeal_phase * TAU * 2.0)) * squeal * squeal
		var sample := engine * engine_volume + intake * intake_volume + turbo * turbo_volume \
			+ crack * shift_volume + tire * squeal_volume
		# Weich begrenzen, damit es nie hart übersteuert
		sample = sample / (1.0 + absf(sample))
		buffer[i] = Vector2(sample, sample)
	_rpm = target_rpm
	_load = target_load
	_squeal = target_squeal
	_playback.push_buffer(buffer)
