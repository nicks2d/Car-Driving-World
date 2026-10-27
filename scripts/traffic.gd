class_name Traffic
extends Node3D
## Verkehr: KI-Autos auf Landstraßen und Autobahnen. Sie fahren kinematisch (ohne Fahrphysik)
## auf ihrer Spur entlang der Straßen-Mittellinien: Landstraße rechts, Autobahn rechte Spur
## (Lkw immer), zum Überholen links mit Blinker. Abstand halten und Bremsen vor langsameren
## Autos und vor dem Spieler regelt das „Intelligent Driver Model“ (IDM). In Orten 50 km/h, in
## Kurven so schnell, wie es die Querbeschleunigung erlaubt. An Anschlussstellen und
## Raststätten fahren manche ab, an Orten mit Zubringer manche auf die Autobahn.
##
## Ein Weg besteht aus Stücken (Leg): Straßenabschnitt, Richtung, von/bis (Meter) und Spur.
## Am Ende eines Stücks wählt das Auto das nächste (an Kreuzungen zufällig) und fährt eine
## kurze Übergangskurve dorthin. Autos entstehen und verschwinden außer Sicht (weit weg oder
## hinter der Kamera). Fahrzeuge sind im Code gebaut (Kästchen), nachts mit Licht.
## Stößt der Spieler mit einem zusammen, bleibt es mit Warnblinker stehen und fährt nach ein
## paar Sekunden weiter.

@export var roads: RoadNetwork
@export var car: Car
@export var camera: Camera3D
@export var day_night: DayNight
@export var debug_tools: DebugTools
## Dichte: 0 = aus, 0.5 = wenig, 1 = normal (Einstellungen)
@export_range(0.0, 1.0) var density: float = 1.0
@export var max_cars: int = 25
## Ein Auto pro so viele Meter je Fahrtrichtung (Landstraße, Autobahn)
@export var road_spacing: float = 2500.0
@export var highway_spacing: float = 450.0
## Autos entstehen in diesem Abstand vom Spieler (näher als spawn_hidden nur hinter der Kamera)
@export var spawn_min: float = 280.0
@export var spawn_hidden: float = 650.0
@export var spawn_max: float = 1050.0
@export var despawn_distance: float = 1300.0
## Bis hierher werfen KI-Autos Schatten, haben eine Kollision, leuchten nachts mit echtem Licht
@export var shadow_distance: float = 120.0
@export var body_distance: float = 160.0
@export var headlight_count: int = 3
@export var headlight_distance: float = 150.0
## Wahrscheinlichkeiten: an einer Anschlussstelle abfahren, an einer Raststätte rausfahren,
## an einem Ort mit Zubringer auf die Autobahn fahren
@export var exit_chance: float = 0.15
@export var rest_chance: float = 0.15
@export var entry_chance: float = 0.3
## Nach einem Zusammenstoß so lange stehen bleiben (Sekunden)
@export var crash_wait: float = 6.0

## Spuren (Meter rechts der Mittellinie): Landstraße, Autobahn rechts/links, Rampenanfang neben
## der Autobahn, Fahrgasse der Raststätte
const ROAD_LANE: float = 2.25
const HW_RIGHT: float = 8.375
const HW_LEFT: float = 4.625
const HW_RAMP: float = 15.55
const LOT_LANE: float = -18.5
## Tempo in Orten und Kurven
const VILLAGE_SPEED: float = 50.0 / 3.6
const VILLAGE_RADIUS: float = 170.0
const LATERAL_ACCEL: float = 2.6
## Spurwechsel: so schnell seitlich (m/s)
const LANE_RATE: float = 1.3
## IDM: Mindestabstand, Zeitlücke, angenehme Verzögerung
const MIN_GAP: float = 4.0
const TIME_GAP: float = 1.4
const COMFORT_BRAKE: float = 3.0
const BLINK_HZ: float = 1.5

enum Kind { ROAD, HIGHWAY, RAMP, CONNECTOR, LOT }

## Fahrzeugtypen: Länge, Breite, Beschleunigung, Anteil auf Landstraße / Autobahn
const TYPES := {
	"limousine": {"length": 4.7, "width": 1.82, "accel": 2.0, "road": 34, "highway": 30},
	"kombi": {"length": 4.8, "width": 1.84, "accel": 1.9, "road": 26, "highway": 22},
	"suv": {"length": 4.75, "width": 1.95, "accel": 1.8, "road": 20, "highway": 16},
	"transporter": {"length": 5.4, "width": 2.0, "accel": 1.3, "road": 14, "highway": 10},
	"lkw": {"length": 12.7, "width": 2.5, "accel": 0.7, "road": 6, "highway": 22},
}
const PAINTS: Array[Color] = [Color("#E9E9E6"), Color("#1B1C1F"), Color("#9EA3A8"), Color("#4A4E54"),
	Color("#1F3A66"), Color("#8E1A1A"), Color("#2C5D8C"), Color("#2F4A35"), Color("#C8B89A"), Color("#5C2A3A")]
const SURFACES: Array[String] = ["paint", "glass", "dark", "white", "head", "tail", "ind_l", "ind_r"]


## Ein Stück Weg auf einem Abschnitt
class Leg:
	var key: Vector3i
	var segment: RoadSegment
	var kind: int
	var forward: bool
	var from: float
	var to: float
	var lateral: float


class TrafficCar:
	var node: Node3D
	var mesh: MeshInstance3D
	var light: SpotLight3D
	var body: AnimatableBody3D
	var type: String
	var length: float
	var width: float
	var truck: bool
	var accel: float
	## Wunschtempo auf Landstraße und Autobahn (m/s); schnelle Autos bleiben gern links
	var road_speed: float
	var highway_speed: float
	var fast: bool
	var leg: Leg
	var s: float = 0.0
	var lateral: float = 0.0
	var lane_target: float = 0.0
	var speed: float = 0.0
	var plan: Array[Leg] = []
	## Übergang zwischen zwei Stücken: Punkte, Länge, gefahrene Meter
	var curve := PackedVector3Array()
	var curve_length: float = 0.0
	var curve_t: float = 0.0
	var next: Leg
	var position := Vector3.ZERO
	var forward := Vector3.FORWARD
	var blink: int = 0
	var blink_timer: float = 0.0
	var hazard: bool = false
	var crash_timer: float = 0.0
	var braking: bool = false
	var stuck: bool = false
	var decide_timer: float = 0.0
	var right_free_time: float = 0.0
	## Zuletzt gesetzte Materialien (nur bei Änderung neu setzen)
	var shown_brake: bool = false
	var shown_left: bool = false
	var shown_right: bool = false


