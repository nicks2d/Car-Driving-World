class_name DebugTools
extends Node
## Test-Werkzeuge, die man über Startargumente einschaltet (alles nach "--").
## Beispiele (im Terminal, im Projektordner):
##   /Applications/Godot.app/Contents/MacOS/Godot --path . -- --shot=abend --time=19 --wait=5
##   /Applications/Godot.app/Contents/MacOS/Godot --path . -- --bench=30
##
## --shot=NAME    nach dem Laden screenshots/NAME.png speichern und beenden
## --pos=X,Z      Auto in der Nähe dieser Stelle starten
## --heading=G    Blickrichtung des Autos in Grad (0 = Richtung +Z)
## --time=H       Tageszeit in Stunden, z. B. 18.5
## --wait=S       so viele Sekunden warten, nachdem alles geladen ist (Standard 3)
## --fly=H        Kamera H Meter über das Auto setzen (Überblicks-Bild)
## --pitch=G      Neigung dieser Überblicks-Kamera in Grad (Standard -10)
## --bench=S      S Sekunden lang fahren und dann FPS-Werte ausgeben

@export var camera: Camera3D

var has_start_position: bool = false
var start_position: Vector2 = Vector2.ZERO
var start_heading: float = 0.0
## Tageszeit aus den Argumenten (negativ = nicht angegeben)
var time_of_day: float = -1.0

var _shot_name: String = ""
var _wait: float = 3.0
var _fly_height: float = 0.0
var _pitch: float = -10.0
var _bench_seconds: float = 0.0
var _game: Node3D
var _state: String = "idle"
var _timer: float = 0.0
var _frame_times: PackedFloat32Array = PackedFloat32Array()
var _gpu_times: PackedFloat32Array = PackedFloat32Array()
var _cpu_times: PackedFloat32Array = PackedFloat32Array()
var _load_start_msec: int = 0


func _ready() -> void:
	_load_start_msec = Time.get_ticks_msec()
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		var value := parts[1] if parts.size() > 1 else ""
		match parts[0]:
			"shot":
				_shot_name = value
			"pos":
				var xz := value.split(",")
				start_position = Vector2(float(xz[0]), float(xz[1]))
				has_start_position = true
			"heading":
				start_heading = float(value)
			"time":
				time_of_day = float(value)
			"wait":
				_wait = float(value)
			"fly":
				_fly_height = float(value)
			"pitch":
				_pitch = float(value)
			"bench":
				_bench_seconds = float(value)


## Das Spiel meldet: Gelände rund ums Auto ist da
func on_world_ready(game: Node3D) -> void:
	_game = game
	print("Welt geladen nach %.1f s" % ((Time.get_ticks_msec() - _load_start_msec) / 1000.0))
	if _fly_height > 0.0:
		_place_fly_camera()
	if _shot_name != "":
		_state = "wait_for_terrain"
	elif _bench_seconds > 0.0:
		# Ohne V-Sync, damit man sieht, wie viel Luft nach oben ist
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		# Falls das System trotzdem bei 60 FPS bremst: echte Rechenzeit pro Bild messen
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
		_game.car.freeze = true
		_state = "bench"
		_timer = 0.0


func _process(delta: float) -> void:
	match _state:
		"wait_for_terrain":
			# Erst warten, bis alle Kacheln ihre endgültige Detailstufe haben
			if _game.terrain.pending_count() == 0:
				_state = "wait_extra"
				_timer = _wait
		"wait_extra":
			_timer -= delta
			if _fly_height > 0.0:
				_place_fly_camera()
			if _timer <= 0.0:
				_state = "done"
				_take_screenshot()
		"bench":
			_timer += delta
			_frame_times.append(delta)
			if delta > 0.025:
				print("Langsames Bild bei %.1f s: %.0f ms (Kacheln in Arbeit: %d)" % [_timer, delta * 1000.0, _game.terrain.pending_count()])
			var viewport_rid := get_viewport().get_viewport_rid()
			_gpu_times.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid))
			_cpu_times.append(RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid)
				+ Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
				+ Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
			if _timer >= _bench_seconds:
				_state = "done"
				_print_bench()
				get_tree().quit()


func _physics_process(delta: float) -> void:
	if _state != "bench":
		return
	# Benchmark: Auto gleitet mit 160 km/h über das Gelände, damit ständig nachgeladen wird
	var car: VehicleBody3D = _game.car
	var forward := Vector3(sin(deg_to_rad(start_heading)), 0.0, cos(deg_to_rad(start_heading)))
	var next := car.global_position + forward * 44.0 * delta
	next.y = _game.ground_height(next.x, next.z) + 1.0
	car.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(start_heading)), next)


func _place_fly_camera() -> void:
	var car: VehicleBody3D = _game.car
	camera.set_physics_process(false)
	var yaw := deg_to_rad(start_heading)
	var eye := car.global_position + Vector3.UP * _fly_height
	camera.global_transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(_pitch), yaw + PI, 0.0)), eye)
	camera.reset_physics_interpolation()


func _take_screenshot() -> void:
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://screenshots")
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder.path_join(_shot_name + ".png")
	var image := get_viewport().get_texture().get_image()
	image.save_png(path)
	print("Screenshot gespeichert: ", path)
	get_tree().quit()


func _print_bench() -> void:
	var sorted := _frame_times.duplicate()
	sorted.sort()
	var total := 0.0
	for t in sorted:
		total += t
	var count := sorted.size()
	var worst := sorted[count - 1]
	var p99 := sorted[int(count * 0.99)]
	print("BENCH frames=%d fps_avg=%.1f fps_1pct_low=%.1f worst_frame_ms=%.1f" % [
		count, count / total, 1.0 / p99, worst * 1000.0])
	# Rechenzeit pro Bild: unter 16,7 ms reicht es für 60 FPS
	print("BENCH gpu_ms avg=%.2f p99=%.2f | cpu_ms avg=%.2f p99=%.2f" % [
		_average(_gpu_times), _percentile(_gpu_times, 0.99), _average(_cpu_times), _percentile(_cpu_times, 0.99)])
	print("BENCH render_size=%s screen_scale=%.1f" % [get_viewport().get_texture().get_size(), DisplayServer.screen_get_scale()])


func _average(values: PackedFloat32Array) -> float:
	var total := 0.0
	for v in values:
		total += v
	return total / maxi(values.size(), 1)


func _percentile(values: PackedFloat32Array, p: float) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[int((sorted.size() - 1) * p)]
