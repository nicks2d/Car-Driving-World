class_name Car
extends VehicleBody3D
## Das Auto des Spielers. Welches Auto es ist (Maße, Motor, Getriebe, Modell, Sound), steht
## in seinem Profil (CarProfile, cars/*.tres). apply_profile() stellt alles darauf ein,
## auch während des Spiels (Garage).
## Die eigentliche Physik (Federung, Reifen-Grip) rechnet Godots VehicleBody3D.
## Dieses Skript ist Motor, Getriebe und Fahrer-Eingaben: wann wie viel Kraft, Bremse
## und Lenkung anliegt.

## Wird beim Gangwechsel gesendet (für das Schaltgeräusch)
signal gear_changed(new_gear: int)
## Wird gesendet, wenn ein anderes Auto gewählt wurde (Modell, Sound usw. bauen sich neu)
signal profile_changed(new_profile: CarProfile)

## Das Auto, mit dem das Spiel startet (die Garage kann es wechseln)
@export var profile: CarProfile

@export_group("Allgemein")
## Leichtes Bremsen, wenn man vom Gas geht (Motorbremse und Rollwiderstand)
@export var engine_brake_strength: float = 1.5
## Wie viel Grip die Hinterräder mit gezogener Handbremse behalten (0 bis 1)
@export_range(0.0, 1.0) var handbrake_grip: float = 0.6
## Höchstgeschwindigkeit rückwärts in km/h
@export var max_reverse_speed_kmh: float = 30.0
## Anteil der Antriebskraft im Rückwärtsgang (0 bis 1)
@export_range(0.0, 1.0) var reverse_force_factor: float = 0.4
## Ab dieser Querbeschleunigung (m/s², 9.81 = 1 g) verliert das Heck bei Vollgas Grip
@export var power_oversteer_lateral: float = 7.0
## Grip-Faktor für alle Räder (Wetter: nass 0,7, Schnee 0,5)
@export_range(0.1, 1.0) var grip_factor: float = 1.0

@export_group("Lenkung")
## Ab diesem Tempo (km/h) gilt nur noch der kleine Lenkwinkel (Winkel stehen im Profil)
@export var steer_reduction_speed_kmh: float = 150.0
## Wie schnell das Lenkrad einschlägt (4 = in einer Viertelsekunde voll eingeschlagen)
@export var steer_speed: float = 4.0

@export_group("Reset")
## Um so viele Meter wird das Auto beim Aufrichten (Taste R) angehoben
@export var reset_lift: float = 1.0
## Fällt das Auto unter diese Höhe (z. B. vom Rand der Welt), geht es zurück zum Start
@export var fall_limit_y: float = -20.0

## Wird gerade gebremst? (für die Bremslichter)
var braking: bool = false
## Aktueller Gang: 1 bis Anzahl Gänge, -1 = Rückwärtsgang (für Drehzahlmesser und Sound)
var gear: int = 1
## Motordrehzahl in 1/min
var engine_rpm: float = 900.0
## Gaspedal 0 bis 1 (für den Sound)
var throttle_input: float = 0.0
## Driftwinkel in Grad: Winkel zwischen Fahrtrichtung und Blickrichtung des Autos
var drift_angle: float = 0.0
## Wie nass (oder verschneit) die Straße unter dem Auto ist, 0 bis 1 (setzt das Wetter;
## für die Gischt hinter den Reifen)
var wetness: float = 0.0
## Fährt das Auto gerade durch einen Tunnel? (setzt TunnelEffects; schaltet das Licht an)
var in_tunnel: bool = false
## Sportauspuff (Garage): an = Pops und Flammen beim Gaswegnehmen
var sport_exhaust: bool = true
## false = Gas und Bremse werden nicht gelesen, Handbremse an (Test-Fotos: Auto bleibt stehen)
var throttle_enabled: bool = true

var _steer_input: float = 0.0
var _shift_timer: float = 0.0
## Antriebskraft dieses Physik-Schritts (alle Räder zusammen, Newton)
var _drive_force_now: float = 0.0
var _spawn_transform: Transform3D