var _cars: Array[TrafficCar] = []
var _rng := RandomNumberGenerator.new()
var _spawn_timer: float = 0.0
var _count_timer: float = 0.0
var _light_timer: float = 0.0
var _wanted: int = 0
var _blink_clock: float = 0.0
var _was_frozen: bool = true
var _fill_timer: float = 0.0
var _ghost: bool = false
## Fahrzeug-Meshes je Typ und die Lage der Flächen darin
var _meshes: Dictionary = {}  # Typ -> ArrayMesh
var _surface_index: Dictionary = {}  # Typ -> {Flächenname: Nummer}
var _materials: Dictionary = {}


func _ready() -> void:
	_rng.seed = 4711
	# Benchmark: der Autopilot weicht nicht aus, deshalb ohne Kollision
	_ghost = debug_tools != null and debug_tools.is_benchmark()
	if debug_tools != null and debug_tools.traffic_density >= 0.0:
		density = debug_tools.traffic_density


## Dichte ändern (Einstellungen): 0 = aus, 0.5 = wenig, 1 = normal
func set_density(value: float) -> void:
	density = value
	if density <= 0.0:
		for traffic_car in _cars.duplicate():
			_remove(traffic_car)


func car_count() -> int:
	return _cars.size()


func _physics_process(delta: float) -> void:
	if roads == null or roads.world_gen == null or car == null:
		return
	_blink_clock += delta
	# Nach dem Laden (Ladebildschirm) dürfen Autos auch in der Nähe entstehen
	if car.freeze:
		_was_frozen = true
		return
	if _was_frozen:
		_was_frozen = false
		_fill_timer = 1.5
	_fill_timer = maxf(_fill_timer - delta, 0.0)
	_count_timer -= delta
	if _count_timer <= 0.0:
		_count_timer = 2.0
		_wanted = _wanted_count()
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = 0.1 if _fill_timer > 0.0 else 0.4
		if _cars.size() < _wanted:
			_try_spawn()
	for traffic_car in _cars.duplicate():
		_drive(traffic_car, delta)
	_update_looks(delta)


# ---------------------------------------------------------------------------
# Entstehen und Verschwinden
# ---------------------------------------------------------------------------

## Wie viele Autos sollten unterwegs sein? Nach Straßenlänge im Umkreis von 1 km.
func _wanted_count() -> int:
	if density <= 0.0:
		return 0
	var p := car.global_position
	var road_length := 0.0
	var highway_length := 0.0
	var reach := 1000.0
	for pair: Array in roads.loaded_segments(Rect2(p.x - reach, p.z - reach, reach * 2.0, reach * 2.0)):
		var key: Vector3i = pair[0]
		if not RoadNetwork.is_road_key(key) and not RoadNetwork.is_highway_key(key):
			continue
		var segment: RoadSegment = pair[1]
		var inside := 0
		for i in range(0, segment.points.size(), 4):
			if Vector2(segment.points[i].x - p.x, segment.points[i].z - p.z).length() < reach:
				inside += 1
		var length := inside * 4.0 * RoadSegment.POINT_SPACING
		if RoadNetwork.is_road_key(key):
			road_length += length
		else:
			highway_length += length
	var wanted := (road_length * 2.0 / road_spacing + highway_length * 2.0 / highway_spacing) * density
	return mini(roundi(wanted), max_cars)


func _try_spawn() -> void:
	var p := car.global_position
	var options: Array = []
	var total := 0.0
	for pair: Array in roads.loaded_segments(Rect2(p.x - spawn_max, p.z - spawn_max, spawn_max * 2.0, spawn_max * 2.0)):
		var key: Vector3i = pair[0]
		if not RoadNetwork.is_road_key(key) and not RoadNetwork.is_highway_key(key):
			continue
		var segment: RoadSegment = pair[1]
		# Autobahn zählt mehr (dichterer Verkehr)
		var weight := segment.total_length() * (2.8 if RoadNetwork.is_highway_key(key) else 1.0)
		options.append([key, segment, weight])
		total += weight
	if options.is_empty():
		return
	for attempt in 6:
		var pick := _rng.randf() * total
		var chosen: Array = options[0]
		for option: Array in options:
			pick -= option[2]
			if pick <= 0.0:
				chosen = option
				break
		var segment: RoadSegment = chosen[1]
		var key: Vector3i = chosen[0]
		var highway := RoadNetwork.is_highway_key(key)
		var length := segment.total_length()
		if length < 120.0:
			continue
		var leg := Leg.new()
		leg.key = key
		leg.segment = segment
		leg.kind = Kind.HIGHWAY if highway else Kind.ROAD
		leg.forward = _rng.randf() < 0.5
		leg.from = 0.0 if highway else 30.0
		leg.to = length if highway else length - 26.0
		var s := _rng.randf_range(leg.from + 10.0, leg.to - 10.0)
		# Beim ersten Füllen (Ladebildschirm) gern in der Nähe des Spielers
		if _fill_timer > 0.0:
			var near := _s_near(segment, leg.forward, Vector2(p.x, p.z))
			var offset := _rng.randf_range(60.0, 400.0) * (1.0 if _rng.randf() < 0.5 else -1.0)
			s = clampf(near + offset, leg.from + 10.0, leg.to - 10.0)
		var type := _pick_type(highway)
		var fast := highway and type != "lkw" and type != "transporter" and _rng.randf() < 0.12
		leg.lateral = HW_LEFT if fast else (HW_RIGHT if highway else ROAD_LANE)
		var pose := _pose(leg, s, leg.lateral)
		var at: Vector3 = pose[0]
		var distance := at.distance_to(p)
		var min_distance := 60.0 if _fill_timer > 0.0 else spawn_min
		if distance < min_distance or distance > spawn_max:
			continue
		if _fill_timer <= 0.0 and distance < spawn_hidden and _in_view(at):
			continue
		var crowded := false
		for other in _cars:
			if other.position.distance_to(at) < 45.0:
				crowded = true
				break
		if crowded:
			continue
		_spawn(type, leg, s, fast)
		return


func _pick_type(highway: bool) -> String:
	var total := 0
	for type: String in TYPES:
		total += TYPES[type]["highway" if highway else "road"]
	var pick := _rng.randi_range(0, total - 1)
	for type: String in TYPES:
		pick -= TYPES[type]["highway" if highway else "road"]
		if pick < 0:
			return type
	return "limousine"


## Ist der Punkt vor der Kamera (ungefähr im Bild)?
func _in_view(at: Vector3) -> bool:
	if camera == null:
		return false
	var to := at - camera.global_position
	return to.normalized().dot(-camera.global_basis.z) > 0.25


