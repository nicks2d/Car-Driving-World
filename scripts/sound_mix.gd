class_name SoundMix
extends Node
## Der Mix aller Geräusche:
##  - Limiter auf dem Master: nichts übersteuert (laute Pops, Aufprall, Gewitter zusammen)
##  - Ansagen (Meldungen und Navi-Hinweise) bekommen einen kurzen Signalton auf dem Bus „Ansagen“,
##    dabei werden Umgebung und Musik kurz leiser (Ducking)
##  - Hall in der Umgebung: Alle 0,2 s schätzen Strahlen in 8 Richtungen und nach oben, wie eng es um das
##    Auto ist (Felswand, Brücke, Unterführung, Häuser). Daraus steuert der Bus „Hall“ (zwischen den
##    Geräuschen des Autos und dem Tunnel-Hall) Motor, Pops und Reifen, schwächer als im Tunnel.

@export var car: Car
@export var navigation: Navigation
@export var tunnel_effects: TunnelEffects

@export_group("Limiter")
## Höchster Pegel auf dem Master (dB) und wie schnell der Limiter wieder loslässt (Sekunden)
@export var limiter_ceiling_db: float = -1.0
@export var limiter_release: float = 0.12

@export_group("Ansagen")
## Lautstärke des Signaltons (dB), wie weit Umgebung und Musik dabei leiser werden (dB) und wie lange
@export var chime_volume_db: float = -10.0
@export var duck_db: float = -9.0
@export var duck_seconds: float = 1.6
## Navi: Hinweis, wenn eine Abbiegung näher als diese Entfernungen kommt (Meter)
@export var nav_announce_distances := Vector2(400.0, 80.0)

@export_group("Hall")
## So weit schauen die Strahlen (Meter), Hall-Anteil bei ganz enger Umgebung (Tunnel: 0,45)
@export var reverb_range: float = 30.0
@export var reverb_max_wet: float = 0.24
@export var reverb_interval: float = 0.2
## Wie schnell sich der Hall der Umgebung anpasst (pro Sekunde)
@export var reverb_smoothing: float = 3.0

const ANNOUNCE_BUS := "Ansagen"
const REVERB_BUS := "Hall"
const DUCKED_BUSES: Array[String] = ["Umgebung", "Musik"]

## Wie eng es gerade um das Auto ist (0 = offen, 1 = ganz umschlossen) und wie weit die Wände im Schnitt
## weg sind (0–1, Anteil von reverb_range)
var enclosure: float = 0.0
var wall_distance: float = 1.0

var _duck_amplifiers: Array[AudioEffectAmplify] = []
var _duck_time: float = 0.0
var _duck_level: float = 0.0
var _chime: AudioStreamPlayer
var _chime_soft: AudioStreamWAV
var _chime_nav: AudioStreamWAV
var _reverb: AudioEffectReverb
var _reverb_timer: float = 0.0
var _target_enclosure: float = 0.0
var _target_distance: float = 1.0
var _nav_last_distance: float = INF
var _nav_timer: float = 0.0


func _ready() -> void:
	add_to_group("announcements")
	_add_limiter()
	_setup_ducking()
	_setup_reverb_bus()
	_chime_soft = _make_chime([880.0, 1320.0], 0.22)
	_chime_nav = _make_chime([660.0, 990.0, 1320.0], 0.42)
	_chime = AudioStreamPlayer.new()
	_chime.bus = ANNOUNCE_BUS
	_chime.volume_db = chime_volume_db
	add_child(_chime)


func _add_limiter() -> void:
	var master := AudioServer.get_bus_index("Master")
	for i in AudioServer.get_bus_effect_count(master):
		if AudioServer.get_bus_effect(master, i) is AudioEffectHardLimiter:
			return
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = limiter_ceiling_db
	limiter.release = limiter_release
	AudioServer.add_bus_effect(master, limiter)


## Bus für Ansagen (wird nicht leiser) und Verstärker auf Umgebung und Musik (für das Ducking; die
## Lautstärke-Regler der Einstellungen bleiben unberührt)
func _setup_ducking() -> void:
	if AudioServer.get_bus_index(ANNOUNCE_BUS) == -1:
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, ANNOUNCE_BUS)
		AudioServer.set_bus_send(index, "Master")
	for bus_name in DUCKED_BUSES:
		var bus := AudioServer.get_bus_index(bus_name)
		if bus == -1:
			continue
		var amplify := AudioEffectAmplify.new()
		amplify.volume_db = 0.0
		AudioServer.add_bus_effect(bus, amplify)
		_duck_amplifiers.append(amplify)


