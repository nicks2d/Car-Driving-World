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
## --garage       Foto mit geöffneter Garage (mit --car=ID ist dieses Auto und seine Marke gewählt)
## --collection=N Garage mit offener Sammlung (0 = Orte, 1 = Aussichtspunkte)
##                Mit --bench öffnen --map und --garage/--collection erst nach der Fahrt
##                (Foto NAME_ende.png bzw. bench_ende.png), z. B. Karte mit Nebel nach der Fahrt.
## --flames       vor dem Foto knallt es ständig im Auspuff (Flammen an den Endrohren prüfen)
## --rainbow      Regenbogen zeigen (tiefe Sonne, z. B. --time=18 --heading=90)
## --cam=X,Z,H    freie Kamera fürs Foto: H Meter über dem Gelände bei X,Z, Blick auf --lookat=X,Z[,H]
##                (Ziel H Meter über dem Gelände, Standard 1), z. B. für Talsperren und Brücken
## --flash        Lichthupe fürs Foto an (Fernlicht hell aufgeblendet)
## --dyno=ID,…    mit --shot: Garage > Prüfstand öffnen und diese Autos nacheinander messen
##                (z. B. --dyno=sl65,m4csl), Foto NAME_lauf.png im ersten Lauf, NAME.png am Ende
## --moon=P       Mondphase fürs Foto (0 = Neumond, 0.25 = zunehmender Halbmond, 0.5 = Vollmond)
## --meteors      Sternschnuppen vor dem Foto auslösen (immer wieder eine neue)
## --lookmoon     freie Kamera (--cam) blickt genau zum Mond
## --splash       Pfützen-Fontäne an den Vorderrädern kurz vor dem Foto
## --windows=S    Fenster öffnen: beim Foto sofort, beim Benchmark nach S Sekunden
## --record=PFAD  mit --bench oder --dyno: den ganzen Ton (Master) als WAV speichern (z. B. zum Vergleich
##                Fenster zu/offen, Ausgabe der Lautstärke pro Sekunde mit einem Python-Skript)
## --signal=left|right|hazard  Blinker bzw. Warnblinker fürs Foto an (leuchtend)
## --aurora       Polarlicht zeigen (Winternacht, z. B. --season=winter --time=23 --heading=180)
## --car=ID       mit diesem Auto starten (Profil cars/ID.tres, z. B. e30, e92, f90, g90)
## --bench=S      S Sekunden lang per Autopilot die Straße entlangfahren, dann FPS-Werte ausgeben
## --volfog       volumetrischen Nebel einschalten
## --benchshot=S  während des Benchmarks nach S Sekunden ein Bild speichern (bench_S.png),
##                mehrere mit Komma (--benchshot=8,16,24)
## --acc         mit --bench: Der Autopilot hält Abstand zum Vordermann (gleiche Regeln wie der
##                Tempomat und die KI) und überholt auf der Autobahn, statt durch den Verkehr zu fahren.
##                Mit --acc=KMH fährt er höchstens so schnell (z. B. --acc=130).
## --signshot=A  Foto vor dem nächsten Verkehrszeichen dieser Art: limit, curve (Kurven-Warnschild),
##                end_limit, end_all, wet (Limit nur bei Nässe), tunnel (80 vor einem Tunnel)
## --race        ein LC 500 fährt 30 m vor dem Spieler los, das Rennen startet sofort (mit --bench
##                fährt der Autopilot mit), Ergebnis in der Ausgabe
## --cruise=KMH,D,V  mit --bench: Der Autopilot lenkt nur, Gas und Bremse macht der echte
##                Tempomat (an, sobald KMH erreicht sind), D Meter voraus fährt ein Lkw mit V km/h;
##                jede Sekunde Tempo, Abstand, Zeitlücke, Beschleunigung, am Ende Zusammenfassung.
##                --gap=0..3 wählt die Abstandsstufe (Standard 2)
## --shotevery=M  während des Benchmarks alle M gefahrenen Meter ein Bild (strecke_M.png), z. B.
##                für Fotos alle 100 m durch einen langen Tunnel
## --exitdrive    mit --bench --highway: Der Autopilot nimmt die nächste Ausfahrt (über den
##                Verzögerungsstreifen), fährt über den Zubringer und auf der anderen Seite
##                wieder auf (Beschleunigungsstreifen)
## --highway     auf der nächsten Autobahn starten (statt auf der nächsten Straße); mit --bench
##               fährt der Autopilot dort Vollgas (bis 360 km/h)
## --nohud       HUD ausblenden (z. B. um zu messen, was es kostet)
## --hide=A,B    einzelne HUD-Teile ausblenden (Namen wie in main.tscn, z. B. Minimap)
## --nowait      Foto machen, ohne auf die Gelände-Kacheln zu warten (nur --wait Sekunden)
## --jump=X,Z    nach dem Laden weit an diese Stelle springen (wie ein Teleport), dann Foto
## --weather=ID   Wetter: clear, cloudy, rain, storm, fog, snow (Tests sonst immer klar)
## --season=ID    Jahreszeit: spring, summer, autumn, winter (Tests sonst immer Sommer)
## --traffic=D    Verkehrsdichte 0 (aus), 0.5 (wenig) oder 1 (normal, Standard)
## --boxcars      Verkehr ohne echte Modelle (nur gebaute Kästchen, zum Vergleichen der Leistung)
## --lineup=M     vor dem Foto von jedem Verkehrs-Typ ein stehendes Auto ab M Metern vor dem
##                Spieler (Standard 18), z. B. mit --fly=6 oder --time=22
## --quality=Q    Grafik-Qualität niedrig, mittel, hoch (Standard) oder ultra
## --full        Randloses Fenster in Bildschirmgröße (so viele Bildpunkte wie im Vollbild). Echtes
##                Vollbild übergeht macOS beim Start oft und bremst es auf 60 FPS (V-Sync lässt
##                sich dort nicht abschalten). Der Benchmark beginnt erst, wenn die Größe stimmt.
## --pause=N      Foto mit Pausemenü: 0 = Hauptseite, 1–5 = Reiter Grafik, Anzeige, Steuerung,
##                Audio, Spiel

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
## Freie Kamera (--cam=X,Z,H): Lage und Höhe über dem Gelände; Ziel-Höhe über dem Gelände (--lookat=X,Z,H)
var _cam := Vector3.ZERO
var _has_cam: bool = false
var _look_height: float = 1.0
var _car_view: float = -1.0
var _steer: String = ""
var _photo: bool = false
var _open_map: bool = false
var _open_garage: bool = false
## Garage mit offener Sammlung (0 = Orte, 1 = Aussichtspunkte), -1 = nicht
var _collection_page: int = -1
## Prüfstand-Test (--dyno=ID,ID,…): diese Autos nacheinander messen, Fotos während des ersten
## Laufs und am Ende mit dem Vergleich
var _dyno_cars: Array[String] = []
var _dyno_shot_taken: bool = false
var _pause_page: int = -1
var _full: bool = false
var _flames: bool = false
## Lichthupe fürs Foto gedrückt halten (--flash)
var _flash: bool = false
## Fenster nach so vielen Sekunden Benchmark öffnen (--windows=S, -1 = nie) und Tonaufnahme
## des ganzen Benchmarks (--record=DATEI.wav)
var _windows_at: float = -1.0
## Pfützen-Fontäne fürs Foto auslösen (--splash)
var _splash: bool = false
## Mondphase fürs Foto (0 = Neumond, 0,5 = Vollmond; -1 = wie gespeichert) und Sternschnuppen
var _moon: float = -1.0
var _meteors: bool = false
var _look_moon: bool = false
var _record_path: String = ""
var _recorder: AudioEffectRecord
var _rainbow: bool = false
var _signal: String = ""
var _aurora: bool = false
var _photo_filter: int = 0
var _target: Vector2 = Vector2.ZERO
var _has_target: bool = false
## Auto aus den Argumenten (leer = nicht angegeben)
var car_id: String = ""
## Wetter und Jahreszeit aus den Argumenten (leer = klar bzw. Sommer)
var weather_id: String = ""
var season_id: String = ""
## Verkehrsdichte aus den Argumenten (negativ = nicht angegeben)
var traffic_density: float = -1.0
## Verkehr nur mit gebauten Kästchen (--boxcars)
var traffic_boxes: bool = false
var _lineup: float = -1.0
## Grafik-Qualität aus den Argumenten (leer = Standard „hoch“)
var quality: String = ""
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
var _tunnel_driven: float = 0.0
var _lowest_up: float = 1.0
var _last_position: Vector3 = Vector3.ZERO
var _log_timer: float = 0.0
var _bench_shots := PackedFloat32Array()
var _shot_every: float = 0.0
## Autopilot mit Abstand und Überholen (--acc): Höchsttempo (km/h, 0 = keins), seitlicher
## Versatz nach links (Meter, zum Überholen) und Ziel dafür
var _race_test: bool = false
var _sign_shot: String = ""
## Kamera-Lage vor dem Schild (wird jedes Bild neu gesetzt, sonst übernimmt die Verfolger-Kamera)
var _sign_camera := Transform3D()
var _has_sign_camera: bool = false
var _acc: bool = false
var _acc_max_kmh: float = 0.0
## Tempomat-Test (--cruise): Wunschtempo, Lkw (Abstand, Tempo), Abstandsstufe, Messwerte
var _cruise_kmh: float = 0.0
var _cruise_leader := Vector2.ZERO
var _cruise_gap: int = 2
var _cruise_log: float = 0.0
var _cruise_min_time_gap: float = INF
var _cruise_max_brake: float = 0.0
var _cruise_warnings: int = 0
var _cruise_last_speed: float = 0.0
var _lane_shift: float = 0.0
var _lane_shift_target: float = 0.0
var _next_distance_shot: float = 0.0
var _exit_drive: bool = false
## Folgt der Autopilot gerade der Route über die Ausfahrt? (Kurven dann wie auf der Landstraße)
var _on_exit_route: bool = false
var _stuck_time: float = 0.0
var _reverse_time: float = 0.0


