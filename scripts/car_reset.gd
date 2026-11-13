class_name CarReset
extends Node
## Reset (Taste R) und Sicherheitsnetz.
##
## Das Spiel merkt sich laufend sichere Stellen: alle vier Räder auf einer Fahrbahn (nicht auf
## dem Bankett), Auto aufrecht, nicht im Portal eines Tunnels und nicht am Rand einer Brücke.
## Beim Reset:
## - Steht das Auto auf der Straße und ist (fast) still, wird es nur am Platz aufgerichtet.
## - Sonst (Graben, Böschung, Wasser, irgendwo im Gelände) geht es ein paar Meter vor die Stelle
##   zurück, an der es die Straße verlassen hat: in Fahrtrichtung der Straße und ohne Tempo.
## Danach ist der Reset 3 s gesperrt (sonst kommt man durch schnelles Drücken in die Luft).
## Sicherheitsnetz: Fällt das Auto unter das Gelände (unter ihm ist gar nichts mehr), geht es
## sofort auf die letzte sichere Stelle. Der Wasser-Manager nutzt back_to_road() auch.

@export var car: Car
@export var roads: RoadNetwork
## So lange ist der Reset nach einem Reset gesperrt (Sekunden)
@export var cooldown: float = 3.0
## Abstand der gemerkten Stellen (Meter) und wie viele es höchstens sind (80 × 4 m = 320 m)
@export var spot_spacing: float = 4.0
@export var spot_count: int = 80
## So weit vor der Stelle, an der man die Straße verlassen hat, setzt der Reset das Auto ab (Meter)
@export var back_distance: float = 10.0
## Darunter (m/s) gilt das Auto als stehend: dann reicht Aufrichten am Platz
@export var upright_speed: float = 3.0
## So hoch über der Fahrbahn wird das Auto abgesetzt (fällt dann sanft auf die Räder)
@export var drop_height: float = 0.6
## Mindestabstand zum Fahrbahnrand für eine sichere Stelle (auf Brücken doppelt)
@export var edge_margin: float = 0.6

## Restzeit der Sperre (Sekunden)
var cooldown_left: float = 0.0
## Gemerkte sichere Stellen (Transform3D: auf der Fahrbahn, Blick in Fahrtrichtung der Straße)
var _spots: Array[Transform3D] = []
var _check_timer: float = 0.0
var _fall_timer: float = 0.0
var _blocked_shown: bool = false


func _ready() -> void:
	if car:
		car.external_reset = true


func _physics_process(delta: float) -> void:
	if car == null or car.freeze:
		return
	cooldown_left = maxf(cooldown_left - delta, 0.0)
	if cooldown_left == 0.0:
		_blocked_shown = false
	if Input.is_action_just_pressed("reset_car"):
		request_reset()
	_check_timer -= delta
	if _check_timer <= 0.0:
		_check_timer = 0.1
		_remember_spot()
	# Sicherheitsnetz: unter dem Auto ist gar nichts mehr (durchs Gelände gefallen)
	_fall_timer -= delta
	if _fall_timer <= 0.0:
		_fall_timer = 0.25
		if car.linear_velocity.y < -3.0 and _ground_below(2500.0).is_empty():
			print("Auto unter das Gelände gefallen bei %s: zurück auf die Straße" % car.global_position.round())
			back_to_road()


## Taste R: aufrichten (auf der Straße, im Stand) oder zurück auf die Straße
func request_reset() -> void:
	if cooldown_left > 0.0:
		if not _blocked_shown:
			_blocked_shown = true
			Toasts.post(get_tree(), "warning", "Reset gesperrt", "In %d s wieder möglich" % ceili(cooldown_left))
		return
	var ground := _ground_below(4.0)
	var on_road := not ground.is_empty() and _is_road(ground["collider"])
	if on_road and car.linear_velocity.length() < upright_speed:
		# Am Platz aufrichten: Blickrichtung bleibt, etwas angehoben
		var forward := car.global_basis.z
		var yaw := atan2(forward.x, forward.z)
		car.teleport(Transform3D(Basis(Vector3.UP, yaw), (ground["position"] as Vector3) + Vector3.UP * (drop_height + 0.4)))
		cooldown_left = cooldown
		Toasts.post(get_tree(), "check", "Aufgerichtet", "Nächster Reset in %d s" % roundi(cooldown))
		return
	back_to_road()
	Toasts.post(get_tree(), "pin", "Zurück auf die Straße", "Nächster Reset in %d s" % roundi(cooldown))


