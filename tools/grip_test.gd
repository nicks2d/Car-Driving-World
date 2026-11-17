extends SceneTree
## Messwerkzeug für das Fahrverhalten: jedes Auto fährt auf einer flachen Ebene drei Tests.
##   Kurvengrenze: 80 km/h, gleichmäßiges Gas (0,3), Lenkung in 5 s langsam bis Anschlag.
##     Gemessen: größte Querbeschleunigung (g), bevor das Auto mehr als 10° schiebt, und bei
##     welcher Querbeschleunigung das Heck kommt (Schwimmwinkel über 5°).
##   Power-Drift: 40 km/h im 2. Gang, Lenkung halb, dann 2 s Vollgas. Größter Schwimmwinkel.
##   Handbremse: 70 km/h, Lenkung 0,7, 0,6 s Handbremse, dann 1,5 s Gas 0,6. Größter Winkel.
##   Schnelle Kurve: 130 km/h, Gas 0,5, Lenkung in 3 s bis Anschlag. Wie Kurvengrenze.
##   Ausweichen: 120 km/h, 0,6 s voll links, 0,6 s voll rechts (wie mit der Tastatur), dann
##     geradeaus. Größter Schwimmwinkel (wie leicht das Auto dabei ausbricht).
##   Vollgas in der Kurve: 100 km/h, Lenkung 0,4, nach 1,5 s Vollgas. Größter Schwimmwinkel.
## Aufruf: Godot --path . -s res://tools/grip_test.gd -- [--cars=m2,e30] [--grip=komfort|sport|drift]
##   [--wet] (Nässe) [--snow] (Schnee) [--2wd] (2WD-Modus der M5) [--trace] (Verlauf des Power-Drifts)

var cars: Array = ["m2", "e30", "e92", "f90", "g90"]
var grip_level: String = ""
## --2wd: 2WD-Modus (Heckantrieb, Stabilitätshilfe aus) bei Autos mit two_wd_switch
var two_wd: bool = false
## --trace: Verlauf des Power-Drifts ausgeben
var trace: bool = false
var surface_grip: float = 1.0
var car: Car
var car_index := -1
var test := ""
var phase := ""
var t := 0.0
var results: Dictionary = {}
var max_g := 0.0
var rear_g := -1.0
var max_slip := 0.0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--cars="):
			cars = Array(arg.trim_prefix("--cars=").split(","))
		elif arg.begins_with("--grip="):
			grip_level = arg.trim_prefix("--grip=")
		elif arg == "--wet":
			surface_grip = 0.7
		elif arg == "--snow":
			surface_grip = 0.5
		elif arg == "--2wd":
			two_wd = true
		elif arg == "--trace":
			trace = true
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20000, 2, 20000)
	shape.shape = box
	shape.position.y = -1.0
	ground.add_child(shape)
	root.add_child(ground)
	_next_car()


func _next_car() -> void:
	if car:
		car.queue_free()
	car_index += 1
	if car_index >= cars.size():
		quit()
		return
	car = load("res://scenes/car.tscn").instantiate()
	car.set("profile", load("res://cars/%s.tres" % cars[car_index]))
	car.position = Vector3(0, 0.8, 0)
	root.add_child(car)
	if grip_level != "" and car.has_method("set_grip_level"):
		car.call("set_grip_level", grip_level)
	car.grip_factor = surface_grip
	_start("kurve")


func _start(name: String) -> void:
	# Hier statt beim Anlegen: Beim ersten Auto läuft dessen _ready (setzt 2WD zurück) erst später
	car.two_wheel_drive = two_wd and car.profile.two_wd_switch
	test = name
	phase = "anfahren"
	t = 0.0
	max_g = 0.0
	rear_g = -1.0
	max_slip = 0.0
	_release_all()
	car.teleport(Transform3D(Basis.IDENTITY, Vector3(0, 0.8, 0)))
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO


func _release_all() -> void:
	for action in ["accelerate", "brake", "steer_left", "steer_right", "handbrake"]:
		Input.action_release(action)


## Winkel zwischen Fahrtrichtung und Blickrichtung (Schwimmwinkel)
func _slip() -> float:
	var v := car.linear_velocity
	v.y = 0.0
	if v.length() < 3.0:
		return 0.0
	var f := car.global_basis.z
	f.y = 0.0
	return rad_to_deg(f.normalized().angle_to(v.normalized()))


