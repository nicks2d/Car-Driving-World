class_name ChillMode
extends CanvasLayer
## Chill-Modus (Pausemenü): Das Auto fährt von selbst endlos weiter, die Kamera wechselt wie im
## Film alle 10–20 s die Einstellung (Hubschrauber, seitlich mitfahrend, tief von vorne,
## Stoßstange, fest am Straßenrand). Kein HUD, schwarze Balken oben und unten, leichte
## Tiefenunschärfe, weiche Überblendung zwischen den Einstellungen. Zeit und Wetter laufen weiter
## (auf Wunsch schneller). Jede Taste, ein Mausklick oder eine deutliche Mausbewegung beendet ihn.
##
## Autopilot: folgt der Route (RoadNetwork.route_from mit scenic = true: an Kreuzungen lieber
## Abschnitte mit Aussicht, Pass, See, Talsperre oder Landmarken-Brücke), Landstraße auf der
## rechten Spur, Autobahn rechts mit Überholen links. Tempo aus Kurven, Tempolimits und dem
## Abstand zum Vordermann (IDM wie Tempomat und KI). Er drückt dieselben Tasten wie ein Spieler.

@export var car: Car
@export var camera: Camera3D
@export var roads: RoadNetwork
@export var traffic: Traffic
@export var limits: SpeedLimits
@export var day_night: DayNight
@export var hud: CanvasLayer
## Meldungen (Toasts): im Chill-Modus ausgeblendet
@export var messages: CanvasLayer
@export var debug_tools: DebugTools
## Zeitraffer im Chill-Modus (1 = normal, Einstellungen > Spiel)
@export var time_factor: float = 1.0

@export_group("Kamera")
## So lange bleibt eine Einstellung (Sekunden, zufällig dazwischen)
@export var shot_min: float = 10.0
@export var shot_max: float = 20.0
## Überblendung zwischen zwei Einstellungen (Sekunden)
@export var blend_time: float = 1.4
## Höhe der schwarzen Balken (Anteil der Bildhöhe, je oben und unten)
@export var bar_height: float = 0.085

@export_group("Fahren")
## Wunschtempo Landstraße / Autobahn (km/h), Querbeschleunigung in Kurven, Bremsen (m/s²)
@export var road_speed_kmh: float = 95.0
@export var highway_speed_kmh: float = 150.0
@export var road_lateral: float = 3.0
@export var highway_lateral: float = 4.5
@export var comfort_brake: float = 2.5
## Abstand zur Straßenmitte auf der Landstraße (rechte Spur, Meter)
@export var road_lane: float = 2.0

const SHOTS: Array[String] = ["heli", "side", "low_front", "bumper", "roadside"]
## Blickwinkel je Einstellung (Grad)
const SHOT_FOV := {"heli": 50.0, "side": 52.0, "low_front": 42.0, "bumper": 72.0, "roadside": 32.0}

var active: bool = false
var shot: String = ""

var _rng := RandomNumberGenerator.new()
var _route := PackedVector3Array()
var _route_index: int = 0
var _recent: Array[Vector3i] = []
var _lane_shift: float = 0.0
var _lane_shift_target: float = 0.0
var _trouble_time: float = 0.0
## Was beim nächsten Schnitt am Auto gerichtet wird: "", "turn" (wenden), "rescue" (auf die Straße)
var _fix: String = ""
var _end_wait: float = 0.0
var _shot_time: float = 0.0
var _shot_length: float = 15.0
var _side: float = 1.0
var _orbit: float = 0.0
var _heading := Vector3.FORWARD
var _fixed_position := Vector3.ZERO
var _attributes := CameraAttributesPractical.new()
var _old_attributes: CameraAttributes
var _old_fov: float = 70.0
var _old_day_length: float = 10.0
var _hud_was_visible: bool = true
var _messages_were_visible: bool = true
var _started_msec: int = 0
var _mouse_moved: float = 0.0
var _snapshot: TextureRect
var _snapshot_texture: ImageTexture
var _fade: float = 0.0
var _bars: Array[ColorRect] = []
var _hint: Label
var _hint_time: float = 0.0
var _cutting: bool = false
var _log_time: float = 0.0
var _replan_timer: float = 0.0