func _spawn(type: String, leg: Leg, s: float, fast: bool) -> void:
	var info: Dictionary = TYPES[type]
	var traffic_car := TrafficCar.new()
	traffic_car.type = type
	traffic_car.length = info["length"]
	traffic_car.width = info["width"]
	traffic_car.accel = info["accel"]
	traffic_car.truck = type == "lkw"
	traffic_car.fast = fast
	match type:
		"lkw":
			traffic_car.road_speed = _rng.randf_range(62.0, 80.0) / 3.6
			traffic_car.highway_speed = _rng.randf_range(82.0, 89.0) / 3.6
		"transporter":
			traffic_car.road_speed = _rng.randf_range(62.0, 90.0) / 3.6
			traffic_car.highway_speed = _rng.randf_range(105.0, 135.0) / 3.6
		_:
			traffic_car.road_speed = _rng.randf_range(65.0, 100.0) / 3.6
			traffic_car.highway_speed = _rng.randf_range(185.0, 230.0) / 3.6 if fast \
				else _rng.randf_range(110.0, 175.0) / 3.6
	traffic_car.leg = leg
	traffic_car.s = s
	traffic_car.lateral = leg.lateral
	traffic_car.lane_target = leg.lateral
	traffic_car.node = Node3D.new()
	traffic_car.mesh = MeshInstance3D.new()
	traffic_car.mesh.mesh = _vehicle_mesh(type)
	var paint := PAINTS[_rng.randi() % PAINTS.size()]
	if type == "transporter" and _rng.randf() < 0.6:
		paint = PAINTS[0]
	traffic_car.mesh.set_surface_override_material(_surface_index[type]["paint"], _paint_material(paint))
	traffic_car.node.add_child(traffic_car.mesh)
	# Scheinwerfer-Licht (nur die nächsten paar nachts eingeschaltet)
	traffic_car.light = SpotLight3D.new()
	traffic_car.light.light_color = Color(1.0, 0.95, 0.85)
	traffic_car.light.spot_range = 45.0
	traffic_car.light.spot_angle = 32.0
	traffic_car.light.light_energy = 2.5
	traffic_car.light.shadow_enabled = false
	traffic_car.light.visible = false
	traffic_car.light.position = Vector3(0.0, 0.8, traffic_car.length * 0.5 + 0.2)
	# Licht zeigt nach -Z, das Auto nach +Z: umdrehen und leicht nach unten
	traffic_car.light.rotation = Vector3(deg_to_rad(-6.0), PI, 0.0)
	traffic_car.node.add_child(traffic_car.light)
	add_child(traffic_car.node)
	var pose := _pose(leg, s, leg.lateral)
	traffic_car.position = pose[0]
	traffic_car.forward = pose[1]
	traffic_car.speed = _desired_speed(traffic_car) * 0.9
	if leg.kind == Kind.HIGHWAY:
		_plan_highway_exit(traffic_car)
	_place(traffic_car)
	traffic_car.node.reset_physics_interpolation()
	_cars.append(traffic_car)


func _remove(traffic_car: TrafficCar) -> void:
	if traffic_car.body:
		traffic_car.body.queue_free()
	traffic_car.node.queue_free()
	_cars.erase(traffic_car)


# ---------------------------------------------------------------------------
# Fahren
# ---------------------------------------------------------------------------

func _drive(c: TrafficCar, delta: float) -> void:
	var player := car.global_position
	var distance := c.position.distance_to(player)
	# Außer Sicht verschwinden: weit weg, hinter der Kamera oder Straße nicht mehr geladen
	var gone := roads.edge_segment(c.leg.key) != c.leg.segment
	if gone or distance > despawn_distance or (distance > spawn_hidden and not _in_view(c.position)) \
			or (c.stuck and not _in_view(c.position)):
		_remove(c)
		return
	if density <= 0.0:
		_remove(c)
		return
	# Zusammenstoß mit dem Spieler?
	if distance < c.length + 6.0:
		_check_crash(c, player)
	var accel := _acceleration(c)
	if c.crash_timer > 0.0:
		c.crash_timer -= delta
		accel = -9.0
		if c.crash_timer <= 0.0:
			if distance < 8.0:
				c.crash_timer = 1.0
			else:
				c.hazard = false
	c.braking = accel < -1.0 or c.speed < 0.5
	c.speed = maxf(c.speed + accel * delta, 0.0)
	_decide_lane(c, delta)
	var step := c.speed * delta
	if c.next != null:
		# Übergangskurve zum nächsten Stück
		c.curve_t += step
		if c.curve_t >= c.curve_length:
			_enter(c, c.next, c.next.from + c.curve_t - c.curve_length)
	else:
		c.s += step
		if c.s >= c.leg.to:
			_leave_leg(c, c.s - c.leg.to)
	if c.lateral != c.lane_target:
		c.lateral = move_toward(c.lateral, c.lane_target, LANE_RATE * delta * clampf(c.speed / 15.0, 0.3, 1.0))
	if c.blink != 0 and c.lateral == c.lane_target:
		c.blink_timer -= delta
		if c.blink_timer <= 0.0:
			c.blink = 0
	_update_pose(c)
	_place(c)


## Lage aus Stück oder Übergangskurve
func _update_pose(c: TrafficCar) -> void:
	if c.next != null and c.curve.size() > 1:
		var f := clampf(c.curve_t / c.curve_length, 0.0, 1.0) * (c.curve.size() - 1)
		var i := mini(floori(f), c.curve.size() - 2)
		var a := c.curve[i]
		var b := c.curve[i + 1]
		c.position = a.lerp(b, f - i)
		if b.distance_to(a) > 0.01:
			c.forward = (b - a).normalized()
		return
	var pose := _pose(c.leg, c.s, c.lateral)
	c.position = pose[0]
	c.forward = pose[1]


func _place(c: TrafficCar) -> void:
	var flat := Vector3(c.forward.x, 0.0, c.forward.z)
	if flat.length() < 0.01:
		return
	var facing := Basis.looking_at(-c.forward, Vector3.UP)
	c.node.global_transform = Transform3D(facing, c.position)
	if c.body:
		c.body.global_transform = Transform3D(facing, c.position + Vector3.UP * _body_height(c) * 0.5)


func _body_height(c: TrafficCar) -> float:
	match c.type:
		"lkw":
			return 3.9
		"transporter":
			return 2.6
		"suv":
			return 1.75
	return 1.45


