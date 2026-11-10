class_name Dyno
extends CanvasLayer
## Leistungsprüfstand (Garage > Prüfstand): Das Auto steht in einer modernen Werkstatt, im Code
## gebaut (eigene 3D-Welt in einem SubViewport): heller Sichtbeton, große Glasfront, LED-Bänder
## an der Decke, glänzender Boden mit Spiegelungen, Rollen im Boden unter den angetriebenen Rädern,
## großes Gebläse vor dem Auto, Absaugschlauch am Auspuff, Bildschirm an der Wand.
##
## Messlauf: Vollgas im 4. Gang von 2000/min bis zum Begrenzer. Wie schnell die Drehzahl steigt,
## folgt aus Drehmoment, Übersetzung, Radradius und Gewicht (wie auf einer Rolle mit der Masse
## des Autos). Dabei läuft der echte Motorsound des Autos (mit Pops), an den Endrohren gibt es
## Flammen, Räder und Rollen drehen sich, die Kamera fährt mit. Ergebnis: PS- und Nm-Kurve aus
## dem Motormodell (Car.torque_curve), Spitzenwerte; die letzten drei gemessenen Autos liegen im
## Diagramm übereinander. Läufe werden pro Auto gespeichert (user://einstellungen.cfg).

## Wird gesendet, wenn der Prüfstand geschlossen wurde (zurück zur Garage)
signal closed

@export var car: Car
## Alle Autos (für die Kurven der gespeicherten Läufe)
@export var cars: Array[CarProfile] = []
## Testläufe (Argumente) speichern nichts, die Läufe bleiben dann nur im Speicher
@export var debug_tools: DebugTools
## Drehzahl beim Start des Messlaufs und Verluste im Antrieb (für die Laufzeit)
@export var start_rpm: float = 2000.0
@export var drivetrain_efficiency: float = 0.85

const SETTINGS_PATH := "user://einstellungen.cfg"
const RUN_COLORS: Array[Color] = [Color("#3D8BFF"), Color("#FF7A1A"), Color("#22C3A6")]
## Rollen: Radius, Abstand der beiden Rollen je Rad (Mitte zu Mitte) und Höhe ihrer Mitte
const ROLLER_RADIUS: float = 0.3
const ROLLER_SPACING: float = 0.64
const ROLLER_Y: float = -0.22

var is_open: bool = false
## Laufzeit des aktuellen Messlaufs (Sekunden)
var run_time: float = 0.0
## Testlauf: diese Autos nacheinander messen (--dyno), danach fertig
var series: Array[String] = []
var series_done: bool = false

var _viewport: SubViewport
var _container: SubViewportContainer
var _model_root: Node3D
var _model: CarModel
var _camera: Camera3D
var _rollers: Array[Node3D] = []
## Boden mit Grube (hängt vom Radstand ab, wird je Auto neu gebaut)
var _floor_parts: Array[Node3D] = []
var _world: Node3D
var _saved_gear: int = 1
var _memory := ConfigFile.new()
var _fan: Node3D
var _screen: Label3D
var _flames: Array[GPUParticles3D] = []
var _ui: Control
var _title: Label
var _values: Label
var _chart: DynoChart
var _start_button: Button
var _running: bool = false
var _coasting: float = 0.0
var _rpm: float = 0.0
var _wheel_angle: float = 0.0
var _orbit: float = 0.6
var _peak := Vector4.ZERO  # PS, Drehzahl, Nm, Drehzahl
var _sound: Node
var _floor_material: StandardMaterial3D


