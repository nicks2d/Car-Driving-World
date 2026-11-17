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
## hinter der Kamera). Pkw sind echte Modelle (vorbereitet von tools/setup_traffic_models.gd) in
## drei Stufen: nah das volle Modell mit drehenden Rädern, mittel vereinfacht, fern eine gebaute
## Kiste in Lackfarbe. Fehlt ein Modell, fährt die gebaute Version. Lkw sind gebaut. Nachts
## mit Licht.
## Stößt der Spieler mit einem zusammen, bleibt es mit Warnblinker stehen und fährt nach ein
## paar Sekunden weiter.
## Vorfahrt (RoadJunction.rules): An Stoppschildern halten die Autos an der Haltelinie, warten und fahren,
## wenn die Kreuzung frei ist; bei „Vorfahrt gewähren“ warten sie nur, wenn jemand auf der Vorfahrtstraße
## kommt. Die Verkehrsdichte hängt von der Uhrzeit ab (Berufsverkehr morgens und nachmittags, nachts
## wenig), im Berufsverkehr stockt es vor manchen Anschlussstellen.

@export var roads: RoadNetwork
@export var car: Car
@export var camera: Camera3D
@export var day_night: DayNight
@export var debug_tools: DebugTools
## Dichte: 0 = aus, 0.5 = wenig, 1 = normal (Einstellungen)
@export_range(0.0, 1.0) var density: float = 1.0
@export var max_cars: int = 40
## Bis zu dieser Entfernung (m) haben Verkehrsautos einen weichen Kontaktschatten (ContactShadow)
@export var contact_shadow_distance: float = 70.0
## Ein Auto pro so viele Meter je Fahrtrichtung (Landstraße, Autobahn)
@export var road_spacing: float = 2100.0
@export var highway_spacing: float = 380.0

@export_group("Tageszeit")
## Faktor auf die Dichte über den Tag: [Uhrzeit, Autobahn, Landstraße], dazwischen weich
@export var time_factors: Array[Vector3] = [Vector3(0.0, 0.3, 0.3), Vector3(5.0, 0.3, 0.3),
	Vector3(6.5, 2.6, 1.3), Vector3(7.75, 3.0, 1.4), Vector3(9.0, 2.6, 1.3), Vector3(9.75, 1.0, 1.0),
	Vector3(15.5, 1.0, 1.0), Vector3(16.25, 2.6, 1.3), Vector3(17.5, 3.0, 1.4), Vector3(19.0, 2.4, 1.25),
	Vector3(20.0, 0.9, 0.8), Vector3(22.0, 0.5, 0.45), Vector3(24.0, 0.3, 0.3)]
## Ab diesem Autobahn-Faktor ist Berufsverkehr: Dann stockt es vor manchen Anschlussstellen (Anteil)
@export var rush_factor: float = 2.0
@export_range(0.0, 1.0) var jam_share: float = 0.45
## Stau-Abschnitt vor der Anschlussstelle (Meter vor dem Ende des Autobahn-Stücks) und Tempo darin (km/h)
@export var jam_zone := Vector2(1100.0, 150.0)
@export var jam_speed_kmh := Vector2(12.0, 70.0)

@export_group("Vorfahrt")
## So lange stehen Autos am Stoppschild mindestens (Sekunden); höchstens so lange warten sie überhaupt
@export var stop_wait: float = 1.5
@export var max_wait: float = 9.0
## Kommt auf der Vorfahrtstraße jemand in weniger als so vielen Sekunden an, wird gewartet
@export var yield_gap: float = 4.5
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
## Echte Modelle verwenden (aus = nur gebaute Kästchen, z. B. zum Vergleichen der Leistung)
@export var use_models: bool = true
## Detailstufen der Modelle (Meter von der Kamera): bis near_distance das volle Modell, bis
## mid_distance das vereinfachte, dahinter die gebaute Kiste
@export var near_distance: float = 60.0
@export var mid_distance: float = 220.0
## Geparkte Fahrzeuge (Raststätten) sind nur bis hierher zu sehen
@export var parked_distance: float = 400.0

## Spuren (Meter rechts der Mittellinie): Landstraße, Autobahn rechts/links, Zusatzfahrstreifen
## (Verzögerungs-/Beschleunigungsstreifen, dort beginnen bzw. enden die Rampen), Fahrgasse der
## Raststätte
const ROAD_LANE: float = 2.25
const HW_RIGHT: float = 8.375
const HW_LEFT: float = 4.625
const HW_RAMP: float = RoadNetwork.RAMP_LATERAL + RoadNetwork.RAMP_LANE_SHIFT
const LOT_LANE: float = -18.5
## Tempo in Orten und Kurven
const VILLAGE_SPEED: float = 50.0 / 3.6
const VILLAGE_RADIUS: float = 170.0
const LATERAL_ACCEL: float = 2.6
## Im Rennen nimmt die KI Kurven so schnell, wie der Grip hergibt (m/s²)
const RACE_LATERAL_ACCEL: float = 7.0
## Spurwechsel: so schnell seitlich (m/s)
const LANE_RATE: float = 1.3
## IDM: Mindestabstand, Zeitlücke, angenehme Verzögerung
const MIN_GAP: float = 4.0
const TIME_GAP: float = 1.4
const COMFORT_BRAKE: float = 3.0
const BLINK_HZ: float = 1.5

enum Kind { ROAD, HIGHWAY, RAMP, CONNECTOR, LOT }

