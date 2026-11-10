class_name RoadNetwork
extends Node3D
## Das Straßennetz. Die Welt ist in Zellen (cell_size) eingeteilt, in jeder liegt höchstens
## ein „Ort“ (Knoten), bevorzugt flach und im Tal. Benachbarte Orte werden mit einer
## Straße verbunden (nach rechts und nach vorne). Jeder Abschnitt hängt nur von seinen
## zwei Orten ab: Deshalb ist das Netz endlos, nahtlos und bei gleichem Seed immer gleich.
##
## Jeder Abschnitt durchläuft im Hintergrund drei Schritte:
##  1. berechnen (RoadSegment.build): Weg, Kurven, Höhenprofil
##  2. prüfen: Kommt er außerhalb der Kreuzungen einer anderen Straße zu nahe (kreuzen,
##     überlappen), fällt der Abschnitt mit dem größeren Hash-Wert weg. Das hängt nur von
##     den beiden Abschnitten ab, ist also immer gleich, egal in welcher Reihenfolge
##     gerechnet wird.
##  3. Mesh bauen: erst wenn an beiden Orten feststeht, welche Straßen dort ankommen.
##     Die Straße endet am Rand der Kreuzung, die Kreuzung (RoadJunction) bekommt eine
##     eigene Fläche.
##
## Dazu kommen Autobahnen (Lage aus HighwayLayout): Abschnitte zwischen zwei Stützpunkten,
## an Anschlussstellen ein Zubringer vom Ort über die Autobahn und vier Rampen. Landstraßen
## werden erst berechnet, wenn die Autobahn in ihrer Nähe fertig ist, und führen dann per
## Brücke darüber (oder darunter durch). Schlüssel: Landstraße (Zelle x, Zelle z, 0/1),
## Autobahn (Stützpunkt, Linie, 2 + Achse), Anschlussstelle (Stützpunkt, Linie, 10 + 10·Achse + Teil).

## Material der Fahrbahn (road.gdshader)
@export var road_material: Material
## Material für Brücken (Beton)
@export var bridge_material: Material
## Landmarken-Brücken (Bogen, Hängebrücke) sind bis hierher zu sehen (Meter)
@export var landmark_distance: float = 6000.0
## Material für Leitplanken (Metall)
@export var rail_material: Material
@export_group("Dörfer")
## Dörfer: so viele echte Lichter an den nächsten Straßenlaternen (nachts), bis zu dieser
## Entfernung; Häuser werfen bis village_shadow_distance Schatten
@export var village_light_count: int = 6
@export var village_light_distance: float = 160.0
@export var village_shadow_distance: float = 700.0

@export_group("Autobahn")
## Material der Autobahn und der Rampen (road.gdshader mit lane_profile 1 bzw. 2)
@export var highway_material: Material
@export var ramp_material: Material
## Parkplatz der Raststätten (road.gdshader mit lane_profile 3)
@export var parking_material: Material
## Echte Lichter an Raststätten nur nachts und bis zu dieser Entfernung vom Auto
@export var rest_light_distance: float = 260.0
## Leitpfosten: Pfosten (Punktfarben) und Rückstrahler (leuchten im Scheinwerferlicht)
@export var post_material: Material
@export var reflector_material: Material
@export_group("")
## Material für Tunnelröhren und Portale (Beton, Farbe aus den Punktfarben) und Deckenlampen
@export var tunnel_material: Material
@export var lamp_material: Material
## Größe einer Zelle mit höchstens einem Ort (Meter)
@export var cell_size: float = 1200.0
## Wahrscheinlichkeit, dass zwei benachbarte Orte verbunden sind
@export_range(0.0, 1.0) var connection_chance: float = 0.8
## Breite der Fahrbahn (zwei Spuren) und des Banketts daneben.
## Alles andere (Markierungen, Brücken, Böschungen, Bäume) passt sich daran an.
@export var road_width: float = 9.0
@export var shoulder_width: float = 1.5
## Höchste Steigung (0.10 = 10 %)
@export var max_grade: float = 0.10
## Wunschradius normaler Kurven und kleinster Radius in engen Kehren (Meter)
@export var curve_radius: float = 60.0
@export var min_curve_radius: float = 20.0
## Querneigung in Kurven (0.05 = 5 %)
@export var max_bank: float = 0.05
## Rasterabstand der Wegsuche (kleiner = genauer, aber langsamer)
@export var grid_step: float = 18.0
## So weit vor der Kreuzungsmitte enden die Straßen mindestens (Meter).
## Laufen zwei Straßen spitz zusammen, wird es automatisch mehr.
@export var junction_radius: float = 14.0
## Bis zu dieser Entfernung werden Straßen vorab berechnet
@export var prefetch_distance: float = 2800.0
## Bis zu dieser Entfernung sind Straßen sichtbar
@export var mesh_distance: float = 2300.0
## Bis zu dieser Entfernung haben Straßen eine Kollision
@export var collision_distance: float = 600.0
## So viele Aufträge laufen gleichzeitig im Hintergrund
@export var max_parallel_jobs: int = 4
## So oft (Sekunden) wird das Netz rund ums Auto aktualisiert (und sofort, wenn ein
## Auftrag fertig wurde). Jedes Bild wäre unnötig teuer.
@export var update_interval: float = 0.1
## Abschnitte vor dem Auto zuerst berechnen: Bezugspunkt so viele Sekunden Fahrweg voraus
## (höchstens max_lookahead Meter)
@export var lookahead_seconds: float = 4.0
@export var max_lookahead: float = 600.0

## Die Schritte eines Abschnitts (in dieser Reihenfolge)
enum State { BUILDING, BUILT, CHECKING, CHECKED, MESHING, READY }

## Rund um gemeinsame Orte dürfen sich Straßen so nahe kommen (dort ist die Kreuzung)
const JUNCTION_CLEARANCE: float = 20.0
## So weit liegen die Abfahrtsrichtungen der Straßen eines Orts mindestens auseinander
const MIN_DEPARTURE_ANGLE: float = deg_to_rad(80.0)
## Ab dieser Entfernung wird ein Abschnitt ganz vergessen (wird bei Bedarf neu berechnet)
const FORGET_DISTANCE: float = 5300.0
## Autobahn: Breite (beide Richtungen mit Stand- und Mittelstreifen) und Breite der Rampen
const HIGHWAY_WIDTH: float = 25.5
const RAMP_WIDTH: float = 5.0
## Rampen: so lang (Meter entlang der Autobahn) und so weit von der Autobahnmitte treffen sie
## auf den Zubringer
const RAMP_LENGTH: float = 280.0
const RAMP_JOIN: float = 55.0
## Rampen beginnen bzw. enden im Zusatzfahrstreifen (Verzögerungs-/Beschleunigungsstreifen):
## Ihre innere Randlinie liegt dort auf der Randlinie der Autobahn (2,5 m Standstreifen).
## Sie liegen RAMP_LIFT höher, damit sich die Flächen dort nicht flimmernd überdecken.
const RAMP_LATERAL: float = HIGHWAY_WIDTH * 0.5 - 2.5 - 0.3 + RAMP_WIDTH * 0.5
const RAMP_LIFT: float = 0.04
## Der Zubringer endet so weit hinter der Autobahn
const CONNECTOR_BEYOND: float = 150.0
## Höhenunterschied, ab dem sich kreuzende Straßen nicht stören (Brücke darüber)
const CROSSING_CLEARANCE: float = 6.0
## Autobahn-Abschnitte werden erst so viel weiter weg vergessen als Landstraßen
const HIGHWAY_FORGET_EXTRA: float = 4500.0
## Auf der Autobahn fährt man rechts: Mitte des rechten Fahrstreifens, Abstand zur Mittellinie
const HIGHWAY_LANE_OFFSET: float = 8.1

var world_gen: WorldGen
var target: Node3D
## Wo die Autobahnen verlaufen
var highways: HighwayLayout
var _nodes: Dictionary = {}  # Vector2i -> Vector3 (Ort) oder null (kein Ort in der Zelle)
var _entries: Dictionary = {}  # Vector3i (Zelle x, Zelle z, Richtung) -> Entry
## Abschnitte, die berechnet werden sollen: 1 = nur berechnen, 2 = auch prüfen
var _wanted: Dictionary = {}  # Vector3i -> int
var _edge_cache: Dictionary = {}  # Vector3i -> bool (gibt es diese Verbindung?)
var _junctions: Dictionary = {}  # Vector2i -> RoadJunction
var _villages: Dictionary = {}  # Vector2i -> Village
var _lantern_lights: Array[OmniLight3D] = []
var _departures: Dictionary = {}  # Vector2i -> Dictionary (Nachbarzelle -> Richtung)
## Abschnitte, die es sicher nicht gibt (zu steil, überlappt): bleibt gemerkt, auch wenn
## der Abschnitt selbst vergessen wird (für das Navi)
var _missing: Dictionary = {}  # Vector3i -> true
var _running: int = 0
var _update_timer: float = 0.0
var _velocity := Vector2.ZERO
var _rest_lights: Array[OmniLight3D] = []
## Vorbereitetes Tankstellen-Modell (fehlt es, wird die Tankstelle aus Kästen gebaut)
const STATION_MODEL := "res://assets/models/raststaette/small_red_gas_station/prepared/model.res"
var _glow_timer: float = 0.0
var _day_night: DayNight
var _last_target := Vector2.ZERO


## Ein Straßenabschnitt und was dazu in der Szene steht
class Entry:
	var segment: RoadSegment
	var state: int = State.BUILDING
	var task_id: int = -1
	## Wird der Abschnitt gebraucht (nicht nur als Nachbar beim Prüfen)? Dann auch prüfen.
	var needed: bool = false
	## Bleibt der Abschnitt im Netz? (gültig und keine Überlappung mit einem wichtigeren)
	var kept: bool = false
	## Abschnitte, denen dieser nahe kommen könnte (wird einmal ausgerechnet)
	var neighbors: Array[Vector3i] = []
	var has_neighbors: bool = false
	var check: OverlapCheck
	var mesh_instance: MeshInstance3D
	## Bogen bzw. Pylone und Seile einer Landmarken-Brücke (von weitem sichtbar)
	var landmark_instance: Node3D
	var body: StaticBody3D


## Hintergrund-Auftrag: Kommt ein Abschnitt einem wichtigeren Abschnitt zu nahe?
class OverlapCheck:
	var segment: RoadSegment
	var others: Array = []  # RoadSegments mit kleinerem Hash-Wert
	## Autobahn, Zubringer und Rampen: zählen nur, wo der Höhenunterschied klein ist
	var raised: Array = []
	var distance: float
	var overlaps: bool = false

	func run() -> void:
		for other: RoadSegment in others:
			if segment.comes_close(other, distance, JUNCTION_CLEARANCE):
				overlaps = true
				return
		for other: RoadSegment in raised:
			var gap := distance + (other.road_width - segment.road_width) * 0.5
			if segment.comes_close(other, gap, JUNCTION_CLEARANCE, CROSSING_CLEARANCE):
				overlaps = true
				return


func start(gen: WorldGen, follow: Node3D) -> void:
	world_gen = gen
	target = follow
	highways = HighwayLayout.new(world_gen, self)
	# Der Straßen-Shader braucht die Breite, damit die Markierungen an der richtigen Stelle sitzen
	if road_material is ShaderMaterial:
		(road_material as ShaderMaterial).set_shader_parameter("road_width", road_width)
	if highway_material is ShaderMaterial:
		(highway_material as ShaderMaterial).set_shader_parameter("road_width", HIGHWAY_WIDTH)
	if ramp_material is ShaderMaterial:
		(ramp_material as ShaderMaterial).set_shader_parameter("road_width", RAMP_WIDTH)
	if parking_material is ShaderMaterial:
		(parking_material as ShaderMaterial).set_shader_parameter("road_width", HighwayLayout.REST_WIDTH)


# ---------------------------------------------------------------------------
# Schlüssel der Autobahn
# ---------------------------------------------------------------------------

static func is_road_key(key: Vector3i) -> bool:
	return key.z < 2


static func is_highway_key(key: Vector3i) -> bool:
	return key.z == 2 or key.z == 3


static func is_interchange_key(key: Vector3i) -> bool:
	return key.z >= 10 and key.z < 40


## Raststätte: (k, Linie, 40 + 10 · Achse + (0 bzw. 5 für Fahrtrichtung -1) + Teil),
## Teil 0 = Parkplatz, 1 = Ausfahrt, 2 = Einfahrt
static func is_rest_key(key: Vector3i) -> bool:
	return key.z >= 40


static func rest_key(axis: int, line: int, k: int, dir: int, part: int) -> Vector3i:
	return Vector3i(k, line, 40 + 10 * axis + (0 if dir > 0 else 5) + part)


static func rest_dir(key: Vector3i) -> int:
	return 1 if (key.z - 40) % 10 < 5 else -1


static func rest_part(key: Vector3i) -> int:
	return (key.z - 40) % 5


## Achse der Autobahn (0 = west–ost, 1 = nord–süd) zu einem Autobahn-, Anschlussstellen- oder
## Raststätten-Schlüssel
static func highway_axis(key: Vector3i) -> int:
	if is_highway_key(key):
		return key.z - 2
	if is_rest_key(key):
		return floori((key.z - 40) / 10.0)
	return floori((key.z - 10) / 10.0)


## Teil einer Anschlussstelle: 0 = Zubringer, 1–4 = Rampen
static func interchange_part(key: Vector3i) -> int:
	return (key.z - 10) % 10


static func interchange_key(axis: int, line: int, k: int, part: int) -> Vector3i:
	return Vector3i(k, line, 10 + 10 * axis + part)


## Gibt es den Abschnitt zu diesem Schlüssel?
func _key_exists(key: Vector3i) -> bool:
	if is_road_key(key):
		return _edge_exists(Vector2i(key.x, key.y), key.z)
	if is_highway_key(key):
		return highways.line_exists(highway_axis(key), key.y)
	if is_rest_key(key):
		return not highways.rest_area_at(highway_axis(key), key.y, key.x, rest_dir(key)).is_empty()
	return not highways.interchange_at(highway_axis(key), key.y, key.x).is_empty()


func _process(delta: float) -> void:
	if world_gen == null or target == null:
		return
	# Tempo messen (weich, ein Sprung zählt nicht)
	var here := Vector2(target.global_position.x, target.global_position.z)
	if delta > 0.0:
		var moved := here - _last_target
		var now := moved / delta if moved.length() < 100.0 else Vector2.ZERO
		_velocity = _velocity.lerp(now, clampf(delta * 3.0, 0.0, 1.0))
	_last_target = here
	_update_night_glow(delta)
	_update_timer -= delta
	if _collect_finished() == 0 and _update_timer > 0.0:
		return
	_update_timer = update_interval
	_prefetch()
	_advance()
	_dispatch()
	_update_visuals()


func _exit_tree() -> void:
	for entry: Entry in _entries.values():
		if entry.task_id != -1:
			WorkerThreadPool.wait_for_task_completion(entry.task_id)
			entry.task_id = -1


# ---------------------------------------------------------------------------
# Orte und Verbindungen
# ---------------------------------------------------------------------------