func _ready() -> void:
	layer = 20
	_rng.randomize()
	# Überblendung: das letzte Bild der alten Einstellung, wird ausgeblendet
	_snapshot = TextureRect.new()
	_snapshot.set_anchors_preset(Control.PRESET_FULL_RECT)
	_snapshot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_snapshot.stretch_mode = TextureRect.STRETCH_SCALE
	_snapshot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_snapshot.visible = false
	add_child(_snapshot)
	for i in 2:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bar)
		_bars.append(bar)
	_hint = UiStyle.label("Chill-Modus  ·  beliebige Taste beendet", 16, "medium", Color(1, 1, 1, 0.85))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 24)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)
	_attributes.dof_blur_far_enabled = true
	_attributes.dof_blur_amount = 0.04
	visible = false


func _testing() -> bool:
	return debug_tools != null and debug_tools.is_active()


func start() -> void:
	if active or car == null or camera == null:
		return
	active = true
	visible = true
	_started_msec = Time.get_ticks_msec()
	_mouse_moved = 0.0
	_hint_time = 5.0
	if hud:
		_hud_was_visible = hud.visible
		hud.visible = false
	if messages:
		_messages_were_visible = messages.visible
		messages.visible = false
	if day_night:
		_old_day_length = day_night.day_length_minutes
		day_night.day_length_minutes = _old_day_length / maxf(time_factor, 0.1)
	var cruise := car.get_node_or_null("../CruiseControl") as CruiseControl
	if cruise and cruise.active:
		cruise.switch_off()
	# Die Fahrkamera übernehmen (dann laufen Regen, Talnebel usw. wie gewohnt mit)
	camera.set_physics_process(false)
	_old_attributes = camera.attributes
	_old_fov = camera.fov
	camera.attributes = _attributes
	_route = PackedVector3Array()
	_fix = ""
	_trouble_time = 0.0
	_end_wait = 0.0
	_lane_shift = 0.0
	_lane_shift_target = 0.0
	_heading = _flat(car.global_basis.z)
	_start_shot(SHOTS[_rng.randi_range(0, 2)])
	_resize_bars()


func stop() -> void:
	if not active:
		return
	active = false
	visible = false
	_cutting = false
	for action: String in ["accelerate", "brake", "handbrake", "steer_left", "steer_right"]:
		Input.action_release(action)
	camera.attributes = _old_attributes
	camera.fov = _old_fov
	camera.set_physics_process(true)
	camera.call("_update_camera", 0.0, true)
	camera.reset_physics_interpolation()
	if hud:
		hud.visible = _hud_was_visible
	if messages:
		messages.visible = _messages_were_visible
	if day_night:
		day_night.day_length_minutes = _old_day_length


func _input(event: InputEvent) -> void:
	if not active or _testing():
		return
	# Der Klick auf „Chill-Modus“ im Menü soll ihn nicht gleich wieder beenden
	if Time.get_ticks_msec() - _started_msec < 800:
		return
	var ends := false
	if event is InputEventKey and event.pressed and not event.is_echo():
		ends = true
	elif event is InputEventMouseButton and event.pressed:
		ends = true
	elif event is InputEventJoypadButton and event.pressed:
		ends = true
	elif event is InputEventMouseMotion:
		_mouse_moved += (event as InputEventMouseMotion).relative.length()
		ends = _mouse_moved > 40.0
	if ends:
		get_viewport().set_input_as_handled()
		stop()


func _process(delta: float) -> void:
	if not active:
		return
	_mouse_moved = maxf(_mouse_moved - delta * 60.0, 0.0)
	_hint_time -= delta
	_hint.modulate.a = clampf(_hint_time, 0.0, 1.0)
	if _fade > 0.0:
		_fade = maxf(_fade - delta / blend_time, 0.0)
		_snapshot.modulate.a = smoothstep(0.0, 1.0, _fade)
		_snapshot.visible = _fade > 0.0
	_resize_bars()