## Kurven im Diagramm: PS (durchgezogen) und Nm (gestrichelt) über der Drehzahl
class DynoChart extends Control:
	## Je Lauf: [Profil, Farbe, Name]
	var runs: Array = []
	## Live-Messung: Punkte [Drehzahl, PS, Nm]
	var live: Array = []
	var live_color: Color = Color.WHITE
	## Das Auto auf dem Prüfstand (zählt für die Skala mit, auch vor seinem ersten Lauf)
	var current: CarProfile

	func _draw() -> void:
		var area := Rect2(Vector2(54, 24), size - Vector2(108, 64))
		var max_ps := 200.0
		var max_nm := 200.0
		var max_rpm := 7000.0
		var scaled: Array[CarProfile] = []
		if current:
			scaled.append(current)
		for run: Array in runs:
			scaled.append(run[0])
		for p in scaled:
			max_rpm = maxf(max_rpm, p.redline_rpm)
			for rpm in range(1000, int(p.redline_rpm) + 1, 100):
				var nm := Car.torque_curve(p, rpm)
				max_nm = maxf(max_nm, nm)
				max_ps = maxf(max_ps, nm * rpm * TAU / 60.0 / 1000.0 * 1.36)
		max_ps = ceilf(max_ps / 100.0) * 100.0
		max_nm = ceilf(max_nm / 100.0) * 100.0
		max_rpm = ceilf(max_rpm / 1000.0) * 1000.0
		# Raster und Achsen
		for k in 6:
			var line_y := area.end.y - area.size.y * k / 5.0
			draw_line(Vector2(area.position.x, line_y), Vector2(area.end.x, line_y), Color(1, 1, 1, 0.08), 1.0)
			UiStyle.draw_text(self, str(roundi(max_ps * k / 5.0)), Vector2(area.position.x - 8, line_y + 5), 12, "medium", UiStyle.TEXT_DIM, 1.0)
			UiStyle.draw_text(self, str(roundi(max_nm * k / 5.0)), Vector2(area.end.x + 8, line_y + 5), 12, "medium", UiStyle.TEXT_DIM, 0.0)
		for rpm in range(1000, int(max_rpm) + 1, 1000):
			var x := area.position.x + area.size.x * (rpm - 1000.0) / (max_rpm - 1000.0)
			draw_line(Vector2(x, area.position.y), Vector2(x, area.end.y), Color(1, 1, 1, 0.06), 1.0)
			UiStyle.draw_text(self, str(roundi(rpm / 1000.0)), Vector2(x, area.end.y + 20), 12, "medium", UiStyle.TEXT_DIM, 0.5)
		UiStyle.draw_text(self, "PS", Vector2(area.position.x - 8, area.position.y - 8), 13, "semibold", UiStyle.TEXT, 1.0)
		UiStyle.draw_text(self, "Nm", Vector2(area.end.x + 8, area.position.y - 8), 13, "semibold", UiStyle.TEXT, 0.0)
		UiStyle.draw_text(self, "Drehzahl (1.000/min)", Vector2(area.get_center().x, area.end.y + 38), 12, "medium", UiStyle.TEXT_DIM, 0.5)
		var to_point := func(rpm: float, value: float, top: float) -> Vector2:
			return Vector2(area.position.x + area.size.x * (rpm - 1000.0) / (max_rpm - 1000.0),
				area.end.y - area.size.y * clampf(value / top, 0.0, 1.05))
		for run: Array in runs:
			var p: CarProfile = run[0]
			var ps_line := PackedVector2Array()
			var nm_line := PackedVector2Array()
			for rpm in range(int(maxf(p.idle_rpm, 1000.0)), int(p.redline_rpm) + 1, 100):
				var nm := Car.torque_curve(p, rpm)
				ps_line.append(to_point.call(rpm, nm * rpm * TAU / 60.0 / 1000.0 * 1.36, max_ps))
				nm_line.append(to_point.call(rpm, nm, max_nm))
			draw_polyline(ps_line, run[1], 3.0, true)
			for k in range(0, nm_line.size() - 1, 2):
				draw_line(nm_line[k], nm_line[k + 1], run[1], 2.0, true)
		# Legende oben links: Farbe, Auto, Spitzenleistung
		var y := area.position.y + 18.0
		for run: Array in runs:
			var p: CarProfile = run[0]
			var best_ps := 0.0
			var best_nm := 0.0
			for rpm in range(1000, int(p.redline_rpm) + 1, 50):
				var nm := Car.torque_curve(p, rpm)
				best_nm = maxf(best_nm, nm)
				best_ps = maxf(best_ps, nm * rpm * TAU / 60.0 / 1000.0 * 1.36)
			draw_circle(Vector2(area.position.x + 18.0, y - 5.0), 5.0, run[1])
			UiStyle.draw_text(self, "%s  ·  %d PS  ·  %d Nm" % [run[2], roundi(best_ps), roundi(best_nm)],
				Vector2(area.position.x + 32.0, y), 14, "semibold", UiStyle.TEXT)
			y += 22.0
		# Live-Messung als helle Punkte
		for point: Array in live:
			draw_circle(to_point.call(point[0], point[1], max_ps), 3.0, live_color)
			draw_circle(to_point.call(point[0], point[2], max_nm), 2.0, live_color)


