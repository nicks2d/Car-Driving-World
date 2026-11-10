class_name CruiseControl
extends Node
## Tempomat mit Abstandsregelung (wie ein ACC im BMW).
## N schaltet ein (ab 30 km/h, übernimmt das aktuelle Tempo) und aus, + / − ändern das
## Wunschtempo um 1 km/h (gedrückt halten: in 10er-Schritten), B wählt die Abstandsstufe.
## Bremsen schaltet ihn aus, Gas geben überstimmt ihn nur, solange man drückt.
## Fährt jemand voraus, hält er Abstand nach derselben Regel wie die KI-Autos (IDM: Mindestabstand
## + Zeitlücke, Vordermann aus Traffic.leader_ahead), bremst selbst höchstens mit max_brake und
## warnt (Ton, rotes Symbol), wenn mehr nötig wäre. Auf Wunsch übernimmt er erkannte Tempolimits.

@export var car: Car
@export var traffic: Traffic
@export var limits: SpeedLimits
## Ab diesem Tempo lässt er sich einschalten (km/h)
@export var min_speed_kmh: float = 30.0
## Abstandsstufen: Zeitlücke zum Vordermann (Sekunden)
@export var gaps: Array[float] = [1.0, 1.4, 1.8, 2.4]
## So stark beschleunigt bzw. bremst er höchstens selbst (m/s²)
@export var max_accel: float = 2.0
@export var max_brake: float = 3.5
## Erkannte Tempolimits übernehmen (Einstellungen > Steuerung)
@export var adopt_limits: bool = true

## An? Wunschtempo (km/h, eventuell vom Limit), vom Fahrer gewähltes Tempo, Abstandsstufe
var active: bool = false
var set_speed_kmh: float = 0.0
var user_speed_kmh: float = 0.0
var gap_level: int = 2
## Abstand zum erkannten Vordermann (Meter, -1 = keiner) und ob er gerade warnt
var leader_gap: float = -1.0
var warning: bool = false

var _throttle: float = 0.0
var _previous_speed: float = 0.0
var _accel: float = 0.0
var _hold: float = 0.0
var _repeat: float = 0.0
var _last_limit: int = -1
var _beep: AudioStreamPlayer
var _beep_timer: float = 0.0


func _ready() -> void:
	# Warnton: zwei kurze hohe Töne, im Code erzeugt
	var rate := 22050
	var data := PackedByteArray()
	for k in int(rate * 0.32):
		var t := float(k) / rate
		var on := fmod(t, 0.16) < 0.09
		var sample := sin(TAU * 1760.0 * t) * (0.5 if on else 0.0)
		data.append(int(clampf(sample, -1.0, 1.0) * 127.0) & 0xFF)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = rate
	stream.data = data
	_beep = AudioStreamPlayer.new()
	_beep.stream = stream
	_beep.volume_db = -10.0
	add_child(_beep)


func _physics_process(delta: float) -> void:
	if car == null or get_tree().paused:
		return
	var speed := car.linear_velocity.dot(car.global_basis.z)
	_accel = lerpf(_accel, (speed - _previous_speed) / maxf(delta, 0.001), 0.15)
	_previous_speed = speed
	if car.throttle_enabled:
		_handle_keys(delta, speed * 3.6)
	if not active:
		car.assist_throttle = -1.0
		car.assist_brake = 0.0
		warning = false
		leader_gap = -1.0
		return
	if Input.get_action_strength("brake") > 0.1 or not car.throttle_enabled or car.gear < 0:
		switch_off()
		return
	# Erkannte Limits übernehmen; wird es wieder unbegrenzt, gilt das selbst gewählte Tempo
	if adopt_limits and limits and limits.effective_limit != _last_limit:
		_last_limit = limits.effective_limit
		if _last_limit > 0:
			set_speed_kmh = float(_last_limit)
		elif _last_limit == 0:
			set_speed_kmh = user_speed_kmh
	var command := desired_accel(speed)
	# Umsetzen: Bremse direkt, Gas über einen Regler auf die gemessene Beschleunigung
	if Input.get_action_strength("accelerate") > 0.05:
		# Fahrer überstimmt: sein Gas gilt, danach geht es von dort weiter
		_throttle = Input.get_action_strength("accelerate")
		car.assist_throttle = -1.0
		car.assist_brake = 0.0
	elif command < -0.4:
		_throttle = 0.0
		car.assist_throttle = 0.0
		# Bremse 0,27 ≈ 3,5 m/s² (mit Luftwiderstand)
		car.assist_brake = clampf(-command / 13.0, 0.0, 0.35)
	else:
		_throttle = clampf(_throttle + (command - _accel) * 0.5 * delta, 0.0, 1.0)
		car.assist_throttle = _throttle
		car.assist_brake = 0.0
	# Warnen, solange mehr Bremse nötig wäre
	_beep_timer -= delta
	if warning and _beep_timer <= 0.0:
		_beep.play()
		_beep_timer = 0.8