func _ready() -> void:
	_load_start_msec = Time.get_ticks_msec()
	# Nach dem Einlesen der Argumente (unten) schon während des Ladens ins Vollbild
	_go_full.call_deferred()
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
				if xz.size() >= 3:
					_look_height = float(xz[2])
			"cam":
				var xzh := value.split(",")
				_cam = Vector3(float(xzh[0]), float(xzh[2]) if xzh.size() >= 3 else 2.0, float(xzh[1]))
				_has_cam = true
			"carview":
				_car_view = float(value)
			"steer":
				_steer = value
			"photo":
				_photo = true
			"map":
				_open_map = true
			"garage":
				_open_garage = true
			"collection":
				_collection_page = int(value)
				_open_garage = true
			"pause":
				_pause_page = int(value)
			"full":
				_full = true
			"flames":
				_flames = true
			"flash":
				_flash = true
			"splash":
				_splash = true
			"moon":
				_moon = float(value)
			"meteors":
				_meteors = true
			"lookmoon":
				_look_moon = true
			"dyno":
				for id in value.split(","):
					_dyno_cars.append(id)
				_open_garage = true
			"windows":
				_windows_at = float(value) if value != "" else 0.0
			"record":
				_record_path = value
			"rainbow":
				_rainbow = true
			"signal":
				_signal = value
			"aurora":
				_aurora = true
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
				for part in value.split(","):
					_bench_shots.append(float(part))
			"exitdrive":
				_exit_drive = true
			"shotevery":
				_shot_every = float(value)
			"race":
				_race_test = true
			"signshot":
				_sign_shot = value
			"cruise":
				var cruise_parts := value.split(",")
				_cruise_kmh = float(cruise_parts[0])
				if cruise_parts.size() >= 3:
					_cruise_leader = Vector2(float(cruise_parts[1]), float(cruise_parts[2]))
			"gap":
				_cruise_gap = int(value)
			"acc":
				_acc = true
				_acc_max_kmh = float(value) if value != "" else 0.0
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
			"traffic":
				traffic_density = float(value)
			"boxcars":
				traffic_boxes = true
			"lineup":
				_lineup = float(value) if value != "" else 18.0
			"quality":
				quality = value
			"weather":
				weather_id = value
			"season":
				season_id = value