func _ready() -> void:
	layer = 22
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


# ---------------------------------------------------------------------------
# Öffnen und schließen
# ---------------------------------------------------------------------------

func open() -> void:
	if is_open or car == null or car.profile == null:
		return
	is_open = true
	visible = true
	if _viewport == null:
		_build_world()
		_build_ui()
	_model.show_profile(car.profile)
	var real_model := car.get_node_or_null("Model") as CarModel
	if real_model:
		_model.set_paint(real_model.paint_index)
	_saved_gear = car.gear
	_place_rollers()
	_sound = car.get_node_or_null("EngineSound")
	if _sound:
		_sound.process_mode = Node.PROCESS_MODE_ALWAYS
	_rpm = car.profile.idle_rpm
	_refresh_chart()


func close() -> void:
	if not is_open:
		return
	_running = false
	is_open = false
	visible = false
	if _sound:
		_sound.process_mode = Node.PROCESS_MODE_INHERIT
	car.throttle_input = 0.0
	car.gear = _saved_gear
	car.engine_rpm = car.profile.idle_rpm
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# Messlauf
# ---------------------------------------------------------------------------

func start_run() -> void:
	if _running or _model.is_loading():
		return
	_running = true
	_coasting = 0.0
	run_time = 0.0
	_rpm = start_rpm
	_peak = Vector4.ZERO
	_chart.live.clear()
	_chart.live_color = RUN_COLORS[0]
	car.gear = 4
	_start_button.disabled = true


func _process(delta: float) -> void:
	if not is_open:
		return
	var p := car.profile
	var ratio: float = p.gear_ratios[mini(3, p.gear_ratios.size() - 1)] * p.final_drive
	if _running:
		run_time += delta
		if _coasting <= 0.0:
			# Vollgas: Drehzahl steigt mit dem Drehmoment (Rolle mit der Masse des Autos)
			var torque := Car.torque_curve(p, _rpm)
			var rise := torque * drivetrain_efficiency * ratio * ratio * 60.0 / (TAU * p.wheel_radius * p.wheel_radius * p.mass)
			var before := _rpm
			_rpm = minf(_rpm + rise * delta, p.redline_rpm)
			car.throttle_input = 1.0
			_record(before, _rpm)
			if _rpm >= p.redline_rpm - 1.0:
				_coasting = 2.5
				car.throttle_input = 0.0
				_save_run()
		else:
			# Gas weg: Drehzahl fällt (dabei knallt es), dann ist der Lauf vorbei
			_coasting -= delta
			car.throttle_input = 0.0
			_rpm = maxf(_rpm - 2200.0 * delta, p.idle_rpm)
			if _coasting <= 0.0:
				_running = false
				_start_button.disabled = false
				_next_in_series()
	else:
		car.throttle_input = 0.0
		_rpm = move_toward(_rpm, p.idle_rpm, 3000.0 * delta)
		if not series.is_empty() and not _model.is_loading() and _model_ready_for_series():
			start_run()
	car.engine_rpm = _rpm
	# Räder und Rollen drehen sich, das Gebläse läuft mit
	var wheel_speed := _rpm / 60.0 * TAU / ratio
	_wheel_angle = wrapf(_wheel_angle + wheel_speed * delta, 0.0, TAU)
	var anchors := _model.wheel_anchors()
	for corner in anchors.size():
		# Nur angetriebene Räder drehen sich (Heckantrieb: hinten)
		if is_instance_valid(anchors[corner]) and (corner >= 2 or p.front_drive_share > 0.0):
			anchors[corner].rotation.x = _wheel_angle
	for roller in _rollers:
		roller.rotation.x = -_wheel_angle * p.wheel_radius / ROLLER_RADIUS
	_fan.rotation.z += delta * (18.0 if _running else 3.0)
	_screen.text = "%d /min\n%d PS" % [roundi(_rpm), roundi(_peak.x)]
	_values.text = "Spitze  %d PS bei %d /min\n%d Nm bei %d /min" % [roundi(_peak.x), roundi(_peak.y),
		roundi(_peak.z), roundi(_peak.w)] if _peak.x > 0.0 else "Messlauf: Vollgas im 4. Gang\nvon 2.000 /min bis zum Begrenzer"
	_move_camera(delta)
	_chart.queue_redraw()