func _resize_bars() -> void:
	var size := get_viewport().get_visible_rect().size
	var h := size.y * bar_height
	_bars[0].position = Vector2.ZERO
	_bars[0].size = Vector2(size.x, h)
	_bars[1].position = Vector2(0.0, size.y - h)
	_bars[1].size = Vector2(size.x, h)


func _physics_process(delta: float) -> void:
	if not active:
		return
	_drive(delta)
	if _testing():
		_log_time += delta
		if _log_time >= 5.0:
			_log_time = 0.0
			print("Chill: %s, %.0f km/h, Position %s, Route %d/%d" % [shot, car.linear_velocity.length() * 3.6,
				car.global_position.round(), _route_index, _route.size()])
	_shot_time += delta
	var passed := shot == "roadside" and _shot_time > 5.0 and \
		_flat(car.global_position - _fixed_position).dot(_heading) > 45.0
	if (_shot_time > _shot_length or passed) and not _cutting:
		_cut()
	_update_camera(delta)


# ---------------------------------------------------------------------------
# Kamera
# ---------------------------------------------------------------------------

## Schnitt: letztes Bild festhalten (für die Überblendung), dann eine andere Einstellung
func _cut() -> void:
	_cutting = true
	await RenderingServer.frame_post_draw
	if not active:
		return
	var image := get_viewport().get_texture().get_image()
	if _snapshot_texture and _snapshot_texture.get_size() == Vector2(image.get_size()):
		_snapshot_texture.update(image)
	else:
		_snapshot_texture = ImageTexture.create_from_image(image)
	_snapshot.texture = _snapshot_texture
	_snapshot.modulate.a = 1.0
	_snapshot.visible = true
	_fade = 1.0
	_apply_fix()
	var options: Array[String] = []
	for kind in SHOTS:
		if kind != shot:
			options.append(kind)
	_start_shot(options[_rng.randi_range(0, options.size() - 1)])
	_cutting = false


## Unter der Überblendung: Auto wenden (Sackgasse) oder zurück auf die Straße setzen
func _apply_fix() -> void:
	if _fix == "turn":
		var t := car.global_transform
		var yaw := atan2(-t.basis.z.x, -t.basis.z.z)
		car.teleport(Transform3D(Basis(Vector3.UP, yaw), t.origin + Vector3.UP * 0.3))
	elif _fix == "rescue":
		var result := roads.nearest_road_transform(car.global_position, car.global_basis.z)
		if result["found"]:
			car.teleport(result["transform"])
	if _fix != "":
		if _testing():
			print("Chill: ", "gewendet" if _fix == "turn" else "zurück auf die Straße", " bei ", car.global_position.round())
		_fix = ""
		_trouble_time = 0.0
		_end_wait = 0.0
		_route = PackedVector3Array()
		_heading = _flat(car.global_basis.z)


func _start_shot(kind: String) -> void:
	shot = kind
	_shot_time = 0.0
	_shot_length = _rng.randf_range(shot_min, shot_max)
	_side = 1.0 if _rng.randf() < 0.5 else -1.0
	_orbit = _rng.randf_range(-0.6, 0.6)
	_heading = _flat(car.linear_velocity) if car.linear_velocity.length() > 3.0 else _flat(car.global_basis.z)
	if kind == "roadside":
		_fixed_position = _roadside_spot()
		if _fixed_position == Vector3.INF:
			_start_shot("side")
			return
	camera.fov = SHOT_FOV[kind]
	_update_camera(0.0)
	camera.reset_physics_interpolation()