## Der Ort in einer Zelle (Vector3) oder null, wenn dort keiner liegt
func node_at(cell: Vector2i) -> Variant:
	if _nodes.has(cell):
		return _nodes[cell]
	var rng := RandomNumberGenerator.new()
	rng.seed = world_gen.hash_cell(cell.x, cell.y, 202)
	var margin := cell_size * 0.15
	var best: Variant = null
	var best_score := INF
	# Führt eine Straße von hier über eine Staumauer, soll der Ort hinter dem nahen Mauerende
	# liegen (sonst müsste die Straße über die Mauer hinaus und in einer Kehre zurück)
	var dams: Array = []
	for option: Array in _arm_keys(cell):
		var lake := world_gen.dam_for_road(option[0])
		if lake:
			dams.append(lake)
	# Mehrere Zufallsstellen probieren und die flachste, tiefste nehmen
	for i in 8:
		var p := Vector2(cell.x * cell_size + rng.randf_range(margin, cell_size - margin),
			cell.y * cell_size + rng.randf_range(margin, cell_size - margin))
		# Nicht auf der Autobahn-Trasse
		if highways and not highways.is_clear(p, HighwayLayout.PLACE_CLEARANCE):
			continue
		var lakes: Array = world_gen.lakes_near(Rect2(p.x - 60.0, p.y - 60.0, 120.0, 120.0))
		if world_gen.water_level_at(p.x, p.y, lakes) > WorldGen.NO_WATER:
			continue
		var too_close_to_lake := false
		for lake: WorldGen.Lake in lakes:
			if lake.covers(p, 50.0):
				too_close_to_lake = true
		if too_close_to_lake:
			continue
		var h := world_gen.terrain_height(p.x, p.y, lakes)
		var relief := h - world_gen.ground_level(p.x, p.y)
		var slope := (absf(world_gen.terrain_height(p.x + 20.0, p.y, lakes) - h)
			+ absf(world_gen.terrain_height(p.x, p.y + 20.0, lakes) - h)) / 20.0
		var score := relief + slope * 400.0
		for lake: WorldGen.Lake in dams:
			var along := (lake.dam_b - lake.dam_a).normalized()
			var center := Vector2(cell) * cell_size + Vector2.ONE * cell_size * 0.5
			var end_point := lake.dam_a if center.distance_to(lake.dam_a) < center.distance_to(lake.dam_b) else lake.dam_b
			var outward := -along if end_point == lake.dam_a else along
			if (p - end_point).dot(outward) < 120.0:
				score += 100000.0
		if relief < 300.0 and score < best_score:
			best_score = score
			best = Vector3(p.x, h, p.y)
	_nodes[cell] = best
	return best


## Gibt es eine Straße von dieser Zelle nach rechts (dir 0) bzw. nach vorne (dir 1)?
func _edge_exists(cell: Vector2i, dir: int) -> bool:
	var key := Vector3i(cell.x, cell.y, dir)
	if _edge_cache.has(key):
		return _edge_cache[key]
	var other := cell + (Vector2i(1, 0) if dir == 0 else Vector2i(0, 1))
	var exists := false
	if node_at(cell) != null and node_at(other) != null:
		var rng := RandomNumberGenerator.new()
		rng.seed = world_gen.hash_cell(cell.x, cell.y, 303 + dir)
		# Über eine Staumauer führt immer eine Straße
		exists = rng.randf() < connection_chance or world_gen.dam_for_road(key) != null
	_edge_cache[key] = exists
	return exists


func _edge_nodes(key: Vector3i) -> Array:
	return [node_at(Vector2i(key.x, key.y)), node_at(_end_cell(key))]


## Zelle des Orts, an dem der Abschnitt endet
func _end_cell(key: Vector3i) -> Vector2i:
	return Vector2i(key.x, key.y) + (Vector2i(1, 0) if key.z == 0 else Vector2i(0, 1))


## Die (bis zu) vier Abschnitte an einem Ort: [Schlüssel, true = beginnt hier]
func _arm_keys(cell: Vector2i) -> Array:
	return [[Vector3i(cell.x, cell.y, 0), true], [Vector3i(cell.x, cell.y, 1), true],
		[Vector3i(cell.x - 1, cell.y, 0), false], [Vector3i(cell.x, cell.y - 1, 1), false]]


## Richtung, in der die Straße zur Nachbarzelle den Ort verlässt (für HighwayLayout)
func departure(cell: Vector2i, toward: Vector2i) -> Vector2:
	return _departure(cell, toward)


## Richtung, in der die Straße zur Nachbarzelle den Ort in cell verlässt.
## Wie die Luftlinie, aber die Straßen eines Orts liegen mindestens MIN_DEPARTURE_ANGLE
## auseinander. Hängt nur vom Ort und seinen Nachbarn ab, ist also immer gleich.
func _departure(cell: Vector2i, toward: Vector2i) -> Vector2:
	if not _departures.has(cell):
		var center: Vector3 = node_at(cell)
		var others: Array[Vector2i] = []
		var angles: Array[float] = []
		for option: Array in _arm_keys(cell):
			var key: Vector3i = option[0]
			if not _edge_exists(Vector2i(key.x, key.y), key.z):
				continue
			var other_cell := _end_cell(key) if option[1] else Vector2i(key.x, key.y)
			var other: Vector3 = node_at(other_cell)
			others.append(other_cell)
			# Über eine Staumauer: zum nahen Mauerende statt zum anderen Ort
			var lake := world_gen.dam_for_road(key)
			if lake:
				var entry_point := dam_entry(lake, Vector2(center.x, center.z), Vector2(other.x, other.z))
				angles.append(atan2(entry_point.y - center.z, entry_point.x - center.x))
			else:
				angles.append(atan2(other.z - center.z, other.x - center.x))
		# Zu eng beieinander liegende Richtungen ein Stück auseinanderdrehen
		for attempt in 30:
			for a in angles.size():
				for b in range(a + 1, angles.size()):
					var diff := angle_difference(angles[a], angles[b])
					if absf(diff) < MIN_DEPARTURE_ANGLE:
						var push := (MIN_DEPARTURE_ANGLE - absf(diff)) * 0.5 * (1.0 if diff >= 0.0 else -1.0)
						angles[a] -= push
						angles[b] += push
		var result := {}
		for i in others.size():
			result[others[i]] = Vector2.from_angle(angles[i])
		_departures[cell] = result
	return _departures[cell].get(toward, Vector2.ZERO)


## Talsperren-Straße: An welchem Mauerende (verlängert um RoadSegment.DAM_RUNOUT) fährt die
## Straße von here aus auf die Krone, wenn sie zu other weiterführt? (Kürzere Summe der Wege)
static func dam_entry(lake: WorldGen.Lake, here: Vector2, other: Vector2) -> Vector2:
	var along := (lake.dam_b - lake.dam_a).normalized()
	var ext_a := lake.dam_a - along * RoadSegment.DAM_RUNOUT
	var ext_b := lake.dam_b + along * RoadSegment.DAM_RUNOUT
	return ext_a if here.distance_to(ext_a) + other.distance_to(ext_b) <= here.distance_to(ext_b) + other.distance_to(ext_a) else ext_b


## Fester Zufallswert pro Abschnitt: Überlappen sich zwei, fällt der mit dem größeren weg
func _priority(key: Vector3i) -> int:
	# Straßen über eine Staumauer gehen vor (sonst fiele die Mauer weg)
	if world_gen.dam_for_road(key) != null:
		return -1
	return world_gen.hash_cell(key.x * 2 + key.z, key.y, 404)


## Abschnitt anfordern: level 1 = nur berechnen, 2 = auch prüfen (wird wirklich gebraucht)
func _want(key: Vector3i, level: int) -> void:
	var entry: Entry = _entries.get(key)
	if entry:
		if level >= 2:
			entry.needed = true
	else:
		_wanted[key] = maxi(_wanted.get(key, 0), level)


## Bereich, den ein Abschnitt höchstens beeinflussen kann (bevor er berechnet ist)
func _edge_area(key: Vector3i) -> Rect2:
	if is_highway_key(key):
		# Die Mittellinie steht ohne Wegsuche fest
		return highways.centerline_box(highway_axis(key), key.y, key.x).grow(HIGHWAY_WIDTH + RoadSegment.MAX_BANK + 30.0)
	if is_rest_key(key):
		var rest := highways.rest_area_at(highway_axis(key), key.y, key.x, rest_dir(key))
		var center: Vector3 = rest.get("center", Vector3.ZERO)
		return Rect2(center.x, center.z, 0.0, 0.0).grow(HighwayLayout.REST_HALF_LARGE + RAMP_LENGTH + 80.0)
	if is_interchange_key(key):
		var interchange := highways.interchange_at(highway_axis(key), key.y, key.x)
		var place: Vector3 = interchange.get("place", Vector3.ZERO)
		var point: Vector3 = interchange.get("point", Vector3.ZERO)
		return Rect2(place.x, place.z, 0.0, 0.0).expand(Vector2(point.x, point.z)).grow(RAMP_LENGTH + 150.0)
	var ends := _edge_nodes(key)
	var a: Vector3 = ends[0]
	var b: Vector3 = ends[1]
	var length := Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
	var rect := Rect2(a.x, a.z, 0.0, 0.0).expand(Vector2(b.x, b.z))
	return rect.grow(RoadSegment.corridor_half_width(length) + 150.0 + road_width + RoadSegment.MAX_BANK)


## Alle Verbindungen, die einen Bereich beeinflussen könnten
func _edges_touching(rect: Rect2) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var reach := 700.0
	var x0 := floori((rect.position.x - reach) / cell_size) - 1
	var x1 := floori((rect.end.x + reach) / cell_size)
	var z0 := floori((rect.position.y - reach) / cell_size) - 1
	var z1 := floori((rect.end.y + reach) / cell_size)
	for cz in range(z0, z1 + 1):
		for cx in range(x0, x1 + 1):
			for dir in 2:
				var cell := Vector2i(cx, cz)
				if _edge_exists(cell, dir) and _edge_area(Vector3i(cx, cz, dir)).intersects(rect):
					result.append(Vector3i(cx, cz, dir))
	# Autobahn-Abschnitte und Anschlussstellen
	if highways:
		for section: Array in highways.sections_touching(rect):
			var axis: int = section[0]
			var line: int = section[1]
			var k: int = section[2]
			result.append(Vector3i(k, line, 2 + axis))
			for at: int in [k, k + 1]:
				for dir: int in [1, -1]:
					if highways.rest_area_at(axis, line, at, dir).is_empty():
						continue
					for part in 3:
						var rest := rest_key(axis, line, at, dir, part)
						if not result.has(rest) and _edge_area(rest).intersects(rect):
							result.append(rest)
				if highways.interchange_at(axis, line, at).is_empty():
					continue
				for part in 5:
					var key := interchange_key(axis, line, at, part)
					if not result.has(key) and _edge_area(key).intersects(rect):
						result.append(key)
	return result


# ---------------------------------------------------------------------------
# Abfragen für Gelände, Spiel und Autopilot
# ---------------------------------------------------------------------------

## Fertige Straßen für einen Bereich: {"segments": [RoadSegment], "pads": PackedVector4Array}
## pads sind die Kreuzungen (Mitte x, y, z und Radius). Leeres Dictionary = noch nicht fertig.
func segments_for_rect(rect: Rect2) -> Dictionary:
	var segments: Array = []
	var cells := {}
	var complete := true
	# Parkbuchten an Aussichtspunkten: flach wie Kreuzungen
	var bay_pads := PackedVector4Array()
	for key in _edges_touching(rect):
		var entry: Entry = _entries.get(key)
		_want(key, 2)
		if entry == null or entry.state < State.CHECKED:
			complete = false
			continue
		if entry.kept and entry.segment.bounds.intersects(rect):
			segments.append(entry.segment)
			if not entry.segment.viewpoint.is_empty():
				bay_pads.append_array(Viewpoints.bay_pads(entry.segment))
			if is_road_key(key):
				cells[Vector2i(key.x, key.y)] = true
				cells[_end_cell(key)] = true
			elif is_interchange_key(key) and interchange_part(key) == 0:
				cells[highways.interchange_at(highway_axis(key), key.y, key.x)["cell"]] = true
	if not complete:
		return {}
	# Orte, deren Dorf bis hierher reichen kann (Häuser ebnen das Gelände ein)
	var near := rect.grow(Village.REACH + 100.0)
	for cz in range(floori(near.position.y / cell_size), floori(near.end.y / cell_size) + 1):
		for cx in range(floori(near.position.x / cell_size), floori(near.end.x / cell_size) + 1):
			var node: Variant = node_at(Vector2i(cx, cz))
			if node != null and near.has_point(Vector2((node as Vector3).x, (node as Vector3).z)):
				cells[Vector2i(cx, cz)] = true
	var pads := PackedVector4Array()
	for cell: Vector2i in cells:
		var junction := _junction(cell)
		if junction == null:
			complete = false
			continue
		# Etwas größer als die Kreuzungsfläche, damit das Gelände rundherum flach bleibt
		pads.append(Vector4(junction.center.x, junction.center.y, junction.center.z, junction.radius + 4.0))
		var village := _village(cell)
		if village == null:
			complete = false
			continue
		pads.append_array(village.pads)
	if not complete:
		return {}
	pads.append_array(bay_pads)
	return {"segments": segments, "pads": pads}


## Sind alle Straßen rund um diesen Punkt fertig (inklusive Mesh und Kollision)?
func is_area_ready(center: Vector2, radius: float) -> bool:
	var rect := Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
	if segments_for_rect(rect).is_empty():
		return false
	for key in _edges_touching(rect):
		var entry: Entry = _entries[key]
		if entry.kept and entry.state != State.READY and _distance_to_rect(center, entry.segment.bounds) < radius:
			return false
	return true


## Nächste Stelle auf einer Straße. preferred_forward wählt die passende Fahrtrichtung.
## Ergebnis: {"found": bool, "transform": Transform3D}
func nearest_road_transform(near: Vector3, preferred_forward: Vector3 = Vector3.ZERO, highway_only: bool = false) -> Dictionary:
	var best_segment: RoadSegment = null
	var best_index := -1
	var best_distance := INF
	for entry: Entry in _entries.values():
		if entry.state != State.READY or not entry.kept:
			continue
		if highway_only and entry.segment.kind != RoadSegment.Kind.HIGHWAY:
			continue
		var points := entry.segment.points
		# Nicht direkt auf einer Kreuzung starten
		for i in range(6, points.size() - 6):
			var d := Vector2(points[i].x - near.x, points[i].z - near.z).length_squared()
			if d < best_distance:
				best_distance = d
				best_segment = entry.segment
				best_index = i
	if best_segment == null:
		return {"found": false}
	var p := best_segment.points[best_index]
	var forward := best_segment.direction_at(best_index)
	if preferred_forward != Vector3.ZERO and forward.dot(preferred_forward) < 0.0:
		forward = -forward
	# Autobahn: auf den rechten Fahrstreifen, nicht auf den Mittelstreifen
	if best_segment.kind == RoadSegment.Kind.HIGHWAY:
		p += forward.cross(Vector3.UP).normalized() * HIGHWAY_LANE_OFFSET
	# Raststätte: in die Fahrgasse an der Autobahnseite (auf der Mittellinie stehen Autos und
	# die Tankstelle). Fahrtrichtung des Parkplatzes = Punktreihenfolge, die Autobahn liegt links.
	if is_rest_key(best_segment.key) and rest_part(best_segment.key) == 0:
		var lot_forward := best_segment.direction_at(best_index)
		p += Vector3.UP.cross(lot_forward).normalized() * (HighwayLayout.REST_WIDTH * 0.5 - 4.5)
		forward = lot_forward
	var yaw := atan2(forward.x, forward.z)
	return {"found": true, "transform": Transform3D(Basis(Vector3.UP, yaw), p + Vector3.UP * 1.0)}


## Ein Fahrweg ab dem nächsten Straßenpunkt in Blickrichtung, über Kreuzungen hinweg.
## Für den Autopiloten im Benchmark.
func route_from(near: Vector3, forward: Vector3, min_length: float) -> PackedVector3Array:
	var route := PackedVector3Array()
	var best_key := Vector3i.ZERO
	var best_index := -1
	var best_distance := INF
	for key: Vector3i in _entries.keys():
		var entry: Entry = _entries[key]
		if entry.state < State.CHECKED or not entry.kept:
			continue
		var points := entry.segment.points
		for i in points.size():
			var d := points[i].distance_squared_to(near)
			if d < best_distance:
				best_distance = d
				best_key = key
				best_index = i
	if best_index == -1:
		return route
	var segment: RoadSegment = _entries[best_key].segment
	var going_forward := segment.direction_at(best_index).dot(forward) >= 0.0
	var key := best_key
	var visited := {}
	while true:
		visited[key] = true
		var points := segment.points
		# Auf der Autobahn rechts fahren (der Weg liegt auf dem rechten Fahrstreifen)
		var lane := HIGHWAY_LANE_OFFSET if segment.kind == RoadSegment.Kind.HIGHWAY else 0.0
		if going_forward:
			for i in range(best_index, points.size()):
				route.append(points[i] + segment.direction_at(i).cross(Vector3.UP).normalized() * lane)
		else:
			for i in range(best_index, -1, -1):
				route.append(points[i] - segment.direction_at(i).cross(Vector3.UP).normalized() * lane)
		if (route.size() - 1) * RoadSegment.POINT_SPACING > min_length:
			break
		# Autobahn: einfach im nächsten Abschnitt derselben Linie weiter
		if is_highway_key(key):
			var next_key := key + Vector3i(1 if going_forward else -1, 0, 0)
			var next_entry: Entry = _entries.get(next_key)
			if next_entry == null or next_entry.state < State.CHECKED or not next_entry.kept:
				break
			key = next_key
			segment = next_entry.segment
			best_index = 1 if going_forward else segment.points.size() - 2
			continue
		# Am Ende angekommen: an diesem Ort eine andere, noch nicht befahrene Straße nehmen
		var end_cell := _end_cell(key) if going_forward else Vector2i(key.x, key.y)
		var arriving := route[route.size() - 1] - route[maxi(route.size() - 7, 0)]
		arriving.y = 0.0
		var next := _next_segment_at(end_cell, visited, arriving.normalized())
		if next.is_empty():
			break
		key = next["key"]
		segment = _entries[key].segment
		going_forward = next["forward"]
		best_index = 1 if going_forward else segment.points.size() - 2
	return route


