class_name WeatherSound
extends Node
## Geräusche fürs Wetter, alles im Code erzeugt (keine Sounddateien): Regenrauschen und
## Wind als Schleifen, Donner in drei Varianten (nah mit Knall, zweimal fern grollend).
## Die Klänge werden beim Start im Hintergrund (WorkerThreadPool) berechnet.

@export var mix_rate: int = 22050
@export var rain_volume_db: float = -8.0
@export var wind_volume_db: float = -12.0
@export var thunder_volume_db: float = -1.0

## Stärke 0 bis 1 (setzt das Wetter)
var rain: float = 0.0
var wind: float = 0.0

var _rain_player: AudioStreamPlayer
var _wind_player: AudioStreamPlayer
var _thunder_players: Array[AudioStreamPlayer] = []
var _next_thunder: int = 0
var _task_id: int = -1
## Ergebnis des Hintergrund-Auftrags: Name -> PackedByteArray (16-Bit-Samples)
var _pcm: Dictionary = {}
var _thunder_streams: Array[AudioStreamWAV] = []


func _ready() -> void:
	_rain_player = _make_player()
	_wind_player = _make_player()
	for i in 2:
		_thunder_players.append(_make_player())
	_task_id = WorkerThreadPool.add_task(_generate, false, "Wetter-Klänge")


func _make_player() -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	add_child(player)
	return player


func _process(_delta: float) -> void:
	if _task_id >= 0 and WorkerThreadPool.is_task_completed(_task_id):
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
		_rain_player.stream = _stream(_pcm["rain"], true)
		_wind_player.stream = _stream(_pcm["wind"], true)
		for key: String in ["thunder_near", "thunder_far_a", "thunder_far_b"]:
			_thunder_streams.append(_stream(_pcm[key], false))
	_set_loop(_rain_player, rain, rain_volume_db)
	_set_loop(_wind_player, wind, wind_volume_db)


func _exit_tree() -> void:
	if _task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1


func _set_loop(player: AudioStreamPlayer, amount: float, volume_db: float) -> void:
	if amount < 0.01 or player.stream == null:
		if player.playing:
			player.stop()
		return
	if not player.playing:
		player.play()
	player.volume_db = volume_db + linear_to_db(amount)


## Donner: nahe Blitze knallen, ferne grollen leiser
func play_thunder(distance: float) -> void:
	if _thunder_streams.is_empty():
		return
	var player := _thunder_players[_next_thunder]
	_next_thunder = (_next_thunder + 1) % _thunder_players.size()
	player.stream = _thunder_streams[0] if distance < 1200.0 else _thunder_streams[1 + randi() % 2]
	player.volume_db = thunder_volume_db - distance / 400.0
	player.pitch_scale = randf_range(0.85, 1.1)
	player.play()


func _stream(data: PackedByteArray, loop: bool) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.data = data
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = int(data.size() / 2.0)
	return stream


# ---------------------------------------------------------------------------
# Klänge erzeugen (läuft im Hintergrund)
# ---------------------------------------------------------------------------

func _generate() -> void:
	_pcm["rain"] = _rain_loop(4.0)
	_pcm["wind"] = _wind_loop(6.0)
	_pcm["thunder_near"] = _thunder(7.0, true, 3)
	_pcm["thunder_far_a"] = _thunder(8.0, false, 5)
	_pcm["thunder_far_b"] = _thunder(7.5, false, 9)


## Regen: weiches Rauschen ohne Tiefen, dazu einzelne Tropfen-Knackser
func _rain_loop(seconds: float) -> PackedByteArray:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var n := int(mix_rate * seconds)
	var fade := int(mix_rate * 0.3)
	var samples := PackedFloat32Array()
	samples.resize(n + fade)
	var low := 0.0
	var lowest := 0.0
	var drop := 0.0
	for i in n + fade:
		var white := rng.randf() * 2.0 - 1.0
		low += (white - low) * 0.45
		lowest += (low - lowest) * 0.01
		if rng.randf() < 0.0015:
			drop = rng.randf_range(0.3, 1.0)
		drop *= 0.9
		samples[i] = (low - lowest) * 0.6 + white * drop * 0.4
	return _loop_pcm(samples, n, fade)


## Wind: tiefes Rauschen, das in Böen lauter und leiser wird
func _wind_loop(seconds: float) -> PackedByteArray:
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var n := int(mix_rate * seconds)
	var fade := int(mix_rate * 0.5)
	var samples := PackedFloat32Array()
	samples.resize(n + fade)
	var brown := 0.0
	for i in n + fade:
		brown = brown * 0.995 + (rng.randf() * 2.0 - 1.0) * 0.05
		var t := float(i) / mix_rate
		# Perioden teilen die Schleifenlänge glatt, damit die Böen nahtlos weiterlaufen
		var gust := 0.6 + 0.25 * sin(TAU * t / seconds) + 0.15 * sin(TAU * t * 3.0 / seconds)
		samples[i] = brown * gust * 1.5
	return _loop_pcm(samples, n, fade)


## Donner: tiefes Grollen mit mehreren Anschwellungen, nah zusätzlich ein heller Knall
func _thunder(seconds: float, near: bool, seed_value: int) -> PackedByteArray:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var n := int(mix_rate * seconds)
	var swells: Array[Vector3] = []  # Zeitpunkt, Breite, Stärke
	for i in rng.randi_range(4, 6):
		swells.append(Vector3(rng.randf_range(0.1, seconds * 0.55), rng.randf_range(0.3, 1.1), rng.randf_range(0.4, 1.0)))
	var samples := PackedFloat32Array()
	samples.resize(n)
	var brown := 0.0
	var low := 0.0
	var peak := 0.001
	for i in n:
		var t := float(i) / mix_rate
		var white := rng.randf() * 2.0 - 1.0
		brown = brown * 0.996 + white * 0.04
		low += (brown - low) * (0.08 if near else 0.04)
		var envelope := 0.0
		for s in swells:
			envelope += s.z * exp(-pow((t - s.x) / s.y, 2.0))
		envelope *= exp(-t / (seconds * 0.45))
		var value := low * envelope
		if near:
			value += white * exp(-t * 14.0) * 0.6
		samples[i] = value
		peak = maxf(peak, absf(value))
	for i in n:
		samples[i] *= 0.9 / peak
	return _loop_pcm(samples, n, 0)


## In 16-Bit umwandeln; bei Schleifen das Ende weich in den Anfang überblenden (kein Knacks)
func _loop_pcm(samples: PackedFloat32Array, n: int, fade: int) -> PackedByteArray:
	for i in fade:
		var t := float(i) / fade
		samples[i] = samples[i] * t + samples[n + i] * (1.0 - t)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	return data
