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
## --lookat=X,Z   Überblicks-Kamera schaut auf diesen Punkt (statt in Fahrtrichtung)
## --carview=G    Kamera neben dem Auto, Blick aufs Auto (0 = von vorne, 90 = von links,
##                180 = von hinten), z. B. um das Automodell anzuschauen
## --steer=left   beim Screenshot nach links (oder right) lenken, um die Vorderräder zu prüfen
## --target=X,Z   vor dem Foto ein Navi-Ziel setzen (Route und Hinweis im HUD prüfen)
## --photo        Foto im Fotomodus machen (mit Bedienfeld), --filter=N wählt den Filter (0–3)
## --map          Foto mit geöffneter großer Karte
## --flames       vor dem Foto knallt es ständig im Auspuff (Flammen an den Endrohren prüfen)
## --car=ID       mit diesem Auto starten (Profil cars/ID.tres, z. B. e30, e92, f90, g90)
## --bench=S      S Sekunden lang per Autopilot die Straße entlangfahren, dann FPS-Werte ausgeben
## --volfog       volumetrischen Nebel einschalten
## --benchshot=S  während des Benchmarks nach S Sekunden ein Bild speichern (bench_S.png)
## --highway     auf der nächsten Autobahn starten (statt auf der nächsten Straße); mit --bench
##               fährt der Autopilot dort Vollgas (bis 360 km/h)
## --nohud       HUD ausblenden (z. B. um zu messen, was es kostet)
## --hide=A,B    einzelne HUD-Teile ausblenden (Namen wie in main.tscn, z. B. Minimap)
## --nowait      Foto machen, ohne auf die Gelände-Kacheln zu warten (nur --wait Sekunden)
## --jump=X,Z    nach dem Laden weit an diese Stelle springen (wie ein Teleport), dann Foto
## --weather=ID   Wetter: clear, cloudy, rain, storm, fog, snow (Tests sonst immer klar)
## --season=ID    Jahreszeit: spring, summer, autumn, winter (Tests sonst immer Sommer)

@export var camera: Camera3D

var has_start_position: bool = false
var start_position: Vector2 = Vector2.ZERO
var start_heading: float = 0.0
## Tageszeit aus den Argumenten (negativ = nicht angegeben)
var time_of_day: float = -1.0
## Volumetrischer Nebel per Argument eingeschaltet?
var volumetric_fog: bool = false

var _shot_name: String = ""
var _no_wait: bool = false
var _no_hud: bool = false
## Auf der Autobahn starten?
var on_highway: bool = false
var _hide: PackedStringArray = PackedStringArray()
var _jump_to: Vector2 = Vector2.ZERO
var _has_jump: bool = false
var _wait: float = 3.0
var _fly_height: float = 0.0
var _pitch: float = -10.0
var _look_at: Vector2 = Vector2.ZERO
var _has_look_at: bool = false
var _car_view: float = -1.0
var _steer: String = ""
var _photo: bool = false
var _open_map: bool = false
var _flames: bool = false
var _photo_filter: int = 0
var _target: Vector2 = Vector2.ZERO
var _has_target: bool = false
## Auto aus den Argumenten (leer = nicht angegeben)
var car_id: String = ""
## Wetter und Jahreszeit aus den Argumenten (leer = klar bzw. Sommer)
var weather_id: String = ""
var season_id: String = ""
var _bench_seconds: float = 0.0
var _game: Node3D
var _state: String = "idle"
var _timer: float = 0.0
var _frame_times: PackedFloat32Array = PackedFloat32Array()
var _gpu_times: PackedFloat32Array = PackedFloat32Array()
var _cpu_times: PackedFloat32Array = PackedFloat32Array()
var _process_times: PackedFloat32Array = PackedFloat32Array()
var _physics_times: PackedFloat32Array = PackedFloat32Array()
var _load_start_msec: int = 0
var _route: PackedVector3Array = PackedVector3Array()
var _route_index: int = 0
var _distance_driven: float = 0.0
var _max_off_road: float = 0.0
var _top_speed: float = 0.0
var _lowest_up: float = 1.0
var _last_position: Vector3 = Vector3.ZERO
var _log_timer: float = 0.0
var _bench_shot_time: float = -1.0
var _stuck_time: float = 0.0
var _reverse_time: float = 0.0


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
			"lookat":
				var xz := value.split(",")
				_look_at = Vector2(float(xz[0]), float(xz[1]))
				_has_look_at = true
			"carview":
				_car_view = float(value)
			"steer":
				_steer = value
			"photo":
				_photo = true
			"map":
				_open_map = true
			"flames":
				_flames = true
			"filter":
				_photo_filter = int(value)
			"target":
				var target_xz := value.split(",")
				_target = Vector2(float(target_xz[0]), float(target_xz[1]))
				_has_target = true
			"car":
				car_id = value
			"bench":
				_bench_seconds = float(value)
			"volfog":
				volumetric_fog = true
			"benchshot":
				_bench_shot_time = float(value)
			"nowait":
				_no_wait = true
			"nohud":
				_no_hud = true
			"highway":
				on_highway = true
			"hide":
				_hide = value.split(",")
			"jump":
				var xz := value.split(",")
				_jump_to = Vector2(float(xz[0]), float(xz[1]))
				_has_jump = true
			"weather":
				weather_id = value
			"season":
				season_id = value