## Test (--exitdrive): Route über die nächste Ausfahrt einer Anschlussstelle in Fahrtrichtung
## (rechte Spur, Verzögerungsstreifen, Ausfahrt, Zubringer über die Brücke, Einfahrt auf der
## anderen Seite, Beschleunigungsstreifen, Autobahn zurück). Leer = keine passende Ausfahrt geladen.
func exit_route(near: Vector3, forward: Vector3) -> PackedVector3Array:
	var route := PackedVector3Array()
	var best_key := Vector3i.ZERO
	var best_index := -1
	var best_distance := INF
	for key: Vector3i in _entries.keys():
		var entry: Entry = _entries[key]
		if not is_highway_key(key) or entry.state < State.CHECKED:
			continue
		for i in entry.segment.points.size():
			var d := entry.segment.points[i].distance_squared_to(near)
			if d < best_distance:
				best_distance = d
				best_key = key
				best_index = i
	if best_index == -1:
		return route
	var axis := highway_axis(best_key)
	var line := best_key.y
	var going_forward := (_entries[best_key] as Entry).segment.direction_at(best_index).dot(forward) >= 0.0
	var dir := 1 if going_forward else -1
	# Nächste Anschlussstelle, deren Ausfahrt noch mindestens 400 m voraus beginnt
	var key := best_key
	var from_index := best_index
	for step in 4:
		var k := key.x + 1 if going_forward else key.x
		var segment := (_entries[key] as Entry).segment
		if not highways.interchange_at(axis, line, k).is_empty():
			var exit_part := 3 if going_forward else 1
			var entry_part := 2 if going_forward else 4
			var exit_entry: Entry = _entries.get(interchange_key(axis, line, k, exit_part))
			var entry_entry: Entry = _entries.get(interchange_key(axis, line, k, entry_part))
			var connector: Entry = _entries.get(interchange_key(axis, line, k, 0))
			var gore := ramp_ends(axis, line, k, exit_part)[0]
			var gore_index := _nearest_index(segment, gore)
			var ahead := (gore_index - from_index) * dir
			if ahead * RoadSegment.POINT_SPACING > 400.0 and exit_entry and entry_entry and connector \
					and exit_entry.state >= State.CHECKED and entry_entry.state >= State.CHECKED \
					and connector.state >= State.CHECKED:
				# 1. Autobahn bis zur Ausfahrt, am Ende der Verziehung auf den Verzögerungsstreifen
				var i := from_index
				while i != gore_index:
					var to_gore := (gore_index - i) * dir * RoadSegment.POINT_SPACING
					var blend := clampf((RoadSegment.AUX_PARALLEL + 40.0 - to_gore) / 100.0, 0.0, 1.0)
					route.append(_lane_point(segment, i, dir, lerpf(HIGHWAY_LANE_OFFSET, RAMP_LATERAL - 0.2, blend)))
					i += dir
				# 2. Ausfahrt, Zubringer (über die Brücke), Einfahrt
				var exit_points := exit_entry.segment.points
				route.append_array(exit_points)
				var c_points := connector.segment.points
				var from := _nearest_index(connector.segment, Vector2(exit_points[exit_points.size() - 1].x,
					exit_points[exit_points.size() - 1].z))
				var entry_points := entry_entry.segment.points
				var to := _nearest_index(connector.segment, Vector2(entry_points[0].x, entry_points[0].z))
				var c_step := 1 if to > from else -1
				for c in range(from, to + c_step, c_step):
					route.append(c_points[c])
				route.append_array(entry_points)
				# 3. Autobahn in Gegenrichtung ab dem Ende der Einfahrt, vom Beschleunigungsstreifen
				# nach 150 m auf die rechte Spur
				var back_dir := -dir
				var merge := ramp_ends(axis, line, k, entry_part)[1]
				var back_key := Vector3i(k - 1, line, best_key.z) if going_forward else Vector3i(k, line, best_key.z)
				var back_entry: Entry = _entries.get(back_key)
				if back_entry == null or back_entry.state < State.CHECKED:
					return route
				var back := back_entry.segment
				var m := _nearest_index(back, merge)
				for n in 250:
					var j := m + n * back_dir
					if j < 0 or j >= back.points.size():
						break
					var blend := clampf((n * RoadSegment.POINT_SPACING - 120.0) / 80.0, 0.0, 1.0)
					route.append(_lane_point(back, j, back_dir, lerpf(RAMP_LATERAL - 0.2, HIGHWAY_LANE_OFFSET, blend)))
				return route
		# Weiter zum nächsten Abschnitt (bis dahin rechte Spur)
		var last := segment.points.size() - 1 if going_forward else 0
		for i in range(from_index, last + dir, dir):
			route.append(_lane_point(segment, i, dir, HIGHWAY_LANE_OFFSET))
		var next_key := key + Vector3i(dir, 0, 0)
		var next_entry: Entry = _entries.get(next_key)
		if next_entry == null or next_entry.state < State.CHECKED:
			return PackedVector3Array()
		key = next_key
		from_index = 0 if going_forward else next_entry.segment.points.size() - 1
	return PackedVector3Array()


func _nearest_index(segment: RoadSegment, p: Vector2) -> int:
	var best := 0
	var best_distance := INF
	for i in segment.points.size():
		var d := Vector2(segment.points[i].x - p.x, segment.points[i].z - p.y).length_squared()
		if d < best_distance:
			best_distance = d
			best = i
	return best


## Punkt rechts neben der Mittellinie (in Fahrtrichtung dir)
func _lane_point(segment: RoadSegment, i: int, dir: int, lateral: float) -> Vector3:
	var travel := segment.direction_at(i) * float(dir)
	return segment.points[i] + travel.cross(Vector3.UP).normalized() * lateral


func _next_segment_at(cell: Vector2i, visited: Dictionary, arriving: Vector3) -> Dictionary:
	# Straßen, die an diesem Ort beginnen (vorwärts) oder enden (rückwärts).
	# Genommen wird die, bei der man am wenigsten abbiegen muss.
	var options := _arm_keys(cell)
	var best: Dictionary = {}
	var best_dot := -2.0
	for option: Array in options:
		var key: Vector3i = option[0]
		if visited.has(key):
			continue
		var entry: Entry = _entries.get(key)
		if entry == null or entry.state < State.CHECKED or not entry.kept:
			continue
		var points := entry.segment.points
		var leaving: Vector3 = points[mini(6, points.size() - 1)] - points[0] if option[1] \
			else points[maxi(points.size() - 7, 0)] - points[points.size() - 1]
		leaving.y = 0.0
		var dot := leaving.normalized().dot(arriving)
		if dot > best_dot:
			best_dot = dot
			best = {"key": key, "forward": option[1]}
	return best


# ---------------------------------------------------------------------------
# Tunnel
# ---------------------------------------------------------------------------

## Wie weit ist dieser Punkt in einem Tunnel? 0 = draußen, 1 = tief drin (ab ~20 m hinter
## dem Portal). Für Licht, Hall, Regen und Grip.
func tunnel_cover(pos: Vector3) -> float:
	var best := 0.0
	var p := Vector2(pos.x, pos.z)
	for entry: Entry in _entries.values():
		if entry.state != State.READY or not entry.kept or entry.segment.tunnel_ranges.is_empty():
			continue
		var segment := entry.segment
		if not segment.bounds.has_point(p):
			continue
		var half := segment.tube_half_width() + 0.5
		for r in segment.tunnel_ranges:
			# Bis zwei Punkte vor dem Portal mitzählen (dort beginnt es langsam)
			var i := maxi(r.x - 2, 0)
			var last := mini(r.y + 2, segment.points.size() - 1)
			while i <= last:
				var q := segment.points[i]
				var d := Vector2(q.x - pos.x, q.z - pos.z).length()
				if d > half:
					# Die Punkte liegen 4 m auseinander: so viele kann man sicher überspringen
					i += maxi(int((d - half) / RoadSegment.POINT_SPACING), 1)
					continue
				if pos.y > q.y - 3.0 and pos.y < q.y + RoadSegment.TUBE_APEX + 1.0:
					# Enden, an denen der Tunnel im nächsten Abschnitt weiterläuft, sind keine Portale
					var from_start := (i - r.x) * RoadSegment.POINT_SPACING if r.x > 0 else 1e6
					var from_end := (r.y - i) * RoadSegment.POINT_SPACING if r.y < segment.points.size() - 1 else 1e6
					var depth := minf(from_start, from_end)
					best = maxf(best, clampf((depth + 6.0) / 26.0, 0.0, 1.0))
				i += 1
	return best


## Nächster Tunnel voraus auf der Straße, auf der das Auto gerade fährt:
## {"distance": Meter bis zum Portal, "length": Meter, "id": Kennung} oder leer
func tunnel_ahead(pos: Vector3, forward: Vector3, max_distance: float) -> Dictionary:
	var best := {}
	var p := Vector2(pos.x, pos.z)
	for key: Vector3i in _entries:
		var entry: Entry = _entries[key]
		if entry.state != State.READY or not entry.kept or entry.segment.tunnel_ranges.is_empty():
			continue
		var segment := entry.segment
		if _distance_to_rect(p, segment.bounds) > 30.0:
			continue
		# Fährt das Auto auf diesem Abschnitt? (nächster Punkt höchstens 15 m entfernt)
		var nearest := -1
		var nearest_distance := 15.0 * 15.0
		for i in segment.points.size():
			var q := segment.points[i]
			var d := (q.x - pos.x) * (q.x - pos.x) + (q.z - pos.z) * (q.z - pos.z)
			if d < nearest_distance:
				nearest_distance = d
				nearest = i
		if nearest == -1:
			continue
		var forward_on_segment := segment.direction_at(nearest).dot(forward) >= 0.0
		for r in segment.tunnel_ranges:
			var steps := (r.x - nearest) if forward_on_segment else (nearest - r.y)
			# Kein echtes Portal (Tunnel kommt aus dem Nachbarabschnitt)
			if steps <= 0 or (forward_on_segment and r.x == 0) or (not forward_on_segment and r.y == segment.points.size() - 1):
				continue
			var distance := steps * RoadSegment.POINT_SPACING
			if distance < max_distance and (best.is_empty() or distance < best["distance"]):
				best = {"distance": distance, "length": (r.y - r.x) * RoadSegment.POINT_SPACING,
					"id": "%s/%d" % [key, r.x]}
	return best


## Lichtpunkte in Tunneln rund um pos (bis radius Meter), die nächsten zuerst
func tunnel_lights_near(pos: Vector3, radius: float) -> PackedVector3Array:
	var found: Array = []
	var area := Rect2(pos.x - radius, pos.z - radius, radius * 2.0, radius * 2.0)
	for entry: Entry in _entries.values():
		if entry.state != State.READY or not entry.kept or entry.segment.tunnel_lights.is_empty():
			continue
		if not entry.segment.bounds.intersects(area):
			continue
		for light in entry.segment.tunnel_lights:
			var d := light.distance_squared_to(pos)
			if d < radius * radius:
				found.append([d, light])
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var result := PackedVector3Array()
	for item: Array in found:
		result.append(item[1])
	return result


# ---------------------------------------------------------------------------
# Für Karte und Navi
# ---------------------------------------------------------------------------

## Zustand einer Verbindung: 0 = noch unbekannt, 1 = berechnet und im Netz,
## 2 = gibt es nicht (keine Orte, zu steil, überlappt)
func edge_status(key: Vector3i) -> int:
	if _missing.has(key) or not _key_exists(key):
		return 2
	var entry: Entry = _entries.get(key)
	if entry and entry.state >= State.CHECKED:
		return 1 if entry.kept else 2
	return 0


## Der berechnete Abschnitt einer Verbindung (null, solange er nicht fertig geprüft ist)
func edge_segment(key: Vector3i) -> RoadSegment:
	var entry: Entry = _entries.get(key)
	if entry and entry.state >= State.CHECKED and entry.kept:
		return entry.segment
	return null


## Ort, an dem eine Verbindung endet (sie beginnt in der Zelle key.x, key.y)
func edge_end_cell(key: Vector3i) -> Vector2i:
	return _end_cell(key)


## Die Verbindungen an einem Ort, die es geben könnte: [Schlüssel, true = beginnt hier]
func edges_at(cell: Vector2i) -> Array:
	var result: Array = []
	for option: Array in _arm_keys(cell):
		var key: Vector3i = option[0]
		if _edge_exists(Vector2i(key.x, key.y), key.z) and not _missing.has(key):
			result.append(option)
	return result


## Alle fertigen Abschnitte, die in einem Bereich liegen: [[Schlüssel, RoadSegment], ...]
func loaded_segments(rect: Rect2) -> Array:
	var result: Array = []
	for key: Vector3i in _entries:
		var entry: Entry = _entries[key]
		if entry.state >= State.CHECKED and entry.kept and entry.segment.bounds.intersects(rect):
			result.append([key, entry.segment])
	return result


# ---------------------------------------------------------------------------
# Kreuzungen
# ---------------------------------------------------------------------------

## Kreuzung an einem Ort. null = noch nicht alle Straßen dort geprüft.
func _junction(cell: Vector2i) -> RoadJunction:
	if _junctions.has(cell):
		return _junctions[cell]
	var arms: Array = []
	var complete := true
	for option: Array in _arm_keys(cell):
		var key: Vector3i = option[0]
		if not _edge_exists(Vector2i(key.x, key.y), key.z):
			continue
		var entry: Entry = _entries.get(key)
		_want(key, 2)
		if entry == null or entry.state < State.CHECKED:
			complete = false
			continue
		if entry.kept:
			arms.append([entry.segment, option[1]])
	# Anschlussstelle an diesem Ort: der Zubringer ist ein weiterer Arm
	var connector_key := _connector_at(cell)
	if connector_key != Vector3i(-1, -1, -1):
		var entry: Entry = _entries.get(connector_key)
		_want(connector_key, 2)
		if entry == null or entry.state < State.CHECKED:
			complete = false
		elif entry.kept:
			arms.append([entry.segment, true])
	if not complete:
		return null
	var junction := RoadJunction.new()
	junction.center = node_at(cell)
	junction.arms = arms
	junction.radius = _junction_size(arms)
	_junctions[cell] = junction
	return junction


## Kreuzung an einem Ort (für den Verkehr). null = noch nicht alle Straßen dort geprüft.
func junction_at(cell: Vector2i) -> RoadJunction:
	return _junction(cell)


