class_name SpeedLimits
extends Node
## Tempolimits und Verkehrszeichenerkennung.
##
## SpeedLimits.compute(segment) legt beim Berechnen eines Abschnitts (im Hintergrund) für jede
## Fahrtrichtung und jeden Punkt das Limit fest und merkt sich die Schilder dazu:
## - Landstraße 100, Tunnel 80, vor engen Kurven Kurvenschild und 70 (Radius < 120 m) bzw. 50
##   (< 60 m), bei Gegenkurven „Doppelkurve“, danach die Aufhebung. Orte (Ortsschild bis
##   Ortsende) 50, das gilt beim Nachschauen (die Dörfer entstehen erst später).
## - Autobahn ohne Limit, an Tunneln 100, in engeren Kurven 120/100 (ein Teil nur „bei Nässe“),
##   auf langen Gefällen 120, einzelne Abschnitte ganz 120 oder „100 bei Nässe“, danach
##   „Ende aller Streckenverbote“; Schilder beidseitig.
## Alles hängt nur vom Abschnitt ab (deterministisch). Der Knoten selbst verfolgt das Limit an
## der Stelle des Autos (für HUD, Tempomat und Navi).

@export var roads: RoadNetwork
@export var car: Car
## So oft nachsehen (Sekunden)
@export var update_interval: float = 0.2

const ROAD_LIMIT: int = 100
const TUNNEL_LIMIT: int = 80
const VILLAGE_LIMIT: int = 50
## Landstraße: Kurven enger als dieser Radius bekommen 70 bzw. 50
const CURVE_70_RADIUS: float = 120.0
const CURVE_50_RADIUS: float = 60.0
## Autobahn: Kurven enger als dieser Radius 120 bzw. 100, Gefälle ab diesem Wert über 1 km 120
const HIGHWAY_CURVE_RADIUS: float = 1900.0
const HIGHWAY_TIGHT_RADIUS: float = 1300.0
const HIGHWAY_GRADE: float = 0.03
## Anteil der Kurven-Abschnitte auf der Autobahn, die nur bei Nässe gelten (Prozent)
const WET_ONLY_SHARE: int = 35
## Anteil der Autobahn-Abschnitte (je Richtung) mit festem 120 bzw. „100 bei Nässe“ (Prozent)
const HIGHWAY_SECTION_120: int = 14
const HIGHWAY_SECTION_WET: int = 12
## Ein Wert im Limit-Array: Tempo / 5 (0 = kein Limit), 255 = noch nichts eingetragen
const NONE: int = 0

## Limit an der Stelle des Autos (km/h, 0 = unbegrenzt, -1 = unbekannt), gilt nur bei Nässe?
var current_limit: int = -1
var current_wet_only: bool = false
## Das Limit, das gerade wirklich gilt (bei trockener Straße zählt „bei Nässe“ nicht)
var effective_limit: int = -1

var _timer: float = 0.0
var _segment: RoadSegment
var _index: int = 0


# ---------------------------------------------------------------------------
# Berechnung pro Abschnitt (im Hintergrund)
# ---------------------------------------------------------------------------