## Fahrzeugtypen: Modell (Ordner in assets/models/verkehr), Form der gebauten Version (fern
## und als Ersatz ohne Modell), Länge, Breite, Höhe (Kollision), Beschleunigung, Anteil auf
## Landstraße / Autobahn, Chance, auf der Autobahn zu den Schnellen links zu gehören
const TYPES := {
	"s3": {"model": "2014_audi_s3_limousine", "shape": "limousine", "length": 4.47, "width": 1.8,
		"height": 1.42, "accel": 2.2, "road": 30, "highway": 26, "fast": 0.12},
	"accord": {"model": "2021_honda_accord", "shape": "limousine", "length": 4.87, "width": 1.86,
		"height": 1.45, "accel": 2.0, "road": 30, "highway": 26, "fast": 0.1},
	"id_buzz": {"model": "2023_volkswagen_id_buzz_gtx", "shape": "suv", "length": 4.71, "width": 1.98,
		"height": 1.85, "accel": 1.8, "road": 16, "highway": 11, "fast": 0.0},
	"aztek": {"model": "2005_pontiac_aztek", "shape": "suv", "length": 4.63, "width": 1.92,
		"height": 1.75, "accel": 1.6, "road": 7, "highway": 5, "fast": 0.05},
	"lc500": {"model": "2017_lexus_lc_500", "shape": "limousine", "length": 4.77, "width": 1.92,
		"height": 1.35, "accel": 2.6, "road": 5, "highway": 7, "fast": 0.6},
	"lkw": {"shape": "lkw", "length": 12.7, "width": 2.5, "height": 3.9, "accel": 0.7, "road": 6,
		"highway": 22, "fast": 0.0},
}
const MODEL_PATH := "res://assets/models/verkehr/%s/prepared/model.res"
## Lackfarben wie auf deutschen Straßen [Farbe, Gewicht]: meist Weiß, Schwarz, Grau, Silber,
## seltener Blau, Rot, Grün, Beige
const PAINTS: Array = [
	[Color("#E9E9E6"), 19], [Color("#1B1C1F"), 19], [Color("#55595E"), 16], [Color("#A9ADB1"), 14],
	[Color("#1F3A66"), 9], [Color("#2C5D8C"), 3], [Color("#8E1A1A"), 7], [Color("#2F4A35"), 4],
	[Color("#C8B89A"), 4], [Color("#5C2A3A"), 2],
]
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
	## Gebaute Version (fern bzw. ohne Modell) und die Stufen des Modells (falls da)
	var far: MeshInstance3D
	var near: MeshInstance3D
	var mid: MeshInstance3D
	## Räder der nahen Stufe (drehen sich) und Blinker am Modell (links, rechts)
	var wheels: Array[MeshInstance3D] = []
	var wheel_centers := PackedVector3Array()
	var wheel_radius: float = 0.33
	var wheel_angle: float = 0.0
	var lamps: Array[MeshInstance3D] = []
	var light: SpotLight3D
	var body: AnimatableBody3D
	var type: String
	var length: float
	var width: float
	var height: float
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
	## Auf dem Beschleunigungsstreifen: bis hierher (Meter auf dem Stück) muss es eingefädelt
	## haben (-1 = fährt nicht gerade auf)
	var merge_end: float = -1.0
	## Wie genau es das Tempolimit nimmt (0,95 bis 1,1)
	var limit_factor: float = 1.0
	## Spontanes Rennen gegen den Spieler (Race): fährt nach Grip statt nach Limits; blinkt zurück
	var racing: bool = false
	var flash_timer: float = 0.0
	var shown_flash: bool = false
	## Zuletzt gesetzte Materialien (nur bei Änderung neu setzen)
	var shown_brake: bool = false
	var shown_left: bool = false
	var shown_right: bool = false
	var shown_shadow: bool = false
	## Vorfahrt an der nächsten Kreuzung: für welches Stück berechnet, Kreuzung, Arm, Regel, Wartezeit,
	## darf fahren
	var rule_leg: Leg
	var rule_junction: RoadJunction
	var rule: int = 0
	var wait_timer: float = 0.0
	var cleared: bool = false
	## Stau vor der Anschlussstelle am Ende dieses Autobahn-Stücks (für welches Stück, gibt es einen)
	var jam_leg: Leg
	var jam: bool = false
	## Zurückspulen (Rewind): seit wann es aufgezeichnet wird und der Fahrzustand je Physik-Schritt [Zeit, Zustand]
	var born: float = -1.0
	var snapshots: Array = []


var _cars: Array[TrafficCar] = []
## Gewünschte Zahl Autos auf Landstraßen und Autobahnen (aus Straßenlänge und Uhrzeit)
var _wanted_road: float = 0.0
var _wanted_highway: float = 0.0
## Wird gerade zurückgespult? Dann fährt der Verkehr nicht selbst, Rewind stellt die Lage ein
var rewinding: bool = false
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
## Vorbereitete Modelle je Typ (null = keins da) und Blinker-Meshes je Modell und Seite
var _models: Dictionary = {}
var _lamp_meshes: Dictionary = {}
## Kennzeichen-Stellen je Modell: [vorne, hinten] (Modell-Koordinaten, Mitte des Schilds)
var _plate_spots: Dictionary = {}
## Geparkte Autos, deren Modell noch lädt: [Knoten, Typ, Lackfarbe]
var _waiting_parked: Array = []
var _parked_timer: float = 0.0


func _ready() -> void:
	add_to_group("traffic")
	_rng.seed = 4711
	# Benchmark: der Autopilot weicht nicht aus, deshalb ohne Kollision
	_ghost = debug_tools != null and debug_tools.is_benchmark()
	if debug_tools != null and debug_tools.traffic_density >= 0.0:
		density = debug_tools.traffic_density
	if debug_tools != null and debug_tools.traffic_boxes:
		use_models = false
	# Modelle einmal im Hintergrund laden (bis sie da sind, fährt die gebaute Version)
	if use_models:
		for type: String in TYPES:
			if TYPES[type].has("model") and ResourceLoader.exists(MODEL_PATH % TYPES[type]["model"]):
				ResourceLoader.load_threaded_request(MODEL_PATH % TYPES[type]["model"])


## Dichte ändern (Einstellungen): 0 = aus, 0.5 = wenig, 1 = normal
func set_density(value: float) -> void:
	density = value
	if density <= 0.0:
		for traffic_car in _cars.duplicate():
			_remove(traffic_car)


func car_count() -> int:
	return _cars.size()


func _physics_process(delta: float) -> void:
	var started := Time.get_ticks_usec()
	_timed_physics_process(delta)
	FrameCosts.add("Verkehr", started)


func _timed_physics_process(delta: float) -> void:
	if rewinding:
		return
	_upgrade_parked(delta)
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
		# Fehlen viele (Berufsverkehr, schnelle Fahrt), schneller nachfüllen
		var missing := _wanted - _cars.size()
		_spawn_timer = 0.1 if _fill_timer > 0.0 else (0.2 if missing > 6 else 0.4)
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
	var factors := time_factor()
	_wanted_road = road_length * 2.0 / road_spacing * factors.y * density
	_wanted_highway = highway_length * 2.0 / highway_spacing * factors.x * density
	return mini(roundi(_wanted_road + _wanted_highway), max_cars)


## Faktor auf die Verkehrsdichte zur aktuellen Uhrzeit: x = Autobahn, y = Landstraße
func time_factor() -> Vector2:
	var hour := day_night.time_of_day if day_night else 12.0
	for k in range(1, time_factors.size()):
		var a := time_factors[k - 1]
		var b := time_factors[k]
		if hour <= b.x:
			var t := smoothstep(a.x, b.x, hour)
			return Vector2(lerpf(a.y, b.y, t), lerpf(a.z, b.z, t))
	return Vector2(time_factors[0].y, time_factors[0].z)


## Gerade Berufsverkehr auf der Autobahn?
func is_rush_hour() -> bool:
	return time_factor().x >= rush_factor