## Fester Platz am Straßenrand 80–140 m voraus, dort, wo die Straße bis zum Auto am geradesten
## ist (sonst steht in Kurven Wald dazwischen). Landstraße: auf der Seite, auf der das Gelände
## tiefer liegt (dort steht keine Böschung im Bild), Autobahn: am Mittelstreifen.
func _roadside_spot() -> Vector3:
	var best := -1
	var best_bend := INF
	for meters: float in [80.0, 100.0, 120.0, 140.0]:
		var k := _route_index + int(meters / RoadSegment.POINT_SPACING)
		if k >= _route.size() - 2:
			break
		# Größter Abstand der Route zur Geraden Auto → Kamera
		var a := Vector2(_route[_route_index].x, _route[_route_index].z)
		var b := Vector2(_route[k].x, _route[k].z)
		var bend := 0.0
		for i in range(_route_index, k, 2):
			var q := Vector2(_route[i].x, _route[i].z)
			bend = maxf(bend, absf((b - a).normalized().cross(q - a)))
		if bend < best_bend:
			best_bend = bend
			best = k
	if best < 0 or best_bend > 25.0:
		return Vector3.INF
	var p := _route[best]
	var along := _flat(_route[best + 1] - _route[best - 1])
	var left := Vector3.UP.cross(along)
	var spot: Vector3
	if _on_highway():
		# Die Route liegt auf der rechten Spur (8,1 m neben der Mitte): knapp neben der Leitplanke
		spot = p + left * 7.2
		spot.y = p.y + 2.2
		return spot
	var spots := [p + left * 7.0, p - left * 7.0]
	var grounds: Array[float] = []
	for candidate: Vector3 in spots:
		grounds.append(get_parent().call("ground_height", candidate.x, candidate.z))
	var pick := 0 if grounds[0] < grounds[1] else 1
	spot = spots[pick]
	spot.y = maxf(grounds[pick], p.y) + 2.6
	return spot


func _update_camera(delta: float) -> void:
	var target := car.global_position + Vector3.UP * 0.7
	var smooth := 1.0 - exp(-1.5 * delta) if delta > 0.0 else 1.0
	var moving := car.linear_velocity.length() > 3.0
	_heading = _heading.slerp(_flat(car.linear_velocity) if moving else _flat(car.global_basis.z), smooth).normalized()
	var right := -Vector3.UP.cross(_heading)
	var eye := Vector3.ZERO
	var look := target
	match shot:
		"heli":
			# Hoch hinten seitlich, kreist langsam um das Auto
			_orbit += delta * 0.05
			var away := (-_heading).rotated(Vector3.UP, _orbit * _side + 0.5 * _side)
			eye = car.global_position + away * 26.0 + Vector3.UP * 12.0
			look = target + _heading * 6.0
		"side":
			# Seitlich mitfahrend, etwas voraus, auf der Seite zur Fahrbahnmitte (dort stehen keine Bäume)
			eye = car.global_position - right * 6.0 + _heading * 1.5 + Vector3.UP * 1.1
			look = target + _heading * 1.0
		"low_front":
			# Tief vor dem Auto, Blick zurück: das Auto fährt auf die Kamera zu
			eye = car.global_position + _heading * 10.0 + right * 1.2 * _side + Vector3.UP * 0.35
			look = target + Vector3.UP * 0.1
		"bumper":
			# Vorne an der Stoßstange, Blick nach vorn
			var basis := car.global_basis
			eye = car.global_position + basis.z * (car.profile.wheelbase * 0.5 + 1.05) + basis.y * 0.15
			look = eye + basis.z * 20.0 - basis.y * 0.6
		"roadside":
			eye = _fixed_position
	# Nicht unter das Gelände
	var ground: float = get_parent().call("ground_height", eye.x, eye.z)
	var clearance := 8.0 if shot == "heli" else 0.4
	if shot != "bumper" and shot != "roadside":
		eye.y = maxf(eye.y, ground + clearance)
	camera.global_position = eye
	if eye.distance_to(look) > 0.1:
		camera.look_at(look, Vector3.UP)
	# Leichte Unschärfe hinter dem Auto (bei der Stoßstange weit weg)
	var focus := eye.distance_to(target)
	_attributes.dof_blur_far_distance = 70.0 if shot == "bumper" else focus + 12.0 + focus * 0.5
	_attributes.dof_blur_far_transition = 40.0 + focus


static func _flat(v: Vector3) -> Vector3:
	v.y = 0.0
	return v.normalized() if v.length() > 0.001 else Vector3.FORWARD


# ---------------------------------------------------------------------------
# Fahren
# ---------------------------------------------------------------------------