## Ende eines Stücks: nächstes wählen und eine kurze Kurve dorthin legen
func _leave_leg(c: TrafficCar, overflow: float) -> void:
	var next: Leg = c.plan.pop_front() if not c.plan.is_empty() else _choose_next(c)
	if next == null:
		# Sackgasse (oder Straße noch nicht da): stehen bleiben, verschwindet außer Sicht
		c.s = c.leg.to
		c.speed = 0.0
		c.stuck = true
		return
	var start := _pose(c.leg, c.leg.to, c.lateral)
	# Von Autobahn zu Autobahn auf derselben Spur weiter
	if next.kind == Kind.HIGHWAY and c.leg.kind == Kind.HIGHWAY:
		next.lateral = c.lateral
	var end := _pose(next, next.from, next.lateral)
	var p0: Vector3 = start[0]
	var p1: Vector3 = end[0]
	var gap := p0.distance_to(p1)
	if gap < 1.0:
		_enter(c, next, next.from + overflow)
		return
	# Hermite-Kurve mit den Fahrtrichtungen an beiden Enden
	var d0: Vector3 = start[1]
	var d1: Vector3 = end[1]
	var tangent := gap * 0.8
	c.curve = PackedVector3Array()
	c.curve_length = 0.0
	for k in 13:
		var t := k / 12.0
		var h00 := 2.0 * t * t * t - 3.0 * t * t + 1.0
		var h10 := t * t * t - 2.0 * t * t + t
		var h01 := -2.0 * t * t * t + 3.0 * t * t
		var h11 := t * t * t - t * t
		var point := p0 * h00 + d0 * tangent * h10 + p1 * h01 + d1 * tangent * h11
		if k > 0:
			c.curve_length += point.distance_to(c.curve[k - 1])
		c.curve.append(point)
	c.next = next
	c.curve_t = overflow


func _enter(c: TrafficCar, leg: Leg, s: float) -> void:
	var previous := c.leg
	c.leg = leg
	c.s = s
	c.next = null
	c.curve = PackedVector3Array()
	if leg.kind == Kind.HIGHWAY:
		# Einfädeln von der Rampe: von neben der Fahrbahn auf die rechte Spur
		if previous.kind != Kind.HIGHWAY:
			c.lateral = leg.lateral
			c.lane_target = HW_RIGHT
			c.blink = 1
			c.blink_timer = 1.0
		_plan_highway_exit(c)
	elif previous.kind != Kind.HIGHWAY or leg.kind != Kind.HIGHWAY:
		c.lateral = leg.lateral
		c.lane_target = leg.lateral


## Nächstes Stück nach dem aktuellen (ohne festen Plan)
func _choose_next(c: TrafficCar) -> Leg:
	var leg := c.leg
	match leg.kind:
		Kind.HIGHWAY:
			var axis := RoadNetwork.highway_axis(leg.key)
			var dir := 1 if leg.forward else -1
			var at := leg.key.x + 1 if leg.forward else leg.key.x
			return _highway_leg(axis, leg.key.y, at, dir, -1.0)
		Kind.ROAD:
			var cell := roads.edge_end_cell(leg.key) if leg.forward else Vector2i(leg.key.x, leg.key.y)
			return _leg_from_place(c, cell)
		Kind.CONNECTOR:
			if not leg.forward:
				var interchange := roads.highways.interchange_at(RoadNetwork.highway_axis(leg.key), leg.key.y, leg.key.x)
				if interchange.is_empty():
					return null
				return _leg_from_place(c, interchange["cell"])
	return null


## Autobahn-Stück ab Stützpunkt at in Richtung dir (ab from Metern, -1 = am Anfang)
func _highway_leg(axis: int, line: int, at: int, dir: int, from_point: float) -> Leg:
	var key := Vector3i(at, line, 2 + axis) if dir > 0 else Vector3i(at - 1, line, 2 + axis)
	var segment := roads.edge_segment(key)
	if segment == null:
		return null
	var leg := Leg.new()
	leg.key = key
	leg.segment = segment
	leg.kind = Kind.HIGHWAY
	leg.forward = dir > 0
	leg.from = maxf(from_point, 0.0)
	leg.to = segment.total_length()
	leg.lateral = HW_RIGHT
	return leg


## An einem Ort: zufällig eine der anderen Straßen nehmen (oder über den Zubringer auf die
## Autobahn). Sackgasse: umdrehen.
func _leg_from_place(c: TrafficCar, cell: Vector2i) -> Leg:
	var junction := roads.junction_at(cell)
	if junction == null:
		return null
	var options: Array[Leg] = []
	var entry_options: Array = []
	for arm: Array in junction.arms:
		var segment: RoadSegment = arm[0]
		if segment == c.leg.segment:
			continue
		var key := segment.key
		if RoadNetwork.is_road_key(key):
			var leg := Leg.new()
			leg.key = key
			leg.segment = segment
			leg.kind = Kind.ROAD
			leg.forward = arm[1]
			leg.from = junction.radius + 2.0
			leg.to = segment.total_length() - 26.0
			leg.lateral = ROAD_LANE
			if leg.to > leg.from + 10.0:
				options.append(leg)
		elif RoadNetwork.is_interchange_key(key) and RoadNetwork.interchange_part(key) == 0:
			entry_options.append([key, segment, junction.radius])
	if not entry_options.is_empty() and (options.is_empty() or _rng.randf() < entry_chance):
		var entry: Array = entry_options[0]
		var legs := _entry_legs(entry[0], entry[1], entry[2])
		if not legs.is_empty():
			c.plan = legs.slice(1)
			return legs[0]
	if options.is_empty():
		# Umdrehen
		var back := Leg.new()
		back.key = c.leg.key
		back.segment = c.leg.segment
		back.kind = c.leg.kind
		back.forward = not c.leg.forward
		back.from = junction.radius + 2.0
		back.to = c.leg.segment.total_length() - 26.0
		back.lateral = c.leg.lateral
		return back
	return options[_rng.randi() % options.size()]


## Vom Ort über den Zubringer, die Auffahrt auf die Autobahn (zufällige Richtung)
func _entry_legs(connector_key: Vector3i, connector: RoadSegment, radius: float) -> Array[Leg]:
	var result: Array[Leg] = []
	var axis := RoadNetwork.highway_axis(connector_key)
	var line := connector_key.y
	var k := connector_key.x
	var dir := 1 if _rng.randf() < 0.5 else -1
	var ramp_key := RoadNetwork.interchange_key(axis, line, k, 4 if dir > 0 else 2)
	var ramp := roads.edge_segment(ramp_key)
	if ramp == null:
		return result
	var ends := roads.ramp_ends(axis, line, k, 4 if dir > 0 else 2)
	var first := Leg.new()
	first.key = connector_key
	first.segment = connector
	first.kind = Kind.CONNECTOR
	first.forward = true
	first.from = radius + 2.0
	first.to = _s_near(connector, true, ends[0])
	first.lateral = ROAD_LANE
	if first.to < first.from + 5.0:
		return result
	var on_ramp := _ramp_leg(ramp_key, ramp)
	var highway_step := _highway_leg(axis, line, k, dir, -1.0)
	if highway_step == null:
		return result
	highway_step.from = _s_near(highway_step.segment, highway_step.forward, ends[1])
	highway_step.lateral = HW_RAMP
	result.append(first)
	result.append(on_ramp)
	result.append(highway_step)
	return result