## Dorf an einem Ort. null = noch nicht fertig (dann wird es geplant, sobald die Kreuzung und
## alle Straßen in der Nähe geprüft sind).
func _village(cell: Vector2i) -> Village:
	var village: Village = _villages.get(cell)
	if village != null:
		if village.task_id == -1:
			return village
		if not WorkerThreadPool.is_task_completed(village.task_id):
			return null
		WorkerThreadPool.wait_for_task_completion(village.task_id)
		village.task_id = -1
		return village
	var junction := _junction(cell)
	if junction == null:
		return null
	var reach := Village.REACH + 60.0
	var rect := Rect2(junction.center.x - reach, junction.center.z - reach, reach * 2.0, reach * 2.0)
	var nearby: Array = []
	var blocked := PackedVector4Array()
	blocked.append(Vector4(junction.center.x, junction.center.y, junction.center.z, junction.radius + 4.0))
	var complete := true
	for key in _edges_touching(rect):
		var entry: Entry = _entries.get(key)
		_want(key, 2)
		if entry == null or entry.state < State.CHECKED:
			complete = false
			continue
		if entry.kept and entry.segment.bounds.intersects(rect):
			nearby.append(entry.segment)
			if not entry.segment.viewpoint.is_empty():
				blocked.append_array(Viewpoints.bay_pads(entry.segment))
	if not complete:
		return null
	# Andere Orte ganz in der Nähe: deren Kreuzung freihalten
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var other: Variant = node_at(cell + Vector2i(dx, dz))
			if (dx != 0 or dz != 0) and other != null and rect.has_point(Vector2((other as Vector3).x, (other as Vector3).z)):
				var o := other as Vector3
				blocked.append(Vector4(o.x, o.y, o.z, 30.0))
	village = Village.new()
	village.cell = cell
	village.center = junction.center
	village.world_gen = world_gen
	village.arms = junction.arms
	village.segments = nearby
	village.obstacles = blocked
	village.task_id = WorkerThreadPool.add_task(village.plan, false, "Dorf")
	_villages[cell] = village
	return null


## Zubringer, der an diesem Ort beginnt (oder (-1, -1, -1), wenn keiner)
func _connector_at(cell: Vector2i) -> Vector3i:
	var node: Variant = node_at(cell)
	if node == null or highways == null:
		return Vector3i(-1, -1, -1)
	var place := node as Vector3
	var area := Rect2(place.x - 1500.0, place.z - 1500.0, 3000.0, 3000.0)
	for section: Array in highways.sections_touching(area):
		for at: int in [section[2], section[2] + 1]:
			var interchange := highways.interchange_at(section[0], section[1], at)
			if not interchange.is_empty() and interchange["cell"] == cell:
				return interchange_key(section[0], section[1], at, 0)
	return Vector3i(-1, -1, -1)


## Wie weit die Straßen vor der Mitte enden: Je spitzer zwei Straßen aufeinander zulaufen,
## desto weiter draußen, sonst würden sich ihre Ränder schon vorher überlappen.
func _junction_size(arms: Array) -> float:
	var size := junction_radius
	var half := road_width * 0.5 + shoulder_width + RoadSegment.VERGE_WIDTH
	for a in arms.size():
		for b in range(a + 1, arms.size()):
			var angle := _arm_direction(arms[a]).angle_to(_arm_direction(arms[b]))
			size = maxf(size, half / tan(maxf(angle, 0.1) * 0.5) + 1.0)
	# Mehr geht nicht: dort ist die Straße schon nicht mehr flach
	return minf(size, RoadSegment.JUNCTION_FLAT * RoadSegment.POINT_SPACING)


## Richtung, in die eine Straße den Ort verlässt
func _arm_direction(arm: Array) -> Vector3:
	var points := (arm[0] as RoadSegment).points
	var n := points.size()
	var d: Vector3 = points[6] - points[0] if arm[1] else points[n - 7] - points[n - 1]
	d.y = 0.0
	return d.normalized()


# ---------------------------------------------------------------------------
# Hintergrund-Aufträge
# ---------------------------------------------------------------------------

func _prefetch() -> void:
	var p := Vector2(target.global_position.x, target.global_position.z)
	for key in _edges_touching(Rect2(p - Vector2.ONE * prefetch_distance, Vector2.ONE * prefetch_distance * 2.0)):
		_want(key, 2)


## Neue Abschnitte berechnen (die nächsten zuerst)
func _dispatch() -> void:
	if _wanted.is_empty() or _running >= max_parallel_jobs:
		return
	# Bezugspunkt für die Reihenfolge: ein Stück voraus in Fahrtrichtung
	var p := Vector2(target.global_position.x, target.global_position.z) \
		+ (_velocity * lookahead_seconds).limit_length(max_lookahead)
	var keys: Array = _wanted.keys()
	keys.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return _edge_area(a).get_center().distance_squared_to(p) < _edge_area(b).get_center().distance_squared_to(p))
	for key: Vector3i in keys:
		if _running >= max_parallel_jobs:
			break
		var level: int = _wanted[key]
		if _entries.has(key):
			_wanted.erase(key)
			continue
		if not _key_exists(key):
			_wanted.erase(key)
			continue
		# Erst bauen, wenn alles fertig ist, wovon der Abschnitt abhängt (sonst später nochmal)
		var segment := _make_segment(key)
		if segment == null:
			continue
		_wanted.erase(key)
		var entry := Entry.new()
		entry.segment = segment
		entry.needed = level >= 2
		entry.task_id = WorkerThreadPool.add_task(segment.build, false, "Straße")
		_entries[key] = entry
		_running += 1


## Abschnitt zu einem Schlüssel vorbereiten (noch nicht berechnet). null, solange etwas
## fehlt, wovon er abhängt: Landstraßen brauchen die Autobahnen in ihrer Nähe, Nord-Süd-
## Autobahnen die West-Ost-Autobahnen (sie führen darüber), Rampen ihren Zubringer.
func _make_segment(key: Vector3i) -> RoadSegment:
	if is_highway_key(key):
		return _make_highway_segment(key)
	if is_interchange_key(key):
		return _make_interchange_segment(key)
	if is_rest_key(key):
		return _make_rest_segment(key)
	var crossings := _built_crossings(_edge_area(key), 1)
	if crossings.size() == 1 and crossings[0] == null:
		return null
	var ends := _edge_nodes(key)
	var segment := RoadSegment.new()
	segment.world_gen = world_gen
	segment.key = key
	segment.start = ends[0]
	segment.end = ends[1]
	segment.start_direction = _departure(Vector2i(key.x, key.y), _end_cell(key))
	segment.end_direction = _departure(_end_cell(key), Vector2i(key.x, key.y))
	segment.road_width = road_width
	segment.shoulder_width = shoulder_width
	segment.max_grade = max_grade
	segment.grid_step = grid_step
	segment.curve_radius = curve_radius
	segment.min_curve_radius = min_curve_radius
	segment.max_bank = max_bank
	segment.crossings = crossings
	# Talsperre: Die Wegsuche muss bis zur Mauer reichen (die Orte liegen nicht in der Zellmitte,
	# die Mauer wurde an der Luftlinie der Zellmitten gesucht)
	var dam := world_gen.dam_for_road(key)
	if dam:
		var a := Vector2(segment.start.x, segment.start.z)
		var b := Vector2(segment.end.x, segment.end.z)
		var t := clampf((dam.dam_center - a).dot(b - a) / a.distance_squared_to(b), 0.0, 1.0)
		var off := dam.dam_center.distance_to(a.lerp(b, t))
		segment.dam = dam
		segment.min_corridor = off + dam.dam_a.distance_to(dam.dam_b) * 0.5 + 150.0
	return segment


## Fertig berechnete Autobahn-Abschnitte in einem Bereich, über die eine Straße hinweg muss.
## max_axis 1 = alle Autobahnen (für Landstraßen), 0 = nur West-Ost (für Nord-Süd-Autobahnen).
## [null], solange einer davon noch fehlt (er wird dann angefordert).
func _built_crossings(area: Rect2, max_axis: int) -> Array:
	var result: Array = []
	var missing := false
	for section: Array in highways.sections_touching(area):
		if section[0] > max_axis:
			continue
		var key := Vector3i(section[2], section[1], 2 + section[0])
		if not _edge_area(key).intersects(area):
			continue
		var entry: Entry = _entries.get(key)
		if entry == null or entry.state == State.BUILDING:
			_want(key, 1)
			missing = true
			continue
		if entry.segment.valid:
			result.append(entry.segment)
	return [null] if missing else result


func _make_highway_segment(key: Vector3i) -> RoadSegment:
	var axis := highway_axis(key)
	var crossings: Array = []
	if axis == 1:
		crossings = _built_crossings(_edge_area(key), 0)
		if crossings.size() == 1 and crossings[0] == null:
			return null
	var segment := RoadSegment.new()
	segment.world_gen = world_gen
	segment.key = key
	segment.kind = RoadSegment.Kind.HIGHWAY
	segment.start = highways.control_point(axis, key.y, key.x)
	segment.end = highways.control_point(axis, key.y, key.x + 1)
	segment.start_direction = highways.direction_at(axis, key.y, key.x)
	segment.end_direction = -highways.direction_at(axis, key.y, key.x + 1)
	segment.road_width = HIGHWAY_WIDTH
	segment.shoulder_width = shoulder_width
	segment.max_grade = 0.04
	segment.grid_step = 40.0
	segment.curve_radius = 1500.0
	segment.min_curve_radius = 900.0
	segment.max_bank = 0.025
	segment.lead = 150.0
	segment.flat_points = 25
	segment.max_fill = 120.0
	segment.profile_window = 25
	segment.simplify_tolerance = 12.0
	segment.max_curve_radius = 8000.0
	segment.curve_bulge = 40.0
	segment.merge_shift = 60.0
	segment.turn_limit_cos = cos(deg_to_rad(25.0))
	segment.turn_soft_cos = cos(deg_to_rad(8.0))
	segment.tunnel_cost = 0.3
	segment.portal_cost = 100.0
	segment.crossings = crossings
	segment.fixed_path = highways.centerline(axis, key.y, key.x)
	# An Anschlussstellen und Raststätten: Rampen statt äußerer Leitplanke, lange gerade und
	# flach (dort setzen die Rampen an)
	for at: int in [key.x, key.x + 1]:
		var interchange := highways.interchange_at(axis, key.y, at)
		var has_rest := not highways.rest_area_at(axis, key.y, at, 1).is_empty() \
			or not highways.rest_area_at(axis, key.y, at, -1).is_empty()
		if not interchange.is_empty() or has_rest:
			var point := highways.control_point(axis, key.y, at)
			segment.rail_gaps.append(Vector3(point.x, point.z, RAMP_LENGTH + 50.0))
			if at == key.x:
				segment.lead = RAMP_LENGTH + 30.0
				segment.flat_points = 80
			else:
				segment.lead_end = RAMP_LENGTH + 30.0
				segment.flat_end = 80
	# Verzögerungs- und Beschleunigungsstreifen an allen Rampen (Anschlussstellen, Raststätten)
	for at: int in [key.x, key.x + 1]:
		segment.aux_lanes.append_array(_aux_lanes_at(axis, key.y, at))
	# Liegen die Stützpunkte weit übereinander, reichen 4 % neben den flachen Stücken nicht:
	# dann lieber etwas steiler als eine Lücke in der Autobahn
	var length := 0.0
	for i in segment.fixed_path.size() - 1:
		length += segment.fixed_path[i].distance_to(segment.fixed_path[i + 1])
	var flat := (segment.flat_points + (segment.flat_end if segment.flat_end >= 0 else segment.flat_points)) \
		* RoadSegment.POINT_SPACING
	var climb := absf(segment.end.y - segment.start.y)
	segment.max_grade = maxf(segment.max_grade, climb / maxf(length - flat - 150.0, 200.0))
	return segment


## Zusatzfahrstreifen an einem Stützpunkt, für RoadSegment.aux_lanes: [Punkt, an dem die Rampe
## die Fahrbahn verlässt bzw. erreicht, Fahrtrichtung (+1 = Richtung wachsender Stützpunkte =
## Punktreihenfolge), Seite (+1 = links), Ausfahrt?]
func _aux_lanes_at(axis: int, line: int, at: int) -> Array:
	var result: Array = []
	var d := highways.direction_at(axis, line, at)
	var left := Vector2(d.y, -d.x)
	if not highways.interchange_at(axis, line, at).is_empty():
		for part: int in [1, 2, 3, 4]:
			var ends := ramp_ends(axis, line, at, part)
			var exit := part == 1 or part == 3
			# Links (Teil 1, 2) fährt man gegen d, rechts in Richtung d
			var side := 1 if part <= 2 else -1
			result.append([ends[0] if exit else ends[1], -side, side, exit])
	for dir: int in [1, -1]:
		var rest := highways.rest_area_at(axis, line, at, dir)
		if rest.is_empty():
			continue
		var travel := 1 if (rest["travel"] as Vector2).dot(d) > 0.0 else -1
		var side := 1 if (rest["side"] as Vector2).dot(left) > 0.0 else -1
		result.append([rest_ends(axis, line, at, dir, 1)[0], travel, side, true])
		result.append([rest_ends(axis, line, at, dir, 2)[1], travel, side, false])
	return result


## Zubringer oder Rampe einer Anschlussstelle. Lage und Höhe der Autobahn dort stehen schon
## fest (Stützpunkt: gerade und flach), deshalb hängt der Zubringer von nichts ab.
## Die Rampen brauchen den fertigen Zubringer (sie enden auf ihm).
func _make_interchange_segment(key: Vector3i) -> RoadSegment:
	var axis := highway_axis(key)
	var interchange := highways.interchange_at(axis, key.y, key.x)
	var place: Vector3 = interchange["place"]
	var point: Vector3 = interchange["point"]
	var d := highways.direction_at(axis, key.y, key.x)
	var x := Vector2(point.x, point.z)
	var cross: Vector2 = interchange["side"]
	# Andere Autobahnen in der Nähe: Zubringer und Rampen führen per Brücke darüber
	var crossings := _built_crossings(_edge_area(key), 1)
	if crossings.size() == 1 and crossings[0] == null:
		return null
	var segment := RoadSegment.new()
	segment.world_gen = world_gen
	segment.key = key
	segment.shoulder_width = shoulder_width
	segment.crossings = crossings
	var part := interchange_part(key)
	if part == 0:
		# Zubringer: verlässt den Ort in einer freien Richtung (leave), schwenkt im Bogen auf
		# die Autobahn zu, überquert sie rechtwinklig (Brücke) und endet CONNECTOR_BEYOND dahinter
		var p := Vector2(place.x, place.z)
		var leave: Vector2 = interchange["leave"]
		var reach := p.distance_to(x)
		var far := x + cross * CONNECTOR_BEYOND
		var connector_path := PackedVector2Array()
		for i in 81:
			connector_path.append(_bezier(p, p + leave * reach * 0.4, x - cross * reach * 0.4, x, i / 80.0))
		connector_path.append_array(_dense_line(PackedVector2Array([x, far])).slice(1))
		segment.kind = RoadSegment.Kind.ROAD
		segment.road_width = road_width
		segment.max_grade = 0.08
		segment.start = place
		segment.end = Vector3(far.x, world_gen.terrain_height(far.x, far.y, world_gen.lakes_near(Rect2(far, Vector2.ONE))), far.y)
		segment.fixed_path = connector_path
		segment.height_constraints = [[x, HIGHWAY_WIDTH * 0.5 + 4.0, point.y + 7.5]]
		segment.flat_points = RoadSegment.JUNCTION_FLAT
		return segment
	# Rampen: 1 = Ausfahrt links, 2 = Einfahrt links, 3 = Ausfahrt rechts, 4 = Einfahrt rechts
	# (links/rechts von der Autobahn aus gesehen; rechts fährt man in Richtung d)
	var connector: Entry = _entries.get(interchange_key(axis, key.y, key.x, 0))
	if connector == null or connector.state == State.BUILDING:
		_want(interchange_key(axis, key.y, key.x, 0), 1)
		return null
	var side := 1.0 if part <= 2 else -1.0
	var exit := part == 1 or part == 3
	var travel := d * -side
	var ends := ramp_ends(axis, key.y, key.x, part)
	var a := ends[0]
	var b := ends[1]
	var path := PackedVector2Array()
	for i in 101:
		var t := i / 100.0
		path.append(_bezier(a, a + travel * RAMP_LENGTH * 0.45, b - travel * RAMP_LENGTH * 0.45, b, t))
	var connector_height := _height_on(connector.segment, b if exit else a)
	segment.kind = RoadSegment.Kind.RAMP
	segment.road_width = RAMP_WIDTH
	segment.shoulder_width = 1.0
	segment.max_grade = 0.07
	segment.follow_ground = false
	segment.flat_points = 3
	segment.profile_window = 6
	segment.fixed_path = path
	var highway_height := point.y + RAMP_LIFT
	segment.start = Vector3(a.x, highway_height if exit else connector_height, a.y)
	segment.end = Vector3(b.x, connector_height if exit else highway_height, b.y)
	if not connector.segment.valid:
		# Ohne Zubringer keine Rampe: ein Weg aus einem Punkt ergibt einen ungültigen Abschnitt
		segment.fixed_path = PackedVector2Array([a])
	return segment