## Läuft ein Test (Screenshot, Benchmark, festes Auto)? Dann keine Garage beim Start.
## Läuft ein Benchmark (Autopilot)?
func is_benchmark() -> bool:
	return _bench_seconds > 0.0


func is_active() -> bool:
	return _shot_name != "" or _bench_seconds > 0.0 or car_id != "" or weather_id != "" or season_id != "" \
		or quality != "" or traffic_density >= 0.0


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
	if _moon >= 0.0:
		var day_night := game.get_node("DayNight") as DayNight
		day_night.moon_age = _moon * DayNight.MOON_CYCLE
		day_night.refresh()
	if _sign_shot != "":
		_place_sign_camera(game)
	if _windows_at >= 0.0 and _bench_seconds <= 0.0:
		(game.get_node("OpenWindows") as OpenWindows).open = true
		game.car.windows_open = 1.0
	if _cruise_kmh > 0.0 and _cruise_leader.x > 0.0:
		var leader := (game.get_node("Traffic") as Traffic).spawn_leader(_cruise_leader.x, _cruise_leader.y)
		print("Tempomat-Test: Lkw %s, %d m voraus, %d km/h" % ["da" if leader else "keiner", _cruise_leader.x, _cruise_leader.y])
	if _race_test:
		var racer := (game.get_node("Traffic") as Traffic).spawn_racer(30.0)
		var started := racer != null and (game.get_node("Race") as Race).start(racer)
		print("Rennen-Test: Gegner %s, gestartet: %s" % ["da" if racer else "keiner", started])
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
		if _full:
			_state = "wait_full"
			_timer = 0.0
		else:
			_start_bench()