func _ramp_leg(key: Vector3i, segment: RoadSegment) -> Leg:
	var leg := Leg.new()
	leg.key = key
	leg.segment = segment
	leg.kind = Kind.RAMP
	leg.forward = true
	leg.from = 0.0
	leg.to = segment.total_length()
	leg.lateral = 0.0
	return leg


## Beim Einfahren in ein Autobahn-Stück: an seinem Ende abfahren (Anschlussstelle) oder
## rausfahren (Raststätte)? Dann endet das Stück am Beginn der Ausfahrt.
func _plan_highway_exit(c: TrafficCar) -> void:
	var leg := c.leg
	var axis := RoadNetwork.highway_axis(leg.key)
	var line := leg.key.y
	var dir := 1 if leg.forward else -1
	var at := leg.key.x + 1 if leg.forward else leg.key.x
	var exit_ramp: Array = []  # [Schlüssel, Anfang x/z]
	var after: Array[Leg] = []
	var rest := roads.highways.rest_area_at(axis, line, at, dir)
	if not rest.is_empty() and _rng.randf() < rest_chance:
		var exit_key := RoadNetwork.rest_key(axis, line, at, dir, 1)
		var lot_key := RoadNetwork.rest_key(axis, line, at, dir, 0)
		var entry_key := RoadNetwork.rest_key(axis, line, at, dir, 2)
		var exit_segment := roads.edge_segment(exit_key)
		var lot := roads.edge_segment(lot_key)
		var entry := roads.edge_segment(entry_key)
		var onward := _highway_leg(axis, line, at, dir, -1.0)
		if exit_segment and lot and entry and onward:
			var lot_leg := _ramp_leg(lot_key, lot)
			lot_leg.kind = Kind.LOT
			lot_leg.lateral = LOT_LANE
			onward.from = _s_near(onward.segment, onward.forward, roads.rest_ends(axis, line, at, dir, 2)[1])
			onward.lateral = HW_RAMP
			after = [_ramp_leg(exit_key, exit_segment), lot_leg, _ramp_leg(entry_key, entry), onward]
			exit_ramp = [exit_key, roads.rest_ends(axis, line, at, dir, 1)[0]]
	elif not c.truck or _rng.randf() < 0.5:
		var interchange := roads.highways.interchange_at(axis, line, at)
		if not interchange.is_empty() and _rng.randf() < exit_chance:
			var part := 3 if dir > 0 else 1
			var exit_key := RoadNetwork.interchange_key(axis, line, at, part)
			var connector_key := RoadNetwork.interchange_key(axis, line, at, 0)
			var exit_segment := roads.edge_segment(exit_key)
			var connector := roads.edge_segment(connector_key)
			if exit_segment and connector:
				var ends := roads.ramp_ends(axis, line, at, part)
				var to_place := Leg.new()
				to_place.key = connector_key
				to_place.segment = connector
				to_place.kind = Kind.CONNECTOR
				to_place.forward = false
				to_place.from = _s_near(connector, false, ends[1])
				to_place.to = connector.total_length() - 26.0
				to_place.lateral = ROAD_LANE
				if to_place.to > to_place.from + 5.0:
					after = [_ramp_leg(exit_key, exit_segment), to_place]
					exit_ramp = [exit_key, ends[0]]
	if after.is_empty():
		return
	# Das Autobahn-Stück endet kurz nach dem Beginn der Ausfahrt (dort liegt die Rampe schon
	# neben der Fahrbahn), vorher fährt das Auto nach rechts hinüber
	var ramp_start := _s_near(leg.segment, leg.forward, exit_ramp[1])
	if ramp_start <= c.s + 150.0:
		return
	leg.to = ramp_start + 12.0
	after[0].from = 12.0
	c.plan = after


## Meter (in Fahrtrichtung) bis zum Punkt des Abschnitts, der p am nächsten liegt
func _s_near(segment: RoadSegment, forward: bool, p: Vector2) -> float:
	var best := 0
	var best_distance := INF
	for i in segment.points.size():
		var d := Vector2(segment.points[i].x - p.x, segment.points[i].z - p.y).length_squared()
		if d < best_distance:
			best_distance = d
			best = i
	var index := best if forward else segment.points.size() - 1 - best
	return index * RoadSegment.POINT_SPACING


## Lage auf einem Stück: [Punkt, Fahrtrichtung (mit Steigung)]
func _pose(leg: Leg, s: float, lateral: float) -> Array:
	var segment := leg.segment
	var n := segment.points.size()
	var f := clampf(s / RoadSegment.POINT_SPACING, 0.0, n - 1.001)
	if not leg.forward:
		f = (n - 1) - f
	var i := clampi(floori(f), 0, n - 2)
	var t := f - i
	var p := segment.points[i].lerp(segment.points[i + 1], t)
	var dir := segment.points[i + 1] - segment.points[i]
	if not leg.forward:
		dir = -dir
	dir = dir.normalized()
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	var right := flat.cross(Vector3.UP)
	# Querneigung: positiv = linke Seite (der Punktfolge) tiefer
	var left_offset := -lateral if leg.forward else lateral
	var bank := lerpf(segment.bank[i], segment.bank[i + 1], t)
	var at := p + right * lateral
	at.y = p.y - bank * left_offset
	return [at, dir]


