extends VehicleBody3D
## Das Auto des Spielers.
## Die eigentliche Physik (Federung, Reifen-Grip) rechnet Godots VehicleBody3D.
## Dieses Skript entscheidet nur, wann wie viel Gas, Bremse und Lenkung anliegt.

@export_group("Motor")
## Maximale Antriebskraft am Boden in Newton (alle Antriebsräder zusammen)
@export var max_engine_force: float = 9000.0
## Motorleistung in Kilowatt (110 kW = ca. 150 PS). Begrenzt die Kraft bei hohem Tempo.
@export var engine_power_kw: float = 110.0
## Höchstgeschwindigkeit rückwärts in km/h
@export var max_reverse_speed_kmh: float = 30.0
## Anteil der Motorkraft im Rückwärtsgang (0 bis 1)
@export_range(0.0, 1.0) var reverse_force_factor: float = 0.5

@export_group("Bremsen")
## Bremswert für S (Godot-Einheit: ca. 50 bremst ein 1300-kg-Auto sehr hart)
@export var brake_strength: float = 50.0
## Leichtes Bremsen, wenn man vom Gas geht (Motorbremse und Rollwiderstand)
@export var engine_brake_strength: float = 1.5
## Bremswert der Handbremse (wirkt nur auf die Hinterräder)
@export var handbrake_strength: float = 30.0
## Wie viel Grip die Hinterräder mit gezogener Handbremse behalten (0 bis 1)
@export_range(0.0, 1.0) var handbrake_grip: float = 0.6

@export_group("Lenkung")
## Maximaler Lenkwinkel im Stand in Grad
@export var max_steer_angle: float = 35.0
## Maximaler Lenkwinkel bei hohem Tempo in Grad
@export var high_speed_steer_angle: float = 4.0
## Ab diesem Tempo (km/h) gilt nur noch der kleine Lenkwinkel
@export var steer_reduction_speed_kmh: float = 150.0
## Wie schnell das Lenkrad einschlägt (4 = in einer Viertelsekunde voll eingeschlagen)
@export var steer_speed: float = 4.0

@export_group("Aerodynamik")
## Luftwiderstand: bremst vor allem bei hohem Tempo
@export var air_drag: float = 0.4
## Anpressdruck: drückt das Auto bei Tempo auf die Straße
@export var downforce: float = 0.5

@export_group("Reset")
## Um so viele Meter wird das Auto beim Aufrichten (Taste R) angehoben
@export var reset_lift: float = 1.0
## Fällt das Auto unter diese Höhe (z. B. vom Rand der Welt), geht es zurück zum Start
@export var fall_limit_y: float = -20.0

var _steer_input: float = 0.0
var _traction_wheel_count: int = 0
var _rear_grip: float = 1.0
var _spawn_transform: Transform3D

@onready var _rear_left: VehicleWheel3D = $WheelRearLeft
@onready var _rear_right: VehicleWheel3D = $WheelRearRight


func _ready() -> void:
	_spawn_transform = global_transform
	_rear_grip = _rear_left.wheel_friction_slip
	# Zählen, wie viele Räder angetrieben sind (bei Heckantrieb: 2).
	# So stimmt die Kraft auch, wenn man im Editor auf Allrad umstellt.
	for child in get_children():
		var wheel := child as VehicleWheel3D
		if wheel and wheel.use_as_traction:
			_traction_wheel_count += 1


func _physics_process(delta: float) -> void:
	# Tempo in Fahrtrichtung in m/s: positiv = vorwärts, negativ = rückwärts.
	# Beim VehicleBody3D zeigt die Nase des Autos in Richtung +Z.
	var forward_speed: float = linear_velocity.dot(global_basis.z)

	_update_steering(delta, absf(forward_speed) * 3.6)
	_update_engine_and_brakes(forward_speed)
	_update_handbrake()
	_apply_aerodynamics(forward_speed)

	if Input.is_action_just_pressed("reset_car"):
		_place_car(_upright_transform())
	if global_position.y < fall_limit_y:
		_place_car(_spawn_transform)