## Raststätte: Parkplatz (sehr breites, kurzes Straßenstück: so gibt es Gelände-Anpassung,
## Kollision und Asphalt von selbst), Ausfahrt- und Einfahrt-Rampe. Alles auf der Höhe der
## Autobahn am Stützpunkt (dort ist sie flach).
func _make_rest_segment(key: Vector3i) -> RoadSegment:
	var axis := highway_axis(key)
	var dir := rest_dir(key)
	var part := rest_part(key)
	var rest := highways.rest_area_at(axis, key.y, key.x, dir)
	var travel: Vector2 = rest["travel"]
	var ends := rest_ends(axis, key.y, key.x, dir, part)
	var a := ends[0]
	var b := ends[1]
	var path := PackedVector2Array()
	if part == 0:
		path = _dense_line(PackedVector2Array([a, b]))
	else:
		var length := a.distance_to(b)
		for i in 81:
			path.append(_bezier(a, a + travel * length * 0.45, b - travel * length * 0.45, b, i / 80.0))
	var height: float = (rest["point"] as Vector3).y
	var segment := RoadSegment.new()
	segment.world_gen = world_gen
	segment.key = key
	segment.kind = RoadSegment.Kind.RAMP
	segment.road_width = HighwayLayout.REST_WIDTH if part == 0 else RAMP_WIDTH
	segment.square_ends = part == 0
	segment.shoulder_width = 1.0
	segment.max_grade = 0.07
	segment.follow_ground = false
	segment.flat_points = 3
	segment.profile_window = 6
	segment.fixed_path = path
	# Am Ende auf der Autobahn etwas höher (liegt im Zusatzfahrstreifen)
	segment.start = Vector3(a.x, height + (RAMP_LIFT if part == 1 else 0.0), a.y)
	segment.end = Vector3(b.x, height + (RAMP_LIFT if part == 2 else 0.0), b.y)
	return segment


## Anfang und Ende eines Raststätten-Teils (x/z), in Fahrtrichtung: Parkplatz (Teil 0),
## Ausfahrt von der Autobahn zum Parkplatz (1), Einfahrt vom Parkplatz zur Autobahn (2).
## Die Rampen treffen den Parkplatz an seinem autobahnnahen Rand.
func rest_ends(axis: int, line: int, k: int, dir: int, part: int) -> PackedVector2Array:
	var rest := highways.rest_area_at(axis, line, k, dir)
	var point: Vector3 = rest["point"]
	var x := Vector2(point.x, point.z)
	var travel: Vector2 = rest["travel"]
	var side: Vector2 = rest["side"]
	var half: float = rest["half_length"]
	if part == 0:
		return PackedVector2Array([x + side * HighwayLayout.REST_OFFSET - travel * half,
			x + side * HighwayLayout.REST_OFFSET + travel * half])
	var on_highway := x + side * RAMP_LATERAL
	var lane := x + side * (HighwayLayout.REST_OFFSET - HighwayLayout.REST_WIDTH * 0.5 + 4.0)
	if part == 1:
		return PackedVector2Array([on_highway - travel * RAMP_LENGTH, lane - travel * half])
	return PackedVector2Array([lane + travel * half, on_highway + travel * RAMP_LENGTH])


## Anfang und Ende einer Rampe (x/z). Teil 1 = Ausfahrt links, 2 = Einfahrt links,
## 3 = Ausfahrt rechts, 4 = Einfahrt rechts (von der Autobahn aus gesehen; rechts fährt man
## in Richtung steigender Stützpunkte). Ausfahrten beginnen auf der Autobahn und enden am
## Zubringer, Einfahrten umgekehrt.
func ramp_ends(axis: int, line: int, k: int, part: int) -> PackedVector2Array:
	var interchange := highways.interchange_at(axis, line, k)
	var point: Vector3 = interchange["point"]
	var d := highways.direction_at(axis, line, k)
	var left := Vector2(d.y, -d.x)
	var x := Vector2(point.x, point.z)
	var cross: Vector2 = interchange["side"]
	var side := 1.0 if part <= 2 else -1.0
	var travel := d * -side
	var join_dir := cross if cross.dot(left * side) > 0.0 else -cross
	var join := x + join_dir * RAMP_JOIN
	var on_highway := x + left * side * RAMP_LATERAL
	if part == 1 or part == 3:
		return PackedVector2Array([on_highway - travel * RAMP_LENGTH, join - travel * (road_width * 0.5 + 1.5)])
	return PackedVector2Array([join + travel * (road_width * 0.5 + 1.5), on_highway + travel * RAMP_LENGTH])


static func _bezier(a: Vector2, b: Vector2, c: Vector2, d: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return a * u * u * u + b * 3.0 * u * u * t + c * 3.0 * u * t * t + d * t * t * t


## Polygonzug mit einem Punkt alle 4 m
static func _dense_line(corners: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array([corners[0]])
	for i in corners.size() - 1:
		var steps := maxi(ceili(corners[i].distance_to(corners[i + 1]) / 4.0), 1)
		for s in range(1, steps + 1):
			result.append(corners[i].lerp(corners[i + 1], float(s) / steps))
	return result


## Höhe der Fahrbahn eines (berechneten) Abschnitts an der Stelle, die p am nächsten ist
static func _height_on(segment: RoadSegment, p: Vector2) -> float:
	if not segment.valid or segment.points.is_empty():
		return 0.0
	var best := 0
	var best_distance := INF
	for i in segment.points.size():
		var d := Vector2(segment.points[i].x, segment.points[i].z).distance_squared_to(p)
		if d < best_distance:
			best_distance = d
			best = i
	return segment.points[best].y


## Fertige Hintergrund-Aufträge übernehmen. Gibt zurück, wie viele es waren.
func _collect_finished() -> int:
	var finished := 0
	for entry: Entry in _entries.values():
		if entry.task_id == -1 or not WorkerThreadPool.is_task_completed(entry.task_id):
			continue
		WorkerThreadPool.wait_for_task_completion(entry.task_id)
		entry.task_id = -1
		_running -= 1
		finished += 1
		match entry.state:
			State.BUILDING:
				entry.state = State.BUILT
			State.CHECKING:
				entry.kept = not entry.check.overlaps
				entry.check = null
				entry.state = State.CHECKED
				if not entry.kept:
					_missing[entry.segment.key] = true
			State.MESHING:
				entry.state = State.READY
	return finished


## Berechnete Abschnitte prüfen und geprüfte (in Sichtweite) zu Meshes machen
func _advance() -> void:
	var p := Vector2(target.global_position.x, target.global_position.z)
	for key: Vector3i in _entries.keys():
		if _running >= max_parallel_jobs:
			return
		var entry: Entry = _entries[key]
		if entry.state == State.BUILT and entry.needed:
			_start_check(key, entry)
		elif entry.state == State.CHECKED and entry.kept \
				and _distance_to_rect(p, entry.segment.bounds) < mesh_distance + 200.0:
			_start_mesh(key, entry)


func _start_check(key: Vector3i, entry: Entry) -> void:
	if not entry.segment.valid:
		entry.kept = false
		entry.state = State.CHECKED
		_missing[key] = true
		return
	# Autobahnen und Anschlussstellen haben Vorrang: sie bleiben immer
	if not is_road_key(key):
		entry.kept = true
		entry.state = State.CHECKED
		return
	if not entry.has_neighbors:
		for other_key in _edges_touching(entry.segment.bounds):
			if other_key != key:
				entry.neighbors.append(other_key)
		entry.has_neighbors = true
	# Alle Nachbarn müssen berechnet sein. Wichtig sind nur die mit kleinerem Hash-Wert:
	# Überlappt dieser Abschnitt einen davon, fällt er weg.
	var others: Array = []
	var raised: Array = []
	var complete := true
	for other_key in entry.neighbors:
		var other: Entry = _entries.get(other_key)
		if other == null or other.state == State.BUILDING:
			_want(other_key, 1)
			complete = false
			continue
		if not other.segment.valid:
			continue
		if not is_road_key(other_key):
			# Autobahn und Rampen: nur stören, wenn sie nicht klar darüber oder darunter liegen
			raised.append(other.segment)
		elif _priority(other_key) < _priority(key):
			others.append(other.segment)
	if not complete:
		return
	var check := OverlapCheck.new()
	check.segment = entry.segment
	check.others = others
	check.raised = raised
	check.distance = road_width + 2.0 * (shoulder_width + RoadSegment.VERGE_WIDTH) + 2.0
	entry.check = check
	entry.task_id = WorkerThreadPool.add_task(check.run, false, "Straße prüfen")
	entry.state = State.CHECKING
	_running += 1


func _start_mesh(key: Vector3i, entry: Entry) -> void:
	var first := 0
	var last := entry.segment.points.size() - 1
	if is_road_key(key):
		var at_start := _junction(Vector2i(key.x, key.y))
		var at_end := _junction(_end_cell(key))
		if at_start == null or at_end == null:
			return
		first = at_start.mouth_steps()
		last -= at_end.mouth_steps()
	elif is_interchange_key(key) and interchange_part(key) == 0:
		var at_place := _junction(highways.interchange_at(highway_axis(key), key.y, key.x)["cell"])
		if at_place == null:
			return
		first = at_place.mouth_steps()
	entry.task_id = WorkerThreadPool.add_task(entry.segment.build_mesh.bind(first, last), false, "Straßen-Mesh")
	entry.state = State.MESHING
	_running += 1


# ---------------------------------------------------------------------------
# Sichtbare Straßen, Kreuzungen, Kollision
# ---------------------------------------------------------------------------

func _update_visuals() -> void:
	var p := Vector2(target.global_position.x, target.global_position.z)
	for key: Vector3i in _entries.keys():
		var entry: Entry = _entries[key]
		if entry.task_id != -1:
			continue
		# Sehr weit weg: ganz vergessen (wird bei Bedarf neu berechnet).
		# Auch ungültige Abschnitte bleiben gemerkt, sonst würden sie ständig neu berechnet.
		# Autobahnen erst viel weiter weg: Landstraßen und Nord-Süd-Autobahnen warten auf sie
		# (Kreuzungen), sonst würden sie berechnet, vergessen, wieder angefordert und so fort.
		var forget := FORGET_DISTANCE + (0.0 if is_road_key(key) else HIGHWAY_FORGET_EXTRA)
		if _distance_to_rect(p, _edge_area(key)) > forget:
			_free_visuals(entry)
			_entries.erase(key)
			continue
		_update_landmark(entry, p)
		if entry.state != State.READY:
			continue
		var segment := entry.segment
		var distance := _distance_to_rect(p, segment.bounds)
		if distance < mesh_distance:
			if entry.mesh_instance == null:
				var mesh := ArrayMesh.new()
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, segment.mesh_arrays)
				var surface_material := road_material
				if segment.kind == RoadSegment.Kind.HIGHWAY and highway_material:
					surface_material = highway_material
				elif is_rest_key(key) and rest_part(key) == 0 and parking_material:
					surface_material = parking_material
				elif segment.kind == RoadSegment.Kind.RAMP and ramp_material:
					surface_material = ramp_material
				mesh.surface_set_material(0, surface_material)
				if not segment.bridge_arrays.is_empty():
					mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, segment.bridge_arrays)
					mesh.surface_set_material(mesh.get_surface_count() - 1, bridge_material)
				if not segment.tunnel_arrays.is_empty():
					mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, segment.tunnel_arrays)
					mesh.surface_set_material(mesh.get_surface_count() - 1, tunnel_material)
				entry.mesh_instance = MeshInstance3D.new()
				entry.mesh_instance.mesh = mesh
				# Brücken werfen Schatten, flache Straßen brauchen das nicht. Tunnelröhren werfen
				# beidseitig Schatten, sonst scheint die Sonne durch die Wand hinein.
				entry.mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				if not segment.tunnel_arrays.is_empty():
					entry.mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
				elif not segment.bridge_arrays.is_empty():
					entry.mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				entry.mesh_instance.position = segment.origin
				add_child(entry.mesh_instance)
				# Leitplanken als eigenes Mesh, damit nur sie (und Brücken) Schatten werfen
				if not segment.rail_arrays.is_empty():
					var rail_mesh := ArrayMesh.new()
					rail_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, segment.rail_arrays)
					var rails := MeshInstance3D.new()
					rails.mesh = rail_mesh
					rails.material_override = rail_material
					entry.mesh_instance.add_child(rails)
				# Leitpfosten und Schilder (Autobahn)
				if not segment.posts.is_empty():
					entry.mesh_instance.add_child(_make_posts(segment))
				if is_highway_key(key):
					_add_signs(segment, key, entry.mesh_instance)
				# Tempolimits und Kurven-Warnschilder (SpeedLimits)
				if not segment.limit_signs.is_empty():
					_add_limit_signs(segment, entry.mesh_instance)
				if is_rest_key(key) and rest_part(key) == 0:
					_add_rest_props(segment, key, entry.mesh_instance)
				# Parkbucht mit Schild und Bank am Aussichtspunkt
				if not segment.bay_arrays.is_empty():
					var bay_mesh := ArrayMesh.new()
					bay_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, segment.bay_arrays)
					var bay := MeshInstance3D.new()
					bay.mesh = bay_mesh
					bay.material_override = road_material
					bay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					entry.mesh_instance.add_child(bay)
					_add_viewpoint_props(segment, entry.mesh_instance)
				# Deckenlampen leuchten selbst und werfen keinen Schatten
				if not segment.lamp_arrays.is_empty():
					var lamp_mesh := ArrayMesh.new()
					lamp_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, segment.lamp_arrays)
					var lamps := MeshInstance3D.new()
					lamps.mesh = lamp_mesh
					lamps.material_override = lamp_material
					lamps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					entry.mesh_instance.add_child(lamps)
		elif entry.mesh_instance:
			entry.mesh_instance.queue_free()
			entry.mesh_instance = null
		if distance < collision_distance and entry.body == null:
			entry.body = _make_body(segment.collision_faces)
		elif distance > collision_distance + 100.0 and entry.body:
			entry.body.queue_free()
			entry.body = null
	_update_villages(p)
	for cell: Vector2i in _junctions.keys():
		var junction: RoadJunction = _junctions[cell]
		var distance := Vector2(junction.center.x - p.x, junction.center.z - p.y).length()
		if distance > FORGET_DISTANCE:
			_free_junction(junction)
			_junctions.erase(cell)
			continue
		if junction.arms.is_empty():
			continue
		if distance < mesh_distance:
			if junction.mesh_instance == null:
				if junction.mesh_arrays.is_empty():
					junction.build()
				var mesh := ArrayMesh.new()
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, junction.mesh_arrays)
				junction.mesh_instance = MeshInstance3D.new()
				junction.mesh_instance.mesh = mesh
				junction.mesh_instance.material_override = road_material
				junction.mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				junction.mesh_instance.position = junction.center
				add_child(junction.mesh_instance)
		elif junction.mesh_instance:
			junction.mesh_instance.queue_free()
			junction.mesh_instance = null
		if distance < collision_distance and junction.body == null:
			if junction.mesh_arrays.is_empty():
				junction.build()
			junction.body = _make_body(junction.collision_faces)
		elif distance > collision_distance + 100.0 and junction.body:
			junction.body.queue_free()
			junction.body = null


# ---------------------------------------------------------------------------
# Autobahn-Schilder
# ---------------------------------------------------------------------------