func _try_spawn() -> void:
	var p := car.global_position
	var options: Array = []
	var total := 0.0
	# Neue Autos dort, wo welche fehlen (Autobahn oder Landstraße)
	var on_highway := 0
	for c in _cars:
		if c.leg.kind == Kind.HIGHWAY:
			on_highway += 1
	var need_highway := on_highway < roundi(_wanted_highway)
	var need_road := _cars.size() - on_highway < roundi(_wanted_road)
	for pair: Array in roads.loaded_segments(Rect2(p.x - spawn_max, p.z - spawn_max, spawn_max * 2.0, spawn_max * 2.0)):
		var key: Vector3i = pair[0]
		if not RoadNetwork.is_road_key(key) and not RoadNetwork.is_highway_key(key):
			continue
		var segment: RoadSegment = pair[1]
		var highway_key := RoadNetwork.is_highway_key(key)
		if (highway_key and not need_highway) or (not highway_key and not need_road):
			continue
		var weight := segment.total_length()
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
		var fast := highway and _rng.randf() < float(TYPES[type]["fast"])
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
		var spacing := 28.0 if highway and is_rush_hour() else 45.0
		for other in _cars:
			if other.position.distance_to(at) < spacing:
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
	return "s3"


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
	traffic_car.height = info["height"]
	traffic_car.accel = info["accel"]
	traffic_car.truck = type == "lkw"
	traffic_car.fast = fast
	match type:
		"lkw":
			traffic_car.road_speed = _rng.randf_range(62.0, 80.0) / 3.6
			traffic_car.highway_speed = _rng.randf_range(82.0, 89.0) / 3.6
		"id_buzz":
			traffic_car.road_speed = _rng.randf_range(62.0, 95.0) / 3.6
			traffic_car.highway_speed = _rng.randf_range(110.0, 150.0) / 3.6
		_:
			traffic_car.road_speed = _rng.randf_range(65.0, 100.0) / 3.6
			traffic_car.highway_speed = _rng.randf_range(185.0, 230.0) / 3.6 if fast \
				else _rng.randf_range(110.0, 175.0) / 3.6
	traffic_car.limit_factor = _rng.randf_range(0.95, 1.1)
	traffic_car.leg = leg
	traffic_car.s = s
	traffic_car.lateral = leg.lateral
	traffic_car.lane_target = leg.lateral
	traffic_car.node = Node3D.new()
	var paint := _pick_paint()
	traffic_car.far = MeshInstance3D.new()
	traffic_car.far.mesh = _vehicle_mesh(type)
	traffic_car.far.set_surface_override_material(_surface_index[type]["paint"], _paint_material(paint))
	traffic_car.node.add_child(traffic_car.far)
	var model := _model(type)
	if model:
		_add_model(traffic_car, model, paint)
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
	# Weicher Kontaktschatten (nur in der Nähe)
	var shadow := ContactShadow.make(Vector2(traffic_car.width, traffic_car.length))
	shadow.position = Vector3(0.0, 0.15, 0.0)
	shadow.distance_fade_enabled = true
	shadow.distance_fade_begin = contact_shadow_distance - 15.0
	shadow.distance_fade_length = 15.0
	traffic_car.node.add_child(shadow)
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


## Test (--lineup): von jedem Typ ein stehendes Auto vor dem Spieler, ab start Metern voraus,
## auf der Autobahn abwechselnd rechte und linke Spur. Jedes zweite blinkt links, jedes dritte
## hat den Warnblinker an (Licht prüfen).
func spawn_lineup(start: float, only: String = "") -> void:
	var p := car.global_position
	var best: Array = []
	var best_distance := INF
	for pair: Array in roads.loaded_segments(Rect2(p.x - 60.0, p.z - 60.0, 120.0, 120.0)):
		var key: Vector3i = pair[0]
		if not RoadNetwork.is_road_key(key) and not RoadNetwork.is_highway_key(key):
			continue
		var candidate: RoadSegment = pair[1]
		for i in candidate.points.size():
			var d := Vector2(candidate.points[i].x - p.x, candidate.points[i].z - p.z).length()
			if d < best_distance:
				best_distance = d
				best = [key, candidate, i]
	if best.is_empty():
		return
	var segment: RoadSegment = best[1]
	var i: int = best[2]
	var along := segment.points[mini(i + 1, segment.points.size() - 1)] - segment.points[maxi(i - 1, 0)]
	var forward := along.dot(car.global_basis.z) > 0.0
	var highway := RoadNetwork.is_highway_key(best[0])
	var s0 := _s_near(segment, forward, Vector2(p.x, p.z))
	var k := 0
	for type: String in TYPES:
		if only != "" and type != only:
			continue
		var leg := Leg.new()
		leg.key = best[0]
		leg.segment = segment
		leg.kind = Kind.HIGHWAY if highway else Kind.ROAD
		leg.forward = forward
		leg.from = 0.0
		leg.to = segment.total_length()
		leg.lateral = (HW_RIGHT if k % 2 == 0 else HW_LEFT) if highway else ROAD_LANE
		var s := s0 + start + (floorf(k / 2.0) if highway else float(k)) * 16.0
		if s > leg.to - 10.0:
			break
		_spawn(type, leg, s, false)
		var c := _cars.back() as TrafficCar
		c.plan.clear()
		c.speed = 0.0
		c.crash_timer = 1e9
		c.blink = 1 if k % 2 == 1 else 0
		c.blink_timer = 1e9
		c.hazard = k % 3 == 2
		k += 1


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
		c.body.global_transform = Transform3D(facing, c.position + Vector3.UP * c.height * 0.5)


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
			# Erst auf dem Beschleunigungsstreifen Tempo aufnehmen, dann in eine Lücke
			c.lateral = leg.lateral
			c.lane_target = HW_RAMP
			c.merge_end = s + RoadSegment.AUX_PARALLEL + RoadSegment.AUX_TAPER * 0.5
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
			leg.to = segment.total_length() - RoadJunction.STOP_DISTANCE
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
	# Mitte des Fahrstreifens (rechts ist der Randstreifen breiter)
	leg.lateral = RoadNetwork.RAMP_LANE_SHIFT
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
				to_place.to = connector.total_length() - RoadJunction.STOP_DISTANCE
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
	# Berufsverkehr: vor manchen Anschlussstellen stockt es (Wellen aus Bremsen und Anfahren)
	if leg.kind == Kind.HIGHWAY and not c.racing:
		target = minf(target, _jam_speed(c))
	# Auf dem Verzögerungsstreifen schon auf Rampentempo bremsen
	if leg.kind == Kind.HIGHWAY and not c.plan.is_empty() and c.lane_target == HW_RAMP:
		target = minf(target, 90.0 / 3.6)
	if (leg.kind == Kind.ROAD or leg.kind == Kind.CONNECTOR) and not c.racing:
		for cell: Vector2i in _cells_of(leg):
			var node: Variant = roads.node_at(cell)
			if node != null and c.position.distance_to(node as Vector3) < VILLAGE_RADIUS:
				target = minf(target, VILLAGE_SPEED)
	# Tempolimits (SpeedLimits), etwas voraus schauen (am Schild schon langsam); „bei Nässe“ nur nass
	if not c.racing and (leg.kind == Kind.ROAD or leg.kind == Kind.HIGHWAY) and not leg.segment.limits_forward.is_empty():
		var count := leg.segment.points.size()
		var limits := leg.segment.limits_forward if leg.forward else leg.segment.limits_backward
		var wet := leg.segment.wet_forward if leg.forward else leg.segment.wet_backward
		for ahead: float in [0.0, 60.0]:
			var f := (c.s + ahead) / RoadSegment.POINT_SPACING
			if not leg.forward:
				f = (count - 1) - f
			var k := clampi(roundi(f), 0, count - 1)
			if limits[k] > 0 and (wet[k] == 0 or car.wetness > 0.3):
				target = minf(target, limits[k] * 5.0 / 3.6 * c.limit_factor)
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
		target = minf(target, sqrt((RACE_LATERAL_ACCEL if c.racing else LATERAL_ACCEL) / curvature))
	# Nässe und Schnee: vorsichtiger
	target *= lerpf(0.7, 1.0, clampf((car.grip_factor - 0.5) / 0.5, 0.0, 1.0))
	return maxf(target, 5.0)


