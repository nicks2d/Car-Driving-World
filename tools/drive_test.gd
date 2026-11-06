extends SceneTree
## Messfahrt auf einer flachen Ebene je Auto: 0–100 und 0–200 km/h (Vollgas aus dem Stand),
## Spitze (Vollgas, bis das Tempo 3 s lang kaum noch steigt, höchstens 70 s) und Bremsweg
## 100–0 km/h (Vollbremsung). Das Fahrverhalten in Kurven misst tools/grip_test.gd.
## Aufruf: Godot --path . -s res://tools/drive_test.gd -- [--cars=m4csl,sl65,c63]

var cars: Array = ["m2", "e30", "e92", "f90", "g90", "m4csl", "sl65", "c63"]
var car: Car
var car_index := -1
var phase := ""
var t := 0.0
var t100 := -1.0
var t200 := -1.0
var top := 0.0
var best_time := 0.0
var brake_start := Vector3.ZERO


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--cars="):
			cars = Array(arg.trim_prefix("--cars=").split(","))
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30000, 2, 30000)
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
	car.position = Vector3(0, 0.8, -12000)
	root.add_child(car)
	phase = "settle"
	t = 0.0
	t100 = -1.0
	t200 = -1.0
	top = 0.0
	best_time = 0.0


func _release() -> void:
	for action in ["accelerate", "brake", "steer_left", "steer_right", "handbrake"]:
		Input.action_release(action)


func _physics_process(delta: float) -> bool:
	if car == null or not car.is_inside_tree():
		return false
	t += delta
	var kmh := car.linear_velocity.length() * 3.6
	match phase:
		"settle":
			if t > 1.0:
				phase = "launch"
				t = 0.0
				Input.action_press("accelerate", 1.0)
		"launch":
			if t100 < 0.0 and kmh >= 100.0:
				t100 = t
			if t200 < 0.0 and kmh >= 200.0:
				t200 = t
			if kmh > top + 0.5:
				top = kmh
				best_time = t
			# Spitze erreicht: 3 s ohne nennenswerten Zuwachs (oder Zeit um)
			if (t - best_time > 3.0 and t > 10.0) or t > 70.0:
				_release()
				phase = "slow"
				t = 0.0
				Input.action_press("brake", 1.0)
		"slow":
			if kmh < 95.0:
				_release()
				Input.action_press("accelerate", 1.0)
				phase = "to100"
		"to100":
			if kmh >= 100.0:
				_release()
				Input.action_press("brake", 1.0)
				brake_start = car.global_position
				phase = "brake"
		"brake":
			if kmh < 0.5:
				var distance := brake_start.distance_to(car.global_position)
				print("%s: 0–100 %.2f s, 0–200 %s, Spitze %.0f km/h, Bremsweg 100–0 %.1f m" % [cars[car_index], t100,
					("%.1f s" % t200) if t200 > 0.0 else "—", top, distance])
				_release()
				_next_car()
	return false