## Zurück auf die Straße: ein paar Meter vor die Stelle, an der das Auto sie verlassen hat
func back_to_road() -> void:
	cooldown_left = cooldown
	if _spots.is_empty():
		var result := roads.nearest_road_transform(car.global_position, car.global_basis.z)
		if result["found"]:
			car.teleport(result["transform"])
		return
	var last := _spots[_spots.size() - 1]
	var pick := 0
	for k in range(_spots.size() - 1, -1, -1):
		if _spots[k].origin.distance_to(last.origin) >= back_distance:
			pick = k
			break
	var spot := _spots[pick]
	# Neuere Stellen vergessen: Ein zweiter Reset geht noch weiter zurück
	_spots.resize(pick + 1)
	car.teleport(Transform3D(spot.basis, spot.origin + Vector3.UP * drop_height))


## Steht das Auto gerade sicher auf einer Fahrbahn? Dann diese Stelle merken.
func _remember_spot() -> void:
	if car.global_basis.y.y < 0.95:
		return
	var segment: RoadSegment = null
	for wheel in car.corner_wheels():
		if not wheel.is_in_contact():
			return
		var body := wheel.get_contact_body()
		if body == null or not body.has_meta("road_segment"):
			return
		segment = body.get_meta("road_segment")
	var here := car.global_position
	# Nicht im Portal eines Tunnels (dort ist die Fahrbahn halb überdacht)
	var cover := roads.tunnel_cover(here)
	if cover > 0.02 and cover < 0.98:
		return
	# Auf der Fahrbahn, nicht auf dem Bankett, nicht am Rand einer Brücke
	var i := _nearest_index(segment, here)
	var p := segment.points[i]
	var forward := segment.direction_at(i)
	var left := Vector3.UP.cross(forward).normalized()
	var lateral := (here - p).dot(left)
	var side := 1.0 if lateral > 0.0 else -1.0
	var margin := edge_margin * (2.0 if segment.bridge[i] == 1 else 1.0)
	if absf(lateral) > segment.road_width * 0.5 + segment.extra_at(i, side) - margin:
		return
	if not _spots.is_empty() and _spots[_spots.size() - 1].origin.distance_to(here) < spot_spacing:
		return
	# In Fahrtrichtung der Straße, so wie das Auto gerade fährt
	if forward.dot(car.global_basis.z) < 0.0:
		forward = -forward
	forward.y = 0.0
	var spot := Transform3D(Basis(Vector3.UP, atan2(forward.x, forward.z)), here)
	_spots.append(spot)
	if _spots.size() > spot_count:
		_spots.remove_at(0)


func _nearest_index(segment: RoadSegment, p: Vector3) -> int:
	var best := 0
	var best_d := INF
	for i in segment.points.size():
		var d := Vector2(segment.points[i].x - p.x, segment.points[i].z - p.z).length_squared()
		if d < best_d:
			best_d = d
			best = i
	return best


## Strahl vom Auto senkrecht nach unten (ohne das Auto selbst). Leer = nichts getroffen.
func _ground_below(depth: float) -> Dictionary:
	var from := car.global_position + Vector3.UP * 0.5
	var query := PhysicsRayQueryParameters3D.create(from, from - Vector3.UP * (depth + 0.5))
	query.exclude = [car.get_rid()]
	return car.get_world_3d().direct_space_state.intersect_ray(query)


func _is_road(collider: Object) -> bool:
	return collider != null and (collider.has_meta("road_segment") or collider.has_meta("junction"))