## Läuft ein Test (Screenshot, Benchmark, festes Auto)? Dann keine Garage beim Start.
func is_active() -> bool:
	return _shot_name != "" or _bench_seconds > 0.0 or car_id != "" or weather_id != "" or season_id != ""


## Das Spiel meldet: Gelände rund ums Auto ist da
func on_world_ready(game: Node3D) -> void:
	_game = game
	print("Welt geladen nach %.1f s" % ((Time.get_ticks_msec() - _load_start_msec) / 1000.0))
	if _fly_height > 0.0:
		_place_fly_camera()
	if _car_view >= 0.0:
		_place_car_view_camera()
	if _steer != "":
		Input.action_press("steer_left" if _steer == "left" else "steer_right")
	if _no_hud and game.has_node("HUD"):
		game.get_node("HUD").visible = false
	for part in _hide:
		if game.has_node("HUD/" + part):
			game.get_node("HUD/" + part).visible = false
	# Bei Fotos bleibt das Auto stehen (sonst rollt es oder Tastendrücke anderer Fenster landen hier)
	if _shot_name != "" and _bench_seconds <= 0.0 and _game.car is Car:
		(_game.car as Car).throttle_enabled = false
	if _has_jump:
		_has_jump = false
		game.jump_to(_jump_to)
		_state = "wait_after_jump"
	elif _shot_name != "":
		_state = "wait_extra" if _no_wait else "wait_for_terrain"
		_timer = _wait
		if _no_wait:
			_prepare_shot()
	elif _bench_seconds > 0.0:
		# Ohne V-Sync, damit man sieht, wie viel Luft nach oben ist
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		# Falls das System trotzdem bei 60 FPS bremst: echte Rechenzeit pro Bild messen
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
		_state = "bench"
		_timer = 0.0
		_extend_route()
		_last_position = _game.car.global_position


func _process(delta: float) -> void:
	match _state:
		"wait_after_jump":
			# Warten, bis das Spiel nach dem Sprung wieder bereit ist
			if _game.world_is_ready:
				_state = "wait_extra" if _no_wait else "wait_for_terrain"
				_timer = _wait
				if _fly_height > 0.0:
					_place_fly_camera()
		"wait_for_terrain":
			# Erst warten, bis alle Kacheln ihre endgültige Detailstufe haben
			if _game.terrain.pending_count() == 0:
				_state = "wait_extra"
				_timer = _wait
				_prepare_shot()
		"wait_extra":
			_timer -= delta
			# Knalle im Auspuff auslösen (Flammen prüfen), etwa alle 50 ms
			if _flames and fmod(_timer, 0.05) < delta:
				_game.car.get_node("EngineSound").popped.emit(1.0)
			if _fly_height > 0.0:
				_place_fly_camera()
			if _car_view >= 0.0:
				_place_car_view_camera()
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
			_process_times.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
			_physics_times.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
			if _bench_shot_time > 0.0 and _timer >= _bench_shot_time:
				_bench_shot_time = -1.0
				_save_image("bench_%d" % int(_timer))
			if _timer >= _bench_seconds:
				_state = "done"
				_print_bench()
				get_tree().quit()


func _physics_process(_delta: float) -> void:
	if _state != "bench":
		return
	_drive_autopilot()


# ---------------------------------------------------------------------------
# Autopilot: fährt die Straße entlang (benutzt dieselben Tasten wie ein Spieler)
# ---------------------------------------------------------------------------