@onready var _front_left: VehicleWheel3D = $WheelFrontLeft
@onready var _front_right: VehicleWheel3D = $WheelFrontRight
@onready var _rear_left: VehicleWheel3D = $WheelRearLeft
@onready var _rear_right: VehicleWheel3D = $WheelRearRight


func _ready() -> void:
	_spawn_transform = global_transform
	if profile:
		apply_profile(profile)


## Ruhelage der Radmitte einer Ecke relativ zum Auto (0 = vorne links, 1 = vorne rechts,
## 2 = hinten links, 3 = hinten rechts). Die Federung ist dann etwas eingedrückt: um
## Gewicht / Federhärte (Godot rechnet die Federkraft mal Masse, deshalb hängt das nicht
## vom Gewicht ab). Aus dem Profil gerechnet, weil die Physik die Lage der Rad-Knoten
## ständig selbst setzt.
static func resting_wheel_center(car_profile: CarProfile, corner: int) -> Vector3:
	var front := corner < 2
	var side := 1.0 if corner % 2 == 0 else -1.0
	var sag := 9.81 / (4.0 * car_profile.suspension_stiffness)
	var track := car_profile.track_front if front else car_profile.track_rear
	return Vector3(track * 0.5 * side, -(car_profile.suspension_rest_length - sag),
		car_profile.wheelbase * 0.5 * (1.0 if front else -1.0))


## Die vier Rad-Knoten in der Reihenfolge der Ecken (siehe resting_wheel_center)
func corner_wheels() -> Array[VehicleWheel3D]:
	return [_front_left, _front_right, _rear_left, _rear_right]


## Auf ein anderes Auto umstellen: Maße, Räder, Gewicht, Kollision. Motorwerte liest das
## Skript laufend aus dem Profil. Modell, Sound und Effekte hören auf profile_changed.
func apply_profile(new_profile: CarProfile) -> void:
	profile = new_profile
	mass = profile.mass
	var front_z := profile.wheelbase * 0.5
	var wheels := {_front_left: Vector3(profile.track_front * 0.5, 0.0, front_z),
		_front_right: Vector3(-profile.track_front * 0.5, 0.0, front_z),
		_rear_left: Vector3(profile.track_rear * 0.5, 0.0, -front_z),
		_rear_right: Vector3(-profile.track_rear * 0.5, 0.0, -front_z)}
	for wheel: VehicleWheel3D in wheels:
		var is_front: bool = wheels[wheel].z > 0.0
		# Godot übernimmt den Befestigungspunkt eines Rads nur, wenn es in die Szene kommt:
		# deshalb kurz herausnehmen, verschieben und wieder einhängen
		remove_child(wheel)
		wheel.position = wheels[wheel]
		wheel.wheel_radius = profile.wheel_radius
		wheel.wheel_rest_length = profile.suspension_rest_length
		wheel.suspension_travel = profile.suspension_travel
		wheel.suspension_stiffness = profile.suspension_stiffness
		wheel.suspension_max_force = profile.suspension_max_force
		wheel.damping_compression = profile.damping_compression
		wheel.damping_relaxation = profile.damping_relaxation
		wheel.wheel_roll_influence = profile.roll_influence
		wheel.wheel_friction_slip = (profile.grip_front if is_front else profile.grip_rear) * grip_factor
		wheel.use_as_steering = is_front
		wheel.use_as_traction = not is_front or profile.front_drive_share > 0.0
		add_child(wheel)
		# Platzhalter-Reifen passend zum Radradius
		var tire := wheel.get_node_or_null("Tire") as MeshInstance3D
		if tire and tire.mesh is CylinderMesh:
			(tire.mesh as CylinderMesh).top_radius = profile.wheel_radius
			(tire.mesh as CylinderMesh).bottom_radius = profile.wheel_radius
	# Kollision und Platzhalter-Box
	_set_box($BodyShape, $BodyMesh, profile.body_size, profile.body_center)
	_set_box($CabinShape, $CabinMesh, profile.cabin_size, profile.cabin_center)
	gear = 1
	engine_rpm = profile.idle_rpm
	profile_changed.emit(profile)