## Werte aus dem Motormodell alle 100 /min aufzeichnen (Spitzen merken)
func _record(from_rpm: float, to_rpm: float) -> void:
	var step := floorf(to_rpm / 100.0) * 100.0
	if step <= floorf(from_rpm / 100.0) * 100.0:
		return
	var nm := Car.torque_curve(car.profile, step)
	var ps := nm * step * TAU / 60.0 / 1000.0 * 1.36
	_chart.live.append([step, ps, nm])
	if ps > _peak.x:
		_peak.x = ps
		_peak.y = step
	if nm > _peak.z:
		_peak.z = nm
		_peak.w = step


## Ergebnis speichern: pro Auto die Spitzen, dazu die Liste der letzten drei Autos
func _save_run() -> void:
	var config := _config()
	config.set_value("pruefstand", car.profile.id, {"ps": roundi(_peak.x), "ps_rpm": roundi(_peak.y),
		"nm": roundi(_peak.z), "nm_rpm": roundi(_peak.w), "datum": Time.get_date_string_from_system()})
	var last: Array = config.get_value("pruefstand", "_vergleich", [])
	last.erase(car.profile.id)
	last.push_front(car.profile.id)
	config.set_value("pruefstand", "_vergleich", last.slice(0, 3))
	if not _testing():
		config.save(SETTINGS_PATH)
	print("Prüfstand %s: %d PS bei %d /min, %d Nm bei %d /min, Lauf %.1f s" % [car.profile.display_name,
		roundi(_peak.x), roundi(_peak.y), roundi(_peak.z), roundi(_peak.w), run_time])
	_refresh_chart()


func _refresh_chart() -> void:
	var config := _config()
	_chart.runs.clear()
	var ids: Array = config.get_value("pruefstand", "_vergleich", [])
	for k in ids.size():
		for profile in cars:
			if profile.id == ids[k]:
				_chart.runs.append([profile, RUN_COLORS[k % RUN_COLORS.size()], profile.display_name])
	_title.text = car.profile.display_name
	_chart.current = car.profile


func _testing() -> bool:
	return debug_tools != null and debug_tools.is_active()


## Einstellungsdatei (im Test nur im Speicher)
func _config() -> ConfigFile:
	if _testing():
		return _memory
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	return config


# ---------------------------------------------------------------------------
# Testreihe (--dyno): mehrere Autos nacheinander messen
# ---------------------------------------------------------------------------

var _series_index: int = -1


func run_series(ids: Array[String]) -> void:
	series = ids
	_series_index = -1
	series_done = false
	_next_in_series()


func _next_in_series() -> void:
	if series.is_empty():
		return
	_series_index += 1
	if _series_index >= series.size():
		series.clear()
		series_done = true
		return
	for profile in cars:
		if profile.id == series[_series_index]:
			car.apply_profile(profile)
			_model.show_profile(profile)
			_place_rollers()
			_refresh_chart()


func _model_ready_for_series() -> bool:
	return car.profile.id == series[_series_index] if _series_index >= 0 and _series_index < series.size() else false


# ---------------------------------------------------------------------------
# Werkstatt (eigene 3D-Welt)
# ---------------------------------------------------------------------------