func _go_full() -> void:
	if _full:
		_fill_screen()


func _fill_screen() -> void:
	var screen := DisplayServer.screen_get_size()
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_position(DisplayServer.screen_get_position())
	DisplayServer.window_set_size(screen)


func _start_bench() -> void:
	# Das Umschalten ins Vollbild setzt V-Sync zurück: hier noch einmal ausschalten
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_state = "bench"
	_timer = 0.0
	_extend_route()
	_last_position = _game.car.global_position
	if _record_path != "":
		_recorder = AudioEffectRecord.new()
		AudioServer.add_bus_effect(AudioServer.get_bus_index("Master"), _recorder)
		_recorder.set_recording_active(true)


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
			# Blinker fürs Foto im leuchtenden Takt halten
			if _signal != "":
				_game.car.turn_signal = 1 if _signal == "left" else (-1 if _signal == "right" else 0)
				_game.car.hazard = _signal == "hazard"
				_game.car.get_node("Signals").set("_time", 0.0)
			# Knalle im Auspuff auslösen (Flammen prüfen), etwa alle 50 ms
			if _flames and fmod(_timer, 0.05) < delta:
				_game.car.get_node("EngineSound").popped.emit(1.0)
			if _flash:
				_game.car.flash_time = 0.2
			# Sternschnuppen: immer wieder neue, damit das Foto welche erwischt
			if _meteors and fmod(_timer, 0.4) < delta:
				(_game.get_node("DayNight") as DayNight).spawn_meteor()
			# Fontäne kurz vor dem Foto, damit sie gerade hochspritzt
			if _splash and _timer <= 0.35 and _timer + delta > 0.35:
				(_game.get_node("Puddles") as Puddles).splash(80.0)
			if _fly_height > 0.0:
				_place_fly_camera()
			if _car_view >= 0.0:
				_place_car_view_camera()
			if _has_sign_camera:
				camera.global_transform = _sign_camera
				camera.reset_physics_interpolation()
			if _has_cam:
				_place_free_camera()
			if _timer <= 0.0:
				_state = "done"
				_take_screenshot()
		"bench_end":
			_timer += delta
			if _timer > 1.5:
				_state = "done"
				_save_image("%s_ende" % (_shot_name if _shot_name != "" else "bench"))
				_print_bench()
				await get_tree().create_timer(0.5, true).timeout
				get_tree().quit()
		"dyno":
			# Prüfstand: ein Foto mitten im ersten Lauf, eins am Ende mit allen Kurven
			var dyno := _game.get_node("Dyno") as Dyno
			if not _dyno_shot_taken and dyno.run_time > 5.0:
				_dyno_shot_taken = true
				_save_image("%s_lauf" % _shot_name)
			if dyno.series_done:
				_timer += delta
				if _timer > 1.0:
					_state = "done"
					if _recorder:
						_recorder.set_recording_active(false)
						_recorder.get_recording().save_to_wav(_record_path)
						print("Aufnahme gespeichert: ", _record_path)
					_take_screenshot()
		"wait_full":
			# Fenster schon bildschirmgroß?
			_timer += delta
			if DisplayServer.window_get_size() != DisplayServer.screen_get_size() and fmod(_timer, 1.0) < delta:
				_fill_screen()
			if DisplayServer.window_get_size() == DisplayServer.screen_get_size() and _timer > 1.0 or _timer > 8.0:
				_start_bench()
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
			if _shot_every > 0.0 and _distance_driven >= _next_distance_shot:
				_save_image("strecke_%04d" % roundi(_next_distance_shot))
				_next_distance_shot += _shot_every
			if not _bench_shots.is_empty() and _timer >= _bench_shots[0]:
				_bench_shots.remove_at(0)
				_save_image("bench_%d" % int(_timer))
			if _windows_at >= 0.0 and _timer >= _windows_at:
				_windows_at = -1.0
				(_game.get_node("OpenWindows") as OpenWindows).open = true
				print("Fenster auf bei %.1f s" % _timer)
			if _timer >= _bench_seconds and (_open_map or _open_garage):
				# Nach der Fahrt: große Karte bzw. Garage öffnen, kurz warten, Foto
				_state = "bench_end"
				_timer = 0.0
				process_mode = Node.PROCESS_MODE_ALWAYS
				if _open_map:
					(_game.get_node("BigMap") as BigMap).open()
				else:
					_open_garage_now()
			elif _timer >= _bench_seconds:
				_state = "done"
				if _recorder:
					_recorder.set_recording_active(false)
					_recorder.get_recording().save_to_wav(_record_path)
					print("Aufnahme gespeichert: ", _record_path)
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
	_on_exit_route = false
	if _exit_drive:
		# Einmal die Route über die Ausfahrt, danach normal weiter
		_exit_drive = false
		_route = _game.roads.exit_route(car.global_position, car.global_basis.z)
		_route_index = 0
		print("Autopilot: Route über die Ausfahrt, %d Punkte" % _route.size())
		if _route.size() >= 10:
			_on_exit_route = true
			return
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
	var step := Vector2(here.x - _last_position.x, here.z - _last_position.z).length()
	_distance_driven += step
	if _game.roads.tunnel_cover(here) > 0.5:
		_tunnel_driven += step
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
	# Überholen: das Ziel liegt eine Spur weiter links
	_lane_shift = move_toward(_lane_shift, _lane_shift_target, 1.3 * get_physics_process_delta_time())
	aim += Vector3.UP.cross(car.global_basis.z).normalized() * _lane_shift
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
	# Auf der Route über die Ausfahrt: Rampen und Zubringer haben enge Kurven
	var lateral := 9.0 if on_highway and not _on_exit_route else 4.0
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
	if _acc:
		target_speed = _acc_speed(car, speed, target_speed)
	if _cruise_kmh > 0.0 and _drive_with_cruise(car, speed):
		return
	if speed < target_speed - 1.0:
		Input.action_press("accelerate")
		Input.action_release("brake")
	elif speed > target_speed + 2.0:
		Input.action_release("accelerate")
		Input.action_press("brake")
	else:
		Input.action_release("accelerate")
		Input.action_release("brake")