## Schilderbrücken 2000 m und 500 m vor jeder Ausfahrt, Ankündigungsbaken 300/200/100 m vor dem
## Beginn der Rampe, an der Spitze der Sperrfläche Anpralldämpfer, Leitpfosten und das
## Ausfahrt-Schild mit Pfeil auf der Insel.
## Die Entfernungen werden entlang der Autobahn gemessen; liegt die Ausfahrt im übernächsten
## Abschnitt und ist der nächste noch nicht berechnet, wird seine Länge geschätzt.
func _add_signs(segment: RoadSegment, key: Vector3i, parent: Node3D) -> void:
	var axis := highway_axis(key)
	var n := segment.points.size()
	var along := PackedFloat32Array()
	along.resize(n)
	for i in range(1, n):
		along[i] = along[i - 1] + segment.points[i].distance_to(segment.points[i - 1])
	var length := along[n - 1]
	for forward: bool in [true, false]:
		# In Richtung wachsender Stützpunkte liegen die Ausfahrten an k+1 und k+2, sonst an k und k-1
		var targets: Array = [key.x + 1, key.x + 2] if forward else [key.x, key.x - 1]
		for exit_k: int in targets:
			var interchange := highways.interchange_at(axis, key.y, exit_k)
			var rest := highways.rest_area_at(axis, key.y, exit_k, 1 if forward else -1)
			if interchange.is_empty() and rest.is_empty():
				continue
			# Strecke vom Abschnittsende (in Fahrtrichtung) bis zum Stützpunkt der Ausfahrt
			var extra := 0.0
			if exit_k == key.x + 2:
				extra = _section_length(Vector3i(key.x + 1, key.y, key.z))
			elif exit_k == key.x - 1:
				extra = _section_length(Vector3i(key.x - 1, key.y, key.z))
			var nose := _gore_nose(axis, key.y, exit_k, forward)
			# [Meter vor dem Beginn der Rampe (negativ = dahinter), was dort steht]
			var places: Array = [[2000.0, "gantry"], [500.0, "gantry"], [300.0, "bake"], [200.0, "bake"],
				[100.0, "bake"], [-nose.x, "cushion"], [-nose.x - 12.0, "post"], [-nose.x - 22.0, "exit"],
				[-nose.x - 34.0, "post"]]
			for place: Array in places:
				var sign_at: float = place[0]
				# Gesucht: Punkt i, von dem es sign_at Meter bis zum Beginn der Ausfahrt-Rampe sind
				var to_ramp_end_of_section := extra - RAMP_LENGTH
				var from_section_end := sign_at - to_ramp_end_of_section
				var position_along := (length - from_section_end) if forward else from_section_end
				if position_along < 0.0 or position_along > length:
					continue
				var i := along.bsearch(position_along)
				i = clampi(i, 1, n - 2)
				if segment.tunnel[i] == 1:
					continue
				var travel := segment.direction_at(i) * (1.0 if forward else -1.0)
				var at := segment.points[i] - segment.origin
				match place[1]:
					"gantry":
						if not rest.is_empty():
							_rest_sign(parent, at, travel, rest, "%d m" % roundi(sign_at))
						else:
							_gantry(parent, at, travel, interchange, "%d m" % roundi(sign_at))
					"bake":
						_countdown_bake(parent, at, travel, roundi(sign_at / 100.0))
					"cushion":
						_crash_cushion(parent, at, travel)
					"post":
						_island_post(parent, at, travel, nose.y)
					"exit":
						if not rest.is_empty():
							_rest_exit_sign(parent, at, travel, nose.y)
						else:
							_exit_sign(parent, at, travel, interchange, nose.y)


var _limit_sign_material: ShaderMaterial
var _landmark_lamp: StandardMaterial3D


## Tempolimit- und Warnschilder eines Abschnitts: ein Mesh (Punktfarben, reflektiert nachts)
## und die Zahlen als Label3D
func _add_limit_signs(segment: RoadSegment, parent: Node3D) -> void:
	var signs := TrafficSigns.new()
	signs.build(segment)
	if _limit_sign_material == null:
		_limit_sign_material = ShaderMaterial.new()
		_limit_sign_material.shader = load("res://shaders/sign.gdshader")
	var instance := MeshInstance3D.new()
	instance.mesh = signs.mesh()
	instance.material_override = _limit_sign_material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	for label: Array in signs.labels:
		var text := Label3D.new()
		text.text = label[0]
		text.font = UiStyle.font("semibold")
		text.font_size = label[3]
		text.pixel_size = 0.004
		text.modulate = label[4]
		text.outline_size = 0
		text.double_sided = false
		text.transform = Transform3D(label[2], label[1])
		parent.add_child(text)


## Landmarken-Brücke (Bogen, Pylone, Seile) zeigen, solange sie in landmark_distance liegt, auch
## wenn die Fahrbahn noch nicht gebaut ist
func _update_landmark(entry: Entry, p: Vector2) -> void:
	if entry.segment == null or entry.state < State.CHECKED or not entry.kept or entry.segment.landmark.is_empty():
		return
	var info := entry.segment.landmark
	var center: Vector3 = info["center"]
	var distance := Vector2(center.x, center.z).distance_to(p)
	if distance > landmark_distance + 300.0:
		if entry.landmark_instance:
			entry.landmark_instance.queue_free()
			entry.landmark_instance = null
		return
	if entry.landmark_instance or distance > landmark_distance:
		return
	if _landmark_lamp == null:
		_landmark_lamp = StandardMaterial3D.new()
		_landmark_lamp.albedo_color = Color(0.6, 0.05, 0.03)
		_landmark_lamp.emission_enabled = true
		_landmark_lamp.emission = Color(1.0, 0.12, 0.05)
		_landmark_lamp.emission_energy_multiplier = 0.4
	var node := Node3D.new()
	add_child(node)
	node.position = center
	for pair: Array in [["concrete", bridge_material], ["steel", rail_material], ["lamps", _landmark_lamp]]:
		var arrays: Array = info[pair[0]]
		if arrays.is_empty():
			continue
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.material_override = pair[1]
		instance.visibility_range_end = landmark_distance + 500.0
		if pair[0] != "concrete":
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(instance)
	entry.landmark_instance = node


## Landmarken-Brücken in der Nähe für die Karte: [{"name", "position" (x/z), "kind"}]
func landmark_bridges(rect: Rect2) -> Array:
	var result: Array = []
	for key: Vector3i in _entries:
		var entry: Entry = _entries[key]
		if entry.segment == null or not entry.kept or entry.segment.landmark.is_empty():
			continue
		var center: Vector3 = entry.segment.landmark["center"]
		if not rect.has_point(Vector2(center.x, center.z)):
			continue
		var cell := Vector2i(floori(center.x / cell_size), floori(center.z / cell_size))
		var kind: String = entry.segment.landmark["kind"]
		result.append({"name": "%s %s" % ["Hängebrücke" if kind == "suspension" else "Talbrücke", highways.place_name(cell)],
			"position": Vector2(center.x, center.z), "kind": kind})
	return result


## Spitze der Sperrfläche einer Ausfahrt (die Rampe ist dort weit genug von der Fahrbahn weg für
## die Insel): [Meter hinter dem Beginn der Rampe, seitlicher Abstand der Inselmitte ~20 m weiter]
func _gore_nose(axis: int, line: int, k: int, forward: bool) -> Vector2:
	var dir := 1 if forward else -1
	var rest := highways.rest_area_at(axis, line, k, dir)
	var ends: PackedVector2Array
	var handle := RAMP_LENGTH * 0.45
	var point: Vector3
	if not rest.is_empty():
		ends = rest_ends(axis, line, k, dir, 1)
		handle = ends[0].distance_to(ends[1]) * 0.45
		point = rest["point"]
	else:
		ends = ramp_ends(axis, line, k, 3 if forward else 1)
		point = highways.interchange_at(axis, line, k)["point"]
	var x := Vector2(point.x, point.z)
	var d := highways.direction_at(axis, line, k)
	var travel := d * float(dir)
	var left := Vector2(d.y, -d.x)
	var a := ends[0]
	var b := ends[1]
	var result := Vector2(-1.0, HIGHWAY_WIDTH * 0.5 + 2.0)
	for i in 101:
		var p := _bezier(a, a + travel * handle, b - travel * handle, b, i / 100.0)
		var along := (p - a).dot(travel)
		# Platz zwischen Fahrbahnrand der Autobahn und Innenrand der Rampe
		var gap := absf((p - x).dot(left)) - RAMP_WIDTH * 0.5 - HIGHWAY_WIDTH * 0.5
		if result.x < 0.0 and gap > 0.6:
			result.x = along
		if result.x >= 0.0 and along >= result.x + 20.0:
			result.y = HIGHWAY_WIDTH * 0.5 + gap * 0.5
			break
	if result.x < 0.0:
		result.x = 70.0
	return result


## Ankündigungsbake (300/200/100 m vor der Ausfahrt): weiße Tafel mit 3/2/1 roten Schrägstreifen
## rechts neben dem Verzögerungsstreifen
func _countdown_bake(parent: Node3D, center: Vector3, travel: Vector3, stripes: int) -> void:
	var right := travel.cross(Vector3.UP).normalized()
	var facing := Basis.looking_at(travel)
	var foot := center + right * (HIGHWAY_WIDTH * 0.5 + RoadSegment.AUX_EXTRA + 1.2)
	_box(parent, foot + Vector3.UP * 1.15, Vector3(0.5, 1.5, 0.06), facing, "white")
	_box(parent, foot + Vector3.UP * 0.2, Vector3(0.08, 0.4, 0.08), Basis(), "steel")
	var tilt := facing * Basis(Vector3.BACK, deg_to_rad(-35.0))
	for k in stripes:
		var y := 1.15 + (k - (stripes - 1) * 0.5) * 0.42
		_box(parent, foot + Vector3.UP * y - travel * 0.035, Vector3(0.58, 0.13, 0.02), tilt, "red")


## Anpralldämpfer an der Spitze der Sperrfläche: gelbes Kissen mit schwarzen Streifen vorne
func _crash_cushion(parent: Node3D, center: Vector3, travel: Vector3) -> void:
	var right := travel.cross(Vector3.UP).normalized()
	var facing := Basis.looking_at(travel)
	var front := center + right * (HIGHWAY_WIDTH * 0.5 + 0.6)
	_box(parent, front + travel * 2.0 + Vector3.UP * 0.45, Vector3(0.8, 0.9, 4.0), facing, "yellow")
	var tilt := facing * Basis(Vector3.BACK, deg_to_rad(45.0))
	for k in 3:
		_box(parent, front + Vector3.UP * (0.18 + k * 0.28) - travel * 0.02, Vector3(0.82, 0.08, 0.02), tilt, "dark")


## Leitpfosten auf der Insel zwischen Autobahn und Rampe
func _island_post(parent: Node3D, center: Vector3, travel: Vector3, lateral: float) -> void:
	var right := travel.cross(Vector3.UP).normalized()
	var foot := center + right * lateral
	_box(parent, foot + Vector3.UP * 0.5, Vector3(0.12, 1.0, 0.12), Basis(), "white")
	_box(parent, foot + Vector3.UP * 0.82, Vector3(0.13, 0.2, 0.13), Basis(), "dark")


## Vorankündigung einer Raststätte: blaues Schild rechts neben der Fahrbahn mit Name,
## Entfernung und weißen Feldern mit Zapfsäule und Tasse
func _rest_sign(parent: Node3D, center: Vector3, travel: Vector3, rest: Dictionary, distance_text: String) -> void:
	var right := travel.cross(Vector3.UP).normalized()
	var facing := Basis.looking_at(travel)
	var foot := center + right * (HIGHWAY_WIDTH * 0.5 + 3.5)
	# Pfosten hinter der Tafel (vom Verkehr aus gesehen)
	for offset: float in [-2.2, 2.2]:
		_box(parent, foot + right * offset + travel * 0.2 + Vector3.UP * 2.8, Vector3(0.18, 5.6, 0.18), Basis(), "steel")
	var panel := foot + Vector3.UP * 4.5
	_box(parent, panel, Vector3(6.0, 3.2, 0.15), facing, "blue")
	var front := -travel * 0.1
	_sign_text(parent, (rest["name"] as String).trim_prefix("Rastanlage "), panel + front + Vector3.UP * 0.95,
		facing, 64, Color.WHITE)
	_sign_text(parent, "Rastanlage", panel + front + Vector3.UP * 0.3, facing, 44, Color(1, 1, 1, 0.9))
	_sign_text(parent, distance_text, panel + front + right * 1.3 + Vector3.DOWN * 0.75, facing, 56, Color.WHITE)
	# Symbole links unten: Zapfsäule und Tasse (aus Kästchen) auf weißen Feldern
	for k in 2:
		var tile := panel + front + right * (-2.0 + 0.95 * k) + Vector3.DOWN * 0.75
		_box(parent, tile, Vector3(0.8, 0.8, 0.04), facing, "white")
		var icon := tile + front * 0.4
		if k == 0:
			_box(parent, icon - right * 0.07, Vector3(0.3, 0.5, 0.02), facing, "dark")
			_box(parent, icon - right * 0.07 + Vector3.UP * 0.12, Vector3(0.18, 0.12, 0.025), facing, "white")
			_box(parent, icon + right * 0.16 + Vector3.UP * 0.06, Vector3(0.05, 0.32, 0.02), facing, "dark")
		else:
			_box(parent, icon + Vector3.DOWN * 0.04 - right * 0.04, Vector3(0.32, 0.32, 0.02), facing, "dark")
			_box(parent, icon + right * 0.17, Vector3(0.1, 0.16, 0.02), facing, "dark")
			_box(parent, icon + Vector3.DOWN * 0.25, Vector3(0.46, 0.05, 0.02), facing, "dark")


## Am Beginn der Ausfahrt zur Raststätte
func _rest_exit_sign(parent: Node3D, center: Vector3, travel: Vector3, lateral: float) -> void:
	_island_sign(parent, center, travel, lateral, "Rastanlage")


## Schild auf der Insel an der Ausfahrt: blau mit Text und Pfeil nach rechts oben
func _island_sign(parent: Node3D, center: Vector3, travel: Vector3, lateral: float, text: String) -> void:
	var right := travel.cross(Vector3.UP).normalized()
	var facing := Basis.looking_at(travel)
	var foot := center + right * lateral
	_box(parent, foot + Vector3.UP * 1.1, Vector3(0.12, 2.2, 0.12), Basis(), "steel")
	var panel := foot + Vector3.UP * 2.4
	_box(parent, panel, Vector3(2.4, 1.5, 0.1), facing, "blue")
	_sign_text(parent, text, panel + Vector3.UP * 0.35 - travel * 0.08, facing, 40, Color.WHITE)
	_sign_text(parent, "↗", panel - Vector3.UP * 0.3 - travel * 0.08, facing, 70, Color.WHITE)


