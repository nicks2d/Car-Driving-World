class_name Rewind
extends Node
## Zurückspulen (Taste Rücktaste gedrückt halten): bis zu 10 s zurück, doppelt so schnell wie die
## Zeit lief. Aufgezeichnet wird jeden Physik-Schritt: Lage und Tempo des Autos, Lenkung, Gang,
## Drehzahl, Gas und die Kamera. Der Verkehr spult mit (Traffic.record/show_time), Wetter und Uhrzeit
## nicht. Beim Loslassen geht alles ab dieser Stelle weiter, die spätere Aufzeichnung fällt weg.
## Dazu ein Bildeffekt (fast schwarz-weiß, Streifen, „◀◀“) und ein Ton, der beim Spulen tiefer wird.

@export var car: Car
@export var camera: FollowCamera
@export var traffic: Traffic
## So viele Sekunden lassen sich zurückspulen
@export var max_seconds: float = 10.0
## So viel schneller als die Zeit lief geht es zurück
@export var speed: float = 2.0
## Springt das Auto in einem Schritt weiter als so viele Meter (Reset, Karte, Garage), beginnt die
## Aufzeichnung neu
@export var jump_distance: float = 25.0
## Lautstärke des Spul-Tons (dB) und seine Tonhöhe am Anfang und nach dem ganzen Weg zurück
@export var tone_volume_db: float = -14.0
@export var tone_pitch := Vector2(1.25, 0.55)

## Wird gerade zurückgespult?
var rewinding: bool = false

## Aufzeichnung: je Physik-Schritt [Zeit, Lage, Tempo, Drehung, Lenkung, Lenkwinkel, Gang, Drehzahl, Gas,
## Kamera]
var _frames: Array = []
var _time: float = 0.0
var _rewind_time: float = 0.0
var _start_time: float = 0.0
var _overlay: CanvasLayer
var _tone: AudioStreamPlayer


func _ready() -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 5
	_overlay.visible = false
	add_child(_overlay)
	var effect := ColorRect.new()
	effect.set_anchors_preset(Control.PRESET_FULL_RECT)
	effect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/rewind.gdshader")
	effect.material = material
	_overlay.add_child(effect)
	var label := UiStyle.label("◀◀  ZURÜCK", 44, "extrabold", Color(1, 1, 1, 0.92), 4)
	label.position = Vector2(56.0, 44.0)
	_overlay.add_child(label)
	_tone = AudioStreamPlayer.new()
	_tone.stream = _make_tone()
	_tone.bus = &"Umgebung"
	_tone.volume_db = tone_volume_db
	add_child(_tone)


func _physics_process(delta: float) -> void:
	if car == null or car.profile == null:
		return
	var wanted := Input.is_action_pressed("rewind") and _can_rewind()
	if wanted and not rewinding and _frames.size() > 10:
		_start()
	elif rewinding and not wanted:
		_finish()
	if rewinding:
		var oldest: float = _frames[0][0]
		_rewind_time = maxf(_rewind_time - delta * speed, oldest)
		_show(_frame_at(_rewind_time))
		if traffic:
			traffic.show_time(_rewind_time, false)
		# Ton wird tiefer, je weiter es zurückgeht
		var progress := clampf((_start_time - _rewind_time) / max_seconds, 0.0, 1.0)
		_tone.pitch_scale = lerpf(tone_pitch.x, tone_pitch.y, progress)
		return
	# Während des Ladens (Auto eingefroren) nichts aufzeichnen
	if car.freeze:
		return
	if not _frames.is_empty() and (_frames.back()[1] as Transform3D).origin.distance_to(car.global_position) > jump_distance:
		_frames.clear()
		if traffic:
			traffic.clear_records()
	_time += delta
	_frames.append([_time, car.global_transform, car.linear_velocity, car.angular_velocity, car.steer_amount(),
		car.steering, car.gear, car.engine_rpm, car.throttle_input, camera.global_transform if camera else Transform3D()])
	while _frames.size() > 1 and (_frames[0][0] as float) < _time - max_seconds:
		_frames.pop_front()
	if traffic:
		traffic.record(_time, max_seconds)


## Nur beim normalen Fahren (nicht im Fotomodus, Chill-Modus, Menüs, Test-Fotos)
func _can_rewind() -> bool:
	return car.throttle_enabled and camera != null and camera.current and camera.is_physics_processing()


func _start() -> void:
	rewinding = true
	_start_time = _time
	_rewind_time = _time
	car.freeze = true
	car.set_physics_process(false)
	camera.rewinding = true
	if traffic:
		traffic.rewinding = true
	_overlay.visible = true
	_tone.pitch_scale = tone_pitch.x
	_tone.play()


func _finish() -> void:
	rewinding = false
	var frame: Array = _frame_at(_rewind_time)
	# Spätere Aufzeichnung verwerfen, ab hier weiter
	while _frames.size() > 1 and (_frames.back()[0] as float) > _rewind_time:
		_frames.pop_back()
	_time = _rewind_time
	_show(frame)
	car.freeze = false
	car.linear_velocity = frame[2]
	car.angular_velocity = frame[3]
	car.set_physics_process(true)
	camera.rewinding = false
	camera.set_view(camera.view)
	if traffic:
		traffic.show_time(_rewind_time, true)
	_overlay.visible = false
	_tone.stop()


## Auto und Kamera in den Zustand eines aufgezeichneten Schritts setzen
func _show(frame: Array) -> void:
	car.global_transform = frame[1]
	# Für Tacho und Sound (das eingefrorene Auto bewegt sich dadurch nicht)
	car.linear_velocity = frame[2]
	car.set_steer_amount(frame[4])
	car.steering = frame[5]
	car.gear = frame[6]
	car.engine_rpm = frame[7]
	car.throttle_input = frame[8]
	camera.rewind_transform = frame[9]


## Letzter Schritt vor oder genau zu dieser Zeit
func _frame_at(time: float) -> Array:
	var index := _frames.size() - 1
	while index > 0 and (_frames[index][0] as float) > time:
		index -= 1
	return _frames[index]


## Spul-Ton: Rauschen mit einem schwankenden Pfeifen wie eine schnell zurückgespulte Kassette, 1 s als
## Schleife (die Tonhöhe sinkt über pitch_scale)
func _make_tone() -> AudioStreamWAV:
	var rate := 22050
	var data := PackedByteArray()
	data.resize(rate * 2)
	var noise := 0.0
	for i in rate:
		var t := float(i) / rate
		noise = lerpf(noise, randf_range(-1.0, 1.0), 0.3)
		var whine := sin(TAU * (520.0 + 40.0 * sin(TAU * 6.0 * t)) * t) * 0.35
		var flutter := sin(TAU * 31.0 * t) * 0.15
		var edge := clampf(minf(t, 1.0 - t) / 0.02, 0.0, 1.0)
		var value := (noise * 0.5 + whine + flutter * noise) * edge
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 26000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = rate
	return wav