func _physics_process(delta: float) -> bool:
	if car == null or not car.is_inside_tree():
		return false
	t += delta
	var kmh := car.linear_velocity.length() * 3.6
	var lateral_g := absf(car.angular_velocity.y) * car.linear_velocity.length() / 9.81
	match test:
		"kurve":
			if phase == "anfahren":
				Input.action_press("accelerate", 0.8)
				if kmh > 80.0:
					phase = "kurve"
					t = 0.0
					Input.action_press("accelerate", 0.3)
			elif phase == "kurve":
				Input.action_press("steer_left", clampf(t / 5.0, 0.0, 1.0))
				var slip := _slip()
				if slip < 10.0:
					max_g = maxf(max_g, lateral_g)
				if rear_g < 0.0 and slip > 5.0:
					rear_g = lateral_g
				if t > 6.0:
					results["kurve"] = "max. %.2f g, Heck kommt %s" % [max_g,
						("bei %.2f g" % rear_g) if rear_g >= 0.0 else "nicht"]
					_start("power")
		"power":
			if phase == "anfahren":
				Input.action_press("accelerate", 0.5)
				if kmh > 40.0:
					phase = "lenken"
					t = 0.0
					Input.action_press("accelerate", 0.2)
					Input.action_press("steer_left", 0.5)
			elif phase == "lenken" and t > 1.0:
				phase = "vollgas"
				t = 0.0
				Input.action_press("accelerate", 1.0)
			elif phase == "vollgas":
				max_slip = maxf(max_slip, _slip())
				if trace and fmod(t, 0.25) < delta:
					print("  %s t=%.2f %.0f km/h Gang %d Gas %.2f Winkel %.0f° 2WD %s" % [car.profile.id, t, kmh, car.gear,
						car.throttle_input, _slip(), car.two_wheel_drive])
				if t > 2.0:
					results["power"] = "Schwimmwinkel max. %.0f°" % max_slip
					_start("handbremse")
		"handbremse":
			if phase == "anfahren":
				Input.action_press("accelerate", 0.8)
				if kmh > 70.0:
					phase = "ziehen"
					t = 0.0
					Input.action_release("accelerate")
					Input.action_press("steer_left", 0.7)
					Input.action_press("handbrake")
			elif phase == "ziehen":
				max_slip = maxf(max_slip, _slip())
				if t > 0.6:
					phase = "gas"
					t = 0.0
					Input.action_release("handbrake")
					Input.action_press("accelerate", 0.6)
			elif phase == "gas":
				max_slip = maxf(max_slip, _slip())
				if t > 1.5:
					results["handbremse"] = "max. %.0f°, am Ende %.0f° bei %.0f km/h" % [max_slip, _slip(), kmh]
					_start("schnell")
		"schnell":
			if phase == "anfahren":
				Input.action_press("accelerate", 1.0)
				if kmh > 130.0:
					phase = "kurve"
					t = 0.0
					Input.action_press("accelerate", 0.5)
			elif phase == "kurve":
				Input.action_press("steer_left", clampf(t / 3.0, 0.0, 1.0))
				var slip := _slip()
				if slip < 10.0:
					max_g = maxf(max_g, lateral_g)
				if rear_g < 0.0 and slip > 5.0:
					rear_g = lateral_g
				max_slip = maxf(max_slip, slip)
				if t > 4.0:
					results["schnell"] = "max. %.2f g, Heck kommt %s, Winkel max. %.0f°" % [max_g,
						("bei %.2f g" % rear_g) if rear_g >= 0.0 else "nicht", max_slip]
					_start("ausweichen")
		"ausweichen":
			if phase == "anfahren":
				Input.action_press("accelerate", 1.0)
				if kmh > 120.0:
					phase = "links"
					t = 0.0
					Input.action_press("accelerate", 0.4)
					Input.action_press("steer_left", 1.0)
			else:
				max_slip = maxf(max_slip, _slip())
				if phase == "links" and t > 0.6:
					phase = "rechts"
					t = 0.0
					Input.action_release("steer_left")
					Input.action_press("steer_right", 1.0)
				elif phase == "rechts" and t > 0.6:
					phase = "gerade"
					t = 0.0
					Input.action_release("steer_right")
				elif phase == "gerade" and t > 2.0:
					results["ausweichen"] = "max. %.0f°" % max_slip
					_start("vollgas")
		"vollgas":
			if phase == "anfahren":
				Input.action_press("accelerate", 0.9)
				if kmh > 100.0:
					phase = "kurve"
					t = 0.0
					Input.action_press("accelerate", 0.35)
					Input.action_press("steer_left", 0.4)
			elif phase == "kurve" and t > 1.5:
				phase = "gas"
				t = 0.0
				Input.action_press("accelerate", 1.0)
			elif phase == "gas":
				max_slip = maxf(max_slip, _slip())
				if t > 2.0:
					results["vollgas"] = "max. %.0f°" % max_slip
					print("%s%s: Kurve 80 %s | schnell 130 %s | Ausweichen %s | Vollgas in Kurve %s | Power-Drift %s | Handbremse %s" % [
						cars[car_index], (" (%s)" % grip_level) if grip_level != "" else "", results["kurve"],
						results["schnell"], results["ausweichen"], results["vollgas"], results["power"], results["handbremse"]])
					_release_all()
					_next_car()
	return false