## Raststätte, aufgebaut wie eine deutsche Rastanlage. Lage: „along“ in Fahrtrichtung (0 bis
## Länge L, groß 280 m, klein 220 m), „across“ vom autobahnseitigen Rand (0–46 m).
## Fahrgasse 0–8 m (auch der Verkehr), Pkw in Doppelreihen quer (2,5 × 5 m, across 8–18) kurz
## vor der Tankstelle, zweite Fahrgasse 18–24 m, Lkw schräg (45°, 4 × 18 m, across 24–40) im
## vorderen Teil, dahinter ein Grünstreifen mit Bäumen und Bänken. Die Tankstelle (Modell) steht
## am Ende vor der Einfahrt, daneben ein Platz mit Gehweg zu den Pkw. Markierungen, Bordsteine
## (14 cm), Inseln, Gehwege, Leitplanke zur Autobahn und Laternen sind ein Mesh mit einer
## Fläche pro Material. 20–50 % der Plätze sind belegt (fest pro Raststätte, vom Verkehr gebaut).
func _add_rest_props(segment: RoadSegment, key: Vector3i, parent: Node3D) -> void:
	var rest := highways.rest_area_at(highway_axis(key), key.y, key.x, rest_dir(key))
	var travel2: Vector2 = rest["travel"]
	var side2: Vector2 = rest["side"]
	var t := Vector3(travel2.x, 0.0, travel2.y)
	var r := Vector3(side2.x, 0.0, side2.y)
	var center: Vector3 = rest["center"]
	var half_length: float = rest["half_length"]
	var length := half_length * 2.0
	var large: bool = rest["large"]
	var o := center - t * half_length - r * HighwayLayout.REST_WIDTH * 0.5 - segment.origin
	var at := func(along: float, across: float, y: float) -> Vector3:
		return o + t * along + r * across + Vector3.UP * y
	# Basis: x quer (weg von der Autobahn), y hoch, z gegen die Fahrtrichtung
	var frame := Basis(r, Vector3.UP, -t)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var lot := LotMesh.new(o, t, r)
	var body := StaticBody3D.new()
	parent.add_child(body)
	# --- Pkw: Doppelreihen in Gruppen à 10 Plätze, dazwischen Inseln mit Baum ---
	var groups := 3 if large else 2
	var car_end := length - 72.0
	var car_start := car_end - groups * 25.0 - (groups + 1) * 3.0
	var car_spots: Array = []  # [along, across, Richtung quer (+1 = Nase weg von der Autobahn)]
	for g in groups + 1:
		var a := car_start + g * 28.0
		lot.block(a + 1.5, 13.0, 3.0, 10.0, 0.0, 0.14, "grass", body)
		_rest_tree(parent, at.call(a + 1.5, 13.0, 0.14), lot, 1.0)
		if g == groups:
			break
		var a0 := a + 3.0
		lot.rect(a0 + 12.5, 13.0, 25.0, 0.12, 0.0, 0.015)
		# Reihe A (zur Fahrgasse): in der letzten Gruppe drei breitere Plätze (Familien)
		var widths: Array[float] = []
		for k in 10:
			widths.append(2.5)
		if g == groups - 1:
			widths = [2.5, 2.5, 2.5, 2.5, 2.5, 2.5, 10.0 / 3.0, 10.0 / 3.0, 10.0 / 3.0]
		for row: int in [0, 1]:
			var row_widths: Array[float] = widths if row == 0 else ([2.5, 2.5, 2.5, 2.5, 2.5, 2.5, 2.5, 2.5, 2.5, 2.5] as Array[float])
			var c_mid := 10.5 if row == 0 else 15.5
			var edge := a0
			lot.rect(edge, c_mid, 0.12, 5.0, 0.0, 0.015)
			for w in row_widths:
				car_spots.append([edge + w * 0.5, c_mid, -1.0 if row == 0 else 1.0])
				edge += w
				lot.rect(edge, c_mid, 0.12, 5.0, 0.0, 0.015)
	# --- Lkw: schräge Plätze (45°), von der zweiten Fahrgasse aus ---
	var trucks := 26 if large else 16
	var truck_spots: Array = []
	for i in trucks + 1:
		var a := 26.0 + i * 5.66
		lot.rect(a + 6.36, 30.36, 18.0, 0.15, PI * 0.25, 0.015)
		if i < trucks:
			truck_spots.append([a + 2.83 + 6.36, 30.36])
	# --- Pfeile auf den Fahrgassen (Einbahn in Fahrtrichtung) ---
	var arrow_at := 18.0
	while arrow_at < length - 75.0:
		lot.arrow(arrow_at, 4.0)
		lot.arrow(arrow_at + 22.0, 21.0)
		arrow_at += 50.0
	# --- Grünstreifen hinten mit Bäumen, Büschen und Bänken ---
	lot.block((14.0 + length - 70.0) * 0.5, 43.25, length - 84.0, 5.5, 0.0, 0.14, "grass", body)
	var tree_at := 24.0
	var bench_side := false
	while tree_at < length - 76.0:
		_rest_tree(parent, at.call(tree_at, 43.5, 0.14), lot, 1.0)
		if bench_side:
			_rest_bench(lot, tree_at + 2.6, 42.0)
		else:
			_rest_bush(parent, at.call(tree_at + 9.0, 44.0, 0.14))
		bench_side = not bench_side
		tree_at += 18.0
	# --- Platz neben der Tankstelle, Gehweg zu den Pkw, Zebrastreifen über die Fahrgasse ---
	var plaza_start := length - 68.0
	lot.block((plaza_start + length - 14.0) * 0.5, 39.5, length - 14.0 - plaza_start, 13.0, 0.0, 0.14, "paving", body)
	lot.block(car_end + 2.0, 13.0, 4.0, 10.0, 0.0, 0.14, "paving", body)
	var zebra := 18.5
	while zebra < 33.0:
		lot.rect(car_end + 2.0, zebra, 4.0, 0.5, 0.0, 0.015)
		zebra += 1.0
	for bench_at: float in [plaza_start + 12.0, plaza_start + 26.0]:
		_rest_bench(lot, bench_at, 44.6)
	# --- Leitplanke zur Autobahn (zwischen Ausfahrt und Einfahrt) ---
	lot.rail(16.0, length - 16.0, -0.6, body)
	# --- Laternen an der Fahrgasse und im Grünstreifen ---
	var lamp_at := 20.0
	while lamp_at < length - 16.0:
		lot.lantern(lamp_at, -1.5, 1.0)
		if lamp_at < length - 76.0:
			lot.lantern(lamp_at + 17.0, 41.2, -1.0)
		lamp_at += 35.0
	# --- Tankstelle am Ende (Modell; ohne Modell die gebaute Version) ---
	var station_at: Vector3 = at.call(length - 47.0, 21.0, 0.0)
	if not _add_station_model(parent, body, station_at, Basis(t, Vector3.UP, r)):
		_add_built_station(parent, at, frame, length)
	# --- Geparkte Fahrzeuge (fest pro Raststätte) ---
	var traffic := get_tree().get_first_node_in_group("traffic") as Traffic
	if traffic:
		var car_rate := rng.randf_range(0.2, 0.5)
		for spot: Array in car_spots:
			if rng.randf() >= car_rate:
				continue
			var type := Traffic.random_car_type(rng)
			var vehicle := traffic.make_parked(type, Traffic.random_paint(rng))
			# Mal vorwärts, mal rückwärts eingeparkt
			var nose := r * float(spot[2]) * (1.0 if rng.randf() < 0.7 else -1.0)
			vehicle.transform = Transform3D(Basis.looking_at(-nose), at.call(spot[0], spot[1], 0.0))
			parent.add_child(vehicle)
			_rest_collision(body, vehicle.transform, Vector3(Traffic.TYPES[type]["width"], Traffic.TYPES[type]["height"],
				Traffic.TYPES[type]["length"]))
		var truck_rate := rng.randf_range(0.25, 0.55)
		var truck_nose := (t + r).normalized()
		for spot: Array in truck_spots:
			if rng.randf() >= truck_rate:
				continue
			var truck := traffic.make_parked("lkw", Traffic.random_paint(rng))
			truck.transform = Transform3D(Basis.looking_at(-truck_nose), at.call(spot[0], spot[1], 0.0))
			parent.add_child(truck)
			_rest_collision(body, truck.transform, Vector3(2.5, 3.9, 12.7))
	parent.add_child(lot.commit(self))
	# Mit Aussicht: braunes Schild „Seeblick“ bzw. „Bergblick“ im Grünstreifen
	if rest["view"] != "":
		var sign_at: Vector3 = at.call(length * 0.35, 44.5, 0.14)
		for offset: float in [-0.9, 0.9]:
			_box(parent, sign_at + t * offset + Vector3.UP * 1.1, Vector3(0.1, 2.2, 0.1), frame, "steel")
		_box(parent, sign_at + Vector3.UP * 2.0 + r * 0.06, Vector3(0.08, 0.7, 2.4), frame, "brown")
		_sign_text(parent, Viewpoints.REST_VIEW_NAMES[rest["view"]], sign_at + Vector3.UP * 2.0,
			Basis.looking_at(r), 40, Color.WHITE)
	# Echte Lichter (aus, bis _update_night_glow sie nachts in der Nähe einschaltet)
	var truck_middle := 26.0 + trucks * 2.83 + 6.0
	for spot: Array in [[length - 40.0, 21.0, 4.4, 24.0], [(car_start + car_end) * 0.5, 13.0, 7.0, 34.0],
			[truck_middle, 30.0, 7.0, 34.0]]:
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.88, 0.7)
		light.omni_range = spot[3]
		light.light_energy = 2.2
		light.shadow_enabled = false
		light.visible = false
		light.position = at.call(spot[0], spot[1], spot[2])
		parent.add_child(light)
		_rest_lights.append(light)


## Kollision eines Kastens (Mitte am Boden unter transform, Größe size)
func _rest_collision(body: StaticBody3D, placement: Transform3D, size: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.transform = Transform3D(placement.basis, placement.origin + Vector3.UP * size.y * 0.5)
	body.add_child(shape)


## Baum (Stamm im Mesh der Raststätte, Krone als Kugel)
func _rest_tree(parent: Node3D, foot: Vector3, lot: LotMesh, size: float) -> void:
	lot.post(foot, 0.3 * size, 3.0 * size, "wood")
	var crown := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 2.4 * size
	sphere.height = 4.2 * size
	sphere.radial_segments = 10
	sphere.rings = 6
	sphere.material = _sign_material("crown")
	crown.mesh = sphere
	crown.position = foot + Vector3.UP * 4.4 * size
	parent.add_child(crown)


func _rest_bush(parent: Node3D, foot: Vector3) -> void:
	var bush := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.1
	sphere.height = 1.4
	sphere.radial_segments = 8
	sphere.rings = 4
	sphere.material = _sign_material("crown")
	bush.mesh = sphere
	bush.position = foot + Vector3.UP * 0.55
	parent.add_child(bush)


## Bank mit Lehne (Blick weg von der Autobahn), Sitzfläche längs
func _rest_bench(lot: LotMesh, along: float, across: float) -> void:
	lot.box(along, across, 1.8, 0.45, 0.0, 0.42, 0.5, "wood")
	lot.box(along, across - 0.22, 1.8, 0.06, 0.0, 0.5, 0.9, "wood")
	for leg: float in [-0.75, 0.75]:
		lot.box(along + leg, across, 0.08, 0.4, 0.0, 0.14, 0.42, "steel")


var _station_model: PreparedModel
var _station_checked: bool = false
var _station_glow: Array[BaseMaterial3D] = []


## Tankstellen-Modell (tools/setup_traffic_models.gd): nah und mittel, Kollision aus seinen
## Kästen, leuchtende Materialien für die Nacht merken. false = kein Modell da.
func _add_station_model(parent: Node3D, body: StaticBody3D, at: Vector3, facing: Basis) -> bool:
	if not _station_checked:
		_station_checked = true
		if ResourceLoader.exists(STATION_MODEL):
			_station_model = load(STATION_MODEL) as PreparedModel
		if _station_model:
			var emissive: Array = _station_model.info.get("emissive", [])
			for mesh: ArrayMesh in [_station_model.near_mesh, _station_model.mid_mesh]:
				for i in mesh.get_surface_count():
					var material := mesh.surface_get_material(i) as BaseMaterial3D
					if material and material.resource_name in emissive and material not in _station_glow:
						material.emission_enabled = true
						if material.emission == Color.BLACK:
							material.emission = Color(1.0, 0.95, 0.85)
						_station_glow.append(material)
	if _station_model == null:
		return false
	# Modell steht mittig auf dem Boden (Mitte der Bounding-Box auf at)
	var box := _station_model.near_mesh.get_aabb()
	var shift := Vector3(box.get_center().x, 0.0, box.get_center().z)
	var origin := at - facing * shift
	for pair: Array in [[_station_model.near_mesh, 0.0, 180.0], [_station_model.mid_mesh, 180.0, 0.0]]:
		var instance := MeshInstance3D.new()
		instance.mesh = pair[0]
		instance.visibility_range_begin = pair[1]
		instance.visibility_range_end = pair[2]
		instance.visibility_range_begin_margin = 5.0 if pair[1] > 0.0 else 0.0
		instance.visibility_range_end_margin = 5.0 if pair[2] > 0.0 else 0.0
		instance.transform = Transform3D(facing, origin)
		parent.add_child(instance)
	for aabb in _station_model.collision_boxes:
		var shape := CollisionShape3D.new()
		var collision := BoxShape3D.new()
		collision.size = aabb.size
		shape.shape = collision
		shape.transform = Transform3D(facing, origin + facing * aabb.get_center())
		body.add_child(shape)
	return true


## Gebaute Tankstelle (ohne Modell): Dach mit leuchtender Unterseite, drei Zapfsäulen-Inseln, Kasse
func _add_built_station(parent: Node3D, at: Callable, frame: Basis, length: float) -> void:
	var a := length - 45.0
	_box(parent, at.call(a, 18.0, 5.6), Vector3(20.0, 0.7, 34.0), frame, "canopy")
	_box(parent, at.call(a, 18.0, 5.23), Vector3(19.0, 0.06, 33.0), frame, "canopy_glow")
	_box(parent, at.call(a, 18.0, 5.75), Vector3(20.1, 0.25, 34.1), frame, "red")
	for across: float in [12.0, 18.0, 24.0]:
		_box(parent, at.call(a, across, 0.1), Vector3(1.3, 0.2, 10.0), frame, "shop")
		_box(parent, at.call(a, across, 2.8), Vector3(0.35, 5.4, 0.35), frame, "canopy")
		for along: float in [a - 3.5, a + 3.5]:
			_box(parent, at.call(along, across, 0.95), Vector3(0.6, 1.7, 0.8), frame, "red")
			_box(parent, at.call(along, across, 1.4), Vector3(0.66, 0.35, 0.5), frame, "screen_glow")
	_box(parent, at.call(a, 39.0, 1.8), Vector3(9.0, 3.6, 16.0), frame, "shop")
	_box(parent, at.call(a, 39.0, 3.75), Vector3(9.6, 0.3, 16.6), frame, "red")
	_box(parent, at.call(a, 34.47, 1.5), Vector3(0.05, 2.0, 12.0), frame, "window_glow")


## Nachts leuchten Laternen, Tankstellendach und Fenster; echte Lichter nur nah am Auto
func _update_night_glow(delta: float) -> void:
	_glow_timer -= delta
	if _glow_timer > 0.0:
		return
	_glow_timer = 0.25
	if _day_night == null:
		_day_night = get_tree().get_first_node_in_group("day_night") as DayNight
	var night := 1.0 - (_day_night.daylight if _day_night else 1.0)
	for pair: Array in [["lamp_glow", 7.0], ["canopy_glow", 5.0], ["window_glow", 3.0], ["screen_glow", 2.5]]:
		_sign_material(pair[0]).emission_energy_multiplier = lerpf(0.15, pair[1], night)
	# Tankstellen-Modell: Dach-Unterseite und Leuchtkästen
	for material in _station_glow:
		material.emission_energy_multiplier = lerpf(0.3, 4.0, night)
	# Lampen auf Landmarken-Brücken: rot, nachts hell
	if _landmark_lamp:
		_landmark_lamp.emission_energy_multiplier = lerpf(0.4, 9.0, night)
	# Erleuchtete Fenster in den Dörfern: tagsüber gar nicht
	_sign_material("house_window_lit").emission_energy_multiplier = lerpf(0.0, 2.6, night)
	var p := target.global_position if target else Vector3.ZERO
	_update_lantern_lights(night, p)
	var kept: Array[OmniLight3D] = []
	for light in _rest_lights:
		if not is_instance_valid(light):
			continue
		kept.append(light)
		light.visible = night > 0.5 and light.global_position.distance_to(p) < rest_light_distance
	_rest_lights = kept


## Am Aussichtspunkt: braunes Schild am Anfang der Parkbucht (für den Verkehr auf dieser
## Seite lesbar) und eine Bank mit Blick in die Landschaft
func _add_viewpoint_props(segment: RoadSegment, parent: Node3D) -> void:
	var spot := segment.viewpoint
	var i0: int = spot["index"]
	var side: float = spot["side"]
	var outer := segment.road_width * 0.5 + segment.shoulder_width - 0.5 + Viewpoints.BAY_WIDTH
	# Rechtsverkehr: Neben der Bucht fährt man in Richtung side (rechts der Punktrichtung = vorwärts)
	var steps := ceili(Viewpoints.BAY_HALF_LENGTH / RoadSegment.POINT_SPACING) + 2
	var j := i0 - steps * int(side)
	var travel := segment.direction_at(j) * side
	var right := travel.cross(Vector3.UP).normalized()
	var foot := segment.points[j] - segment.origin + right * (outer + 1.0)
	var facing := Basis.looking_at(travel)
	_box(parent, foot + Vector3.UP * 1.4, Vector3(0.12, 2.8, 0.12), Basis(), "steel")
	var panel := foot + Vector3.UP * 2.7
	_box(parent, panel, Vector3(3.0, 1.3, 0.1), facing, "brown")
	_sign_text(parent, "Aussichtspunkt", panel - travel * 0.07 + Vector3.UP * 0.2, facing, 44, Color.WHITE)
	_sign_text(parent, Viewpoints.KIND_NAMES[spot["kind"]], panel - travel * 0.07 + Vector3.DOWN * 0.28, facing, 34,
		Color(1, 1, 1, 0.85))
	# Bank am äußeren Rand, Blick weg von der Straße
	var look: Vector3 = spot["look"]
	var seat := (spot["center"] as Vector3) - segment.origin + look * (Viewpoints.BAY_WIDTH * 0.5 + 1.4)
	var bench_basis := Basis.looking_at(look)
	_box(parent, seat + Vector3.UP * 0.45, Vector3(1.8, 0.08, 0.45), bench_basis, "wood")
	_box(parent, seat + Vector3.UP * 0.78 + look * -0.22, Vector3(1.8, 0.4, 0.06), bench_basis, "wood")
	for leg: float in [-0.75, 0.75]:
		_box(parent, seat + bench_basis.x * leg + Vector3.UP * 0.22, Vector3(0.08, 0.45, 0.4), bench_basis, "steel")


## Länge eines Autobahn-Abschnitts (berechnet oder geschätzt)
func _section_length(key: Vector3i) -> float:
	var entry: Entry = _entries.get(key)
	if entry and entry.state >= State.BUILT and entry.segment.valid:
		return entry.segment.total_length()
	var a := highways.control_point(highway_axis(key), key.y, key.x)
	var b := highways.control_point(highway_axis(key), key.y, key.x + 1)
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z)) * 1.03