func _update_steering(delta: float, speed_kmh: float) -> void:
	# Ziel zwischen -1 (ganz rechts) und +1 (ganz links). Bei Godot lenkt "positiv" nach links.
	var target: float = Input.get_axis("steer_right", "steer_left")
	# Das Lenkrad springt nicht sofort, sondern dreht zügig zum Ziel
	_steer_input = move_toward(_steer_input, target, steer_speed * delta)
	# Je schneller, desto kleiner der maximale Lenkwinkel. Die Wurzel sorgt dafür,
	# dass der Winkel schon bei mittlerem Tempo deutlich kleiner wird.
	var t: float = clampf(speed_kmh / steer_reduction_speed_kmh, 0.0, 1.0)
	var max_angle: float = lerpf(max_steer_angle, high_speed_steer_angle, sqrt(t))
	steering = deg_to_rad(max_angle) * _steer_input


func _update_engine_and_brakes(forward_speed: float) -> void:
	var throttle: float = Input.get_action_strength("accelerate")
	var brake_input: float = Input.get_action_strength("brake")
	var drive_force: float = 0.0
	var brake_value: float = 0.0

	if throttle > 0.0:
		if forward_speed < -0.5:
			# Rollt noch rückwärts: Gas bremst erst einmal ab
			brake_value = brake_strength * throttle
		else:
			drive_force = _engine_force_at(forward_speed) * throttle
	elif brake_input > 0.0:
		if forward_speed > 0.5:
			# Fährt vorwärts: S bremst
			brake_value = brake_strength * brake_input
		elif -forward_speed * 3.6 < max_reverse_speed_kmh:
			# Steht (fast): S fährt rückwärts, aber nur bis zum Rückwärts-Tempolimit
			drive_force = -max_engine_force * reverse_force_factor * brake_input
	else:
		# Kein Pedal gedrückt: Auto rollt langsam aus
		brake_value = engine_brake_strength

	# Godot erwartet die Kraft pro Antriebsrad
	engine_force = drive_force / maxi(_traction_wheel_count, 1)
	brake = brake_value


## Antriebskraft des Motors bei einem bestimmten Tempo (m/s).
## Langsam: volle Kraft. Schnell: begrenzt durch die Leistung (Kraft = Leistung / Tempo).
func _engine_force_at(speed: float) -> float:
	var power_limited_force: float = engine_power_kw * 1000.0 / maxf(speed, 1.0)
	return minf(max_engine_force, power_limited_force)


func _update_handbrake() -> void:
	var pulled: bool = Input.is_action_pressed("handbrake")
	if pulled:
		# Mit gezogener Handbremse ist quasi die Kupplung getreten
		engine_force = 0.0
	for wheel: VehicleWheel3D in [_rear_left, _rear_right]:
		if pulled:
			wheel.brake = handbrake_strength
			wheel.wheel_friction_slip = _rear_grip * handbrake_grip
		else:
			wheel.wheel_friction_slip = _rear_grip


func _apply_aerodynamics(forward_speed: float) -> void:
	# Luftwiderstand wirkt gegen die Bewegung und wächst mit dem Tempo im Quadrat
	apply_central_force(-linear_velocity * linear_velocity.length() * air_drag)
	# Anpressdruck drückt das Auto nach unten (von der Karosserie aus gesehen)
	apply_central_force(-global_basis.y * downforce * forward_speed * forward_speed)


## Aktuelle Position, aber aufrecht und etwas angehoben. Die Blickrichtung bleibt.
func _upright_transform() -> Transform3D:
	var forward: Vector3 = global_basis.z
	var yaw: float = atan2(forward.x, forward.z)
	return Transform3D(Basis(Vector3.UP, yaw), global_position + Vector3.UP * reset_lift)


func _place_car(new_transform: Transform3D) -> void:
	global_transform = new_transform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_steer_input = 0.0
	# Sonst würde die Physik-Interpolation das Auto sichtbar zum neuen Ort gleiten lassen
	reset_physics_interpolation()