## Bus „Hall“ mit eigenem Reverb: Geräusche des Autos → Hall → Tunnel → Motor
func _setup_reverb_bus() -> void:
	if AudioServer.get_bus_index(REVERB_BUS) == -1:
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, REVERB_BUS)
		var target := TunnelEffects.BUS_NAME if AudioServer.get_bus_index(TunnelEffects.BUS_NAME) != -1 else "Motor"
		AudioServer.set_bus_send(index, target)
		_reverb = AudioEffectReverb.new()
		_reverb.room_size = 0.5
		_reverb.damping = 0.55
		_reverb.spread = 0.7
		_reverb.predelay_msec = 40.0
		_reverb.wet = 0.0
		_reverb.dry = 1.0
		AudioServer.add_bus_effect(index, _reverb)
	if car:
		for player in car.find_children("*", "AudioStreamPlayer", true, false):
			var audio := player as AudioStreamPlayer
			if audio.bus == TunnelEffects.BUS_NAME or audio.bus == "Motor":
				audio.bus = REVERB_BUS


func _process(delta: float) -> void:
	_update_ducking(delta)
	_update_nav_announcements(delta)
	_reverb_timer -= delta
	if _reverb_timer <= 0.0:
		_reverb_timer = reverb_interval
		_measure_enclosure()
	var smooth := 1.0 - exp(-reverb_smoothing * delta)
	enclosure = lerpf(enclosure, _target_enclosure, smooth)
	wall_distance = lerpf(wall_distance, _target_distance, smooth)
	if _reverb:
		# Im Tunnel übernimmt der Tunnel-Hall
		var tunnel := tunnel_effects.car_cover if tunnel_effects else 0.0
		_reverb.wet = reverb_max_wet * enclosure * (1.0 - tunnel)
		_reverb.room_size = lerpf(0.3, 0.75, wall_distance)


## Eine Ansage: Signalton (Navi: drei Töne, sonst zwei leise) und kurz Umgebung und Musik leiser.
## Aufgerufen von Toasts.post (Gruppe „announcements“) und von den Navi-Hinweisen.
func announce(kind: String = "toast") -> void:
	_chime.stream = _chime_nav if kind == "nav" else _chime_soft
	_chime.play()
	_duck_time = duck_seconds


func _update_ducking(delta: float) -> void:
	_duck_time = maxf(_duck_time - delta, 0.0)
	# Schnell leiser (0,15 s), langsam wieder lauter (0,6 s)
	var wanted := 1.0 if _duck_time > 0.0 else 0.0
	_duck_level = move_toward(_duck_level, wanted, delta / (0.15 if wanted > _duck_level else 0.6))
	for amplify in _duck_amplifiers:
		amplify.volume_db = duck_db * _duck_level


## Navi: Hinweis, wenn die nächste Abbiegung unter 400 m bzw. 80 m kommt
func _update_nav_announcements(delta: float) -> void:
	_nav_timer -= delta
	if _nav_timer > 0.0 or navigation == null:
		return
	_nav_timer = 0.25
	if not navigation.has_target:
		_nav_last_distance = INF
		return
	var turn := navigation.next_turn()
	var distance: float = turn.get("distance", INF)
	for threshold in [nav_announce_distances.x, nav_announce_distances.y]:
		if distance < threshold and _nav_last_distance >= threshold:
			announce("nav")
			break
	_nav_last_distance = distance


## Wie eng ist es ums Auto? 8 Strahlen waagerecht (1,2 m über dem Auto) und einer nach oben. Nähere Wände
## zählen mehr, ein Dach (Brücke, Unterführung) zählt extra.
func _measure_enclosure() -> void:
	if car == null or not car.is_inside_tree():
		return
	var space := car.get_world_3d().direct_space_state
	var origin := car.global_position + Vector3.UP * 1.2
	var exclude: Array[RID] = [car.get_rid()]
	var walls := 0.0
	var distance_sum := 0.0
	var hits := 0
	for k in 8:
		var direction := Vector3.FORWARD.rotated(Vector3.UP, TAU * k / 8.0)
		var hit := _ray(space, origin, origin + direction * reverb_range, exclude)
		if not hit.is_empty():
			var d := origin.distance_to(hit["position"]) / reverb_range
			walls += 1.0 - d
			distance_sum += d
			hits += 1
	var roof := 0.0
	var up := _ray(space, origin, origin + Vector3.UP * reverb_range, exclude)
	if not up.is_empty():
		roof = 1.0 - origin.distance_to(up["position"]) / reverb_range
	_target_enclosure = clampf(walls / 8.0 * 1.3 + roof * 0.6, 0.0, 1.0)
	_target_distance = distance_sum / hits if hits > 0 else 1.0


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, exclude: Array[RID]) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = exclude
	return space.intersect_ray(query)


## Signalton: Töne nacheinander (je 0,09 s versetzt), weich ein- und ausklingend, mit etwas Glocken-Oberton
func _make_chime(tones: Array, seconds: float) -> AudioStreamWAV:
	var rate := 48000
	var count := int(rate * (seconds + 0.25))
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t := float(i) / rate
		var value := 0.0
		for n in tones.size():
			var start := n * 0.09
			if t < start:
				continue
			var local := t - start
			var envelope := minf(local / 0.008, 1.0) * exp(-local * 9.0)
			var f: float = tones[n]
			value += (sin(TAU * f * local) + 0.25 * sin(TAU * f * 2.76 * local)) * envelope
		data.encode_s16(i * 2, int(clampf(value * 0.45, -1.0, 1.0) * 30000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = data
	return wav