var _sign_materials: Dictionary = {}


func _sign_material(name_key: String) -> StandardMaterial3D:
	if not _sign_materials.has(name_key):
		var material := StandardMaterial3D.new()
		match name_key:
			"blue":
				material.albedo_color = Color("#1F4FA8")
				material.emission_enabled = true
				material.emission = Color("#1F4FA8")
				material.emission_energy_multiplier = 0.25
			"white":
				material.albedo_color = Color(0.95, 0.95, 0.95)
				material.emission_enabled = true
				material.emission = Color(0.9, 0.9, 0.9)
				material.emission_energy_multiplier = 0.25
			"brown":
				# Braun wie touristische Hinweisschilder
				material.albedo_color = Color("#6E4424")
				material.emission_enabled = true
				material.emission = Color("#6E4424")
				material.emission_energy_multiplier = 0.2
			"wood":
				material.albedo_color = Color("#7A5636")
				material.roughness = 0.85
			"line":
				# Markierungen auf dem Parkplatz
				material.albedo_color = Color(0.86, 0.86, 0.83)
				material.roughness = 0.7
			"curb":
				material.albedo_color = Color(0.62, 0.62, 0.6)
				material.roughness = 0.9
			"grass":
				material.albedo_color = Color(0.22, 0.36, 0.13)
				material.roughness = 0.95
			"paving":
				material.albedo_color = Color(0.5, 0.48, 0.45)
				material.roughness = 0.85
			"lamp_glow", "canopy_glow", "window_glow", "screen_glow":
				# Leuchten nachts (Stärke setzt _update_night_glow), tagsüber kaum
				material.albedo_color = Color(0.95, 0.93, 0.85) if name_key != "window_glow" else Color(0.55, 0.6, 0.62)
				material.emission_enabled = true
				material.emission = Color(1.0, 0.86, 0.6) if name_key != "screen_glow" else Color(0.5, 0.8, 1.0)
				material.emission_energy_multiplier = 0.2
			"canopy":
				material.albedo_color = Color(0.92, 0.93, 0.95)
				material.roughness = 0.5
			"red":
				material.albedo_color = Color("#C8252B")
				material.roughness = 0.5
			"shop":
				material.albedo_color = Color("#D9D2C3")
				material.roughness = 0.8
			"roof":
				material.albedo_color = Color("#5B5F66")
				material.roughness = 0.7
			"crown":
				material.albedo_color = Color("#3E6B2C")
				material.roughness = 0.9
			"dark":
				material.albedo_color = Color(0.12, 0.13, 0.15)
				material.roughness = 0.6
			"yellow":
				# Ortsschild
				material.albedo_color = Color("#F2C200")
				material.emission_enabled = true
				material.emission = Color("#F2C200")
				material.emission_energy_multiplier = 0.15
			"house_wall", "house_roof":
				# Häuser: Farbe kommt aus den Punktfarben
				material.vertex_color_use_as_albedo = true
				material.vertex_color_is_srgb = true
				material.roughness = 0.9 if name_key == "house_wall" else 0.75
				if name_key == "house_roof":
					material.cull_mode = BaseMaterial3D.CULL_DISABLED
			"house_window", "house_window_lit":
				material.albedo_color = Color(0.09, 0.11, 0.14)
				material.roughness = 0.12
				material.metallic = 0.3
				if name_key == "house_window_lit":
					material.emission_enabled = true
					material.emission = Color(1.0, 0.78, 0.45)
					material.emission_energy_multiplier = 0.0
			_:
				material.albedo_color = Color(0.55, 0.57, 0.6)
				material.metallic = 0.6
				material.roughness = 0.45
		_sign_materials[name_key] = material
	return _sign_materials[name_key]


func _box(parent: Node3D, center: Vector3, size: Vector3, box_basis: Basis, material_key: String) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _sign_material(material_key)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.transform = Transform3D(box_basis, center)
	parent.add_child(instance)


func _sign_text(parent: Node3D, text: String, at: Vector3, text_basis: Basis, size: int, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.font = UiStyle.font("semibold")
	label.font_size = size
	label.pixel_size = 0.01
	label.modulate = color
	label.outline_size = 0
	label.double_sided = false
	label.transform = Transform3D(text_basis, at)
	parent.add_child(label)


## Schilderbrücke über der Fahrbahn in Fahrtrichtung travel: „14  Tannbach  2000 m“
func _gantry(parent: Node3D, center: Vector3, travel: Vector3, interchange: Dictionary, distance_text: String) -> void:
	var right := travel.cross(Vector3.UP).normalized()
	# Das Schild schaut dem Verkehr entgegen (Text lesbar von vorne)
	var facing := Basis.looking_at(travel)
	var near := center + right * 1.2
	var far := center + right * (HIGHWAY_WIDTH * 0.5 + 1.2)
	for foot in [near, far]:
		_box(parent, foot + Vector3.UP * 3.6, Vector3(0.35, 7.2, 0.35), Basis(), "steel")
	var middle := (near + far) * 0.5
	var beam_basis := Basis.looking_at(far - near)
	_box(parent, middle + Vector3.UP * 6.9, Vector3(0.4, 0.5, near.distance_to(far)), beam_basis, "steel")
	# Blaue Tafel über den Fahrstreifen
	var panel := center + right * 6.6 + Vector3.UP * 5.6
	_box(parent, panel, Vector3(7.2, 2.6, 0.15), facing, "blue")
	var front := -travel * 0.1
	var number_box := panel + front + right * -2.7 + Vector3.UP * 0.55
	_box(parent, number_box, Vector3(1.1, 0.8, 0.05), facing, "white")
	# Label3D zeigt seinen Text nach +Z: bei looking_at(travel) ist das dem Verkehr zugewandt
	var text_basis := facing
	_sign_text(parent, str(interchange["number"]), number_box + front * 0.5, text_basis, 56, Color("#1F4FA8"))
	_sign_text(parent, interchange["name"], panel + front + right * 0.6 + Vector3.UP * 0.55, text_basis, 70, Color.WHITE)
	_sign_text(parent, distance_text, panel + front + Vector3.DOWN * 0.7, text_basis, 60, Color.WHITE)


## Ausfahrt-Schild am Beginn der Rampe: „Ausfahrt 14“
func _exit_sign(parent: Node3D, center: Vector3, travel: Vector3, interchange: Dictionary, lateral: float) -> void:
	_island_sign(parent, center, travel, lateral, "Ausfahrt %d" % interchange["number"])


## Leitpfosten als MultiMesh: weißer Pfosten mit schwarzem Band und Rückstrahler
func _make_posts(segment: RoadSegment) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = _post_mesh()
	multimesh.instance_count = segment.posts.size()
	for i in segment.posts.size():
		var t := segment.posts[i]
		multimesh.set_instance_transform(i, Transform3D(t.basis, t.origin - segment.origin))
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


var _post_mesh_cache: ArrayMesh


func _post_mesh() -> ArrayMesh:
	if _post_mesh_cache:
		return _post_mesh_cache
	var post := BoxMesh.new()
	post.size = Vector3(0.12, 1.0, 0.12)
	var tool := SurfaceTool.new()
	tool.create_from(post, 0)
	var arrays := tool.commit_to_arrays()
	# Pfosten 1 m hoch, unten im Boden; schwarzes Band oben
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors := PackedColorArray()
	for i in verts.size():
		verts[i].y += 0.5
		colors.append(Color(0.08, 0.08, 0.08) if verts[i].y > 0.72 and verts[i].y < 0.95 else Color(0.92, 0.92, 0.9))
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	_post_mesh_cache = ArrayMesh.new()
	_post_mesh_cache.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_post_mesh_cache.surface_set_material(0, post_material)
	# Rückstrahler: zwei kleine Flächen vorne und hinten im schwarzen Band
	var reflector := PackedVector3Array()
	var normals := PackedVector3Array()
	for z: float in [0.061, -0.061]:
		var n := Vector3(0, 0, signf(z))
		var quad := [Vector3(-0.04, 0.76, z), Vector3(0.04, 0.76, z), Vector3(0.04, 0.9, z), Vector3(-0.04, 0.9, z)]
		var order := [0, 1, 2, 0, 2, 3] if z < 0.0 else [0, 2, 1, 0, 3, 2]
		for index: int in order:
			reflector.append(quad[index])
			normals.append(n)
	var reflector_arrays: Array = []
	reflector_arrays.resize(Mesh.ARRAY_MAX)
	reflector_arrays[Mesh.ARRAY_VERTEX] = reflector
	reflector_arrays[Mesh.ARRAY_NORMAL] = normals
	_post_mesh_cache.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, reflector_arrays)
	_post_mesh_cache.surface_set_material(1, reflector_material)
	return _post_mesh_cache


func _make_body(faces: PackedVector3Array) -> StaticBody3D:
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	var body := StaticBody3D.new()
	body.add_child(collision)
	add_child(body)
	return body


func _free_visuals(entry: Entry) -> void:
	if entry.mesh_instance:
		entry.mesh_instance.queue_free()
		entry.mesh_instance = null
	if entry.landmark_instance:
		entry.landmark_instance.queue_free()
		entry.landmark_instance = null
	if entry.body:
		entry.body.queue_free()
		entry.body = null


## Liegt Punkt i eines Abschnitts zwischen Ortsschild und Ortsmitte (dort gilt 50)?
func in_village(segment: RoadSegment, i: int) -> bool:
	if not is_road_key(segment.key):
		return false
	var s := i * RoadSegment.POINT_SPACING
	var length := (segment.points.size() - 1) * RoadSegment.POINT_SPACING
	for end: Array in [[Vector2i(segment.key.x, segment.key.y), s], [edge_end_cell(segment.key), length - s]]:
		var village: Village = _villages.get(end[0])
		if village == null:
			continue
		var reach := village.sign_reach(segment)
		if reach > 0.0 and end[1] < reach:
			return true
	return false


## Dörfer: Mesh, Schilder und Kollision je nach Entfernung, ganz weit weg vergessen
func _update_villages(p: Vector2) -> void:
	for cell: Vector2i in _villages.keys():
		var village: Village = _villages[cell]
		if village.task_id != -1:
			if not WorkerThreadPool.is_task_completed(village.task_id):
				continue
			WorkerThreadPool.wait_for_task_completion(village.task_id)
			village.task_id = -1
		var distance := Vector2(village.center.x - p.x, village.center.z - p.y).length()
		if distance > FORGET_DISTANCE:
			_free_village(village)
			_villages.erase(cell)
			continue
		if village.houses.is_empty():
			continue
		if distance < mesh_distance:
			if village.mesh_instance == null:
				_build_village(village)
			var shadows := distance < village_shadow_distance
			village.mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif village.mesh_instance:
			village.mesh_instance.queue_free()
			village.mesh_instance = null
		if distance < collision_distance and village.body == null:
			village.body = StaticBody3D.new()
			for box: Array in village.boxes:
				var shape := BoxShape3D.new()
				shape.size = box[1]
				var collision := CollisionShape3D.new()
				collision.shape = shape
				collision.transform = box[0]
				village.body.add_child(collision)
			add_child(village.body)
		elif distance > collision_distance + 100.0 and village.body:
			village.body.queue_free()
			village.body = null


## Mesh eines Dorfs (eine Fläche pro Material) und die Ortsschilder
func _build_village(village: Village) -> void:
	var mesh := ArrayMesh.new()
	var materials := {"wall": "house_wall", "roof": "house_roof", "window": "house_window",
		"window_lit": "house_window_lit", "lamp": "lamp_glow"}
	for key: String in village.surfaces:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, village.surfaces[key])
		mesh.surface_set_material(mesh.get_surface_count() - 1, _sign_material(materials[key]))
	village.mesh_instance = MeshInstance3D.new()
	village.mesh_instance.mesh = mesh
	village.mesh_instance.position = village.center
	add_child(village.mesh_instance)
	var place := highways.place_name(village.cell)
	for place_sign: Array in village.signs:
		_village_sign(village.mesh_instance, (place_sign[0] as Vector3) - village.center, place_sign[1], place)


## Gelbes Ortsschild: vorne der Name (für den Verkehr in den Ort hinein), hinten der Name mit
## rotem Schrägstrich (Ortsende)
func _village_sign(parent: Node3D, foot: Vector3, inward: Vector3, place: String) -> void:
	var facing := Basis.looking_at(inward)
	_box(parent, foot + Vector3.UP * 1.25 + inward * 0.06, Vector3(0.09, 2.5, 0.09), Basis(), "steel")
	var panel := foot + Vector3.UP * 2.4
	_box(parent, panel, Vector3(2.5, 1.3, 0.05), facing, "dark")
	_box(parent, panel, Vector3(2.4, 1.2, 0.07), facing, "yellow")
	var size := clampi(roundi(2.2 / (0.0058 * place.length())), 20, 52)
	_sign_text(parent, place, panel - inward * 0.045, facing, size, Color(0.05, 0.05, 0.05))
	var back := Basis.looking_at(-inward)
	_sign_text(parent, place, panel + inward * 0.045, back, size, Color(0.05, 0.05, 0.05))
	_box(parent, panel + inward * 0.05, Vector3(2.6, 0.13, 0.01), back * Basis(Vector3.BACK, 0.42), "red")


## Nachts: echte Lichter an den nächsten Straßenlaternen der Dörfer (wenige, ohne Schatten)
func _update_lantern_lights(night: float, p: Vector3) -> void:
	if _lantern_lights.is_empty():
		for k in village_light_count:
			var light := OmniLight3D.new()
			light.light_color = Color(1.0, 0.85, 0.62)
			light.omni_range = 16.0
			light.light_energy = 1.8
			light.shadow_enabled = false
			light.visible = false
			add_child(light)
			_lantern_lights.append(light)
	var near: Array = []  # [Abstand², Lage]
	if night > 0.5:
		var limit := village_light_distance * village_light_distance
		for village: Village in _villages.values():
			if village.task_id != -1 or village.mesh_instance == null \
					or village.center.distance_to(p) > Village.REACH + village_light_distance + 40.0:
				continue
			for head in village.lanterns:
				var d := head.distance_squared_to(p)
				if d < limit:
					near.append([d, head])
		near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for k in _lantern_lights.size():
		var light := _lantern_lights[k]
		light.visible = k < near.size()
		if light.visible:
			light.global_position = near[k][1]


func _free_village(village: Village) -> void:
	if village.task_id != -1:
		WorkerThreadPool.wait_for_task_completion(village.task_id)
		village.task_id = -1
	if village.mesh_instance:
		village.mesh_instance.queue_free()
		village.mesh_instance = null
	if village.body:
		village.body.queue_free()
		village.body = null


func _free_junction(junction: RoadJunction) -> void:
	if junction.mesh_instance:
		junction.mesh_instance.queue_free()
		junction.mesh_instance = null
	if junction.body:
		junction.body.queue_free()
		junction.body = null


func _distance_to_rect(point: Vector2, rect: Rect2) -> float:
	return point.distance_to(point.clamp(rect.position, rect.end))