## Füllt segment.limits_forward/backward (Tempo/5 je Punkt, 0 = keins), wet_forward/backward
## (1 = gilt nur bei Nässe) und segment.limit_signs: [Punkt, Richtung (+1 = Punktreihenfolge),
## Art, Wert, bei Nässe?]. Arten: limit, end_limit, end_all, curve_left, curve_right, double_curve.
## Limit-Schilder stehen dort, wo sich das Limit ändert (Tunnel 80 und Kurve 70 können sich so
## überlappen, ohne dass eines verloren geht), Warnschilder am Beginn jeder Kurvenzone.
static func compute(segment: RoadSegment) -> void:
	var n := segment.points.size()
	segment.limit_signs = []
	var highway := segment.kind == RoadSegment.Kind.HIGHWAY
	var default := 0 if highway else roundi(ROAD_LIMIT / 5.0)
	for d: int in [1, -1]:
		var limits := PackedByteArray()
		var wet := PackedByteArray()
		limits.resize(n)
		wet.resize(n)
		if segment.kind == RoadSegment.Kind.ROAD:
			limits.fill(default)
		var zones := _zones(segment, d)
		# Trockene Limits zuerst, „bei Nässe“ nur, wo sonst nichts Kleineres gilt
		for pass_wet: bool in [false, true]:
			for zone: Array in zones:
				if zone[3] != pass_wet:
					continue
				for i in range(maxi(zone[0], 0), mini(zone[1], n - 1) + 1):
					var value: int = roundi(zone[2] / 5.0)
					if pass_wet:
						if limits[i] == default:
							limits[i] = value
							wet[i] = 1
					elif limits[i] == NONE or value < limits[i]:
						limits[i] = value
		_fill_short_gaps(limits, wet, default, 50 if highway else 25)
		# Fahrzeit fürs Navi: Landstraße mit Limit (ohne 100) und etwas Abschlag für Kurven und Orte,
		# Autobahn ohne Limit wie bisher mit 130
		var seconds := 0.0
		var free_kmh := 130.0 if highway else float(ROAD_LIMIT)
		for i in range(1, n):
			var kmh := limits[i] * 5.0 if limits[i] > 0 and wet[i] == 0 else free_kmh
			if segment.kind == RoadSegment.Kind.ROAD:
				kmh *= 0.8
			seconds += RoadSegment.POINT_SPACING / (minf(kmh, 130.0) / 3.6)
		if d > 0:
			segment.limits_forward = limits
			segment.wet_forward = wet
			segment.nav_seconds_forward = seconds
		else:
			segment.limits_backward = limits
			segment.wet_backward = wet
			segment.nav_seconds_backward = seconds
		_add_signs(segment, zones, limits, wet, default, d)


## Zonen in Fahrtrichtung d: [erster Punkt, letzter Punkt (Punktreihenfolge), Limit, nur bei
## Nässe?, Warnschild (leer = keins)]. Nahe Kurvenzonen werden zusammengefasst (ein Warnschild).
static func _zones(segment: RoadSegment, d: int) -> Array:
	var zones: Array = []
	var n := segment.points.size()
	var highway := segment.kind == RoadSegment.Kind.HIGHWAY
	if segment.kind != RoadSegment.Kind.ROAD and not highway:
		return zones
	# Vorlauf (Schild vor der Gefahr) und Nachlauf in Punkten, in Fahrtrichtung
	var lead := 100 if highway else 15
	var tail := 25 if highway else 5
	for r in segment.tunnel_ranges:
		zones.append(_directed(r.x, r.y, lead, tail, d, 100 if highway else TUNNEL_LIMIT, false, ""))
	# Kurven: zusammenhängende Stücke enger als der Grenzradius
	var curves: Array = []
	var limit_radius := HIGHWAY_CURVE_RADIUS if highway else CURVE_70_RADIUS
	var i := 0
	while i < n:
		if absf(segment.curvature[i]) < 1.0 / limit_radius:
			i += 1
			continue
		var a := i
		var tightest := 0.0
		var left := false
		var right := false
		while i < n and absf(segment.curvature[i]) >= 1.0 / limit_radius:
			tightest = maxf(tightest, absf(segment.curvature[i]))
			# Positiv = Linkskurve in Punktreihenfolge, in Gegenrichtung umgekehrt
			left = left or segment.curvature[i] * d > 0.0
			right = right or segment.curvature[i] * d < 0.0
			i += 1
		var b := i - 1
		if b - a < 3:
			continue
		var value := 0
		var wet := false
		var warning := ""
		if highway:
			value = 100 if tightest > 1.0 / HIGHWAY_TIGHT_RADIUS else 120
			wet = _hash(segment, a) < WET_ONLY_SHARE
		else:
			value = 50 if tightest > 1.0 / CURVE_50_RADIUS else 70
			warning = "double_curve" if left and right else ("curve_left" if left else "curve_right")
		curves.append(_directed(a, b, lead, tail, d, value, wet, warning))
	# Kurvenzonen mit weniger als 100 m Lücke werden eine (kleinstes Limit, ein Warnschild)
	curves.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	for zone: Array in curves:
		if not zones.is_empty() and (zones.back() as Array)[4] != "" and zone[0] - (zones.back() as Array)[1] < 25:
			var last: Array = zones.back()
			last[1] = maxi(last[1], zone[1])
			last[2] = mini(last[2], zone[2])
			last[3] = last[3] and zone[3]
			if last[4] != zone[4]:
				last[4] = "double_curve"
		else:
			zones.append(zone.duplicate())
	if highway:
		# Lange Gefälle in Fahrtrichtung (über 1 km im Schnitt mehr als 3 %)
		var window := roundi(1000.0 / RoadSegment.POINT_SPACING)
		var start := -1
		for k in n:
			var ahead := k + window * d
			var down := false
			if ahead >= 0 and ahead < n:
				down = (segment.points[k].y - segment.points[ahead].y) / 1000.0 > HIGHWAY_GRADE
			if down and start < 0:
				start = k
			elif not down and start >= 0:
				zones.append(_directed(mini(start, k), maxi(start, k), 25, 25, d, 120, false, ""))
				start = -1
		if start >= 0:
			zones.append(_directed(mini(start, n - 1), maxi(start, n - 1), 25, 25, d, 120, false, ""))
		# Manche Abschnitte haben ein festes Limit (Lärmschutz, Unfallschwerpunkt): 120 oder
		# „100 bei Nässe“, je Abschnitt und Richtung fest
		var roll := _hash(segment, 7 + d)
		if roll < HIGHWAY_SECTION_120:
			zones.append([30, n - 31, 120, false, ""])
		elif roll < HIGHWAY_SECTION_120 + HIGHWAY_SECTION_WET:
			zones.append([30, n - 31, 100, true, ""])
	return zones