## Tempo im Stau vor der Anschlussstelle am Ende dieses Autobahn-Stücks (sonst sehr hoch). Ob es dort
## stockt, ist pro Anschlussstelle und Stunde fest (Zufall aus Lage und Uhrzeit, also bei jedem Start gleich).
func _jam_speed(c: TrafficCar) -> float:
	if c.jam_leg != c.leg:
		c.jam_leg = c.leg
		c.jam = false
		var axis := RoadNetwork.highway_axis(c.leg.key)
		var at := c.leg.key.x + 1 if c.leg.forward else c.leg.key.x
		if not roads.highways.interchange_at(axis, c.leg.key.y, at).is_empty():
			var hour := floori(day_night.time_of_day) if day_night else 12
			var mix := (axis * 73856093) ^ (c.leg.key.y * 19349663) ^ (at * 83492791) ^ (hour * 2654435)
			c.jam = absi(mix) % 100 < roundi(jam_share * 100.0)
	if not c.jam or not is_rush_hour():
		return 1000.0
	var total := c.leg.segment.total_length()
	var to_end := total - c.s
	if to_end > jam_zone.x or to_end < jam_zone.y:
		return 1000.0
	# Welle, die gegen die Fahrtrichtung wandert: mal fast stehen, mal zügig rollen
	var wave := 0.5 + 0.5 * sin(_blink_clock * 0.35 + c.s * 0.018)
	return lerpf(jam_speed_kmh.x, jam_speed_kmh.y, wave * wave) / 3.6


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
	# Auf dem Beschleunigungsstreifen: dessen Ende ist wie ein stehendes Hindernis
	if c.merge_end > 0.0 and c.lane_target == HW_RAMP:
		var wanted_end := MIN_GAP + c.speed * TIME_GAP + c.speed * c.speed / (2.0 * sqrt(c.accel * COMFORT_BRAKE))
		interaction = maxf(interaction, pow(wanted_end / maxf(c.merge_end + 20.0 - c.s, 0.5), 2.0))
	# Vorfahrt: Haltelinie wie ein stehendes Hindernis (die Front hält an der Linie)
	var hold := _junction_hold(c)
	if hold >= 0.0:
		var gap := hold - 0.8 - c.s - c.length * 0.5 + MIN_GAP
		var wanted_stop := MIN_GAP + c.speed * TIME_GAP * 0.5 + c.speed * c.speed / (2.0 * sqrt(c.accel * COMFORT_BRAKE))
		interaction = maxf(interaction, pow(wanted_stop / maxf(gap, 0.3), 2.0))
	var accel := c.accel * (free - interaction)
	return clampf(accel, -9.0, c.accel)


## Vorfahrt an der Kreuzung am Ende des aktuellen Stücks: Wo muss das Auto halten (Meter auf dem Stück,
## die Haltelinie), oder -1 = darf fahren. Stoppschild: erst halten (stop_wait), dann fahren, wenn frei.
## Vorfahrt gewähren: nur halten, solange die Kreuzung nicht frei ist. Nach max_wait fährt es trotzdem.
func _junction_hold(c: TrafficCar) -> float:
	if c.next != null or c.racing or c.crash_timer > 0.0:
		return -1.0
	if c.rule_leg != c.leg:
		_find_rule(c)
	if c.rule == RoadJunction.RULE_PRIORITY or c.cleared:
		return -1.0
	var line := c.leg.to
	var distance := line - c.s - c.length * 0.5
	if distance > 60.0:
		return -1.0
	if c.speed < 0.4 and distance < 2.0:
		c.wait_timer += get_physics_process_delta_time()
	var stopped_long_enough := c.rule != RoadJunction.RULE_STOP or c.wait_timer >= stop_wait
	if (stopped_long_enough and _junction_clear(c)) or c.wait_timer > max_wait:
		c.cleared = true
		return -1.0
	return line


## Kreuzung und Regel für das Ende des aktuellen Stücks (Landstraße oder Zubringer zum Ort)
func _find_rule(c: TrafficCar) -> void:
	c.rule_leg = c.leg
	c.rule_junction = null
	c.rule = RoadJunction.RULE_PRIORITY
	c.wait_timer = 0.0
	c.cleared = false
	var cell := Vector2i(-99999, -99999)
	match c.leg.kind:
		Kind.ROAD:
			cell = roads.edge_end_cell(c.leg.key) if c.leg.forward else Vector2i(c.leg.key.x, c.leg.key.y)
		Kind.CONNECTOR:
			if c.leg.forward:
				return
			var interchange := roads.highways.interchange_at(RoadNetwork.highway_axis(c.leg.key), c.leg.key.y, c.leg.key.x)
			if interchange.is_empty():
				return
			cell = interchange["cell"]
		_:
			return
	var junction := roads.junction_at(cell)
	if junction == null:
		return
	c.rule_junction = junction
	c.rule = junction.rule_of(junction.arm_of(c.leg.segment, c.leg.forward))


## Ist die Kreuzung frei? Niemand fährt gerade darüber, niemand kommt auf der Vorfahrtstraße in weniger als
## yield_gap Sekunden an, und wer vorher losgefahren ist, ist schon durch. Der Spieler zählt mit.
func _junction_clear(c: TrafficCar) -> bool:
	var junction := c.rule_junction
	var center := junction.center
	for other in _cars:
		if other == c:
			continue
		var distance := other.position.distance_to(center)
		if distance < junction.radius + 6.0:
			return false
		if other.rule_junction != junction or other.next != null or other.rule_leg != other.leg:
			continue
		var to_line := other.leg.to - other.s
		if to_line < 0.0 or to_line > 160.0:
			continue
		var eta := to_line / maxf(other.speed, 1.0)
		# Vorfahrtstraße: kommt bald an. Nebenstraße: ist schon losgefahren und gleich da.
		if other.rule == RoadJunction.RULE_PRIORITY and eta < yield_gap:
			return false
		if other.cleared and to_line < 25.0:
			return false
	var player := car.global_position
	var player_distance := Vector2(player.x - center.x, player.z - center.z).length()
	if player_distance < junction.radius + 8.0:
		return false
	var toward := (center - player).normalized().dot(car.linear_velocity)
	if player_distance < 120.0 and toward > 2.0 and (player_distance - junction.radius) / toward < yield_gap:
		return false
	return true


## Vordermann in der eigenen Spur (seitlicher Versatz offset, positiv = rechts):
## [Lücke in Metern, Tempo in Fahrtrichtung] oder leer
# ---------------------------------------------------------------------------
# Spontane Rennen (Race)
# ---------------------------------------------------------------------------

## KI-Auto, dem der Spieler gerade Lichthupe gibt: bis 40 m vor ihm (oder neben ihm), gleiche
## Richtung, auf Landstraße oder Autobahn. null = keins
func race_candidate(from: Vector3, forward: Vector3) -> TrafficCar:
	var flat_forward := Vector3(forward.x, 0.0, forward.z).normalized()
	var best: TrafficCar = null
	var best_distance := 40.0
	for c in _cars:
		if c.truck or c.crash_timer > 0.0 or (c.leg.kind != Kind.ROAD and c.leg.kind != Kind.HIGHWAY):
			continue
		var rel := c.position - from
		var ahead := rel.dot(flat_forward)
		if ahead < -4.0 or ahead > 40.0 or Vector3(c.forward.x, 0.0, c.forward.z).normalized().dot(flat_forward) < 0.7:
			continue
		if rel.length() < best_distance:
			best_distance = rel.length()
			best = c
	return best


