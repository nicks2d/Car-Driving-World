class_name SelfTest
extends Node
## Automatischer Testlauf (--selftest, gestartet von DebugTools, aufgerufen von tools/test.sh):
## fährt mit dem Autopiloten Landstraße und Autobahn, spult 2 s zurück, schaltet Cockpit- und Ego-Sicht (mit Regen),
## Regen, Schnee, Nacht, Garage, Karte, Fotomodus, Pausemenü und Chill-Modus kurz durch und schreibt am Ende
## „SELFTEST ENDE“. Fehlt diese Zeile im Log, ist das Spiel unterwegs abgestürzt.
## Mit --selftest=shots macht er bei jedem Schritt ein Foto (screenshots/selftest_*.png,
## in der exportierten App user://selftest/).

## Sekunden pro Fahrt (Landstraße und Autobahn)
@export var drive_seconds: float = 25.0
## Sekunden pro Wetter-, Nacht- und Menü-Schritt
@export var step_seconds: float = 3.5
## Sekunden im Chill-Modus (mindestens ein Kameraschnitt)
@export var chill_seconds: float = 12.0
## Hierhin springt der Test für die Autobahn-Fahrt (gerade Autobahn west–ost)
@export var highway_point: Vector2 = Vector2(1200.0, -4000.0)

var debug_tools: Node
var game: Node3D
var shots: bool = false

## Schritte: [Name, Dauer]
var _steps: Array = []
var _index: int = -1
var _timer: float = 0.0
var _waiting_for_world: bool = false
var _start_msec: int = 0
var _start_position: Vector3 = Vector3.ZERO
var _driven: Dictionary = {}  # Schritt -> gefahrene Meter
var _last_position: Vector3 = Vector3.ZERO


func _ready() -> void:
	# Garage, Karte, Fotomodus und Pausemenü halten das Spiel an, der Test läuft weiter
	process_mode = Node.PROCESS_MODE_ALWAYS
	_steps = [["landstrasse", drive_seconds], ["sprung", 0.0], ["autobahn", drive_seconds],
		["zurueckspulen", 2.0], ["cockpit", step_seconds], ["ego", step_seconds], ["regen", step_seconds], ["schnee", step_seconds], ["nacht", step_seconds],
		["garage", step_seconds], ["karte", step_seconds], ["fotomodus", step_seconds],
		["pausemenue", step_seconds], ["chill", chill_seconds]]
	_start_msec = Time.get_ticks_msec()
	_last_position = game.car.global_position
	print("SELFTEST START")
	_next_step()


func _process(delta: float) -> void:
	if _index >= _steps.size():
		return
	var step: String = _steps[_index][0]
	if _waiting_for_world:
		if game.world_is_ready:
			_waiting_for_world = false
			debug_tools.restart_autopilot(true)
			_last_position = game.car.global_position
			print("SELFTEST Autobahn erreicht bei %s" % _flat(game.car.global_position))
			_next_step()
		elif Time.get_ticks_msec() - _start_msec > 600000:
			_fail("Sprung zur Autobahn: Welt wurde nicht fertig")
		return
	var here: Vector3 = game.car.global_position
	_driven[step] = _driven.get(step, 0.0) + _flat(here - _last_position).length()
	_last_position = here
	_timer += delta
	if _timer >= _steps[_index][1]:
		_end_step(step)
		_next_step()