## Wunschtempo hier (Straßenart, Ort, Kurve, Wetter)
func _desired_speed(c: TrafficCar) -> float:
	var leg := c.leg
	var target := c.road_speed
	match leg.kind:
		Kind.HIGHWAY:
			target = c.highway_speed
		Kind.RAMP:
			target = minf(c.road_speed, 80.0 / 3.6)
		Kind.LOT:
			target = 25.0 / 3.6
	if leg.kind == Kind.ROAD or leg.kind == Kind.CONNECTOR:
		for cell: Vector2i in _cells_of(leg):
			var node: Variant = roads.node_at(cell)
			if node != null and c.position.distance_to(node as Vector3) < VILLAGE_RADIUS:
				target = minf(target, VILLAGE_SPEED)
	# Kurven: nach vorne schauen (bremsen braucht Weg)
	var curvature := 0.0
	if c.next != null:
		var turn := c.forward.angle_to(_pose(c.next, c.next.from, c.next.lateral)[1])
		curvature = turn / maxf(c.curve_length, 1.0)
	else:
		var n := leg.segment.points.size()
		for ahead: float in [0.0, 25.0, 50.0, 80.0]:
			var f := (c.s + ahead) / RoadSegment.POINT_SPACING
			if not leg.forward:
				f = (n - 1) - f
			var i := clampi(roundi(f), 0, n - 1)
			curvature = maxf(curvature, absf(leg.segment.curvature[i]))
	if curvature > 0.0001:
		target = minf(target, sqrt(LATERAL_ACCEL / curvature))
	# Nässe und Schnee: vorsichtiger
	target *= lerpf(0.7, 1.0, clampf((car.grip_factor - 0.5) / 0.5, 0.0, 1.0))
	return maxf(target, 5.0)


func _cells_of(leg: Leg) -> Array[Vector2i]:
	if leg.kind == Kind.ROAD:
		return [Vector2i(leg.key.x, leg.key.y), roads.edge_end_cell(leg.key)]
	var interchange := roads.highways.interchange_at(RoadNetwork.highway_axis(leg.key), leg.key.y, leg.key.x)
	if interchange.is_empty():
		return []
	return [interchange["cell"]]


## Beschleunigung nach dem IDM: freie Fahrt gegen Abstand zum Vordermann (oder zum Spieler)
func _acceleration(c: TrafficCar) -> float:
	var desired := _desired_speed(c)
	var free := 1.0 - pow(c.speed / desired, 4.0)
	var leader := _leader(c, 0.0, 160.0)
	var interaction := 0.0
	if not leader.is_empty():
		var gap: float = leader[0]
		var leader_speed: float = leader[1]
		var closing := c.speed - leader_speed
		var wanted := MIN_GAP + c.speed * TIME_GAP + c.speed * closing / (2.0 * sqrt(c.accel * COMFORT_BRAKE))
		interaction = pow(maxf(wanted, 0.0) / maxf(gap, 0.5), 2.0)
	var accel := c.accel * (free - interaction)
	return clampf(accel, -9.0, c.accel)


## Vordermann in der eigenen Spur (seitlicher Versatz offset, positiv = rechts):
## [Lücke in Metern, Tempo in Fahrtrichtung] oder leer
func _leader(c: TrafficCar, offset: float, reach: float) -> Array:
	var right := Vector3(c.forward.x, 0.0, c.forward.z).normalized().cross(Vector3.UP)
	var flat_forward := Vector3(c.forward.x, 0.0, c.forward.z).normalized()
	var best: Array = []
	var best_gap := reach
	for other in _cars:
		if other == c:
			continue
		var rel := other.position - c.position
		var ahead := rel.dot(flat_forward)
		if ahead <= 0.0 or ahead > reach + other.length:
			continue
		if absf(rel.dot(right) - offset) > 2.1 or absf(rel.y) > 4.0:
			continue
		# Gegenverkehr in der eigenen Spur gibt es nicht (nur Kurven-Artefakte)
		var other_forward := Vector3(other.forward.x, 0.0, other.forward.z).normalized()
		if other_forward.dot(flat_forward) < 0.3:
			continue
		var gap := ahead - (c.length + other.length) * 0.5
		if gap < best_gap:
			best_gap = gap
			best = [gap, other.speed * other_forward.dot(flat_forward)]
	# Der Spieler zählt auch (egal in welche Richtung er fährt)
	var to_player := car.global_position - c.position
	var player_ahead := to_player.dot(flat_forward)
	if player_ahead > 0.0 and player_ahead < reach and absf(to_player.dot(right) - offset) < 2.4 and absf(to_player.y) < 4.0:
		var gap := player_ahead - (c.length + 4.5) * 0.5
		if gap < best_gap:
			best = [gap, maxf(car.linear_velocity.dot(flat_forward), 0.0)]
	return best


## Ist die Nachbarspur (offset) frei? Vorne bis front, hinten bis back Meter (schnellere
## Autos von hinten zählen weiter)
func _lane_free(c: TrafficCar, offset: float, front: float, back: float) -> bool:
	var flat_forward := Vector3(c.forward.x, 0.0, c.forward.z).normalized()
	var right := flat_forward.cross(Vector3.UP)
	for other in _cars:
		if other == c:
			continue
		var rel := other.position - c.position
		var ahead := rel.dot(flat_forward)
		var behind_reach := back + maxf(other.speed - c.speed, 0.0) * 4.0
		if ahead > front or ahead < -behind_reach:
			continue
		if absf(rel.dot(right) - offset) < 2.4:
			return false
	var to_player := car.global_position - c.position
	var player_ahead := to_player.dot(flat_forward)
	var player_speed := car.linear_velocity.dot(flat_forward)
	if player_ahead < front and player_ahead > -(back + maxf(player_speed - c.speed, 0.0) * 4.0) \
			and absf(to_player.dot(right) - offset) < 2.6:
		return false
	return true


## Autobahn: überholen und wieder rechts einordnen, vor einer Ausfahrt nach rechts
func _decide_lane(c: TrafficCar, delta: float) -> void:
	if c.leg.kind != Kind.HIGHWAY or c.next != null or c.crash_timer > 0.0:
		return
	# Vor der Ausfahrt rüber auf die Rampe (über die rechte Spur)
	if not c.plan.is_empty() and c.leg.to - c.s < 260.0:
		if c.lane_target != HW_RAMP and (c.lane_target == HW_RIGHT or _lane_free(c, HW_RIGHT - c.lateral, 40.0, 25.0)):
			c.lane_target = HW_RIGHT if c.lane_target == HW_LEFT else HW_RAMP
			c.blink = -1
			c.blink_timer = 1.5
		return
	c.decide_timer -= delta
	if c.decide_timer > 0.0:
		return
	c.decide_timer = 0.5
	if c.lateral != c.lane_target or c.lateral > HW_RIGHT + 0.5:
		return
	var exiting_soon := not c.plan.is_empty() and c.leg.to - c.s < 900.0
	if c.lane_target == HW_RIGHT:
		if c.truck or exiting_soon:
			return
		var leader := _leader(c, 0.0, 130.0)
		var slower: bool = not leader.is_empty() and (leader[1] as float) < c.highway_speed - 4.0
		if (slower or c.fast) and _lane_free(c, HW_LEFT - HW_RIGHT, 70.0, 35.0):
			c.lane_target = HW_LEFT
			c.blink = 1
			c.blink_timer = 1.5
	else:
		# Links: zurück nach rechts, wenn dort eine Weile frei ist (Rechtsfahrgebot)
		var right_leader := _leader(c, HW_RIGHT - HW_LEFT, 180.0)
		var right_ok: bool = right_leader.is_empty() or (right_leader[1] as float) > c.highway_speed - 3.0
		if right_ok and _lane_free(c, HW_RIGHT - HW_LEFT, 90.0, 30.0):
			c.right_free_time += 0.5
		else:
			c.right_free_time = 0.0
		if c.right_free_time > (6.0 if c.fast else 2.0) or exiting_soon:
			c.lane_target = HW_RIGHT
			c.blink = -1
			c.blink_timer = 1.5
			c.right_free_time = 0.0