func _on_highway() -> bool:
	var segment := limits.place_segment() if limits else null
	return segment != null and segment.kind == RoadSegment.Kind.HIGHWAY


func _extend_route() -> void:
	_replan_timer = 1.0
	var forward := car.global_basis.z
	_route = roads.route_from(car.global_position, forward, 2500.0, true, _recent)
	_route_index = 0
	for key in roads.last_route_keys:
		if not _recent.has(key):
			_recent.append(key)
	# Die letzten paar Abschnitte merken, damit er nicht hin und her pendelt
	while _recent.size() > 16:
		_recent.remove_at(0)


func _drive(delta: float) -> void:
	_replan_timer -= delta
	if _route.size() < 10:
		if _replan_timer <= 0.0:
			_extend_route()
		if _route.size() < 10:
			# Kein Weg mehr (Ende einer Sackgasse): anhalten, dann beim Schnitt wenden; ohne
			# jede Straße in der Nähe zurück auf die nächste
			_end_wait = _end_wait + delta if car.linear_velocity.length() < 1.5 else 0.0
			if _end_wait > 1.5 and _fix == "":
				_fix = "turn" if _route.size() > 0 else "rescue"
			if _fix != "" and not _cutting:
				_cut()
			_press(0.0, 0.0, 0.6)
			return
	var here := car.global_position
	var best_distance := INF
	for i in range(_route_index, mini(_route_index + 10, _route.size())):
		var d := Vector2(_route[i].x - here.x, _route[i].z - here.z).length()
		if d < best_distance:
			best_distance = d
			_route_index = i
	var highway := _on_highway()
	# Route verloren (z. B. abgedrängt) oder bald zu Ende: neu planen (höchstens einmal pro Sekunde)
	if (best_distance > 25.0 or _route.size() - _route_index < (200 if highway else 60)) and _replan_timer <= 0.0:
		_extend_route()
		if _route.size() < 10:
			_press(0.0, 0.0, 0.5)
			return
	var speed := car.linear_velocity.length()
	var left_over := (_route.size() - 1 - _route_index) * RoadSegment.POINT_SPACING
	# Sackgasse: am Ende der Straße ausrollen, dann beim nächsten Schnitt wenden (unsichtbar
	# unter der Überblendung). Festgefahren, gekippt oder weit neben der Straße: beim Schnitt
	# zurück auf die nächste Straße.
	# (1,5 s warten: so lange wird mindestens einmal neu geplant, falls dahinter doch etwas lädt)
	_end_wait = _end_wait + delta if left_over < 20.0 and speed < 1.5 else 0.0
	if _end_wait > 1.5 and _fix == "":
		_fix = "turn"
	var in_trouble := (speed < 1.0 and left_over > 30.0) or car.global_basis.y.y < 0.85 or best_distance > 18.0
	_trouble_time = _trouble_time + delta if in_trouble else 0.0
	if _trouble_time > 4.0 and _fix == "":
		_fix = "rescue"
	if _fix != "" and not _cutting:
		_press(0.0, 0.0, 1.0)
		_cut()
		return

	# Lenken: auf einen Punkt voraus zielen, Landstraße auf der rechten Spur
	var look_ahead := maxi(int((7.0 + speed * 0.5) / RoadSegment.POINT_SPACING), 2)
	var aim := _route[mini(_route_index + look_ahead, _route.size() - 1)]
	_lane_shift = move_toward(_lane_shift, _lane_shift_target, 1.0 * delta)
	# Blinker nach dem Spurwechsel wieder aus
	if car.turn_signal != 0 and absf(_lane_shift - _lane_shift_target) < 0.1:
		car.turn_signal = 0
	var left := Vector3.UP.cross(car.global_basis.z).normalized()
	aim += left * (_lane_shift if highway else -road_lane)
	var local := car.global_transform.affine_inverse() * aim
	var aim_angle := atan2(local.x, local.z)
	var steer := clampf(aim_angle * 3.5, -1.0, 1.0)

	# Tempo: Kurven der nächsten Meter (sanft), Tempolimit, Vordermann
	var target_speed := (highway_speed_kmh if highway else road_speed_kmh) / 3.6
	if limits and limits.effective_limit > 0:
		target_speed = minf(target_speed, limits.effective_limit / 3.6)
	var lateral := highway_lateral if highway else road_lateral
	var horizon := 175 if highway else 40
	for i in range(_route_index + 3, mini(_route_index + horizon, _route.size() - 3)):
		var d1 := Vector2(_route[i].x - _route[i - 3].x, _route[i].z - _route[i - 3].z)
		var d2 := Vector2(_route[i + 3].x - _route[i].x, _route[i + 3].z - _route[i].z)
		var angle_change := absf(d1.angle_to(d2))
		if angle_change < 0.01:
			continue
		var radius := 3.0 * RoadSegment.POINT_SPACING / angle_change
		var curve_speed := maxf(sqrt(lateral * radius), 4.0)
		var distance_to_curve := (i - _route_index) * RoadSegment.POINT_SPACING
		target_speed = minf(target_speed, sqrt(curve_speed * curve_speed + 2.0 * comfort_brake * distance_to_curve))
	# Ziel liegt weit seitlich oder hinten (Wenden): langsam
	if absf(aim_angle) > 0.8:
		target_speed = minf(target_speed, 4.0)
	# Am Ende der Route (Sackgasse oder noch nichts weiter geladen): anhalten
	target_speed = minf(target_speed, sqrt(2.0 * comfort_brake * maxf(left_over - 8.0, 0.0)))
	target_speed = _follow(speed, target_speed, highway)
	var throttle := clampf((target_speed - speed) * 0.3, 0.0, 1.0)
	var brake := clampf((speed - target_speed - 0.8) * 0.12, 0.0, 1.0)
	_press(steer, throttle, brake)