func _extend_route() -> void:
	var car: VehicleBody3D = _game.car
	_route = _game.roads.route_from(car.global_position, car.global_basis.z, 2500.0)
	_route_index = 0


func _drive_autopilot() -> void:
	var car: VehicleBody3D = _game.car
	if _route.size() < 10:
		_extend_route()
		return
	var here := car.global_position
	# Nächsten Punkt der Route suchen (nur ein kurzes Stück vorwärts, sonst springt er
	# in einer Kehre auf den nächsten Ast der Straße und kürzt quer über den Hang ab)
	var best_distance := INF
	for i in range(_route_index, mini(_route_index + 10, _route.size())):
		var d := Vector2(_route[i].x - here.x, _route[i].z - here.z).length()
		if d < best_distance:
			best_distance = d
			_route_index = i
	if best_distance > 8.0 and best_distance > _max_off_road + 1.0:
		print("Autopilot weit neben der Straße: %.1f m bei %s, %.0f km/h, Driftwinkel %.0f Grad" % [
			best_distance, here.round(), car.linear_velocity.length() * 3.6, car.get("drift_angle")])
	_max_off_road = maxf(_max_off_road, best_distance)
	_distance_driven += Vector2(here.x - _last_position.x, here.z - _last_position.z).length()
	_last_position = here
	_lowest_up = minf(_lowest_up, car.global_basis.y.y)
	_top_speed = maxf(_top_speed, car.linear_velocity.length())
	_log_timer += get_physics_process_delta_time()
	if _log_timer >= 3.0:
		_log_timer = 0.0
		print("Autopilot: %.0f km/h, %.1f m neben der Mitte, Routenpunkt %d/%d, Position %s" % [
			car.linear_velocity.length() * 3.6, best_distance, _route_index, _route.size(), here.round()])
	if _route.size() - _route_index < (200 if on_highway else 60):
		_extend_route()
		return

	var speed := car.linear_velocity.length()
	# Festgefahren? Dann kurz zurücksetzen, wie ein Mensch es tun würde
	_stuck_time = _stuck_time + get_physics_process_delta_time() if speed < 0.5 else 0.0
	if _stuck_time > 2.0:
		_reverse_time = 2.5
		_stuck_time = 0.0
	if _reverse_time > 0.0:
		_reverse_time -= get_physics_process_delta_time()
		Input.action_release("accelerate")
		Input.action_release("steer_left")
		Input.action_release("steer_right")
		Input.action_press("brake")
		return

	# Lenken: auf einen Punkt etwas voraus zielen (je schneller, desto weiter voraus)
	var look_ahead := maxi(int((6.0 + speed * 0.45) / RoadSegment.POINT_SPACING), 2)
	var aim := _route[mini(_route_index + look_ahead, _route.size() - 1)]
	var local := car.global_transform.affine_inverse() * aim
	var angle := atan2(local.x, local.z)  # positiv = Ziel liegt links
	if angle > 0.0:
		Input.action_press("steer_left", clampf(angle * 4.0, 0.0, 1.0))
		Input.action_release("steer_right")
	else:
		Input.action_press("steer_right", clampf(-angle * 4.0, 0.0, 1.0))
		Input.action_release("steer_left")

	# Tempo: Für jede Kurve der nächsten 120 m ausrechnen, wie schnell man sie fahren kann
	# (Querbeschleunigung max. 4 m/s²) und rechtzeitig bremsen (max. 4 m/s²).
	# Auf der Autobahn: Vollgas, Kurven mit 9 m/s² und 700 m Vorausschau
	var target_speed := 100.0 if on_highway else 26.0
	var lateral := 9.0 if on_highway else 4.0
	var horizon := 175 if on_highway else 30
	for i in range(_route_index + 3, mini(_route_index + horizon, _route.size() - 3)):
		var d1 := Vector2(_route[i].x - _route[i - 3].x, _route[i].z - _route[i - 3].z)
		var d2 := Vector2(_route[i + 3].x - _route[i].x, _route[i + 3].z - _route[i].z)
		var angle_change := absf(d1.angle_to(d2))
		if angle_change < 0.01:
			continue
		var radius := 3.0 * RoadSegment.POINT_SPACING / angle_change
		var curve_speed := maxf(sqrt(lateral * radius), 4.0)
		var distance_to_curve := (i - _route_index) * RoadSegment.POINT_SPACING
		target_speed = minf(target_speed, sqrt(curve_speed * curve_speed + 2.0 * 4.0 * distance_to_curve))
	if speed < target_speed - 1.0:
		Input.action_press("accelerate")
		Input.action_release("brake")
	elif speed > target_speed + 2.0:
		Input.action_release("accelerate")
		Input.action_press("brake")
	else:
		Input.action_release("accelerate")
		Input.action_release("brake")