func _set_box(shape_node: CollisionShape3D, mesh_node: MeshInstance3D, size: Vector3, center: Vector3) -> void:
	var box := BoxShape3D.new()
	box.size = size
	shape_node.shape = box
	shape_node.position = center
	var mesh := mesh_node.mesh.duplicate() as BoxMesh
	mesh.size = size
	mesh_node.mesh = mesh
	mesh_node.position = center


func _physics_process(delta: float) -> void:
	# Tempo in Fahrtrichtung in m/s: positiv = vorwärts, negativ = rückwärts.
	# Beim VehicleBody3D zeigt die Nase des Autos in Richtung +Z.
	var forward_speed: float = linear_velocity.dot(global_basis.z)
	drift_angle = _measure_drift_angle()

	_update_steering(delta, absf(forward_speed) * 3.6)
	_update_gearbox(delta, forward_speed)
	_update_engine_and_brakes(forward_speed)
	_update_rear_grip()
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
	var max_angle: float = lerpf(profile.max_steer_angle, profile.high_speed_steer_angle, sqrt(t))
	steering = deg_to_rad(max_angle) * _steer_input


## Drehzahl aus dem Tempo und Gangwahl wie bei einer Automatik
func _update_gearbox(delta: float, forward_speed: float) -> void:
	throttle_input = Input.get_action_strength("accelerate") if throttle_enabled else 0.0
	_shift_timer = maxf(_shift_timer - delta, 0.0)
	# Rückwärtsgang: nur aus dem Stand mit S. Gas legt wieder den 1. Gang ein.
	if gear == -1:
		if throttle_input > 0.0 and forward_speed > -0.5:
			_shift_to(1)
	elif Input.get_action_strength("brake") > 0.0 and forward_speed < 0.5 and throttle_input == 0.0:
		_shift_to(-1)
	var ratio := _current_ratio()
	# So schnell dreht sich der Motor, wenn die Kupplung geschlossen ist
	var wheel_rpm := absf(forward_speed) / (TAU * _rear_left.wheel_radius) * 60.0
	var rpm_from_wheels := wheel_rpm * ratio
	if gear >= 1 and _shift_timer == 0.0:
		# Bei Vollgas spät hoch- und früh herunterschalten, bei wenig Gas umgekehrt
		# Bei wenig Gas schaltet die Automatik bei ca. 40 % der Begrenzer-Drehzahl hoch
		var up := lerpf(profile.redline_rpm * 0.37, profile.shift_up_rpm, throttle_input)
		var down := lerpf(1300.0, profile.shift_down_rpm, throttle_input)
		if rpm_from_wheels > up and gear < profile.gear_ratios.size():
			_shift_to(gear + 1)
		elif rpm_from_wheels < down and gear > 1:
			# Nur, wenn der kleinere Gang nicht gleich wieder über die Schaltdrehzahl käme
			var lower_rpm := wheel_rpm * profile.gear_ratios[gear - 2] * profile.final_drive
			if lower_rpm < up * 0.9:
				_shift_to(gear - 1)
	# Beim Anfahren schleift die Kupplung: Die Drehzahl hängt dann vom Gas ab, nicht vom Tempo
	var clutch_rpm := profile.idle_rpm + throttle_input * profile.launch_rpm
	var target := maxf(rpm_from_wheels, profile.idle_rpm)
	if absi(gear) == 1:
		target = maxf(target, clutch_rpm)
	engine_rpm = move_toward(engine_rpm, minf(target, profile.redline_rpm), 30000.0 * delta)


func _shift_to(new_gear: int) -> void:
	if new_gear == gear:
		return
	gear = new_gear
	_shift_timer = profile.shift_time
	gear_changed.emit(gear)