## Wie gern nimmt dieses Auto an? (0–1) Die Schnellen und der LC 500 fast immer, sonst selten
func race_chance(c: TrafficCar) -> float:
	if c.type == "lc500" or c.fast:
		return 0.8
	if c.type == "s3":
		return 0.5
	return 0.12


func start_race(c: TrafficCar) -> void:
	c.racing = true
	c.flash_timer = 1.2
	c.plan.clear()
	c.road_speed = 220.0 / 3.6
	c.highway_speed = 260.0 / 3.6
	c.fast = true
	c.accel = maxf(c.accel, 3.2)


func end_race(c: TrafficCar) -> void:
	if not is_instance_valid(c.node):
		return
	c.racing = false
	c.road_speed = _rng.randf_range(65.0, 100.0) / 3.6
	c.highway_speed = _rng.randf_range(150.0, 200.0) / 3.6


## Punkt s Meter auf dem Stück, auf dem das Auto fährt (Mitte der Spur)
func point_on_leg(c: TrafficCar, s: float) -> Vector3:
	return _pose(c.leg, clampf(s, c.leg.from, c.leg.to), c.leg.lateral)[0]


func is_alive(c: TrafficCar) -> bool:
	return c in _cars


## Die count nächsten Autos bis radius Meter (für die Vorbeifahrt-Geräusche)
func nearest_cars(from: Vector3, count: int, radius: float) -> Array:
	var near: Array = []
	for c in _cars:
		var d := c.position.distance_to(from)
		if d < radius:
			near.append([d, c])
	near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var result: Array = []
	for k in mini(count, near.size()):
		result.append(near[k][1])
	return result


## Test (--race): ein LC 500 fährt distance Meter vor dem Spieler auf derselben Straße los
func spawn_racer(distance: float) -> TrafficCar:
	spawn_lineup(distance)
	var racer: TrafficCar = null
	for c in _cars.duplicate():
		if c.crash_timer > 1e8:
			if c.type == "lc500" and racer == null:
				racer = c
				c.crash_timer = 0.0
				c.blink = 0
				c.hazard = false
				c.speed = 20.0
			else:
				_remove(c)
	return racer


## Test (--cruise): ein Lkw fährt distance Meter vor dem Spieler mit kmh los (rechte Spur)
func spawn_leader(distance: float, kmh: float) -> TrafficCar:
	spawn_lineup(distance, "lkw")
	var leader: TrafficCar = null
	for c in _cars.duplicate():
		if c.crash_timer > 1e8:
			if c.type == "lkw" and leader == null:
				leader = c
				c.crash_timer = 0.0
				c.blink = 0
				c.blink_timer = 0.0
				c.hazard = false
				c.speed = kmh / 3.6
				c.road_speed = kmh / 3.6
				c.highway_speed = kmh / 3.6
				c.fast = false
				if c.leg.kind == Kind.HIGHWAY:
					c.leg.lateral = HW_RIGHT
					c.lateral = HW_RIGHT
					c.lane_target = HW_RIGHT
			else:
				_remove(c)
	return leader


## Für Tests (DebugTools --junctionshot): ein Pkw auf diesem Arm der Kreuzung, before Meter vor der
## Haltelinie, unterwegs zur Kreuzung. null = ging nicht
func spawn_on_arm(junction: RoadJunction, arm_index: int, before: float) -> TrafficCar:
	var arm: Array = junction.arms[arm_index]
	var segment: RoadSegment = arm[0]
	var leg := Leg.new()
	leg.key = segment.key
	leg.segment = segment
	leg.kind = Kind.ROAD
	leg.forward = not arm[1]
	leg.from = 0.0
	leg.to = segment.total_length() - RoadJunction.STOP_DISTANCE
	leg.lateral = ROAD_LANE
	if leg.to - before < 5.0:
		return null
	var count := _cars.size()
	_spawn(_pick_type(false), leg, leg.to - before, false)
	if _cars.size() == count:
		return null
	var c := _cars.back() as TrafficCar
	c.speed = 9.0
	return c


## Für Tempomat und Autopilot (gleiche Regeln wie für die KI): nächstes KI-Auto in der Spur
## vor position (seitlich um offset nach rechts versetzt): [Lücke in Metern, Tempo in
## Fahrtrichtung] oder leer. curvature (1/m, positiv = Linkskurve) sagt den eigenen Weg voraus
## (wie ein Radar-Tempomat aus der Drehrate), sonst fällt der Vordermann in Kurven aus der Spur.
func leader_ahead(from: Vector3, forward: Vector3, own_length: float, reach: float, offset: float = 0.0,
		curvature: float = 0.0) -> Array:
	var flat_forward := Vector3(forward.x, 0.0, forward.z).normalized()
	var right := flat_forward.cross(Vector3.UP)
	var best: Array = []
	var best_gap := reach
	for other in _cars:
		var rel := other.position - from
		var ahead := rel.dot(flat_forward)
		if ahead <= 0.0 or ahead > reach + other.length:
			continue
		var bend := -curvature * ahead * ahead * 0.5
		if absf(rel.dot(right) - offset - bend) > 2.1 or absf(rel.y) > 4.0 + ahead * 0.06:
			continue
		var other_forward := Vector3(other.forward.x, 0.0, other.forward.z).normalized()
		if other_forward.dot(flat_forward) < 0.3:
			continue
		var gap := ahead - (own_length + other.length) * 0.5
		if gap < best_gap:
			best_gap = gap
			best = [gap, other.speed * other_forward.dot(flat_forward)]
	return best


## Ist die Spur um offset Meter rechts (negativ = links) neben from frei? Vorne bis front,
## hinten bis back Meter (schnellere Autos von hinten zählen weiter)
func lane_free_at(from: Vector3, forward: Vector3, own_speed: float, offset: float, front: float, back: float) -> bool:
	var flat_forward := Vector3(forward.x, 0.0, forward.z).normalized()
	var right := flat_forward.cross(Vector3.UP)
	for other in _cars:
		var rel := other.position - from
		var ahead := rel.dot(flat_forward)
		var behind_reach := back + maxf(other.speed - own_speed, 0.0) * 4.0
		if ahead > front or ahead < -behind_reach:
			continue
		if absf(rel.dot(right) - offset) < 2.4:
			return false
	return true


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


## Fährt rechts neben bzw. kurz vor c jemand auf dem Beschleunigungsstreifen?
func _merging_near(c: TrafficCar) -> bool:
	var flat_forward := Vector3(c.forward.x, 0.0, c.forward.z).normalized()
	var right := flat_forward.cross(Vector3.UP)
	for other in _cars:
		if other == c or other.merge_end <= 0.0 or other.lane_target != HW_RAMP:
			continue
		var rel := other.position - c.position
		var ahead := rel.dot(flat_forward)
		if ahead > -10.0 and ahead < 70.0 and absf(rel.dot(right) - (HW_RAMP - HW_RIGHT)) < 2.0:
			return true
	return false


