class_name HighwayLayout
extends RefCounted
## Wo die Autobahnen verlaufen, nur aus dem Seed (ohne Wegsuche): lange Linien quer durch
## die Welt, west–ost und nord–süd. Auf jeder Linie liegt alle CONTROL_SPACING Meter ein
## Stützpunkt. Seine Lage quer zur Linie folgt einem glatten Rauschen (weite, sanfte Bögen),
## nur wenige Meter daneben wird die günstigste Stelle gesucht (tief, flach, nicht im See).
## Zwischen zwei Stützpunkten verläuft die Autobahn als glatte Kurve (centerline), an den
## Stützpunkten geradeaus weiter. Berge bekommen Tunnel, Täler Brücken.
## Orte entstehen nicht auf der Trasse (RoadNetwork fragt is_clear). An jedem
## INTERCHANGE_EVERY-ten Stützpunkt kann eine Anschlussstelle zu einem nahen Ort liegen,
## der Zubringer führt vom Ort zum Stützpunkt. Die Orte bekommen erfundene, deutsch
## klingende Namen.

## Mittlerer Abstand der Linien und Anteil der Linien, die es wirklich gibt
const LINE_SPACING: float = 6000.0
const LINE_CHANCE: float = 0.75
## Abstand der Stützpunkte entlang einer Linie
const CONTROL_SPACING: float = 1600.0
## So weit weicht die Linie höchstens seitlich ab (glattes Rauschen, Stützwerte alle
## WANDER_KNOT Stützpunkte)
const CONTROL_WANDER: float = 900.0
const WANDER_KNOT: int = 4
## Am Stützpunkt wird bis zu so weit daneben die günstigste Stelle gesucht (Meter, quer).
## Mehr macht engere Kurven (S-Kurve zwischen zwei Stützpunkten).
const LOCAL_SEARCH: float = 120.0
## Gerades Stück an jedem Stützpunkt, an möglichen Anschlussstellen länger (Rampen)
const LEAD: float = 150.0
## Höhe der Fahrbahn an den Stützpunkten: höchstens so viel über dem Talboden (darüber Tunnel)
const MAX_ABOVE_FLOOR: float = 50.0
## Ein Stützpunkt liegt höchstens so viel über oder unter der Mitte seiner Nachbarn (sonst
## wird es zwischen zwei Stützpunkten zu steil)
const HEIGHT_SMOOTHING: float = 15.0
## Nur an jedem zweiten Stützpunkt eine Anschlussstelle (also höchstens alle 3,2 km)
const INTERCHANGE_EVERY: int = 2
## Abstand Ort–Autobahn an einer Anschlussstelle (Länge des Zubringers bis zur Autobahn)
const INTERCHANGE_MIN: float = 220.0
const INTERCHANGE_REACH: float = 900.0
## So weit bleiben Orte von der Mittellinie weg
const PLACE_CLEARANCE: float = 220.0

const NAME_STARTS: Array[String] = ["Tann", "Ober", "Unter", "Alt", "Neu", "Wald", "Berg", "Stein", "Hohen",
	"Kirch", "Mühl", "Linden", "Eichen", "Buch", "Rosen", "Wolfs", "Hasel", "Lauter", "Sonnen", "Brunn",
	"Fichten", "Erlen", "Schön", "Grün", "Roth", "Weiß", "Mittel", "Kalten", "Falken", "Birken"]
const NAME_ENDS: Array[String] = ["bach", "berg", "dorf", "feld", "hausen", "heim", "ingen", "au", "stein",
	"tal", "wald", "brück", "furt", "hof", "kirchen", "weiler", "rode", "stadt", "see", "hagen", "beuren",
	"münster", "wangen", "bronn"]

var world_gen: WorldGen
var roads: RoadNetwork
var _points: Dictionary = {}  # Vector3i(Achse, Linie, k) -> Vector3
var _spots: Dictionary = {}  # Vector3i(Achse, Linie, k) -> Vector3 (Höhe noch nicht geglättet)
var _interchanges: Dictionary = {}  # Vector3i(Achse, Linie, k) -> Dictionary (leer = keine)
var _centerlines: Dictionary = {}  # Vector3i(Achse, Linie, k) -> PackedVector2Array
var _boxes: Dictionary = {}  # Vector3i(Achse, Linie, k) -> Rect2 um die Mittellinie
var _knots: Dictionary = {}  # Vector3i(Achse, Linie, j) -> float


func _init(gen: WorldGen, network: RoadNetwork) -> void:
	world_gen = gen
	roads = network


## Gibt es diese Linie? Achse 0 = west–ost (z ≈ Linie · LINE_SPACING), 1 = nord–süd
func line_exists(axis: int, line: int) -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_gen.hash_cell(line, axis, 707)
	return rng.randf() < LINE_CHANCE