## Gesamtübersetzung vom Motor bis zum Rad
func _current_ratio() -> float:
	if gear == -1:
		return profile.gear_ratios[0] * profile.final_drive
	return profile.gear_ratios[gear - 1] * profile.final_drive


## Drehmoment des Motors (Nm) bei Vollgas und einer bestimmten Drehzahl
func _torque_at(rpm: float) -> float:
	var p := profile
	if rpm < p.torque_plateau_start_rpm:
		# Unten herum: vom Leerlauf bis zum vollen Drehmoment ansteigend (Turbo baut Druck auf)
		return lerpf(p.max_torque_nm * p.low_end_torque, p.max_torque_nm,
			clampf((rpm - p.idle_rpm) / (p.torque_plateau_start_rpm - p.idle_rpm), 0.0, 1.0))
	# Leistung = Drehmoment mal Winkelgeschwindigkeit: oben herum begrenzt die Leistung
	var power_limited := p.max_power_kw * 1000.0 / (rpm * TAU / 60.0)
	if rpm > p.power_end_rpm:
		power_limited *= lerpf(1.0, 0.8, clampf((rpm - p.power_end_rpm) / (p.redline_rpm - p.power_end_rpm), 0.0, 1.0))
	return minf(p.max_torque_nm, power_limited)


## Fahrhilfe: Wie viel Leistung darf bei diesem Driftwinkel noch anliegen (0 bis 1)?
func _drift_control() -> float:
	if profile.drift_angle_limit <= 0.0:
		return 1.0
	# Bis zum Grenzwert volle Leistung, 15° darüber nur noch 20 %
	return clampf(1.0 - (drift_angle - profile.drift_angle_limit) / 15.0 * 0.8, 0.2, 1.0)


func _measure_drift_angle() -> float:
	var velocity := linear_velocity
	velocity.y = 0.0
	if velocity.length() < 5.0:
		return 0.0
	var heading := global_basis.z
	heading.y = 0.0
	return rad_to_deg(heading.normalized().angle_to(velocity.normalized()))


## Wie stark rutscht dieses Rad (0 = haftet, 1 = rutscht voll)? Für Reifenspuren, Rauch
## und Quietschen. Godot meldet Rutschen über get_skidinfo(); bei den Hinterrädern zählt
## zusätzlich der Driftwinkel des ganzen Autos.
func wheel_slip(wheel: VehicleWheel3D) -> float:
	if not wheel.is_in_contact() or linear_velocity.length() < 2.0:
		return 0.0
	var slip := clampf((0.9 - wheel.get_skidinfo()) / 0.6, 0.0, 1.0)
	if wheel == _rear_left or wheel == _rear_right:
		slip = maxf(slip, clampf((drift_angle - 6.0) / 14.0, 0.0, 1.0))
	return slip


## Antriebskraft am Boden (alle Antriebsräder zusammen, Newton) bei Vollgas
func _drive_force() -> float:
	if _shift_timer > 0.0 or engine_rpm >= profile.redline_rpm:
		return 0.0
	var force := _torque_at(engine_rpm) * _current_ratio() * profile.drivetrain_efficiency / _rear_left.wheel_radius
	return minf(force, profile.max_drive_force)