## Autobahn: überholen und wieder rechts einordnen, vor einer Ausfahrt nach rechts
func _decide_lane(c: TrafficCar, delta: float) -> void:
	if c.leg.kind != Kind.HIGHWAY or c.next != null or c.crash_timer > 0.0:
		return
	# Auffahren: auf dem Beschleunigungsstreifen in eine Lücke der rechten Spur einfädeln
	# (schnell genug oder der Streifen geht zu Ende)
	if c.merge_end > 0.0:
		if c.lane_target == HW_RAMP:
			var fast_enough := c.speed > minf(c.highway_speed, 100.0 / 3.6) * 0.85 or c.merge_end - c.s < 120.0
			if fast_enough and _lane_free(c, HW_RIGHT - c.lateral, 15.0 + c.speed * 0.6, 12.0):
				c.lane_target = HW_RIGHT
				c.blink = 1
				c.blink_timer = 1.5
		elif c.lateral == c.lane_target:
			c.merge_end = -1.0
		return
	# Vor der Ausfahrt: rechts einordnen, am Beginn der Verziehung auf den Verzögerungsstreifen
	var to_exit := c.leg.to - c.s
	if not c.plan.is_empty() and to_exit < 600.0:
		var aux_begins := to_exit < RoadSegment.AUX_PARALLEL + RoadSegment.AUX_TAPER + 12.0
		if c.lane_target == HW_LEFT and _lane_free(c, HW_RIGHT - c.lateral, 40.0, 25.0):
			c.lane_target = HW_RIGHT
			c.blink = -1
			c.blink_timer = 1.5
		elif c.lane_target == HW_RIGHT and c.lateral == HW_RIGHT and (aux_begins or to_exit < 200.0):
			c.lane_target = HW_RAMP
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
		# Platz machen für Auffahrende auf dem Beschleunigungsstreifen
		if _merging_near(c) and _lane_free(c, HW_LEFT - HW_RIGHT, 60.0, 30.0):
			c.lane_target = HW_LEFT
			c.blink = 1
			c.blink_timer = 1.5
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
	var eye := camera.global_position if camera else player
	var lit := fmod(_blink_clock, 1.0 / BLINK_HZ) < 0.5 / BLINK_HZ
	for c in _cars:
		var distance := c.position.distance_to(player)
		# Schatten nur nah (beim Modell die nahe und mittlere Stufe, die ferne Kiste nie)
		var shadows := distance < shadow_distance
		if shadows != c.shown_shadow:
			c.shown_shadow = shadows
			var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			for mesh: MeshInstance3D in ([c.near, c.mid] + c.wheels) if c.near else [c.far]:
				mesh.cast_shadow = mode
		var indices: Dictionary = _surface_index[c.type]
		if c.braking != c.shown_brake:
			c.shown_brake = c.braking
			var tail := _material("brake" if c.braking else "tail")
			c.far.set_surface_override_material(indices["tail"], tail)
			for mesh: MeshInstance3D in [c.near, c.mid]:
				if mesh and PreparedModel.surface_index(mesh.mesh, "tail") >= 0:
					mesh.set_surface_override_material(PreparedModel.surface_index(mesh.mesh, "tail"), tail)
		var left_on := lit and (c.hazard or c.blink == 1)
		var right_on := lit and (c.hazard or c.blink == -1)
		if left_on != c.shown_left:
			c.shown_left = left_on
			c.far.set_surface_override_material(indices["ind_l"], _material("ind_on" if left_on else "ind_off"))
			if not c.lamps.is_empty():
				c.lamps[0].visible = left_on
		if right_on != c.shown_right:
			c.shown_right = right_on
			c.far.set_surface_override_material(indices["ind_r"], _material("ind_on" if right_on else "ind_off"))
			if not c.lamps.is_empty():
				c.lamps[1].visible = right_on
		# Zurückblinken (Rennen angenommen): Scheinwerfer kurz hell
		c.flash_timer = maxf(c.flash_timer - delta, 0.0)
		var flashing := c.flash_timer > 0.0 and fmod(c.flash_timer, 0.5) > 0.2
		if flashing != c.shown_flash:
			c.shown_flash = flashing
			c.far.set_surface_override_material(indices["head"], _material("head_flash") if flashing else null)
			for mesh: MeshInstance3D in [c.near, c.mid]:
				if mesh and PreparedModel.surface_index(mesh.mesh, "head") >= 0:
					mesh.set_surface_override_material(PreparedModel.surface_index(mesh.mesh, "head"),
						_material("head_flash") if flashing else null)
		# Räder drehen sich nur in der nahen Stufe
		if not c.wheels.is_empty() and c.position.distance_to(eye) < near_distance + 5.0:
			c.wheel_angle = wrapf(c.wheel_angle + c.speed * delta / c.wheel_radius, 0.0, TAU)
			var spin := Basis(Vector3.RIGHT, c.wheel_angle)
			for i in c.wheels.size():
				c.wheels[i].transform = Transform3D(spin, c.wheel_centers[i])
		# Kollision nur in der Nähe (und nicht im Benchmark)
		var wants_body := distance < body_distance and not _ghost
		if wants_body and c.body == null:
			c.body = AnimatableBody3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(c.width, c.height, c.length)
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
	# Viele Modellteile sind nur von einer Seite gebaut
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	match key:
		"body":
			# Karosserie der Modelle: Farben als Punktfarben (Materialfarbe × Textur)
			material.vertex_color_use_as_albedo = true
			material.vertex_color_is_srgb = true
			material.roughness = 0.6
		"cover":
			# Fast klare Abdeckung über Scheinwerfern und Rücklichtern
			material.albedo_color = Color(0.9, 0.95, 1.0, 0.18)
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.roughness = 0.05
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
		"head_flash":
			material.albedo_color = Color(1.0, 1.0, 0.95)
			material.emission_enabled = true
			material.emission = Color(1.0, 0.97, 0.9)
			material.emission_energy_multiplier = 12.0
		"head_off":
			material.albedo_color = Color(0.7, 0.72, 0.74)
			material.roughness = 0.15
			material.metallic = 0.4
		"tail_off":
			material.albedo_color = Color(0.32, 0.03, 0.03)
			material.roughness = 0.2
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
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials[key] = material
	return _materials[key]


# ---------------------------------------------------------------------------
# Geparkte Fahrzeuge (Raststätten)
# ---------------------------------------------------------------------------

## Zufälliger Pkw-Typ (Anteile wie auf der Landstraße) aus einem eigenen Zufallsgenerator
static func random_car_type(rng: RandomNumberGenerator) -> String:
	var total := 0
	for type: String in TYPES:
		if type != "lkw":
			total += TYPES[type]["road"] as int
	var pick := rng.randi_range(0, total - 1)
	for type: String in TYPES:
		if type == "lkw":
			continue
		pick -= TYPES[type]["road"] as int
		if pick < 0:
			return type
	return "s3"


## Zufällige Lackfarbe nach den Gewichten in PAINTS aus einem eigenen Zufallsgenerator
static func random_paint(rng: RandomNumberGenerator) -> Color:
	var total := 0
	for entry: Array in PAINTS:
		total += entry[1] as int
	var pick := rng.randi_range(0, total - 1)
	for entry: Array in PAINTS:
		pick -= entry[1] as int
		if pick < 0:
			return entry[0]
	return PAINTS[0][0]