## Lage der Linie quer zur Fahrtrichtung (z bei Achse 0, x bei Achse 1)
func line_position(axis: int, line: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_gen.hash_cell(line, axis, 708)
	return (line + rng.randf_range(-0.25, 0.25)) * LINE_SPACING


## Wo der Stützpunkt k auf der geraden Linie läge (x/z)
func nominal(axis: int, line: int, k: int) -> Vector2:
	if axis == 0:
		return Vector2(k * CONTROL_SPACING, line_position(axis, line))
	return Vector2(line_position(axis, line), k * CONTROL_SPACING)


## Richtung entlang der Linie (x/z) und quer dazu
static func along(axis: int) -> Vector2:
	return Vector2(1.0, 0.0) if axis == 0 else Vector2(0.0, 1.0)


static func across(axis: int) -> Vector2:
	return Vector2(0.0, 1.0) if axis == 0 else Vector2(1.0, 0.0)


## Stützpunkt k (Weltposition, y = Höhe der Fahrbahn dort, mit den Nachbarn geglättet)
func control_point(axis: int, line: int, k: int) -> Vector3:
	var id := Vector3i(axis, line, k)
	if not _points.has(id):
		var spot := _spot(axis, line, k)
		var middle := (_spot(axis, line, k - 1).y + _spot(axis, line, k + 1).y) * 0.5
		spot.y = clampf(spot.y, middle - HEIGHT_SMOOTHING, middle + HEIGHT_SMOOTHING)
		_points[id] = spot
	return _points[id]


func _spot(axis: int, line: int, k: int) -> Vector3:
	var id := Vector3i(axis, line, k)
	if not _spots.has(id):
		_spots[id] = _best_spot(axis, line, k)
	return _spots[id]


## Fahrtrichtung der Autobahn am Stützpunkt (x/z): von k-1 nach k+1
func direction_at(axis: int, line: int, k: int) -> Vector2:
	var before := control_point(axis, line, k - 1)
	var after := control_point(axis, line, k + 1)
	return Vector2(after.x - before.x, after.z - before.z).normalized()


## Gerades Stück am Stützpunkt k (an möglichen Anschlussstellen lang genug für die Rampen)
static func lead_at(k: int) -> float:
	return RoadNetwork.RAMP_LENGTH + 30.0 if posmod(k, INTERCHANGE_EVERY) == 0 else LEAD


## Mittellinie von Stützpunkt k bis k+1 (x/z): an beiden Enden gerade (lead_at), dazwischen
## eine glatte Hermite-Kurve, alle ~8 m ein Punkt
func centerline(axis: int, line: int, k: int) -> PackedVector2Array:
	var id := Vector3i(axis, line, k)
	if _centerlines.has(id):
		return _centerlines[id]
	var a3 := control_point(axis, line, k)
	var b3 := control_point(axis, line, k + 1)
	var a := Vector2(a3.x, a3.z)
	var b := Vector2(b3.x, b3.z)
	var leave := direction_at(axis, line, k)
	var arrive := direction_at(axis, line, k + 1)
	var p0 := a + leave * lead_at(k)
	var p1 := b - arrive * lead_at(k + 1)
	var length := p0.distance_to(p1)
	var m0 := leave * length
	var m1 := arrive * length
	var result := PackedVector2Array([a, p0])
	var steps := maxi(ceili(length / 8.0), 2)
	for i in range(1, steps + 1):
		var t := float(i) / steps
		var t2 := t * t
		var t3 := t2 * t
		result.append(p0 * (2.0 * t3 - 3.0 * t2 + 1.0) + m0 * (t3 - 2.0 * t2 + t)
			+ p1 * (-2.0 * t3 + 3.0 * t2) + m1 * (t3 - t2))
	result.append(b)
	_centerlines[id] = result
	var box := Rect2(a, Vector2.ZERO)
	for point in result:
		box = box.expand(point)
	_boxes[id] = box
	return result


## Rechteck um die Mittellinie von Stützpunkt k bis k+1
func centerline_box(axis: int, line: int, k: int) -> Rect2:
	centerline(axis, line, k)
	return _boxes[Vector3i(axis, line, k)]


## Seitliche Abweichung der Linie am Stützpunkt k: glattes Rauschen (Zufallswerte alle
## WANDER_KNOT Stützpunkte, weich überblendet)
func _wander(axis: int, line: int, k: int) -> float:
	var j := floori(k / float(WANDER_KNOT))
	var t := float(k - j * WANDER_KNOT) / WANDER_KNOT
	return lerpf(_knot(axis, line, j), _knot(axis, line, j + 1), (1.0 - cos(t * PI)) * 0.5)


## Stützwert des Rauschens: die tiefste, flachste Lage quer zur Linie (Tal), damit die
## Autobahn möglichst wenig Tunnel braucht. Gemessen auf 800 m entlang der Linie.
func _knot(axis: int, line: int, j: int) -> float:
	var id := Vector3i(axis, line, j)
	if _knots.has(id):
		return _knots[id]
	var rng := RandomNumberGenerator.new()
	rng.seed = world_gen.hash_cell(j, line * 2 + axis, 709)
	var base := nominal(axis, line, j * WANDER_KNOT)
	var best := 0.0
	var best_cost := INF
	var count := int(CONTROL_WANDER / 100.0)
	for s in range(-count, count + 1):
		var cost := rng.randf() * 10.0
		for t: float in [-400.0, 0.0, 400.0]:
			var p := base + across(axis) * (s * 100.0) + along(axis) * t
			var h := world_gen.terrain_height(p.x, p.y, [])
			cost += h - world_gen.ground_level(p.x, p.y)
		if cost < best_cost:
			best_cost = cost
			best = s * 100.0
	_knots[id] = best
	return best


## Günstigste Stelle nahe der geglätteten Linie: tief (wenig Relief über dem Talboden),
## flach und trocken
func _best_spot(axis: int, line: int, k: int) -> Vector3:
	var side := across(axis)
	var base := nominal(axis, line, k) + side * _wander(axis, line, k)
	var best := base
	var best_cost := INF
	for s in range(-2, 3):
		var p := base + side * (s * LOCAL_SEARCH * 0.5)
		var lakes: Array = world_gen.lakes_near(Rect2(p - Vector2(80.0, 80.0), Vector2(160.0, 160.0)))
		if world_gen.water_level_at(p.x, p.y, lakes) > WorldGen.NO_WATER:
			continue
		var h := world_gen.terrain_height(p.x, p.y, lakes)
		var slope := (absf(world_gen.terrain_height(p.x + 40.0, p.y, lakes) - h)
			+ absf(world_gen.terrain_height(p.x, p.y + 40.0, lakes) - h)) / 40.0
		var cost := (h - world_gen.ground_level(p.x, p.y)) + slope * 400.0 + absi(s) * 15.0
		if cost < best_cost:
			best_cost = cost
			best = p
	return Vector3(best.x, _road_height(best), best.y)


## Höhe der Fahrbahn am Stützpunkt: das Gelände (gemittelt), aber nahe am Talboden. So liegen
## benachbarte Stützpunkte nie weit übereinander; Berge dazwischen bekommen Tunnel.
func _road_height(p: Vector2) -> float:
	var floor_height := world_gen.ground_level(p.x, p.y)
	return clampf(_smooth_height(p), floor_height + 3.0, floor_height + MAX_ABOVE_FLOOR)


## Geländehöhe im Mittel über 120 m (damit die flache Stelle am Stützpunkt nicht auf einem Buckel liegt)
func _smooth_height(p: Vector2) -> float:
	var lakes: Array = world_gen.lakes_near(Rect2(p - Vector2(80.0, 80.0), Vector2(160.0, 160.0)))
	var total := 0.0
	for offset: Vector2 in [Vector2.ZERO, Vector2(60, 0), Vector2(-60, 0), Vector2(0, 60), Vector2(0, -60)]:
		total += world_gen.terrain_height(p.x + offset.x, p.y + offset.y, lakes)
	return total / 5.0


## Liegt dieser Punkt mindestens clearance Meter neben jeder Autobahn? (Für die Orte: sie
## entstehen nicht auf der Trasse.)
func is_clear(p: Vector2, clearance: float) -> bool:
	var reach := CONTROL_WANDER + LOCAL_SEARCH + clearance + 100.0
	for axis in 2:
		var across_position := p.y if axis == 0 else p.x
		var along_position := p.x if axis == 0 else p.y
		var first := floori((across_position - reach) / LINE_SPACING - 0.25)
		var last := ceili((across_position + reach) / LINE_SPACING + 0.25)
		for line in range(first, last + 1):
			if not line_exists(axis, line) or absf(line_position(axis, line) - across_position) > reach:
				continue
			var k := floori(along_position / CONTROL_SPACING)
			for section in [k - 1, k]:
				var path := centerline(axis, line, section)
				if not (_boxes[Vector3i(axis, line, section)] as Rect2).grow(clearance).has_point(p):
					continue
				for i in path.size() - 1:
					var closest := Geometry2D.get_closest_point_to_segment(p, path[i], path[i + 1])
					if closest.distance_squared_to(p) < clearance * clearance:
						return false
	return true


## Anschlussstelle am Stützpunkt k: {"cell": Ort-Zelle, "place": Ort, "point": Stützpunkt,
## "side": Richtung, in der der Zubringer die Autobahn rechtwinklig überquert (x/z),
## "leave": Richtung, in der er den Ort verlässt, "number": Ausfahrt-Nummer, "name": Ortsname}
## Leer, wenn es dort keine gibt.
func interchange_at(axis: int, line: int, k: int) -> Dictionary:
	var id := Vector3i(axis, line, k)
	if _interchanges.has(id):
		return _interchanges[id]
	var result := {}
	if posmod(k, INTERCHANGE_EVERY) == 0 and line_exists(axis, line):
		result = _find_interchange(axis, line, k)
	_interchanges[id] = result
	return result


## Nächster Ort neben dem Stützpunkt (nicht zu weit, nicht zu schräg), an dem in Richtung
## Autobahn noch Platz für den Zubringer ist
func _find_interchange(axis: int, line: int, k: int) -> Dictionary:
	var point := control_point(axis, line, k)
	var q := Vector2(point.x, point.z)
	var dir := direction_at(axis, line, k)
	var normal := Vector2(dir.y, -dir.x)
	var best: Dictionary = {}
	var best_distance := INF
	var cell := Vector2i(floori(q.x / roads.cell_size), floori(q.y / roads.cell_size))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var place_cell := cell + Vector2i(dx, dz)
			var node: Variant = roads.node_at(place_cell)
			if node == null:
				continue
			var place := node as Vector3
			var offset := Vector2(place.x, place.z) - q
			var distance := absf(offset.dot(normal))
			if distance < INTERCHANGE_MIN or distance > INTERCHANGE_REACH or absf(offset.dot(dir)) > distance * 1.2 \
					or offset.length() >= best_distance:
				continue
			var leave := _free_leave(place_cell, -offset.normalized())
			if leave == Vector2.ZERO:
				continue
			best_distance = offset.length()
			best = {"cell": place_cell, "place": place, "side": normal * -signf(offset.dot(normal)),
				"leave": leave, "point": point,
				"number": posmod(int(floor(k / float(INTERCHANGE_EVERY))) + line * 7, 90) + 1,
				"name": place_name(place_cell)}
	return best


## Freie Richtung am Ort, möglichst nah an toward (höchstens 60° daneben), sonst Vector2.ZERO
func _free_leave(cell: Vector2i, toward: Vector2) -> Vector2:
	for step in 13:
		var angle := deg_to_rad(ceili(step / 2.0) * 10.0 * (1.0 if step % 2 == 1 else -1.0))
		var direction := toward.rotated(angle)
		if _free_direction(cell, direction):
			return direction
	return Vector2.ZERO


## Ist am Ort in dieser Richtung Platz für den Zubringer (≥ 50° Abstand zu den Straßen dort)?
func _free_direction(cell: Vector2i, direction: Vector2) -> bool:
	for option: Array in roads.edges_at(cell):
		var key: Vector3i = option[0]
		var toward := roads.edge_end_cell(key) if option[1] else Vector2i(key.x, key.y)
		var leave := roads.departure(cell, toward)
		if leave != Vector2.ZERO and absf(leave.angle_to(direction)) < deg_to_rad(50.0):
			return false
	return true


## Erfundener Ortsname, immer gleich für dieselbe Zelle
func place_name(cell: Vector2i) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_gen.hash_cell(cell.x, cell.y, 909)
	var first := NAME_STARTS[rng.randi_range(0, NAME_STARTS.size() - 1)]
	var last := NAME_ENDS[rng.randi_range(0, NAME_ENDS.size() - 1)]
	# Doppelungen wie „Bergberg“ oder „Steinstein“ vermeiden
	if first.to_lower() == last or first.to_lower().ends_with(last):
		last = "hausen"
	return first + last


## Linien und Stützpunkte, die einen Bereich berühren: [Achse, Linie, k] für jeden
## Abschnitt von Stützpunkt k nach k+1
func sections_touching(rect: Rect2) -> Array:
	var result: Array = []
	var margin := CONTROL_WANDER + LOCAL_SEARCH + LINE_SPACING * 0.25 + INTERCHANGE_REACH
	for axis in 2:
		var low := rect.position.y if axis == 0 else rect.position.x
		var high := rect.end.y if axis == 0 else rect.end.x
		var start_along := rect.position.x if axis == 0 else rect.position.y
		var end_along := rect.end.x if axis == 0 else rect.end.y
		for line in range(floori((low - margin) / LINE_SPACING), floori((high + margin) / LINE_SPACING) + 1):
			if not line_exists(axis, line):
				continue
			for k in range(floori(start_along / CONTROL_SPACING) - 1, floori(end_along / CONTROL_SPACING) + 1):
				var a := control_point(axis, line, k)
				var b := control_point(axis, line, k + 1)
				var area := Rect2(a.x, a.z, 0.0, 0.0).expand(Vector2(b.x, b.z)).grow(500.0)
				if area.intersects(rect):
					result.append([axis, line, k])
	return result