func _update_engine_and_brakes(forward_speed: float) -> void:
	var throttle: float = throttle_input
	var brake_input: float = Input.get_action_strength("brake")
	var drive_force: float = 0.0
	var brake_value: float = 0.0
	var speed_kmh := forward_speed * 3.6

	if throttle > 0.0:
		if forward_speed < -0.5:
			# Rollt noch rückwärts: Gas bremst erst einmal ab
			brake_value = profile.brake_strength * throttle
		else:
			drive_force = _drive_force() * throttle
			# Abregelung: kurz vor der Höchstgeschwindigkeit sanft weniger Kraft
			drive_force *= clampf((profile.top_speed_kmh + 1.5 - speed_kmh) / 3.0, 0.0, 1.0)
			drive_force *= _drift_control()
	elif brake_input > 0.0:
		if forward_speed > 0.5:
			# Fährt vorwärts: S bremst
			brake_value = profile.brake_strength * brake_input
		elif -speed_kmh < max_reverse_speed_kmh and gear == -1:
			# Steht (fast): S fährt rückwärts, aber nur bis zum Rückwärts-Tempolimit
			drive_force = -profile.max_drive_force * reverse_force_factor * brake_input
	else:
		# Kein Pedal gedrückt: Auto rollt langsam aus
		brake_value = engine_brake_strength

	# Kraft auf die Räder verteilen: Heckantrieb nur hinten, Allrad nach front_drive_share
	_drive_force_now = drive_force
	var front := drive_force * profile.front_drive_share * 0.5
	var rear := drive_force * (1.0 - profile.front_drive_share) * 0.5
	_front_left.engine_force = front
	_front_right.engine_force = front
	_rear_left.engine_force = rear
	_rear_right.engine_force = rear
	brake = brake_value
	braking = brake_value > engine_brake_strength


## Grip der Hinterräder: Handbremse und Vollgas in schnellen Kurven lassen das Heck rutschen
## Dazu der Grip-Faktor vom Wetter für alle Räder.
func _update_rear_grip() -> void:
	var grip := profile.grip_rear * grip_factor
	var pulled: bool = Input.is_action_pressed("handbrake") or not throttle_enabled
	if pulled:
		# Mit gezogener Handbremse ist quasi die Kupplung getreten
		for wheel: VehicleWheel3D in [_front_left, _front_right, _rear_left, _rear_right]:
			wheel.engine_force = 0.0
		_drive_force_now = 0.0
		grip *= handbrake_grip
	# Godots Reifenmodell zählt die Antriebskraft kaum gegen den Seitenhalt. Echte Hinterreifen
	# mit viel Drehmoment verlieren in der Kurve Seitenhalt, wenn man Gas gibt: das wird hier
	# nachgebildet. Quadratisch: Mit wenig Gas bleibt das Heck ruhig.
	var lateral := absf(angular_velocity.y) * linear_velocity.length()
	var power := clampf(absf(_drive_force_now) / profile.max_drive_force, 0.0, 1.0)
	grip *= 1.0 - profile.power_oversteer * power * power * clampf(lateral / power_oversteer_lateral, 0.0, 1.0)
	for wheel: VehicleWheel3D in [_rear_left, _rear_right]:
		if pulled:
			wheel.brake = profile.handbrake_strength
		wheel.wheel_friction_slip = grip
	for wheel: VehicleWheel3D in [_front_left, _front_right]:
		wheel.wheel_friction_slip = profile.grip_front * grip_factor


func _apply_aerodynamics(forward_speed: float) -> void:
	# Luftwiderstand wirkt gegen die Bewegung und wächst mit dem Tempo im Quadrat
	apply_central_force(-linear_velocity * linear_velocity.length() * profile.air_drag)
	# Anpressdruck drückt das Auto nach unten (von der Karosserie aus gesehen)
	apply_central_force(-global_basis.y * profile.downforce * forward_speed * forward_speed)


## Aktuelle Position, aber aufrecht und etwas angehoben. Die Blickrichtung bleibt.
func _upright_transform() -> Transform3D:
	var forward: Vector3 = global_basis.z
	var yaw: float = atan2(forward.x, forward.z)
	return Transform3D(Basis(Vector3.UP, yaw), global_position + Vector3.UP * reset_lift)


## Setzt das Auto an eine neue Stelle (z. B. Start auf der Straße).
## Mit as_spawn = true landet es auch dort, falls es einmal aus der Welt fällt.
func teleport(new_transform: Transform3D, as_spawn: bool = false) -> void:
	if as_spawn:
		_spawn_transform = new_transform
	_place_car(new_transform)


func _place_car(new_transform: Transform3D) -> void:
	global_transform = new_transform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_steer_input = 0.0
	# Sonst würde die Physik-Interpolation das Auto sichtbar zum neuen Ort gleiten lassen
	reset_physics_interpolation()