## Stehendes Fahrzeug (Nase nach +Z, Boden = 0) mit denselben Stufen wie der Verkehr, fern nur
## bis parked_distance. Lädt das Modell noch, kommt es nach (_upgrade_parked).
func make_parked(type: String, paint: Color) -> Node3D:
	var node := Node3D.new()
	var far := MeshInstance3D.new()
	far.mesh = _vehicle_mesh(type)
	far.set_surface_override_material(_surface_index[type]["paint"], _paint_material(paint))
	far.visibility_range_end = parked_distance
	far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if type == "lkw" \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lights_off(far)
	node.add_child(far)
	var model := _model(type)
	if model:
		_add_parked_model(node, far, model, paint)
	elif use_models and TYPES[type].has("model"):
		_waiting_parked.append([node, type, paint, far])
	return node


func _add_parked_model(node: Node3D, far: MeshInstance3D, model: PreparedModel, paint: Color) -> void:
	far.visibility_range_begin = mid_distance
	far.visibility_range_begin_margin = 5.0
	var near := _lod_instance(model.near_mesh, 0.0, near_distance, paint)
	var mid := _lod_instance(model.mid_mesh, near_distance, mid_distance, paint)
	mid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lights_off(near)
	_lights_off(mid)
	node.add_child(near)
	node.add_child(mid)
	for i in model.wheel_meshes.size():
		var wheel := MeshInstance3D.new()
		wheel.mesh = model.wheel_meshes[i]
		wheel.position = model.wheel_centers[i]
		wheel.visibility_range_end = near_distance
		wheel.visibility_range_end_margin = 5.0
		node.add_child(wheel)


## Geparkt: Scheinwerfer, Rücklichter und Blinker aus (nicht das leuchtende Material des Verkehrs)
func _lights_off(instance: MeshInstance3D) -> void:
	var mesh := instance.mesh as ArrayMesh
	for i in mesh.get_surface_count():
		match mesh.surface_get_name(i):
			"head":
				instance.set_surface_override_material(i, _material("head_off"))
			"tail", "ind_l", "ind_r":
				instance.set_surface_override_material(i, _material("tail_off"))
	# Gebaute Kästen haben keine Flächennamen: über die gemerkten Nummern
	for type: String in _surface_index:
		if _meshes.get(type) == mesh:
			var indices: Dictionary = _surface_index[type]
			instance.set_surface_override_material(indices["head"], _material("head_off"))
			instance.set_surface_override_material(indices["tail"], _material("tail_off"))
			instance.set_surface_override_material(indices["ind_l"], _material("ind_off"))
			instance.set_surface_override_material(indices["ind_r"], _material("ind_off"))


## Geparkte Autos bekommen ihr Modell, sobald es geladen ist (alle 0,5 s nachsehen)
func _upgrade_parked(delta: float) -> void:
	if _waiting_parked.is_empty():
		return
	_parked_timer -= delta
	if _parked_timer > 0.0:
		return
	_parked_timer = 0.5
	var still: Array = []
	for entry: Array in _waiting_parked:
		var node: Node3D = entry[0]
		if not is_instance_valid(node):
			continue
		var model := _model(entry[1])
		if model:
			_add_parked_model(node, entry[3], model, entry[2])
		elif not _models.has(entry[1]):
			still.append(entry)
	_waiting_parked = still


## Zufällige Lackfarbe nach den Gewichten in PAINTS
func _pick_paint() -> Color:
	var total := 0
	for entry: Array in PAINTS:
		total += entry[1] as int
	var pick := _rng.randi_range(0, total - 1)
	for entry: Array in PAINTS:
		pick -= entry[1] as int
		if pick < 0:
			return entry[0]
	return PAINTS[0][0]


# ---------------------------------------------------------------------------
# Echte Modelle (nahe und mittlere Stufe)
# ---------------------------------------------------------------------------

## Vorbereitetes Modell des Typs (null = keins da oder noch beim Laden)
func _model(type: String) -> PreparedModel:
	if _models.has(type):
		return _models[type]
	if not use_models or not TYPES[type].has("model"):
		_models[type] = null
		return null
	var path := MODEL_PATH % TYPES[type]["model"]
	match ResourceLoader.load_threaded_get_status(path):
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return null
		ResourceLoader.THREAD_LOAD_LOADED:
			var model := ResourceLoader.load_threaded_get(path) as PreparedModel
			_models[type] = model
			if model:
				_set_model_materials(model)
			return model
	_models[type] = null
	return null


## Materialien nach den Rollen der Flächen (einmal pro Modell; Lack und Rücklicht setzt
## jedes Auto selbst)
func _set_model_materials(model: PreparedModel) -> void:
	var meshes: Array[ArrayMesh] = [model.near_mesh, model.mid_mesh]
	meshes.append_array(model.wheel_meshes)
	for mesh in meshes:
		for i in mesh.get_surface_count():
			var role := mesh.surface_get_name(i)
			match role:
				"paint":
					mesh.surface_set_material(i, _paint_material(PAINTS[0][0]))
				"glass", "cover", "head", "tail":
					mesh.surface_set_material(i, _material(role))
				_:
					mesh.surface_set_material(i, _material("body"))


## Nahe und mittlere Stufe, Räder und Blinker anbauen; die gebaute Kiste ist dann nur fern zu sehen
func _add_model(c: TrafficCar, model: PreparedModel, paint: Color) -> void:
	c.far.visibility_range_begin = mid_distance
	c.far.visibility_range_begin_margin = 5.0
	c.far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	c.near = _lod_instance(model.near_mesh, 0.0, near_distance, paint)
	c.mid = _lod_instance(model.mid_mesh, near_distance, mid_distance, paint)
	c.node.add_child(c.near)
	c.node.add_child(c.mid)
	for i in model.wheel_meshes.size():
		var wheel := MeshInstance3D.new()
		wheel.mesh = model.wheel_meshes[i]
		wheel.position = model.wheel_centers[i]
		wheel.visibility_range_end = near_distance
		wheel.visibility_range_end_margin = 5.0
		c.node.add_child(wheel)
		c.wheels.append(wheel)
	c.wheel_centers = model.wheel_centers
	if not model.wheel_centers.is_empty():
		c.wheel_radius = maxf(model.wheel_centers[0].y, 0.2)
	for side in 2:
		var lamp := MeshInstance3D.new()
		lamp.mesh = _lamp_mesh(model, side)
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lamp.visibility_range_end = mid_distance
		lamp.visible = false
		c.node.add_child(lamp)
		c.lamps.append(lamp)
	c.shown_shadow = false
	for mesh: MeshInstance3D in [c.near, c.mid] + c.wheels:
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Zufallskennzeichen mit einem Kürzel aus einem Ortsnamen in der Nähe (nur nah zu sehen)
	var place := roads.highways.place_name(Vector2i(floori(c.position.x / roads.cell_size) + _rng.randi_range(-3, 3),
		floori(c.position.z / roads.cell_size) + _rng.randi_range(-3, 3)))
	var text := LicensePlate.random(_rng, place)
	var spots := _plate_spots_of(model)
	for k in 2:
		var spot: Dictionary = spots[k]
		if spot.is_empty():
			continue
		var plate := LicensePlate.make_mesh(text, spot["size"])
		# 1,2 cm vor die Fläche des Original-Kennzeichens (entlang seiner Normale)
		var tilt := deg_to_rad(spot["tilt"])
		var normal := Vector3(0.0, sin(tilt), cos(tilt) * (1.0 if k == 0 else -1.0))
		LicensePlate.place(plate, (spot["center"] as Vector3) + normal * 0.012, k == 0, spot["tilt"])
		plate.visibility_range_end = near_distance
		c.node.add_child(plate)