## Kurz vor dem Foto: Navi-Ziel setzen, Fotomodus öffnen (wenn gewünscht)
func _prepare_shot() -> void:
	if _has_target:
		(_game.get_node("Navigation") as Navigation).set_target(Vector3(_target.x, 0.0, _target.y))
	# Fotomodus und große Karte halten das Spiel an, das Foto muss trotzdem ausgelöst werden
	if _photo or _open_map:
		process_mode = Node.PROCESS_MODE_ALWAYS
	if _open_map:
		(_game.get_node("BigMap") as BigMap).open()
	if _photo:
		var photo := _game.get_node("PhotoMode") as PhotoMode
		photo.open()
		photo.set_filter(_photo_filter)


## Überblicks-Kamera: hoch über und hinter dem Auto, Blick in Fahrtrichtung
func _place_fly_camera() -> void:
	var car: VehicleBody3D = _game.car
	camera.set_physics_process(false)
	var forward := car.global_basis.z
	if _has_look_at:
		forward = Vector3(_look_at.x, 0.0, _look_at.y) - car.global_position
	forward.y = 0.0
	forward = forward.normalized()
	var eye := car.global_position + Vector3.UP * _fly_height - forward * _fly_height * 0.8
	var yaw := atan2(forward.x, forward.z)
	camera.global_transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(_pitch), yaw + PI, 0.0)), eye)
	camera.reset_physics_interpolation()


## Kamera 5,5 m neben dem Auto auf Augenhöhe, Blick auf die Automitte
func _place_car_view_camera() -> void:
	var car: VehicleBody3D = _game.car
	camera.set_physics_process(false)
	var forward := car.global_basis.z
	forward.y = 0.0
	var direction := forward.normalized().rotated(Vector3.UP, deg_to_rad(_car_view))
	var target := car.global_position + Vector3.UP * 0.3
	var eye := target + direction * 5.5 + Vector3.UP * 0.9
	camera.global_transform = Transform3D(Basis.looking_at(target - eye), eye)
	camera.reset_physics_interpolation()


func _take_screenshot() -> void:
	await _save_image(_shot_name)
	get_tree().quit()


func _save_image(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://screenshots")
	DirAccess.make_dir_recursive_absolute(folder)
	# .gdignore: Godot soll die Bilder nicht als Spiel-Assets importieren
	if not FileAccess.file_exists(folder.path_join(".gdignore")):
		FileAccess.open(folder.path_join(".gdignore"), FileAccess.WRITE).close()
	var path := folder.path_join(file_name + ".png")
	var image := get_viewport().get_texture().get_image()
	image.save_png(path)
	print("Screenshot gespeichert: ", path)


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
	# Aufgeteilt: Skripte (_process) und Physik-Schritte (inkl. _physics_process)
	print("BENCH process_ms avg=%.2f | physics_ms avg=%.2f" % [_average(_process_times), _average(_physics_times)])
	# Rechenzeit pro Bild: unter 16,7 ms reicht es für 60 FPS
	print("BENCH gpu_ms avg=%.2f p99=%.2f | cpu_ms avg=%.2f p99=%.2f" % [
		_average(_gpu_times), _percentile(_gpu_times, 0.99), _average(_cpu_times), _percentile(_cpu_times, 0.99)])
	print("BENCH window=%s screen_scale=%.1f" % [DisplayServer.window_get_size(), DisplayServer.screen_get_scale()])
	print("BENCH autopilot: %.0f m gefahren (%.0f km/h im Schnitt, max. %.0f km/h), max. %.1f m neben der Straßenmitte, min. Aufrecht-Wert %.2f" % [
		_distance_driven, _distance_driven / maxf(_timer, 0.1) * 3.6, _top_speed * 3.6, _max_off_road, _lowest_up])


func _average(values: PackedFloat32Array) -> float:
	var total := 0.0
	for v in values:
		total += v
	return total / maxi(values.size(), 1)


func _percentile(values: PackedFloat32Array, p: float) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[int((sorted.size() - 1) * p)]