## Zahl 0–99, fest pro Abschnitt und Stelle
static func _hash(segment: RoadSegment, salt: int) -> int:
	return posmod(segment.key.x * 7919 + segment.key.y * 104729 + segment.key.z * 15485863 + salt * 31, 100)


## Zone von a bis b (Punktreihenfolge) mit Vorlauf vor dem Beginn und Nachlauf nach dem Ende in
## Fahrtrichtung d
static func _directed(a: int, b: int, lead: int, tail: int, d: int, value: int, wet: bool, warning: String) -> Array:
	if d > 0:
		return [a - lead, b + tail, value, wet, warning]
	return [a - tail, b + lead, value, wet, warning]


## Kurze Stücke mit höherem Limit zwischen zwei niedrigeren (unter `gap` Punkten) bekommen das
## höhere der beiden Nachbarn: sonst steht alle paar Meter ein neues Schild
static func _fill_short_gaps(limits: PackedByteArray, wet: PackedByteArray, default: int, gap: int) -> void:
	var n := limits.size()
	var rank := func(at: int) -> int:
		return 1000 if limits[at] == 0 or limits[at] == default else limits[at] + (500 if wet[at] == 1 else 0)
	var i := 0
	while i < n:
		var j := i
		while j + 1 < n and limits[j + 1] == limits[i] and wet[j + 1] == wet[i]:
			j += 1
		if i > 0 and j < n - 1 and j - i < gap:
			var low: int = maxi(rank.call(i - 1), rank.call(j + 1))
			if rank.call(i) > low:
				var source := i - 1 if rank.call(i - 1) == low else j + 1
				for k in range(i, j + 1):
					limits[k] = limits[source]
					wet[k] = wet[source]
		i = j + 1


## Schilder in Fahrtrichtung d: Warnschild am Beginn jeder Kurvenzone, Limit-Schild an jeder
## Änderung, Aufhebung (Landstraße) bzw. „Ende aller Streckenverbote“ (Autobahn) zurück auf frei.
## Fällt eine Stelle in einen Tunnel oder auf eine Brücke, steht das Schild davor.
static func _add_signs(segment: RoadSegment, zones: Array, limits: PackedByteArray, wet: PackedByteArray, default: int, d: int) -> void:
	var n := segment.points.size()
	var highway := segment.kind == RoadSegment.Kind.HIGHWAY
	for zone: Array in zones:
		if zone[4] != "":
			var at := _sign_spot(segment, zone[0] if d > 0 else zone[1], d)
			if at >= 0:
				segment.limit_signs.append([at, d, zone[4], 0, false])
	# Am Anfang des Abschnitts (in Fahrtrichtung) gilt schon ein Limit: Schild wiederholen
	var first := 0 if d > 0 else n - 1
	var previous := Vector2i(default, 0)
	var k := first
	while k >= 0 and k < n:
		var now := Vector2i(limits[k], wet[k])
		if now != previous:
			var at := _sign_spot(segment, k, d)
			if at >= 0:
				if now.x == default or now.x == NONE:
					var kind := "end_all" if highway else "end_limit"
					segment.limit_signs.append([at, d, kind, previous.x * 5, false])
				else:
					segment.limit_signs.append([at, d, "limit", now.x * 5, now.y == 1])
			previous = now
		k += d