## Wunschbeschleunigung (m/s², begrenzt auf -max_brake) nach dem IDM wie bei der KI; setzt
## leader_gap und warning
func desired_accel(speed: float) -> float:
	var v0 := maxf(set_speed_kmh / 3.6, 1.0)
	var free := 1.0 - pow(maxf(speed, 0.0) / v0, 4.0)
	var interaction := 0.0
	leader_gap = -1.0
	# Eigener Weg aus der Drehrate (positiv = links), bei wenig Tempo keiner
	var curvature := car.angular_velocity.y / speed if speed > 5.0 else 0.0
	var leader: Array = traffic.leader_ahead(car.global_position, car.global_basis.z, 4.6, 220.0, 0.0, curvature) if traffic else []
	if not leader.is_empty():
		leader_gap = leader[0]
		var closing: float = speed - (leader[1] as float)
		var wanted := Traffic.MIN_GAP + speed * gaps[gap_level] + speed * closing / (2.0 * sqrt(max_accel * 2.5))
		interaction = pow(maxf(wanted, 0.0) / maxf(leader_gap, 0.5), 2.0)
	var desired := max_accel * (free - interaction)
	warning = desired < -max_brake - 0.5 and Input.get_action_strength("accelerate") < 0.05
	return maxf(desired, -max_brake)


func switch_on(kmh: float) -> void:
	active = true
	user_speed_kmh = roundf(kmh)
	set_speed_kmh = user_speed_kmh
	_last_limit = limits.effective_limit if limits else -1
	_throttle = 0.3


func switch_off() -> void:
	active = false
	warning = false
	car.assist_throttle = -1.0
	car.assist_brake = 0.0


func _handle_keys(delta: float, kmh: float) -> void:
	if Input.is_action_just_pressed("cruise_toggle"):
		if active:
			switch_off()
		elif kmh >= min_speed_kmh:
			switch_on(kmh)
		else:
			Toasts.post(get_tree(), "clock", "Tempomat", "Erst ab %d km/h" % roundi(min_speed_kmh), "", "")
	if Input.is_action_just_pressed("cruise_distance"):
		gap_level = (gap_level + 1) % gaps.size()
	if not active:
		return
	# + / −: kurz 1 km/h, gedrückt halten alle 0,4 s auf den nächsten Zehner
	var direction := int(Input.is_action_pressed("cruise_faster")) - int(Input.is_action_pressed("cruise_slower"))
	if direction == 0:
		_hold = 0.0
		return
	if Input.is_action_just_pressed("cruise_faster") or Input.is_action_just_pressed("cruise_slower"):
		_change(float(direction))
		_hold = 0.0
		_repeat = 0.0
		return
	_hold += delta
	if _hold > 0.5:
		_repeat -= delta
		if _repeat <= 0.0:
			_repeat = 0.4
			var target := (floorf(set_speed_kmh / 10.0) + 1.0) * 10.0 if direction > 0 else (ceilf(set_speed_kmh / 10.0) - 1.0) * 10.0
			_change(target - set_speed_kmh)


func _change(amount: float) -> void:
	set_speed_kmh = clampf(set_speed_kmh + amount, min_speed_kmh, 300.0)
	user_speed_kmh = set_speed_kmh