func _build_world() -> void:
	_container = SubViewportContainer.new()
	_container.stretch = true
	_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_container)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	_container.add_child(_viewport)
	var world := Node3D.new()
	_viewport.add_child(world)
	_world = world
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.55, 0.62, 0.7)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.86, 0.88, 0.9)
	environment.ambient_light_energy = 0.9
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.ssr_enabled = true
	environment.glow_enabled = true
	environment.glow_intensity = 0.6
	environment.ssao_enabled = true
	var env_node := WorldEnvironment.new()
	env_node.environment = environment
	world.add_child(env_node)
	var concrete := _material(Color(0.74, 0.73, 0.7), 0.85, 0.0)
	var floor_material := _material(Color(0.25, 0.26, 0.27), 0.12, 0.1)
	var ceiling := _material(Color(0.42, 0.42, 0.41), 0.9, 0.0)
	var steel := _material(Color(0.5, 0.52, 0.55), 0.35, 0.8)
	var dark := _material(Color(0.05, 0.05, 0.06), 0.6, 0.0)
	var glass := _material(Color(0.6, 0.75, 0.85, 0.18), 0.05, 0.0)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var led := _material(Color.WHITE, 0.5, 0.0)
	led.emission_enabled = true
	led.emission = Color(1.0, 0.98, 0.95)
	led.emission_energy_multiplier = 6.0
	_floor_material = floor_material
	# Raum: Rückwand, Seitenwände, Decke, Glasfront mit Pfosten (Boden mit Grube: _place_rollers)
	_box(world, Vector3(0, 3.2, -9), Vector3(26, 6.4, 0.4), concrete)
	_box(world, Vector3(-13, 3.2, 0), Vector3(0.4, 6.4, 18), concrete)
	_box(world, Vector3(13, 3.2, 0), Vector3(0.4, 6.4, 18), concrete)
	_box(world, Vector3(0, 6.5, 0), Vector3(26, 0.2, 18), ceiling)
	_box(world, Vector3(0, 3.2, 9), Vector3(26, 6.4, 0.05), glass)
	for x in range(-12, 13, 3):
		_box(world, Vector3(x, 3.2, 9), Vector3(0.12, 6.4, 0.2), steel)
	# LED-Bänder an der Decke
	for x: float in [-6.0, -2.0, 2.0, 6.0]:
		_box(world, Vector3(x, 6.35, 0), Vector3(0.25, 0.06, 15), led)
	# Gebläse vor dem Auto, Absaugschlauch vom Heck nach oben zur Decke
	_fan = Node3D.new()
	_fan.position = Vector3(0, 0.9, 4.6)
	world.add_child(_fan)
	_box(world, Vector3(0, 0.9, 4.95), Vector3(1.9, 1.9, 0.5), steel)
	for k in 6:
		var blade := Node3D.new()
		blade.rotation.z = TAU * k / 6.0
		_fan.add_child(blade)
		_box(blade, Vector3(0, 0.38, 0), Vector3(0.22, 0.7, 0.04), dark)
	var hose: Array[Vector3] = [Vector3(0, 0.35, -3.2), Vector3(0, 0.5, -4.4), Vector3(0.4, 1.8, -5.6),
		Vector3(0.6, 4.2, -6.4), Vector3(0.6, 6.4, -6.6)]
	for k in hose.size() - 1:
		_tube(world, hose[k], hose[k + 1], 0.11, dark)
	# Bildschirm an der Wand mit Drehzahl und Leistung
	_box(world, Vector3(6.5, 3.0, -8.75), Vector3(4.0, 2.2, 0.08), dark)
	_screen = Label3D.new()
	_screen.font = UiStyle.font("semibold")
	_screen.font_size = 96
	_screen.pixel_size = 0.006
	_screen.modulate = Color(0.55, 0.85, 1.0)
	_screen.position = Vector3(6.5, 3.0, -8.68)
	world.add_child(_screen)
	# Licht
	for spot: Vector3 in [Vector3(-4, 5.8, 2), Vector3(4, 5.8, -2), Vector3(0, 5.8, 6), Vector3(-4, 5.8, -5)]:
		var light := OmniLight3D.new()
		light.position = spot
		light.omni_range = 22.0
		light.light_energy = 3.0
		light.shadow_enabled = spot.x < 0.0
		world.add_child(light)
	# Auto (Vorschau ohne Physik) und Flammen an den Endrohren
	_model_root = Node3D.new()
	world.add_child(_model_root)
	_model = CarModel.new()
	_model_root.add_child(_model)
	_camera = Camera3D.new()
	_camera.fov = 50.0
	# Bild verschoben: das Auto steht oben rechts zwischen Panel und Diagramm
	_camera.h_offset = -1.3
	_camera.v_offset = -0.9
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	world.add_child(_camera)
	_camera.current = true
	for k in 4:
		var flame := GPUParticles3D.new()
		flame.one_shot = true
		flame.emitting = false
		flame.amount = 24
		flame.lifetime = 0.12
		flame.explosiveness = 0.9
		var process := ParticleProcessMaterial.new()
		process.direction = Vector3(0, 0, -1)
		process.spread = 12.0
		process.initial_velocity_min = 4.0
		process.initial_velocity_max = 7.0
		process.gravity = Vector3.ZERO
		flame.process_material = process
		var quad := QuadMesh.new()
		quad.size = Vector2(0.18, 0.18)
		var fire := StandardMaterial3D.new()
		fire.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		fire.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fire.albedo_color = Color(1.0, 0.55, 0.15)
		fire.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		quad.material = fire
		flame.draw_pass_1 = quad
		world.add_child(flame)
		_flames.append(flame)
	var engine := car.get_node_or_null("EngineSound")
	if engine and engine.has_signal("popped"):
		engine.connect("popped", _on_popped)