func _check_crash(c: TrafficCar, player: Vector3) -> void:
	var facing := Basis.looking_at(-c.forward, Vector3.UP)
	var local := facing.inverse() * (player - c.position)
	if absf(local.x) < c.width * 0.5 + 1.0 and absf(local.z) < c.length * 0.5 + 2.3 and absf(local.y) < 3.0:
		if c.crash_timer <= 0.0:
			c.hazard = true
		c.crash_timer = crash_wait


# ---------------------------------------------------------------------------
# Aussehen: Licht, Blinker, Schatten, Kollision
# ---------------------------------------------------------------------------

func _update_looks(delta: float) -> void:
	var player := car.global_position
	var lit := fmod(_blink_clock, 1.0 / BLINK_HZ) < 0.5 / BLINK_HZ
	for c in _cars:
		var distance := c.position.distance_to(player)
		var shadows := distance < shadow_distance
		c.mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var indices: Dictionary = _surface_index[c.type]
		if c.braking != c.shown_brake:
			c.shown_brake = c.braking
			c.mesh.set_surface_override_material(indices["tail"], _material("brake" if c.braking else "tail"))
		var left_on := lit and (c.hazard or c.blink == 1)
		var right_on := lit and (c.hazard or c.blink == -1)
		if left_on != c.shown_left:
			c.shown_left = left_on
			c.mesh.set_surface_override_material(indices["ind_l"], _material("ind_on" if left_on else "ind_off"))
		if right_on != c.shown_right:
			c.shown_right = right_on
			c.mesh.set_surface_override_material(indices["ind_r"], _material("ind_on" if right_on else "ind_off"))
		# Kollision nur in der Nähe (und nicht im Benchmark)
		var wants_body := distance < body_distance and not _ghost
		if wants_body and c.body == null:
			c.body = AnimatableBody3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(c.width, _body_height(c), c.length)
			var collision := CollisionShape3D.new()
			collision.shape = shape
			c.body.add_child(collision)
			add_child(c.body)
			_place(c)
		elif not wants_body and c.body:
			c.body.queue_free()
			c.body = null
	_light_timer -= delta
	if _light_timer <= 0.0:
		_light_timer = 0.3
		_update_lights(player)


## Nachts: Licht-Materialien heller, echte Scheinwerfer an den nächsten Autos
func _update_lights(player: Vector3) -> void:
	var daylight := day_night.daylight if day_night else 1.0
	var night := clampf((0.45 - daylight) / 0.35, 0.0, 1.0)
	_material("head").emission_energy_multiplier = lerpf(0.4, 5.0, night)
	_material("tail").emission_energy_multiplier = lerpf(0.4, 2.2, night)
	_material("brake").emission_energy_multiplier = lerpf(2.5, 7.0, night)
	var order: Array = []
	if night > 0.3:
		for c in _cars:
			var distance := c.position.distance_to(player)
			if distance < headlight_distance:
				order.append([distance, c])
		order.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var lit := {}
	for k in mini(order.size(), headlight_count):
		lit[order[k][1]] = true
	for c in _cars:
		c.light.visible = lit.has(c)


func _material(key: String) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	match key:
		"glass":
			material.albedo_color = Color(0.07, 0.09, 0.12)
			material.roughness = 0.08
			material.metallic = 0.5
		"dark":
			material.albedo_color = Color(0.06, 0.06, 0.07)
			material.roughness = 0.8
		"white":
			material.albedo_color = Color(0.86, 0.87, 0.88)
			material.roughness = 0.6
		"head":
			material.albedo_color = Color(0.95, 0.95, 0.9)
			material.emission_enabled = true
			material.emission = Color(1.0, 0.96, 0.88)
		"tail", "brake":
			material.albedo_color = Color(0.5, 0.03, 0.03)
			material.emission_enabled = true
			material.emission = Color(1.0, 0.05, 0.03)
		"ind_on", "ind_off":
			material.albedo_color = Color(0.9, 0.45, 0.05) if key == "ind_on" else Color(0.45, 0.25, 0.08)
			material.emission_enabled = key == "ind_on"
			material.emission = Color(1.0, 0.5, 0.05)
			material.emission_energy_multiplier = 4.0
	_materials[key] = material
	return material


func _paint_material(color: Color) -> StandardMaterial3D:
	var key := "paint_" + color.to_html(false)
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.metallic = 0.45
		material.roughness = 0.32
		_materials[key] = material
	return _materials[key]


# ---------------------------------------------------------------------------
# Fahrzeuge aus Kästchen (vorne = +Z, Boden = 0)
# ---------------------------------------------------------------------------