## Kamera 9 m vor das nächste Verkehrszeichen der gewünschten Art (--signshot), Blick darauf
func _place_sign_camera(game: Node3D) -> void:
	var here: Vector3 = game.car.global_position
	var best: Array = []
	var best_distance := INF
	for pair: Array in game.roads.loaded_segments(Rect2(here.x - 2500.0, here.z - 2500.0, 5000.0, 5000.0)):
		var candidate: RoadSegment = pair[1]
		for entry: Array in candidate.limit_signs:
			var kind: String = entry[2]
			var wanted := false
			match _sign_shot:
				"curve":
					wanted = kind.begins_with("curve") or kind == "double_curve"
				"wet":
					wanted = kind == "limit" and entry[4]
				"tunnel":
					wanted = kind == "limit" and entry[3] == SpeedLimits.TUNNEL_LIMIT and candidate.kind == RoadSegment.Kind.ROAD
				_:
					wanted = kind == _sign_shot
			if not wanted:
				continue
			var p: Vector3 = candidate.points[entry[0]]
			var d := p.distance_to(here)
			if d < best_distance:
				best_distance = d
				best = [candidate, entry]
	if best.is_empty():
		# Zur Fehlersuche: welche Schilder gibt es in der Nähe?
		var found := {}
		for pair: Array in game.roads.loaded_segments(Rect2(here.x - 2500.0, here.z - 2500.0, 5000.0, 5000.0)):
			for entry: Array in (pair[1] as RoadSegment).limit_signs:
				var label := "%s %d%s" % [entry[2], entry[3], " nass" if entry[4] else ""]
				found[label] = found.get(label, 0) + 1
		print("Kein Schild der Art %s in der Nähe, gefunden: %s" % [_sign_shot, found])
		# Autobahn-Kurven: wie viele Meter enger als 2000/1500/1200 m Radius, Tunnel an Landstraßen
		var radii := [0, 0, 0, 0]
		var tunnels := 0
		for pair: Array in game.roads.loaded_segments(Rect2(here.x - 2500.0, here.z - 2500.0, 5000.0, 5000.0)):
			var nearby: RoadSegment = pair[1]
			if nearby.kind == RoadSegment.Kind.ROAD:
				tunnels += nearby.tunnel_ranges.size()
			if nearby.kind != RoadSegment.Kind.HIGHWAY:
				continue
			for k in nearby.curvature:
				radii[0] += 4
				for j in 3:
					if absf(k) > 1.0 / [2000.0, 1500.0, 1200.0][j]:
						radii[j + 1] += 4
		print("Autobahn %d m, enger als 2000/1500/1200 m: %s; Tunnel an Landstraßen: %d" % [radii[0], radii.slice(1), tunnels])
		return
	var segment: RoadSegment = best[0]
	var entry: Array = best[1]
	var travel := segment.direction_at(entry[0]) * float(entry[1])
	travel.y = 0.0
	travel = travel.normalized()
	var right := travel.cross(Vector3.UP).normalized()
	var sign_at: Vector3 = segment.points[entry[0]] + right * (segment.road_width * 0.5 + segment.shoulder_width + 0.8) + Vector3.UP * 2.0
	var eye := sign_at - travel * 9.0 - right * 3.0 + Vector3.UP * -0.4
	_sign_camera = Transform3D(Basis.looking_at(sign_at - eye), eye)
	_has_sign_camera = true
	camera.set_physics_process(false)
	camera.global_transform = _sign_camera
	camera.reset_physics_interpolation()
	_fly_height = 0.0
	_car_view = -1.0
	print("Schild %s (%d km/h) bei %s" % [entry[2], entry[3], Vector2(sign_at.x, sign_at.z).round()])