func _next_step() -> void:
	_index += 1
	_timer = 0.0
	if _index >= _steps.size():
		_finish()
		return
	var step: String = _steps[_index][0]
	print("SELFTEST Schritt: %s" % step)
	var weather := game.get_node("Weather") as Weather
	var day_night := game.get_node("DayNight") as DayNight
	var camera := game.get_node("Camera") as FollowCamera
	match step:
		"sprung":
			debug_tools.autopilot_enabled = false
			_release_keys()
			debug_tools.on_highway = true
			game.jump_to(highway_point)
			_waiting_for_world = true
		"autobahn":
			debug_tools.autopilot_enabled = true
		"zurueckspulen":
			Input.action_press("rewind")
		"cockpit":
			camera.set_view(FollowCamera.View.COCKPIT)
			weather.set_mode(Weather.Kind.RAIN, true, false)
		"ego":
			camera.set_view(FollowCamera.View.EGO)
		"regen":
			camera.set_view(FollowCamera.View.FOLLOW)
			weather.set_mode(Weather.Kind.RAIN, true, false)
		"schnee":
			weather.set_season(Weather.Season.WINTER, true, false)
			weather.set_mode(Weather.Kind.SNOW, true, false)
		"nacht":
			weather.set_season(Weather.Season.SUMMER, true, false)
			weather.set_mode(Weather.Kind.CLEAR, true, false)
			day_night.set_time(23.0)
		"garage":
			debug_tools.autopilot_enabled = false
			_release_keys()
			(game.get_node("Garage") as Garage).open()
		"karte":
			(game.get_node("BigMap") as BigMap).open()
		"fotomodus":
			(game.get_node("PhotoMode") as PhotoMode).open()
		"pausemenue":
			(game.get_node("PauseMenu") as PauseMenu).open()
		"chill":
			day_night.set_time(14.0)
			(game.get_node("ChillMode") as ChillMode).start()
	if shots and step != "sprung":
		_shot_later(step)


func _end_step(step: String) -> void:
	match step:
		"zurueckspulen":
			Input.action_release("rewind")
		"garage":
			(game.get_node("Garage") as Garage).close(true)
		"karte":
			(game.get_node("BigMap") as BigMap).close()
		"fotomodus":
			(game.get_node("PhotoMode") as PhotoMode).close()
		"pausemenue":
			(game.get_node("PauseMenu") as PauseMenu).close()
		"chill":
			(game.get_node("ChillMode") as ChillMode).stop()


func _finish() -> void:
	var seconds := (Time.get_ticks_msec() - _start_msec) / 1000.0
	print("SELFTEST gefahren: Landstraße %.0f m, Autobahn %.0f m, Chill-Modus %.0f m" % [
		_driven.get("landstrasse", 0.0), _driven.get("autobahn", 0.0), _driven.get("chill", 0.0)])
	print("SELFTEST FPS im Schnitt %.0f" % Engine.get_frames_per_second())
	# Zu wenig gefahren = Autopilot hängt fest (zählt als Fehler)
	if _driven.get("landstrasse", 0.0) < 150.0 or _driven.get("autobahn", 0.0) < 300.0:
		push_error("SELFTEST: Autopilot ist kaum gefahren (Landstraße %.0f m, Autobahn %.0f m)" % [
			_driven.get("landstrasse", 0.0), _driven.get("autobahn", 0.0)])
	print("SELFTEST ENDE nach %.0f s" % seconds)
	await get_tree().create_timer(0.3, true, false, true).timeout
	get_tree().quit()


func _fail(reason: String) -> void:
	push_error("SELFTEST: " + reason)
	_index = _steps.size()
	print("SELFTEST ENDE (abgebrochen)")
	get_tree().quit(1)


func _release_keys() -> void:
	for action: String in ["accelerate", "brake", "handbrake", "steer_left", "steer_right"]:
		Input.action_release(action)


## Foto kurz vor Ende des Schritts (dann ist Wetter bzw. Menü schon zu sehen)
func _shot_later(step: String) -> void:
	await get_tree().create_timer(maxf(_steps[_index][1] - 0.8, 0.5), true, false, true).timeout
	await RenderingServer.frame_post_draw
	var folder := "user://selftest" if OS.has_feature("template") else "res://screenshots"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var path := ProjectSettings.globalize_path(folder.path_join("selftest_%s.png" % step))
	get_viewport().get_texture().get_image().save_png(path)
	print("SELFTEST Foto: ", path)


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