func _vehicle_mesh(type: String) -> ArrayMesh:
	if _meshes.has(type):
		return _meshes[type]
	var parts: Dictionary = {}  # Fläche -> SurfaceTool
	for key in SURFACES:
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		parts[key] = tool
	var length: float = TYPES[type]["length"]
	var width: float = TYPES[type]["width"]
	var front := length * 0.5
	match type:
		"limousine", "kombi", "suv":
			var suv := type == "suv"
			var low := 0.45 if suv else 0.32
			var body_top := 1.15 if suv else 0.93
			var cabin_length := 2.8 if suv else (3.05 if type == "kombi" else 2.5)
			var cabin_z := -0.35 if suv else (-0.55 if type == "kombi" else -0.25)
			var cabin_top := body_top + (0.58 if suv else 0.5)
			_box(parts["paint"], Vector3(0.0, (low + body_top) * 0.5, 0.0), Vector3(width, body_top - low, length))
			_box(parts["glass"], Vector3(0.0, (body_top + cabin_top) * 0.5, cabin_z),
				Vector3(width - 0.2, cabin_top - body_top, cabin_length))
			_box(parts["paint"], Vector3(0.0, cabin_top + 0.03, cabin_z - 0.05), Vector3(width - 0.24, 0.06, cabin_length - 0.35))
			for z: float in [front - 0.05, -front + 0.05]:
				_box(parts["dark"], Vector3(0.0, low + 0.12, z), Vector3(width + 0.02, 0.24, 0.12))
			var radius := 0.38 if suv else 0.33
			for x: float in [width * 0.5 - 0.12, -width * 0.5 + 0.12]:
				for z: float in [length * 0.31, -length * 0.31]:
					_wheel(parts["dark"], Vector3(x, radius, z), radius, 0.24)
			_lights(parts, width, length, low + 0.42, low + 0.5)
		"transporter":
			_box(parts["paint"], Vector3(0.0, 1.45, -0.35), Vector3(width, 2.2, length - 0.7))
			_box(parts["paint"], Vector3(0.0, 0.8, front - 0.4), Vector3(width - 0.05, 0.9, 0.8))
			_box(parts["glass"], Vector3(0.0, 1.85, front - 0.79), Vector3(width - 0.2, 0.75, 0.04))
			for x: float in [width * 0.5 + 0.005, -width * 0.5 - 0.005]:
				_box(parts["glass"], Vector3(x, 1.85, front - 1.35), Vector3(0.02, 0.6, 0.9))
			_box(parts["dark"], Vector3(0.0, 0.45, front - 0.02), Vector3(width + 0.02, 0.25, 0.1))
			for x: float in [width * 0.5 - 0.12, -width * 0.5 + 0.12]:
				for z: float in [length * 0.33, -length * 0.3]:
					_wheel(parts["dark"], Vector3(x, 0.36, z), 0.36, 0.24)
			_lights(parts, width, length, 0.95, 1.0)
		"lkw":
			# Fahrerhaus vorne, Kofferaufbau, Fahrgestell
			_box(parts["paint"], Vector3(0.0, 1.95, front - 1.15), Vector3(width, 2.7, 2.3))
			_box(parts["glass"], Vector3(0.0, 2.6, front + 0.005), Vector3(width - 0.25, 1.0, 0.04))
			_box(parts["white"], Vector3(0.0, 2.45, -1.3), Vector3(width + 0.05, 3.0, 10.2))
			_box(parts["dark"], Vector3(0.0, 0.75, -0.2), Vector3(width - 0.2, 0.35, length - 0.4))
			_box(parts["dark"], Vector3(0.0, 0.6, front - 0.05), Vector3(width, 0.4, 0.12))
			for x: float in [width * 0.5 - 0.2, -width * 0.5 + 0.2]:
				for z: float in [front - 1.4, -3.6, -4.9]:
					_wheel(parts["dark"], Vector3(x, 0.52, z), 0.52, 0.32)
			_lights(parts, width, length, 0.75, 1.05)
	var mesh := ArrayMesh.new()
	var indices: Dictionary = {}
	for key in SURFACES:
		var tool: SurfaceTool = parts[key]
		var arrays := tool.commit_to_arrays()
		# Leere Fläche (z. B. kein Kofferaufbau beim Pkw): Godot liefert dann null statt Punkten
		if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
			continue
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		indices[key] = mesh.get_surface_count() - 1
		mesh.surface_set_material(indices[key], _material(key) if key != "paint" else _paint_material(PAINTS[0]))
	_meshes[type] = mesh
	_surface_index[type] = indices
	return mesh


## Scheinwerfer, Rücklichter und Blinker an den Ecken
func _lights(parts: Dictionary, width: float, length: float, front_y: float, rear_y: float) -> void:
	var front := length * 0.5 + 0.012
	for side: float in [1.0, -1.0]:
		_box(parts["head"], Vector3(side * (width * 0.5 - 0.3), front_y, front), Vector3(0.36, 0.13, 0.03))
		_box(parts["tail"], Vector3(side * (width * 0.5 - 0.28), rear_y, -front), Vector3(0.34, 0.15, 0.03))
		# Links = +X (Nase zeigt nach +Z)
		var indicator: SurfaceTool = parts["ind_l" if side > 0.0 else "ind_r"]
		_box(indicator, Vector3(side * (width * 0.5 - 0.06), front_y, front + 0.002), Vector3(0.1, 0.1, 0.03))
		_box(indicator, Vector3(side * (width * 0.5 - 0.06), rear_y + 0.14, -front - 0.002), Vector3(0.1, 0.08, 0.03))


func _box(tool: SurfaceTool, center: Vector3, size: Vector3) -> void:
	var h := size * 0.5
	for axis in 3:
		for s: float in [1.0, -1.0]:
			var n := Vector3.ZERO
			n[axis] = s
			var u := Vector3.ZERO
			u[(axis + 1) % 3] = 1.0
			var v := Vector3.ZERO
			v[(axis + 2) % 3] = 1.0
			var corners: Array[Vector3] = []
			for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				corners.append(center + n * h + u * h * c.x + v * h * c.y)
			if s > 0.0:
				_quad(tool, corners[0], corners[1], corners[2], corners[3], n)
			else:
				_quad(tool, corners[0], corners[3], corners[2], corners[1], n)


## Rad als achteckiges Prisma (Achse = X)
func _wheel(tool: SurfaceTool, center: Vector3, radius: float, width: float) -> void:
	var ring: Array[Vector2] = []
	for k in 8:
		var angle := TAU * (k + 0.5) / 8.0
		ring.append(Vector2(cos(angle), sin(angle)) * radius)
	var hw := width * 0.5
	for k in 8:
		var a := ring[k]
		var b := ring[(k + 1) % 8]
		var normal := Vector3(0.0, (a.x + b.x) * 0.5, (a.y + b.y) * 0.5).normalized()
		_quad(tool, center + Vector3(-hw, a.x, a.y), center + Vector3(-hw, b.x, b.y),
			center + Vector3(hw, b.x, b.y), center + Vector3(hw, a.x, a.y), normal)
	for side: float in [1.0, -1.0]:
		for k in 8:
			var a := ring[k]
			var b := ring[(k + 1) % 8]
			var p0 := center + Vector3(side * hw, 0.0, 0.0)
			var p1 := center + Vector3(side * hw, a.x, a.y)
			var p2 := center + Vector3(side * hw, b.x, b.y)
			tool.set_normal(Vector3(side, 0.0, 0.0))
			if side > 0.0:
				tool.add_vertex(p0)
				tool.add_vertex(p2)
				tool.add_vertex(p1)
			else:
				tool.add_vertex(p0)
				tool.add_vertex(p1)
				tool.add_vertex(p2)


## Viereck a-b-c-d (gegen den Uhrzeigersinn von vorne gesehen)
func _quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	tool.set_normal(normal)
	# Godot: Vorderseite im Uhrzeigersinn
	for p: Vector3 in [a, c, b, a, d, c]:
		tool.add_vertex(p)