## Tempomat-Test (--cruise): bis zum Wunschtempo fährt der Autopilot, dann der echte Tempomat
## (Gas und Bremse los). Gibt true zurück, solange der Tempomat fährt.
func _drive_with_cruise(car: VehicleBody3D, speed: float) -> bool:
	var cruise := _game.get_node("CruiseControl") as CruiseControl
	var delta := get_physics_process_delta_time()
	if not cruise.active:
		if speed * 3.6 < _cruise_kmh - 2.0:
			return false
		cruise.gap_level = _cruise_gap
		cruise.switch_on(_cruise_kmh)
		print("Tempomat an bei %.0f km/h, Stufe %d (%.1f s)" % [speed * 3.6, _cruise_gap, cruise.gaps[_cruise_gap]])
	Input.action_release("accelerate")
	Input.action_release("brake")
	if cruise.warning:
		_cruise_warnings += 1
	if cruise.leader_gap > 0.0 and speed > 5.0:
		_cruise_min_time_gap = minf(_cruise_min_time_gap, cruise.leader_gap / speed)
	_cruise_log += delta
	if _cruise_log >= 1.0:
		# Verzögerung über die letzte Sekunde (einzelne Physikschritte springen zu stark)
		if _cruise_last_speed > 0.0:
			_cruise_max_brake = maxf(_cruise_max_brake, (_cruise_last_speed - speed) / _cruise_log)
		_cruise_last_speed = speed
		_cruise_log = 0.0
		print("Tempomat: %.0f km/h (Wunsch %.0f), Abstand %s, Zeitlücke %s, Gas %.2f, Bremse %.2f%s" % [
			speed * 3.6, cruise.set_speed_kmh,
			"%.0f m" % cruise.leader_gap if cruise.leader_gap > 0.0 else "-",
			"%.2f s" % (cruise.leader_gap / speed) if cruise.leader_gap > 0.0 and speed > 1.0 else "-",
			maxf(cruise.car.assist_throttle, 0.0), cruise.car.assist_brake, ", WARNUNG" if cruise.warning else ""])
	return true


