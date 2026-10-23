class_name Car
extends VehicleBody3D
## Das Auto des Spielers: ein BMW M2 Competition (F87) mit Heckantrieb.
## Die eigentliche Physik (Federung, Reifen-Grip) rechnet Godots VehicleBody3D.
## Dieses Skript ist Motor, Getriebe und Fahrer-Eingaben: wann wie viel Kraft, Bremse
## und Lenkung anliegt.

## Wird beim Gangwechsel gesendet (für das Schaltgeräusch)
signal gear_changed(new_gear: int)

@export_group("Motor (S55, Reihensechszylinder)")
## Höchstes Drehmoment (Nm), liegt zwischen torque_plateau_start_rpm und ca. 5200 1/min an
@export var max_torque_nm: float = 550.0
## Höchstleistung in Kilowatt (302 kW = 410 PS), ab ca. 5250 1/min
@export var max_power_kw: float = 302.0
@export var idle_rpm: float = 900.0
## Ab dieser Drehzahl liegt das volle Drehmoment an
@export var torque_plateau_start_rpm: float = 2350.0
## Bis hier hält der Motor seine volle Leistung, danach fällt sie bis zum Begrenzer ab
@export var power_end_rpm: float = 7000.0
## Drehzahlbegrenzer
@export var redline_rpm: float = 7600.0
## Anteil der Motorkraft, der an den Rädern ankommt (Getriebe, Differenzial)
@export_range(0.5, 1.0) var drivetrain_efficiency: float = 0.88
## Traktionskontrolle: höchste Antriebskraft am Boden (Newton). Mehr würde die Hinterräder
## nur durchdrehen lassen. Größer = mehr Leistung beim Anfahren, Heck bricht leichter aus.
@export var max_drive_force: float = 11000.0
## Abgeregelte Höchstgeschwindigkeit
@export var top_speed_kmh: float = 250.0
## Höchstgeschwindigkeit rückwärts in km/h
@export var max_reverse_speed_kmh: float = 30.0
## Anteil der Antriebskraft im Rückwärtsgang (0 bis 1)
@export_range(0.0, 1.0) var reverse_force_factor: float = 0.4

@export_group("Getriebe (7-Gang-Doppelkupplung)")
## Übersetzungen der Gänge 1 bis 7
@export var gear_ratios: Array[float] = [4.806, 2.593, 1.701, 1.277, 1.0, 0.844, 0.671]
## Achsübersetzung (Differenzial)
@export var final_drive: float = 3.462
## Bei Vollgas wird bei dieser Drehzahl hochgeschaltet (bei wenig Gas früher)
@export var shift_up_rpm: float = 7200.0
## Bei Vollgas wird unter dieser Drehzahl heruntergeschaltet (bei wenig Gas später)
@export var shift_down_rpm: float = 3200.0
## So lange (Sekunden) liegt beim Schalten keine Kraft an
@export var shift_time: float = 0.12

@export_group("Bremsen")
## Bremswert für S (Godot-Einheit: Bremsimpuls pro Rad und Physik-Schritt;
## 76 bremst den 1575 kg schweren M2 in ca. 34 m von 100 auf 0)
@export var brake_strength: float = 76.0
## Leichtes Bremsen, wenn man vom Gas geht (Motorbremse und Rollwiderstand)
@export var engine_brake_strength: float = 1.5
## Bremswert der Handbremse (wirkt nur auf die Hinterräder)
@export var handbrake_strength: float = 30.0
## Wie viel Grip die Hinterräder mit gezogener Handbremse behalten (0 bis 1)
@export_range(0.0, 1.0) var handbrake_grip: float = 0.6

@export_group("Fahrverhalten")
## So viel Grip (Anteil) verlieren die Hinterräder bei Vollgas in einer schnellen Kurve.
## Dann bricht das Heck aus; Gas weg, und es fängt sich wieder. 0 = nie.
@export_range(0.0, 0.6) var power_oversteer: float = 0.12
## Ab dieser Querbeschleunigung (m/s², 9.81 = 1 g) wirkt das voll
@export var power_oversteer_lateral: float = 7.0
## Fahrhilfe wie der „M Dynamic Mode“: Das Heck darf bis zu diesem Driftwinkel (Grad)
## ausbrechen, darüber nimmt die Elektronik Leistung weg. 0 = ausgeschaltet.
@export_range(0.0, 90.0) var drift_angle_limit: float = 15.0

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

## Wird gerade gebremst? (für die Bremslichter)
var braking: bool = false
## Aktueller Gang: 1 bis 7, -1 = Rückwärtsgang (für Drehzahlmesser und Sound)
var gear: int = 1
## Motordrehzahl in 1/min
var engine_rpm: float = 900.0
## Gaspedal 0 bis 1 (für den Sound)
var throttle_input: float = 0.0
## Driftwinkel in Grad: Winkel zwischen Fahrtrichtung und Blickrichtung des Autos
var drift_angle: float = 0.0

var _steer_input: float = 0.0
var _shift_timer: float = 0.0
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
	var max_angle: float = lerpf(max_steer_angle, high_speed_steer_angle, sqrt(t))
	steering = deg_to_rad(max_angle) * _steer_input