## Stelle für ein Schild: nicht ganz am Rand des Abschnitts (Kreuzungen), nicht in Tunneln und auf
## Brücken (dann davor, höchstens 60 Punkte zurück); -1 = keine
static func _sign_spot(segment: RoadSegment, i: int, d: int) -> int:
	var n := segment.points.size()
	i = clampi(i, 8, n - 9)
	for step in 60:
		if i < 8 or i > n - 9:
			return -1
		if segment.tunnel[i] == 0 and segment.bridge[i] == 0:
			return i
		i -= d
	return -1


# ---------------------------------------------------------------------------
# Limit an der Stelle des Autos
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	var started := Time.get_ticks_usec()
	_timed_process(delta)
	FrameCosts.add("Tempolimits", started)


func _timed_process(delta: float) -> void:
	if roads == null or car == null:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = update_interval
	_find_place(car.global_position)
	if _segment == null:
		return
	var forward := _segment.direction_at(_index).dot(car.global_basis.z) >= 0.0
	var limit := limit_at(_segment, _index, forward)
	# Auf Rampen, Parkplätzen und Kreuzungen bleibt das zuletzt erkannte Limit stehen
	if limit.x >= 0:
		current_limit = limit.x
		current_wet_only = limit.y == 1
	effective_limit = current_limit
	if current_wet_only and car.wetness < 0.3:
		effective_limit = 0 if _segment.kind == RoadSegment.Kind.HIGHWAY else ROAD_LIMIT


## Straßenabschnitt und Punkt unter dem Auto (zuletzt gefunden), null = keiner
func place_segment() -> RoadSegment:
	return _segment


func place_index() -> int:
	return _index


## Limit an Punkt i in einer Richtung: (km/h, 0 = keins; -1 = keine Angabe), (1 = bei Nässe)
func limit_at(segment: RoadSegment, i: int, forward: bool) -> Vector2i:
	if segment.limits_forward.is_empty():
		return Vector2i(-1, 0)
	if segment.kind == RoadSegment.Kind.ROAD and roads.in_village(segment, i):
		return Vector2i(VILLAGE_LIMIT, 0)
	var limits := segment.limits_forward if forward else segment.limits_backward
	var wet := segment.wet_forward if forward else segment.wet_backward
	return Vector2i(limits[i] * 5, wet[i])


## Nächster Straßenpunkt zum Auto: erst in der Nähe des letzten suchen, sonst alle Abschnitte
## in 40 m Umkreis
func _find_place(p: Vector3) -> void:
	if _segment and is_instance_valid(roads) and _segment.points.size() > 0:
		var best := INF
		var best_i := _index
		for i in range(maxi(_index - 12, 0), mini(_index + 13, _segment.points.size())):
			var d := Vector2(_segment.points[i].x - p.x, _segment.points[i].z - p.z).length_squared()
			if d < best:
				best = d
				best_i = i
		if best < 100.0 and best_i > 0 and best_i < _segment.points.size() - 1:
			_index = best_i
			return
	var best_distance := 30.0 * 30.0
	_segment = null
	for pair: Array in roads.loaded_segments(Rect2(p.x - 40.0, p.z - 40.0, 80.0, 80.0)):
		var segment: RoadSegment = pair[1]
		for i in segment.points.size():
			var d := Vector2(segment.points[i].x - p.x, segment.points[i].z - p.z).length_squared()
			if d < best_distance:
				best_distance = d
				_segment = segment
				_index = i