## Autopilot mit Abstand (--acc): Wunschtempo nach dem IDM wie Tempomat und KI, auf der Autobahn
## links überholen, wenn der Vordermann langsamer ist und links frei ist, danach wieder rechts
func _acc_speed(car: VehicleBody3D, speed: float, target_speed: float) -> float:
	var traffic := _game.get_node_or_null("Traffic") as Traffic
	if _acc_max_kmh > 0.0:
		target_speed = minf(target_speed, _acc_max_kmh / 3.6)
	if traffic == null:
		return target_speed
	var forward := car.global_basis.z
	var curvature := car.angular_velocity.y / speed if speed > 5.0 else 0.0
	var leader := traffic.leader_ahead(car.global_position, forward, 4.6, 200.0, 0.0, curvature)
	if on_highway:
		var slower: bool = not leader.is_empty() and (leader[1] as float) < target_speed - 3.0 and (leader[0] as float) < 120.0
		if _lane_shift_target == 0.0 and slower and traffic.lane_free_at(car.global_position, forward, speed, -3.75, 60.0, 40.0):
			_lane_shift_target = 3.75
		elif _lane_shift_target > 0.0 and absf(_lane_shift - _lane_shift_target) < 0.2 \
				and traffic.lane_free_at(car.global_position, forward, speed, 3.75, 70.0, 25.0):
			_lane_shift_target = 0.0
	if leader.is_empty():
		return target_speed
	# Wie der Tempomat: Mindestabstand + 1,8 s, schneller annähern bremst früher
	var gap: float = leader[0]
	var wanted := Traffic.MIN_GAP + speed * 1.8
	return minf(target_speed, maxf((leader[1] as float) + (gap - wanted) * 0.35, 0.0))