func _press(steer: float, throttle: float, brake: float) -> void:
	if steer > 0.0:
		Input.action_press("steer_left", steer)
		Input.action_release("steer_right")
	else:
		Input.action_press("steer_right", -steer)
		Input.action_release("steer_left")
	if throttle > 0.01:
		Input.action_press("accelerate", throttle)
	else:
		Input.action_release("accelerate")
	# Fast im Stand: Handbremse statt Bremse (Bremse im Stand = Rückwärtsgang)
	var hold := brake > 0.01 and car.linear_velocity.length() < 1.0
	if brake > 0.01 and not hold:
		Input.action_press("brake", brake)
	else:
		Input.action_release("brake")
	if hold:
		Input.action_press("handbrake")
	else:
		Input.action_release("handbrake")


## Abstand halten wie Tempomat und KI (Mindestabstand + 2 s), auf der Autobahn links überholen,
## wenn der Vordermann langsamer ist und links frei ist, danach wieder rechts
func _follow(speed: float, target_speed: float, highway: bool) -> float:
	if traffic == null:
		return target_speed
	var forward := car.global_basis.z
	var curvature := car.angular_velocity.y / speed if speed > 5.0 else 0.0
	var leader := traffic.leader_ahead(car.global_position, forward, 4.6, 200.0, 0.0, curvature)
	if highway:
		var slower: bool = not leader.is_empty() and (leader[1] as float) < target_speed - 3.0 and (leader[0] as float) < 120.0
		if _lane_shift_target == 0.0 and slower and traffic.lane_free_at(car.global_position, forward, speed, -3.75, 60.0, 45.0):
			_lane_shift_target = 3.75
			car.turn_signal = 1
		elif _lane_shift_target > 0.0 and absf(_lane_shift - _lane_shift_target) < 0.2 \
				and traffic.lane_free_at(car.global_position, forward, speed, 3.75, 80.0, 30.0):
			_lane_shift_target = 0.0
			car.turn_signal = -1
	else:
		_lane_shift_target = 0.0
	if leader.is_empty():
		return target_speed
	var gap: float = leader[0]
	var wanted := Traffic.MIN_GAP + speed * 2.0
	return minf(target_speed, maxf((leader[1] as float) + (gap - wanted) * 0.3, 0.0))