## Boden mit Grube und Rollen unter den angetriebenen Rädern (Heckantrieb hinten, Allrad vorne und
## hinten). Je Rad zwei Rollen, das Rad liegt dazwischen. Das Auto steht so hoch, dass die Räder
## die Rollen berühren.
func _place_rollers() -> void:
	for node in _rollers + _floor_parts:
		node.queue_free()
	_rollers.clear()
	_floor_parts.clear()
	var p := car.profile
	var front_z := Car.resting_wheel_center(p, 0).z
	var rear_z := Car.resting_wheel_center(p, 2).z
	# Grube: 2,8 m breit, 0,9 m vor bzw. hinter den Achsen, 0,55 m tief
	var pit := Rect2(-1.4, minf(front_z, rear_z) - 0.9, 2.8, absf(front_z - rear_z) + 1.8)
	var floor_rect := Rect2(-13.0, -9.0, 26.0, 18.0)
	_floor_box(Rect2(floor_rect.position.x, floor_rect.position.y, pit.position.x - floor_rect.position.x, floor_rect.size.y))
	_floor_box(Rect2(pit.end.x, floor_rect.position.y, floor_rect.end.x - pit.end.x, floor_rect.size.y))
	_floor_box(Rect2(pit.position.x, floor_rect.position.y, pit.size.x, pit.position.y - floor_rect.position.y))
	_floor_box(Rect2(pit.position.x, pit.end.y, pit.size.x, floor_rect.end.y - pit.end.y))
	var steel := _material(Color(0.32, 0.33, 0.35), 0.4, 0.7)
	var pit_floor := MeshInstance3D.new()
	var pit_mesh := BoxMesh.new()
	pit_mesh.size = Vector3(pit.size.x, 0.55, pit.size.y)
	pit_mesh.material = _material(Color(0.08, 0.08, 0.09), 0.7, 0.0)
	pit_floor.mesh = pit_mesh
	pit_floor.position = Vector3(pit.get_center().x, -0.55 * 0.5 - 0.3, pit.get_center().y)
	_world.add_child(pit_floor)
	_floor_parts.append(pit_floor)
	var corners: Array[int] = [2, 3]
	if p.front_drive_share > 0.0:
		corners = [0, 1, 2, 3]
	var rubber := _material(Color(0.12, 0.12, 0.13), 0.35, 0.6)
	for corner in corners:
		var center := Car.resting_wheel_center(p, corner)
		for shift: float in [-ROLLER_SPACING * 0.5, ROLLER_SPACING * 0.5]:
			var roller := Node3D.new()
			roller.position = Vector3(center.x, ROLLER_Y, center.z + shift)
			_world.add_child(roller)
			var mesh := MeshInstance3D.new()
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = ROLLER_RADIUS
			cylinder.bottom_radius = ROLLER_RADIUS
			cylinder.height = 0.45
			cylinder.material = rubber
			mesh.mesh = cylinder
			mesh.rotation.z = PI * 0.5
			roller.add_child(mesh)
			_rollers.append(roller)
	# Abdeckplatten zwischen den Rollen (Stahl, bündig mit dem Boden)
	for z: float in [front_z, rear_z]:
		for x: float in [-1.0, 1.0]:
			var plate := MeshInstance3D.new()
			var plate_mesh := BoxMesh.new()
			plate_mesh.size = Vector3(0.5, 0.04, 1.4)
			plate_mesh.material = steel
			plate.mesh = plate_mesh
			plate.position = Vector3(x * 1.15, -0.02, z)
			_world.add_child(plate)
			_floor_parts.append(plate)
	# Radmitte über den Rollen: Abstand Rad–Rolle = Radradius + Rollenradius
	var reach := p.wheel_radius + ROLLER_RADIUS
	var wheel_y := ROLLER_Y + sqrt(maxf(reach * reach - pow(ROLLER_SPACING * 0.5, 2.0), 0.01))
	_model_root.position = Vector3(0.0, wheel_y - Car.resting_wheel_center(p, 2).y, 0.0)