## Wo am Modell die Kennzeichen hingehören: dort, wo das Original-Kennzeichen war
## (PreparedModel.plate_spots, gleiche Größe und Neigung), sonst vorderster bzw. hinterster Punkt in
## der Mitte auf Höhe der Stoßstange (vorne 0,40 m, hinten 0,55 m). Einmal pro Modell.
## Ergebnis: [vorne, hinten] als {"center", "size", "tilt"}, leer = keins
func _plate_spots_of(model: PreparedModel) -> Array:
	if _plate_spots.has(model):
		return _plate_spots[model]
	var stored: Array = model.plate_spots if model.plate_spots.size() == 2 else [{}, {}]
	var front := -INF
	var rear := INF
	for i in model.near_mesh.get_surface_count():
		var verts: PackedVector3Array = model.near_mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]
		for p in verts:
			if absf(p.x) > 0.3:
				continue
			if absf(p.y - 0.40) < 0.07:
				front = maxf(front, p.z)
			if absf(p.y - 0.55) < 0.07:
				rear = minf(rear, p.z)
	var result: Array = [stored[0], stored[1]]
	if (result[0] as Dictionary).is_empty() and not is_inf(front):
		result[0] = {"center": Vector3(0.0, 0.40, front), "size": LicensePlate.SIZE, "tilt": 0.0}
	if (result[1] as Dictionary).is_empty() and not is_inf(rear):
		result[1] = {"center": Vector3(0.0, 0.55, rear), "size": LicensePlate.SIZE, "tilt": 0.0}
	_plate_spots[model] = result
	return result


func _lod_instance(mesh: ArrayMesh, begin: float, end: float, paint: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.visibility_range_begin = begin
	instance.visibility_range_begin_margin = 5.0 if begin > 0.0 else 0.0
	instance.visibility_range_end = end
	instance.visibility_range_end_margin = 5.0
	var paint_index := PreparedModel.surface_index(mesh, "paint")
	if paint_index >= 0:
		instance.set_surface_override_material(paint_index, _paint_material(paint))
	return instance


## Blinker einer Seite (0 = links = +X): je ein Kästchen an der äußeren Ecke vorne und hinten
func _lamp_mesh(model: PreparedModel, side: int) -> ArrayMesh:
	var key := "%s/%d" % [model.resource_path, side]
	if _lamp_meshes.has(key):
		return _lamp_meshes[key]
	var mirror := Vector3(1.0 if side == 0 else -1.0, 1.0, 1.0)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(tool, model.front_corner * mirror - Vector3(0.0, 0.0, 0.03), Vector3(0.1, 0.06, 0.07))
	_box(tool, model.rear_corner * mirror + Vector3(0.0, 0.0, 0.03), Vector3(0.1, 0.06, 0.07))
	var mesh := tool.commit()
	mesh.surface_set_material(0, _material("ind_on"))
	_lamp_meshes[key] = mesh
	return mesh


# ---------------------------------------------------------------------------
# Gebaute Fahrzeuge aus Kästchen (fern und als Ersatz ohne Modell; vorne = +Z, Boden = 0)
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
	match TYPES[type]["shape"]:
		"limousine", "suv":
			var suv: bool = TYPES[type]["shape"] == "suv"
			var low := 0.45 if suv else 0.32
			var body_top := 1.15 if suv else 0.93
			var cabin_length := 2.8 if suv else 2.5
			var cabin_z := -0.35 if suv else -0.25
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
		mesh.surface_set_material(indices[key], _material(key) if key != "paint" else _paint_material(PAINTS[0][0]))
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


# ---------------------------------------------------------------------------
# Zurückspulen (Rewind, Taste Rücktaste)
# ---------------------------------------------------------------------------

## Fahrzustand jedes Autos aufzeichnen (jeden Physik-Schritt), älter als keep Sekunden fällt weg
func record(time: float, keep: float) -> void:
	for c in _cars:
		if c.born < 0.0:
			c.born = time
		c.snapshots.append([time, {"leg": c.leg, "s": c.s, "lateral": c.lateral, "lane_target": c.lane_target,
			"speed": c.speed, "plan": c.plan.duplicate(), "curve": c.curve, "curve_length": c.curve_length,
			"curve_t": c.curve_t, "next": c.next, "blink": c.blink, "blink_timer": c.blink_timer,
			"hazard": c.hazard, "crash_timer": c.crash_timer, "merge_end": c.merge_end,
			"decide_timer": c.decide_timer, "right_free_time": c.right_free_time, "braking": c.braking,
			"rule_leg": c.rule_leg, "wait_timer": c.wait_timer, "cleared": c.cleared}])
		while c.snapshots.size() > 1 and (c.snapshots[0][0] as float) < time - keep:
			c.snapshots.pop_front()


## Aufzeichnung verwerfen (z. B. nach einem Sprung des Spielers)
func clear_records() -> void:
	for c in _cars:
		c.born = -1.0
		c.snapshots.clear()


## Jedes Auto in den Zustand zur Zeit time setzen. Autos, die es da noch nicht gab, sind unsichtbar.
## finish = true: Zurückspulen ist vorbei, spätere Aufzeichnung fällt weg, Autos ohne Vergangenheit
## werden entfernt und der Verkehr fährt von hier aus weiter.
func show_time(time: float, finish: bool) -> void:
	for c in _cars.duplicate():
		if c.born < 0.0 or c.born > time or c.snapshots.is_empty():
			if finish:
				_remove(c)
			else:
				c.node.visible = false
				if c.body:
					c.body.global_position = c.position + Vector3.DOWN * 500.0
			continue
		# Letzter Zustand vor oder genau zu dieser Zeit (von hinten suchen: meist nah am Ende)
		var index: int = c.snapshots.size() - 1
		while index > 0 and (c.snapshots[index][0] as float) > time:
			index -= 1
		var state: Dictionary = c.snapshots[index][1]
		c.leg = state["leg"]
		c.s = state["s"]
		c.lateral = state["lateral"]
		c.lane_target = state["lane_target"]
		c.speed = state["speed"]
		c.plan.assign(state["plan"])
		c.curve = state["curve"]
		c.curve_length = state["curve_length"]
		c.curve_t = state["curve_t"]
		c.next = state["next"]
		c.blink = state["blink"]
		c.blink_timer = state["blink_timer"]
		c.hazard = state["hazard"]
		c.crash_timer = state["crash_timer"]
		c.merge_end = state["merge_end"]
		c.decide_timer = state["decide_timer"]
		c.right_free_time = state["right_free_time"]
		c.braking = state["braking"]
		c.rule_leg = state["rule_leg"]
		c.wait_timer = state["wait_timer"]
		c.cleared = state["cleared"]
		c.node.visible = true
		_update_pose(c)
		_place(c)
		if finish:
			c.snapshots.resize(index + 1)
	if finish:
		rewinding = false


## Für den Benchmark: [Autos auf der Autobahn, davon langsamer als 50 km/h]
func highway_stats() -> Vector2i:
	var total := 0
	var slow := 0
	for c in _cars:
		if c.leg.kind == Kind.HIGHWAY:
			total += 1
			if c.speed < 50.0 / 3.6:
				slow += 1
	return Vector2i(total, slow)