## Kurz vor dem Foto: Navi-Ziel setzen, Fotomodus öffnen (wenn gewünscht)
func _prepare_shot() -> void:
	var weather := _game.get_node("Weather") as Weather
	if _rainbow:
		weather.start_rainbow()
	if _aurora:
		weather.force_aurora()
	if _has_target:
		(_game.get_node("Navigation") as Navigation).set_target(Vector3(_target.x, 0.0, _target.y))
	if _lineup >= 0.0:
		(_game.get_node("Traffic") as Traffic).spawn_lineup(_lineup)
	# Fotomodus und große Karte halten das Spiel an, das Foto muss trotzdem ausgelöst werden
	if _photo or _open_map or _open_garage or _pause_page >= 0:
		process_mode = Node.PROCESS_MODE_ALWAYS
	# Mit Benchmark erst am Ende (Karte mit Nebel nach der Fahrt, Orte-Sammlung)
	if _open_garage and _bench_seconds <= 0.0:
		_open_garage_now()
	if not _dyno_cars.is_empty():
		var garage := _game.get_node("Garage") as Garage
		garage.open_dyno()
		(_game.get_node("Dyno") as Dyno).run_series(_dyno_cars)
		_state = "dyno"
		_timer = 0.0
		if _record_path != "":
			_recorder = AudioEffectRecord.new()
			AudioServer.add_bus_effect(AudioServer.get_bus_index("Master"), _recorder)
			_recorder.set_recording_active(true)
	if _pause_page >= 0:
		var menu := _game.get_node("PauseMenu") as PauseMenu
		menu.open()
		if _pause_page > 0:
			menu.show_settings_tab(_pause_page - 1)
	if _open_map and _bench_seconds <= 0.0:
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


## Freie Kamera (--cam): über dem Gelände an einer festen Stelle, Blick auf --lookat
func _place_free_camera() -> void:
	camera.set_physics_process(false)
	var eye := Vector3(_cam.x, _game.ground_height(_cam.x, _cam.z) + _cam.y, _cam.z)
	var target := eye + Vector3.FORWARD
	if _has_look_at:
		target = Vector3(_look_at.x, _game.ground_height(_look_at.x, _look_at.y) + _look_height, _look_at.y)
	if _look_moon:
		target = eye + (_game.get_node("DayNight") as DayNight).moon_direction() * 100.0
	camera.global_transform = Transform3D(Basis.looking_at(target - eye), eye)
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


func _open_garage_now() -> void:
	var garage := _game.get_node("Garage") as Garage
	garage.open()
	if _collection_page >= 0:
		garage.call("_show_collection", _collection_page)


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
	var traffic := get_node_or_null("../Traffic") as Traffic
	if traffic:
		print("Verkehr: %d Autos unterwegs" % traffic.car_count())


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
	print("BENCH autopilot: %.0f m gefahren (%.0f km/h im Schnitt, max. %.0f km/h, davon %.0f m im Tunnel), max. %.1f m neben der Straßenmitte, min. Aufrecht-Wert %.2f" % [
		_distance_driven, _distance_driven / maxf(_timer, 0.1) * 3.6, _top_speed * 3.6, _tunnel_driven, _max_off_road, _lowest_up])
	var puddles := _game.get_node_or_null("Puddles") as Puddles
	if puddles and puddles.splash_count > 0:
		print("BENCH pfützen: %d Fontänen" % puddles.splash_count)
	if _cruise_kmh > 0.0:
		print("BENCH tempomat: kleinste Zeitlücke %.2f s, stärkste Bremsung %.1f m/s², Warnung %d Bilder" % [
			_cruise_min_time_gap, _cruise_max_brake, _cruise_warnings])


func _average(values: PackedFloat32Array) -> float:
	var total := 0.0
	for v in values:
		total += v
	return total / maxi(values.size(), 1)


func _percentile(values: PackedFloat32Array, p: float) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[int((sorted.size() - 1) * p)]