func _floor_box(rect: Rect2) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(rect.size.x, 0.2, rect.size.y)
	mesh.material = _floor_material
	instance.mesh = mesh
	instance.position = Vector3(rect.get_center().x, -0.1, rect.get_center().y)
	_world.add_child(instance)
	_floor_parts.append(instance)


func _on_popped(strength: float) -> void:
	if not is_open or strength < 0.3:
		return
	var tips := car.profile.exhaust_tips
	for k in mini(tips.size(), _flames.size()):
		_flames[k].position = _model_root.position + tips[k]
		_flames[k].restart()


## Kamera: im Stand langsam um das Auto, beim Messlauf fährt sie seitlich mit nach hinten
func _move_camera(delta: float) -> void:
	var target := Vector3(0, 0.8, 0)
	var eye: Vector3
	if _running:
		var t := clampf(run_time / 9.0, 0.0, 1.0)
		eye = Vector3(-6.0, 1.2 + 0.6 * t, lerpf(4.5, -3.5, t))
		target = Vector3(0, 0.6, lerpf(1.0, -1.6, t))
	else:
		_orbit += delta * 0.15
		eye = Vector3(sin(_orbit) * 7.5, 2.0, cos(_orbit) * 7.5)
	_camera.global_transform = Transform3D(Basis.looking_at(target - eye), eye)


# ---------------------------------------------------------------------------
# Bedienung (Glas-Stil wie die Garage)
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui)
	var panel := Control.new()
	panel.position = Vector2(40, 36)
	panel.size = Vector2(440, 380)
	_ui.add_child(panel)
	var glass := GlassPanel.new()
	glass.radius = 28.0
	glass.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(glass)
	var box := VBoxContainer.new()
	box.position = Vector2(32, 30)
	box.size = Vector2(376, 330)
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	box.add_child(UiStyle.label("PRÜFSTAND", 13, "semibold", UiStyle.accent, 2))
	_title = UiStyle.label("", 18, "semibold")
	box.add_child(_title)
	_values = UiStyle.label("", 16, "regular", UiStyle.TEXT_DIM)
	box.add_child(_values)
	_start_button = Button.new()
	_start_button.text = "Messlauf starten"
	_start_button.custom_minimum_size = Vector2(0, 52)
	_start_button.focus_mode = Control.FOCUS_NONE
	_start_button.add_theme_font_override("font", UiStyle.font("semibold"))
	_start_button.add_theme_font_size_override("font_size", 18)
	_start_button.add_theme_stylebox_override("normal", UiStyle.box(UiStyle.accent, 14))
	_start_button.add_theme_stylebox_override("hover", UiStyle.box(UiStyle.accent.lightened(0.12), 14))
	_start_button.add_theme_stylebox_override("disabled", UiStyle.box(Color(1, 1, 1, 0.12), 14))
	_start_button.pressed.connect(start_run)
	box.add_child(_start_button)
	var back := Button.new()
	back.text = "Zurück zur Garage (Esc)"
	back.focus_mode = Control.FOCUS_NONE
	back.custom_minimum_size = Vector2(0, 42)
	back.add_theme_stylebox_override("normal", UiStyle.box(Color(0, 0, 0, 0), 12, Color(1, 1, 1, 0.22), 1))
	back.pressed.connect(close)
	box.add_child(back)
	# Diagramm unten rechts
	var chart_panel := Control.new()
	chart_panel.position = Vector2(640, 520)
	chart_panel.size = Vector2(920, 344)
	_ui.add_child(chart_panel)
	var chart_glass := GlassPanel.new()
	chart_glass.radius = 28.0
	chart_glass.set_anchors_preset(Control.PRESET_FULL_RECT)
	chart_panel.add_child(chart_glass)
	_chart = DynoChart.new()
	_chart.set_anchors_preset(Control.PRESET_FULL_RECT)
	_chart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chart_panel.add_child(_chart)


func _box(parent: Node3D, center: Vector3, size: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = center
	parent.add_child(instance)


## Röhre (Zylinder) von a nach b
func _tube(parent: Node3D, a: Vector3, b: Vector3, radius: float, material: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = a.distance_to(b) + radius
	mesh.radial_segments = 16
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	var up := (b - a).normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	instance.transform = Transform3D(Basis(side, up, side.cross(up)), (a + b) * 0.5)
	parent.add_child(instance)


func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material