## Drehzahl aus dem Tempo und Gangwahl wie bei einer Automatik
func _update_gearbox(delta: float, forward_speed: float) -> void:
	throttle_input = Input.get_action_strength("accelerate")
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
		var up := lerpf(2800.0, shift_up_rpm, throttle_input)
		var down := lerpf(1300.0, shift_down_rpm, throttle_input)
		if rpm_from_wheels > up and gear < gear_ratios.size():
			_shift_to(gear + 1)
		elif rpm_from_wheels < down and gear > 1:
			# Nur, wenn der kleinere Gang nicht gleich wieder über die Schaltdrehzahl käme
			var lower_rpm := wheel_rpm * gear_ratios[gear - 2] * final_drive
			if lower_rpm < up * 0.9:
				_shift_to(gear - 1)
	# Beim Anfahren schleift die Kupplung: Die Drehzahl hängt dann vom Gas ab, nicht vom Tempo
	var clutch_rpm := idle_rpm + throttle_input * 3300.0
	var target := maxf(rpm_from_wheels, idle_rpm)
	if absi(gear) == 1:
		target = maxf(target, clutch_rpm)
	engine_rpm = move_toward(engine_rpm, minf(target, redline_rpm), 30000.0 * delta)


func _shift_to(new_gear: int) -> void:
	if new_gear == gear:
		return
	gear = new_gear
	_shift_timer = shift_time
	gear_changed.emit(gear)


## Gesamtübersetzung vom Motor bis zum Rad
func _current_ratio() -> float:
	if gear == -1:
		return gear_ratios[0] * final_drive
	return gear_ratios[gear - 1] * final_drive


## Drehmoment des Motors (Nm) bei Vollgas und einer bestimmten Drehzahl
func _torque_at(rpm: float) -> float:
	if rpm < torque_plateau_start_rpm:
		# Unten herum: vom Leerlauf bis zum vollen Drehmoment ansteigend (Turbo baut Druck auf)
		return lerpf(max_torque_nm * 0.6, max_torque_nm, clampf((rpm - idle_rpm) / (torque_plateau_start_rpm - idle_rpm), 0.0, 1.0))
	# Leistung = Drehmoment mal Winkelgeschwindigkeit: oben herum begrenzt die Leistung
	var power_limited := max_power_kw * 1000.0 / (rpm * TAU / 60.0)
	if rpm > power_end_rpm:
		power_limited *= lerpf(1.0, 0.8, clampf((rpm - power_end_rpm) / (redline_rpm - power_end_rpm), 0.0, 1.0))
	return minf(max_torque_nm, power_limited)


## Fahrhilfe: Wie viel Leistung darf bei diesem Driftwinkel noch anliegen (0 bis 1)?
func _drift_control() -> float:
	if drift_angle_limit <= 0.0:
		return 1.0
	# Bis zum Grenzwert volle Leistung, 15° darüber nur noch 20 %
	return clampf(1.0 - (drift_angle - drift_angle_limit) / 15.0 * 0.8, 0.2, 1.0)


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
	if _shift_timer > 0.0 or engine_rpm >= redline_rpm:
		return 0.0
	var force := _torque_at(engine_rpm) * _current_ratio() * drivetrain_efficiency / _rear_left.wheel_radius
	return minf(force, max_drive_force)


func _update_engine_and_brakes(forward_speed: float) -> void:
	var throttle: float = throttle_input
	var brake_input: float = Input.get_action_strength("brake")
	var drive_force: float = 0.0
	var brake_value: float = 0.0
	var speed_kmh := forward_speed * 3.6

	if throttle > 0.0:
		if forward_speed < -0.5:
			# Rollt noch rückwärts: Gas bremst erst einmal ab
			brake_value = brake_strength * throttle
		else:
			drive_force = _drive_force() * throttle
			# Abregelung: kurz vor der Höchstgeschwindigkeit sanft weniger Kraft
			drive_force *= clampf((top_speed_kmh + 1.5 - speed_kmh) / 3.0, 0.0, 1.0)
			drive_force *= _drift_control()
	elif brake_input > 0.0:
		if forward_speed > 0.5:
			# Fährt vorwärts: S bremst
			brake_value = brake_strength * brake_input
		elif -speed_kmh < max_reverse_speed_kmh and gear == -1:
			# Steht (fast): S fährt rückwärts, aber nur bis zum Rückwärts-Tempolimit
			drive_force = -max_drive_force * reverse_force_factor * brake_input
	else:
		# Kein Pedal gedrückt: Auto rollt langsam aus
		brake_value = engine_brake_strength

	# Godot erwartet die Kraft pro Antriebsrad
	engine_force = drive_force / maxi(_traction_wheel_count, 1)
	brake = brake_value
	braking = brake_value > engine_brake_strength


## Grip der Hinterräder: Handbremse und Vollgas in schnellen Kurven lassen das Heck rutschen
func _update_rear_grip() -> void:
	var grip := _rear_grip
	var pulled: bool = Input.is_action_pressed("handbrake")
	if pulled:
		# Mit gezogener Handbremse ist quasi die Kupplung getreten
		engine_force = 0.0
		grip *= handbrake_grip
	# Godots Reifenmodell zählt die Antriebskraft kaum gegen den Seitenhalt. Echte Hinterreifen
	# mit 550 Nm verlieren in der Kurve Seitenhalt, wenn man Gas gibt: das wird hier nachgebildet.
	var lateral := absf(angular_velocity.y) * linear_velocity.length()
	# Quadratisch: Mit wenig Gas bleibt das Heck ruhig, erst viel Gas lässt es rutschen
	var power := clampf(absf(engine_force) * 2.0 / max_drive_force, 0.0, 1.0)
	grip *= 1.0 - power_oversteer * power * power * clampf(lateral / power_oversteer_lateral, 0.0, 1.0)
	for wheel: VehicleWheel3D in [_rear_left, _rear_right]:
		if pulled:
			wheel.brake = handbrake_strength
		wheel.wheel_friction_slip = grip


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
