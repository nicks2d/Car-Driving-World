class_name RoadSegment
extends RefCounted
## Ein Straßenabschnitt zwischen zwei Orten (Knoten). build() läuft im Hintergrund:
##  1. Wegsuche übers Gelände (A*): steil und Wasser sind teuer, so entstehen am Hang
##     von selbst Serpentinen und in der Ebene weite Bögen.
##  2. Trassierung wie im echten Straßenbau: Geraden und Kreisbögen, alle 4 m ein Punkt.
##     Dazu die Querneigung in Kurven.
##  3. Höhenprofil glätten und die Steigung begrenzen (Gelände wird später angepasst).
##     Liegt die Fahrbahn mehr als TUNNEL_DEPTH Meter unter dem Gelände, wird ein Tunnel daraus.
## Macht der Weg einen großen Umweg (oder gibt es keinen), wird zusätzlich eine Variante
## gerechnet, bei der die Wegsuche Berge durchbohren darf. Die bessere gewinnt.
## Später (wenn feststeht, wie groß die Kreuzungen an den Enden sind) baut build_mesh()
## die Mesh-Daten für Fahrbahn und Kollision, ebenfalls im Hintergrund.

# Rasterpunkte sind durchnummeriert (Zeile * Breite + Spalte). Die Ganzzahl-Divisionen
# in diesem Skript sind deshalb gewollt.
@warning_ignore_start("integer_division")

# --- Eingaben ---
var world_gen: WorldGen
var key: Vector3i
var start: Vector3
var end: Vector3
## Richtung, in der die Straße die Orte verlässt (am Ende: vom Ort aus gesehen).
## Vector2.ZERO = Luftlinie zum anderen Ort.
var start_direction: Vector2 = Vector2.ZERO
var end_direction: Vector2 = Vector2.ZERO
var road_width: float = 9.0
var shoulder_width: float = 1.5
var max_grade: float = 0.10
var grid_step: float = 18.0
## Wunschradius normaler Kurven und kleinster erlaubter Radius (enge Kehren)
var curve_radius: float = 60.0
var min_curve_radius: float = 20.0
## Querneigung in Kurven (0.05 = 5 %)
var max_bank: float = 0.05

# --- Ergebnisse ---
## Mittellinie, alle POINT_SPACING Meter ein Punkt, y = Höhe der Fahrbahn
var points: PackedVector3Array
## Geländehöhe unter jedem Punkt (vor der Anpassung)
var ground: PackedFloat32Array
## 1 = an diesem Punkt ist die Straße eine Brücke (über Wasser oder hoch über dem Gelände)
var bridge: PackedByteArray
## Krümmung an jedem Punkt (1 / Radius): positiv = Linkskurve, 0 = Gerade
var curvature: PackedFloat32Array
## Querneigung an jedem Punkt: positiv = linke Seite tiefer (in Linkskurven), 0.05 = 5 %
var bank: PackedFloat32Array
## Rechteck (x/z), in dem die Straße das Gelände beeinflusst
var bounds: Rect2
## false = es gab keinen vernünftigen Weg, hier entsteht keine Straße
var valid: bool = false
var mesh_arrays: Array = []
## Mesh-Daten für Brücken (Beton): Fahrbahnplatte, Brüstungen, Pfeiler. Leer = keine Brücke.
var bridge_arrays: Array = []
## Mesh-Daten für Leitplanken (Metall). Leer = keine Leitplanke.
var rail_arrays: Array = []
## 1 = an diesem Punkt liegt die Straße in einem Tunnel
var tunnel: PackedByteArray
## Tunnel als (erster Punkt, letzter Punkt); dort sind die Portale
var tunnel_ranges: Array[Vector2i] = []
## Mesh-Daten für Tunnelröhren und Portale (Beton, mit Punktfarben) und für die Deckenlampen
var tunnel_arrays: Array = []
var lamp_arrays: Array = []
## Stellen im Tunnel, an denen echte Lichter stehen können (Weltkoordinaten)
var tunnel_lights: PackedVector3Array
var collision_faces: PackedVector3Array
## Mittelpunkt, auf den sich die Mesh-Koordinaten beziehen (für Genauigkeit)
var origin: Vector3

const POINT_SPACING: float = 4.0
## So weit kann die Böschung neben der Straße höchstens reichen
const MAX_BANK: float = 60.0
## Neigung der Böschungen: pro Meter Abstand darf das Gelände 0,65 m höher oder tiefer liegen
const BANK_SLOPE: float = 0.65
## Höchster erlaubter Einschnitt ins Gelände (sonst keine Straße)
const MAX_CUT: float = 35.0
## Höchste erlaubte Höhe über dem Gelände (Brücke)
const MAX_FILL: float = 50.0
## So lang ist die Straße an beiden Orten mindestens gerade (Platz für die Kreuzung)
const END_STRAIGHT: float = 30.0
## Die ersten und letzten LEAD Meter führen genau in Abfahrtsrichtung (Kreuzungszufahrt)
const LEAD: float = 50.0
## So viele Punkte (je 4 m) liegen an beiden Orten flach auf Ortshöhe (Kreuzungsfläche)
const JUNCTION_FLAT: int = 6
## Querschnitt neben der Fahrbahn: Böschungskante (Breite, Absenkung) und Bankett-Absenkung
const VERGE_WIDTH: float = 1.8
const VERGE_DROP: float = -1.3
const SHOULDER_DROP: float = -0.06
## Ab so vielen Metern über dem Gelände wird statt eines Damms eine Brücke gebaut
const BRIDGE_HEIGHT: float = 7.0
## Ab so vielen Metern Gelände über der Fahrbahn wird ein Tunnel gebaut (statt eines Einschnitts)
const TUNNEL_DEPTH: float = 25.0
## An den Portalen liegt die Fahrbahn mindestens so tief unter dem Gelände (Platz für Röhre und Portal)
const PORTAL_DEPTH: float = 12.0
## Röhre: Höhe der senkrechten Wand und des Scheitels über der Fahrbahn, Abstand Wand–Bankett
const TUBE_WALL: float = 4.6
const TUBE_APEX: float = 7.6
const TUBE_CLEARANCE: float = 0.4
## Lampen an der Decke alle LAMP_EVERY Punkte, echte Lichter alle LIGHT_EVERY Punkte
const LAMP_EVERY: int = 2
const LIGHT_EVERY: int = 4
## Längere Tunnel gibt es nicht (der Abschnitt fällt dann weg wie früher ohne Tunnel)
const MAX_TUNNEL_LENGTH: float = 3000.0
## Tunnel-Variante der Wegsuche: Mehrkosten pro Meter Tunnel (1.0 = zählt doppelt) und pro Tunnel
const TUNNEL_COST: float = 1.0
const PORTAL_COST: float = 150.0
## Die Tunnel-Variante wird nur gerechnet, wenn der normale Weg so viel länger ist als die Luftlinie
const DETOUR_FOR_TUNNEL: float = 1.15
## Tunnel-Variante: In Bergen „sieht“ die Wegsuche das Gelände höchstens so viele Meter über
## dem tiefsten Punkt im Umkreis von TUNNEL_REF_CELLS Rasterfeldern
const TUNNEL_REF_ALLOW: float = 20.0
const TUNNEL_REF_CELLS: int = 12

## Tunnel-Variante: Bezugshöhe (tiefster Punkt im Umkreis) im Raster der Wegsuche
var _ref_grid := PackedFloat32Array()
var _grid_origin := Vector2.ZERO
var _grid_u := Vector2.ZERO
var _grid_v := Vector2.ZERO
var _grid_nu: int = 0
var _grid_nv: int = 0


func build() -> void:
	var straight := Vector2(start.x, start.z).distance_to(Vector2(end.x, end.z))
	var best := _build_variant(false)
	# Großer Umweg oder gar kein Weg: auch eine Variante rechnen, die Berge durchbohren darf
	if best.is_empty() or best["length"] > straight * DETOUR_FOR_TUNNEL:
		var bored := _build_variant(true)
		# Die Tunnel-Variante gewinnt nur mit Tunnel (sonst bleibt die Straße wie bisher)
		# und wenn sie deutlich günstiger ist
		if not bored.is_empty() and bored["tunnel_length"] > 0.0 \
				and (best.is_empty() or _score(bored) < _score(best) * 0.9):
			best = bored
	_ref_grid = PackedFloat32Array()
	if best.is_empty():
		return
	points = best["points"]
	curvature = best["curvature"]
	bank = best["bank"]
	ground = best["ground"]
	bridge = best["bridge"]
	tunnel = best["tunnel"]
	tunnel_ranges = best["tunnel_ranges"]
	bounds = best["bounds"]
	valid = true


## Eine Variante komplett berechnen (Weg, Kurven, Profil). Leer = kein vernünftiger Weg.
func _build_variant(allow_tunnels: bool) -> Dictionary:
	var path := _find_path(allow_tunnels)
	if path.size() < 2:
		return {}
	# Kleine Zickzacks der Wegsuche entfernen: übrig bleibt ein Polygonzug aus langen Geraden.
	# Die geraden Kreuzungszufahrten (erster und letzter Abschnitt) bleiben unverändert.
	var last := path.size() - 1
	path = PackedVector2Array([path[0]]) + _simplify(path.slice(1, last), 4.0) + PackedVector2Array([path[last]])
	if path.size() < 4:
		return {}
	if not _fit_curves(path):
		return {}
	_make_bank()
	if not _make_profile(allow_tunnels):
		return {}
	var tunnel_length := 0.0
	for r in tunnel_ranges:
		tunnel_length += (r.y - r.x) * POINT_SPACING
	return {"points": points, "curvature": curvature, "bank": bank, "ground": ground,
		"bridge": bridge, "tunnel": tunnel, "tunnel_ranges": tunnel_ranges.duplicate(), "bounds": bounds,
		"length": (points.size() - 1) * POINT_SPACING, "tunnel_length": tunnel_length}


## Wie „teuer“ eine Variante ist: Länge, Tunnel zählen mehr
func _score(variant: Dictionary) -> float:
	return variant["length"] + variant["tunnel_length"] * TUNNEL_COST \
		+ (variant["tunnel_ranges"] as Array).size() * PORTAL_COST


# ---------------------------------------------------------------------------
# 1. Wegsuche (A*) auf einem Raster zwischen Start und Ziel
# ---------------------------------------------------------------------------

func _find_path(allow_tunnels: bool) -> PackedVector2Array:
	var a := Vector2(start.x, start.z)
	var b := Vector2(end.x, end.z)
	var length := a.distance_to(b)
	var dir_u := (b - a) / length
	var dir_v := Vector2(-dir_u.y, dir_u.x)
	var margin := 150.0
	var half_width := corridor_half_width(length)
	var nu := int((length + 2.0 * margin) / grid_step) + 1
	var nv := int(2.0 * half_width / grid_step) + 1
	var grid_origin := a - dir_u * margin - dir_v * half_width
	var count := nu * nv
	var leave_a := start_direction if start_direction != Vector2.ZERO else dir_u
	var leave_b := end_direction if end_direction != Vector2.ZERO else -dir_u

	# Höhe und Zusatzkosten (Wasser, Berge) für jeden Rasterpunkt
	var corridor := Rect2(a, Vector2.ZERO).expand(b).grow(half_width + margin)
	var lakes: Array = world_gen.lakes_near(corridor)
	var heights := PackedFloat32Array()
	heights.resize(count)
	var extra := PackedFloat32Array()
	extra.resize(count)
	for iv in nv:
		for iu in nu:
			var p := grid_origin + dir_u * (iu * grid_step) + dir_v * (iv * grid_step)
			var i := iv * nu + iu
			var h := world_gen.terrain_height(p.x, p.y, lakes)
			heights[i] = h
			var penalty := (h - world_gen.ground_level(p.x, p.y)) * 0.02
			if world_gen.water_level_at(p.x, p.y, lakes) > WorldGen.NO_WATER:
				var in_lake := false
				for lake: WorldGen.Lake in lakes:
					if p.distance_to(lake.center) < lake.radius + 15.0:
						in_lake = true
				penalty += 100000.0 if in_lake else 250.0
			# In den ersten und letzten 250 m soll die Straße in einem Kegel von ±30° um ihre
			# Abfahrtsrichtung bleiben. Die Abfahrtsrichtungen eines Orts liegen mindestens 80°
			# auseinander (RoadNetwork), so laufen seine Straßen nicht nebeneinander her.
			var from_a := p - a
			var from_b := p - b
			if from_a.length() < 250.0 and from_a.length() > 1.0 and from_a.normalized().dot(leave_a) < 0.866:
				penalty += 300.0
			if from_b.length() < 250.0 and from_b.length() > 1.0 and from_b.normalized().dot(leave_b) < 0.866:
				penalty += 300.0
			extra[i] = penalty

	# Tunnel-Variante: Berge werden für die Wegsuche „abgeschnitten“ (höchstens
	# TUNNEL_REF_ALLOW über dem tiefsten Punkt der Umgebung). Was viel höher liegt, wäre Tunnel
	# und kostet pro Meter extra, jeder neue Tunnel noch einmal PORTAL_COST.
	var bored := PackedByteArray()
	bored.resize(count)
	if allow_tunnels:
		_ref_grid = _min_filter(heights, nu, nv, TUNNEL_REF_CELLS)
		_grid_origin = grid_origin
		_grid_u = dir_u
		_grid_v = dir_v
		_grid_nu = nu
		_grid_nv = nv
		for i in count:
			var cap := _ref_grid[i] + TUNNEL_REF_ALLOW
			if heights[i] > cap:
				if heights[i] - cap > TUNNEL_DEPTH:
					bored[i] = 1
				heights[i] = cap

	# Die Wegsuche beginnt und endet am Ende der geraden Kreuzungszufahrten
	var lead_a := a + leave_a * LEAD
	var lead_b := b + leave_b * LEAD
	var start_index := _grid_index(lead_a, grid_origin, dir_u, dir_v, nu, nv)
	var goal_index := _grid_index(lead_b, grid_origin, dir_u, dir_v, nu, nv)

	# A*: immer den Punkt mit den geringsten (bisherigen + geschätzten) Kosten weiter untersuchen.
	# Erlaubt sind Schritte in 48 Richtungen (z. B. „4 vor, 1 zur Seite“). Nur so kann der Weg
	# schräg am Hang hochlaufen, statt direkt bergauf: daraus entstehen die Serpentinen.
	var cost := PackedFloat32Array()
	cost.resize(count)
	cost.fill(INF)
	var came_from := PackedInt32Array()
	came_from.resize(count)
	came_from.fill(-1)
	var closed := PackedByteArray()
	closed.resize(count)
	var heap := MinHeap.new()
	cost[start_index] = 0.0
	heap.push(0.0, start_index)
	var goal_u_f := float(goal_index % nu)
	var goal_v_f := float(goal_index / nu)
	var moves := _moves()
	var move_dirs: Array[Vector2] = []
	for o in moves:
		move_dirs.append(Vector2(o).normalized())
	var found := false
	while not heap.is_empty():
		var current := heap.pop()
		if closed[current] == 1:
			continue
		if current == goal_index:
			found = true
			break
		closed[current] = 1
		var cu := current % nu
		var cv := current / nu
		var h0 := heights[current]
		# Aus welcher Richtung sind wir gekommen? (für die Kurven-Kosten)
		var incoming := Vector2.ZERO
		var previous := came_from[current]
		if previous != -1:
			incoming = Vector2(cu - previous % nu, cv - previous / nu).normalized()
		for m in moves.size():
			var o := moves[m]
			var nu_i := cu + o.x
			var nv_i := cv + o.y
			if nu_i < 0 or nv_i < 0 or nu_i >= nu or nv_i >= nv:
				continue
			var next := nv_i * nu + nu_i
			if closed[next] == 1:
				continue
			var step := grid_step * sqrt(float(o.x * o.x + o.y * o.y))
			var h1 := heights[next]
			var grade := absf(h1 - h0) / step
			# Punkt in der Mitte des Schritts: Wie viel müsste man auf- oder abtragen?
			var mid := (cv + o.y / 2) * nu + (cu + o.x / 2)
			var bump := absf(heights[mid] - (h0 + h1) * 0.5)
			# Steigung kostet etwas, zu steil kostet sehr viel, Wasser und Berge kosten extra
			var step_cost := step * (1.0 + grade * 6.0) + bump * step * 0.3 \
				+ (extra[next] + extra[mid]) * 0.5 * step / grid_step
			if grade > max_grade:
				step_cost += step * (grade - max_grade) * 250.0
			if bored[next] == 1:
				step_cost += step * TUNNEL_COST + (PORTAL_COST if bored[current] == 0 else 0.0)
			# Knicke über 30° kosten extra, über 45° sind sie verboten: Eine Kehre besteht so
			# aus mindestens vier Knicken und wird gut 40 m breit. Nur dann passt später ein
			# Kreisbogen mit mindestens 20 m Radius hinein (siehe _fit_curves).
			var turn_cos := incoming.dot(move_dirs[m])
			if previous != -1 and turn_cos < 0.7:
				continue
			if turn_cos < 0.866:
				step_cost += (0.866 - turn_cos) * 250.0
			var new_cost := cost[current] + step_cost
			if new_cost < cost[next]:
				cost[next] = new_cost
				came_from[next] = current
				var du := (goal_u_f - nu_i) * grid_step
				var dv := (goal_v_f - nv_i) * grid_step
				heap.push(new_cost + sqrt(du * du + dv * dv), next)
	if not found:
		return PackedVector2Array()

	# Weg rückwärts vom Ziel zum Start einsammeln
	var path := PackedVector2Array()
	var node := goal_index
	while node != -1:
		path.append(grid_origin + dir_u * ((node % nu) * grid_step) + dir_v * ((node / nu) * grid_step))
		node = came_from[node]
	path.reverse()
	path[0] = lead_a
	path[path.size() - 1] = lead_b
	path.insert(0, a)
	path.append(b)
	return path


## Tiefster Wert im Umkreis von radius Feldern (Quadrat), erst zeilen-, dann spaltenweise
static func _min_filter(values: PackedFloat32Array, nu: int, nv: int, radius: int) -> PackedFloat32Array:
	var rows := PackedFloat32Array()
	rows.resize(values.size())
	for iv in nv:
		for iu in nu:
			var m := INF
			for k in range(maxi(iu - radius, 0), mini(iu + radius, nu - 1) + 1):
				m = minf(m, values[iv * nu + k])
			rows[iv * nu + iu] = m
	var result := PackedFloat32Array()
	result.resize(values.size())
	for iu in nu:
		for iv in nv:
			var m := INF
			for k in range(maxi(iv - radius, 0), mini(iv + radius, nv - 1) + 1):
				m = minf(m, rows[k * nu + iu])
			result[iv * nu + iu] = m
	return result


## Nächster Rasterpunkt zu p
func _grid_index(p: Vector2, grid_origin: Vector2, dir_u: Vector2, dir_v: Vector2, nu: int, nv: int) -> int:
	var rel := p - grid_origin
	var iu := clampi(roundi(rel.dot(dir_u) / grid_step), 0, nu - 1)
	var iv := clampi(roundi(rel.dot(dir_v) / grid_step), 0, nv - 1)
	return iv * nu + iu


## Alle erlaubten Schritte: (x, y) mit höchstens 4 Feldern Abstand und ohne gemeinsamen Teiler
## (also nicht (2, 2), das wäre nur zweimal (1, 1)). Ergibt 48 Richtungen.
static func _moves() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for x in range(-4, 5):
		for y in range(-4, 5):
			if (x != 0 or y != 0) and _gcd(absi(x), absi(y)) == 1:
				result.append(Vector2i(x, y))
	return result


static func _gcd(a: int, b: int) -> int:
	while b != 0:
		var t := b
		b = a % b
		a = t
	return a


## Halbe Breite des Suchbereichs neben der Luftlinie
static func corridor_half_width(length: float) -> float:
	return clampf(length * 0.35, 200.0, 400.0)


## Kleine Hilfsklasse: Prioritätswarteschlange (kleinster Wert zuerst)
class MinHeap:
	var keys: PackedFloat32Array = PackedFloat32Array()
	var values: PackedInt32Array = PackedInt32Array()

	func is_empty() -> bool:
		return values.is_empty()

	func push(key: float, value: int) -> void:
		keys.append(key)
		values.append(value)
		var i := values.size() - 1
		while i > 0:
			var parent := (i - 1) / 2
			if keys[parent] <= keys[i]:
				break
			_swap(i, parent)
			i = parent

	func pop() -> int:
		var top := values[0]
		var last := values.size() - 1
		keys[0] = keys[last]
		values[0] = values[last]
		keys.resize(last)
		values.resize(last)
		var i := 0
		while true:
			var left := i * 2 + 1
			var right := left + 1
			var smallest := i
			if left < last and keys[left] < keys[smallest]:
				smallest = left
			if right < last and keys[right] < keys[smallest]:
				smallest = right
			if smallest == i:
				break
			_swap(i, smallest)
			i = smallest
		return top

	func _swap(a: int, b: int) -> void:
		var k := keys[a]
		keys[a] = keys[b]
		keys[b] = k
		var v := values[a]
		values[a] = values[b]
		values[b] = v


# ---------------------------------------------------------------------------
# 2. Glätten
# ---------------------------------------------------------------------------

## Ramer-Douglas-Peucker: entfernt Punkte, die kaum vom geraden Weg abweichen
func _simplify(path: PackedVector2Array, tolerance: float) -> PackedVector2Array:
	var keep := PackedByteArray()
	keep.resize(path.size())
	keep[0] = 1
	keep[path.size() - 1] = 1
	var stack: Array[Vector2i] = [Vector2i(0, path.size() - 1)]
	while not stack.is_empty():
		var range_: Vector2i = stack.pop_back()
		var a := path[range_.x]
		var b := path[range_.y]
		var worst := -1.0
		var worst_index := -1
		for i in range(range_.x + 1, range_.y):
			var d := _distance_to_line(path[i], a, b)
			if d > worst:
				worst = d
				worst_index = i
		if worst > tolerance:
			keep[worst_index] = 1
			stack.append(Vector2i(range_.x, worst_index))
			stack.append(Vector2i(worst_index, range_.y))
	var result := PackedVector2Array()
	for i in path.size():
		if keep[i] == 1:
			result.append(path[i])
	return result


func _distance_to_line(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Wie im echten Straßenbau: Der vereinfachte Weg ist ein Polygonzug aus Geraden. An jeden
## Knick kommt ein Kreisbogen, der beide Geraden berührt. Der Radius ist so groß wie möglich
## (mindestens curve_radius, bei kleinen Knicken mehr), die Bögen dürfen sich aber nicht
## überlappen. Ist ein Bogen zu eng, werden zwei Knicke zu einem zusammengefasst:
##  - unter min_curve_radius immer (klappt das nicht, gibt es hier keine Straße, false),
##  - unter curve_radius nur, wenn sich der Weg dadurch höchstens 15 m verschiebt.
func _fit_curves(poly: PackedVector2Array) -> bool:
	# Knicke, bei denen sich das Zusammenfassen nicht lohnt (Weg würde zu weit wandern)
	var keep := PackedVector2Array()
	for attempt in 300:
		var tangents := _tangent_lengths(poly)
		var tightest := -1
		var tightest_radius := INF
		var candidate := -1
		var candidate_radius := curve_radius
		for c in range(1, poly.size() - 1):
			var half := _corner_angle(poly, c) * 0.5
			if half < 0.002:
				continue
			var radius := tangents[c] / tan(half)
			if radius < tightest_radius:
				tightest_radius = radius
				tightest = c
			if radius < candidate_radius and not _is_kept(keep, poly[c]):
				candidate_radius = radius
				candidate = c
		if tightest_radius < min_curve_radius:
			poly = _merge_corner(poly, tightest, INF)
			if poly.size() < 2:
				return false
		elif candidate != -1:
			var merged := _merge_corner(poly, candidate, 15.0)
			if merged.size() < 2:
				keep.append(poly[candidate])
			else:
				poly = merged
		else:
			_sample_curves(poly, tangents)
			return true
	return false


func _is_kept(keep: PackedVector2Array, p: Vector2) -> bool:
	for k in keep:
		if k.distance_squared_to(p) < 0.01:
			return true
	return false


## Knickwinkel (ohne Vorzeichen) am Punkt c des Polygonzugs
func _corner_angle(poly: PackedVector2Array, c: int) -> float:
	return absf((poly[c] - poly[c - 1]).angle_to(poly[c + 1] - poly[c]))


## Platz auf der Geraden j (von Punkt j zu j+1) für die Bögen an ihren Enden
func _room(poly: PackedVector2Array, j: int) -> float:
	var room := poly[j].distance_to(poly[j + 1])
	if j == 0:
		room -= END_STRAIGHT
	if j == poly.size() - 2:
		room -= END_STRAIGHT
	return maxf(room, 0.0)


## Tangentenlänge jedes Bogens: so weit vor und nach dem Knick beginnt bzw. endet er.
## Radius r und Knickwinkel w hängen so zusammen: Tangentenlänge = r * tan(w / 2).
func _tangent_lengths(poly: PackedVector2Array) -> PackedFloat32Array:
	var count := poly.size()
	var want := PackedFloat32Array()
	want.resize(count)
	for c in range(1, count - 1):
		var angle := _corner_angle(poly, c)
		# Kleine Knicke bekommen größere Radien, solange der Bogen höchstens 8 m von der Ecke
		# abweicht. So entstehen lange, weite Bögen statt kurzer Knicke.
		var bulge := 1.0 / cos(angle * 0.5) - 1.0
		var radius := clampf(8.0 / maxf(bulge, 0.00001), curve_radius, 500.0)
		want[c] = radius * tan(angle * 0.5)
	# Jede Gerade wird im Verhältnis der Wünsche zwischen ihren beiden Bögen aufgeteilt ...
	var result := PackedFloat32Array()
	result.resize(count)
	for c in range(1, count - 1):
		var share_in := _room(poly, c - 1) * want[c] / maxf(want[c - 1] + want[c], 0.0001)
		var share_out := _room(poly, c) * want[c] / maxf(want[c] + want[c + 1], 0.0001)
		result[c] = minf(want[c], minf(share_in, share_out))
	# ... und was ein Nachbar nicht braucht, darf der andere nutzen
	for c in range(1, count - 1):
		var free_in := _room(poly, c - 1) - result[c - 1]
		var free_out := _room(poly, c) - result[c + 1]
		result[c] = maxf(minf(want[c], minf(free_in, free_out)), 0.0)
	return result


## Den Knick c mit einem Nachbarn zusammenfassen (über die kürzere Gerade hinweg).
## Liegt diese Gerade an einem Ort, wird der Knick einfach entfernt.
## Verschiebt sich der Weg dabei um mehr als max_shift Meter, gibt es kein Ergebnis (leer).
## Die Enden der Kreuzungszufahrten (Punkt 1 und vorletzter) bleiben dabei immer, wo sie sind.
func _merge_corner(poly: PackedVector2Array, c: int, max_shift: float) -> PackedVector2Array:
	var last := poly.size() - 1
	var options: Array[int] = [c - 1, c]
	if _room(poly, c) < _room(poly, c - 1):
		options = [c, c - 1]
	for leg in options:
		var result := poly.duplicate()
		if leg == 0 or leg == last - 1:
			if c == 1 or c == last - 1:
				continue
			if _distance_to_line(poly[c], poly[c - 1], poly[c + 1]) > max_shift:
				continue
			result.remove_at(c)
			return result
		# Die beiden Knicke an den Enden der Geraden „leg“
		var a := leg
		var b := leg + 1
		var turn_a := (poly[a] - poly[a - 1]).angle_to(poly[a + 1] - poly[a])
		var turn_b := (poly[b] - poly[b - 1]).angle_to(poly[b + 1] - poly[b])
		var shift := 0.0
		if a == 1 or b == last - 1:
			# Ein Ende einer Kreuzungszufahrt: das bleibt, der andere Knick fällt weg
			if a == 1 and b == last - 1:
				continue
			var gone := b if a == 1 else a
			shift = _distance_to_line(poly[gone], poly[gone - 1], poly[gone + 1])
			if shift > max_shift:
				continue
			result.remove_at(gone)
			return result
		if signf(turn_a) != signf(turn_b):
			# S-Kurve: beide Knicke durch einen in der Mitte ersetzen (die S-Kurve wird gerader)
			result[a] = (poly[a] + poly[b]) * 0.5
			shift = maxf(_distance_to_line(poly[a], poly[a - 1], result[a]),
				_distance_to_line(poly[b], result[a], poly[b + 1]))
		elif absf(turn_a + turn_b) < deg_to_rad(150.0):
			# Gleiche Richtung: neuer Knick dort, wo sich die Geraden davor und danach schneiden
			var d1 := (poly[a] - poly[a - 1]).normalized()
			var d2 := (poly[b + 1] - poly[b]).normalized()
			var s := (poly[b] - poly[a]).cross(d2) / d1.cross(d2)
			result[a] = poly[a] + d1 * s
			shift = _distance_to_line(result[a], poly[a], poly[b])
		else:
			# Fast eine Kehrtwende: daraus lässt sich kein einzelner Knick machen
			continue
		if shift > max_shift:
			continue
		result.remove_at(b)
		return result
	return PackedVector2Array()


## Geraden und Bögen abtasten (Bögen alle ~1 m), dann alle POINT_SPACING Meter einen Punkt
func _sample_curves(poly: PackedVector2Array, tangents: PackedFloat32Array) -> void:
	var dense := PackedVector2Array([poly[0]])
	var dense_curvature := PackedFloat32Array([0.0])
	for c in range(1, poly.size() - 1):
		var d_in := (poly[c] - poly[c - 1]).normalized()
		var turn := d_in.angle_to(poly[c + 1] - poly[c])
		if tangents[c] < 0.01 or absf(turn) < 0.002:
			dense.append(poly[c])
			dense_curvature.append(0.0)
			continue
		var radius := tangents[c] / tan(absf(turn) * 0.5)
		var arc_start := poly[c] - d_in * tangents[c]
		# Der Kreismittelpunkt liegt auf der Innenseite der Kurve
		var center := arc_start + d_in.rotated(signf(turn) * PI * 0.5) * radius
		# Im Spiel zeigt „links“ in die Richtung, in die sich der Weg bei turn < 0 dreht
		var k := -signf(turn) / radius
		dense.append(arc_start)
		dense_curvature.append(0.0)
		var steps := maxi(ceili(absf(turn) * radius), 1)
		for i in range(1, steps + 1):
			dense.append(center + (arc_start - center).rotated(turn * i / steps))
			dense_curvature.append(k)
	dense.append(poly[poly.size() - 1])
	dense_curvature.append(0.0)
	_resample(dense, dense_curvature)


## Gleichmäßig alle POINT_SPACING Meter einen Punkt setzen. Die Krümmung eines Stücks
## steht beim Punkt an seinem Ende.
func _resample(path: PackedVector2Array, path_curvature: PackedFloat32Array) -> void:
	points = PackedVector3Array()
	curvature = PackedFloat32Array()
	var carry := 0.0
	points.append(Vector3(path[0].x, 0.0, path[0].y))
	curvature.append(0.0)
	for i in path.size() - 1:
		var a := path[i]
		var b := path[i + 1]
		var seg_len := a.distance_to(b)
		var t := POINT_SPACING - carry
		while t <= seg_len:
			var p := a.lerp(b, t / seg_len)
			points.append(Vector3(p.x, 0.0, p.y))
			curvature.append(path_curvature[i + 1])
			t += POINT_SPACING
		carry = seg_len - (t - POINT_SPACING)
	var last := path[path.size() - 1]
	if Vector2(points[points.size() - 1].x, points[points.size() - 1].z).distance_to(last) > 0.5:
		points.append(Vector3(last.x, 0.0, last.y))
		curvature.append(0.0)


## Querneigung: in Kurven neigt sich die Fahrbahn nach innen (enge Kurven max_bank,
## weite weniger). Sie baut sich über etwa 50 m sanft auf und ab, an den Orten ist sie 0.
func _make_bank() -> void:
	var n := points.size()
	var raw := PackedFloat32Array()
	raw.resize(n)
	for i in range(10, n - 10):
		raw[i] = max_bank * clampf(curvature[i] * curve_radius, -1.0, 1.0)
	bank = PackedFloat32Array()
	bank.resize(n)
	var window := 6
	for i in n:
		var total := 0.0
		for j in range(i - window, i + window + 1):
			total += raw[clampi(j, 0, n - 1)]
		bank[i] = total / (2 * window + 1)


# ---------------------------------------------------------------------------
# 3. Höhenprofil
# ---------------------------------------------------------------------------

func _make_profile(allow_tunnels: bool) -> bool:
	var n := points.size()
	var lakes: Array = world_gen.lakes_near(_points_rect())
	ground = PackedFloat32Array()
	ground.resize(n)
	# Wunschhöhe: das Gelände; in der Tunnel-Variante in Bergen abgeschnitten (wie bei der Wegsuche)
	var wish := PackedFloat32Array()
	wish.resize(n)
	for i in n:
		ground[i] = world_gen.terrain_height(points[i].x, points[i].z, lakes)
		wish[i] = ground[i]
		if allow_tunnels and not _ref_grid.is_empty():
			var cell := _grid_index(Vector2(points[i].x, points[i].z), _grid_origin, _grid_u, _grid_v, _grid_nu, _grid_nv)
			wish[i] = minf(ground[i], _ref_grid[cell] + TUNNEL_REF_ALLOW)
	# Gleitender Mittelwert über ±32 m: kleine Buckel verschwinden
	var smooth := PackedFloat32Array()
	smooth.resize(n)
	var window := 8
	for i in n:
		var total := 0.0
		var count := 0
		for j in range(maxi(i - window, 0), mini(i + window, n - 1) + 1):
			total += wish[j]
			count += 1
		smooth[i] = total / count
	# Über Flüsse hinweg mindestens ein paar Meter über dem Wasser bleiben
	var over_water := PackedByteArray()
	over_water.resize(n)
	for i in n:
		var water := world_gen.water_level_at(points[i].x, points[i].z, lakes)
		if water > WorldGen.NO_WATER:
			smooth[i] = maxf(smooth[i], water + 4.5)
			over_water[i] = 1
	# An den Orten liegt die Straße flach auf Ortshöhe (dort ist die Kreuzung)
	for i in n:
		if i < JUNCTION_FLAT:
			smooth[i] = start.y
		elif i >= n - JUNCTION_FLAT:
			smooth[i] = end.y
	# Steigung begrenzen: vorwärts und rückwärts durchgehen
	var max_step := max_grade * POINT_SPACING
	for i in range(JUNCTION_FLAT, n - JUNCTION_FLAT):
		smooth[i] = clampf(smooth[i], smooth[i - 1] - max_step, smooth[i - 1] + max_step)
	for i in range(n - JUNCTION_FLAT - 1, JUNCTION_FLAT - 1, -1):
		smooth[i] = clampf(smooth[i], smooth[i + 1] - max_step, smooth[i + 1] + max_step)
	# Passt es trotzdem nicht (Höhenunterschied zu groß für die Länge), keine Straße
	for i in range(1, n):
		if absf(smooth[i] - smooth[i - 1]) > max_step + 0.01:
			return false
	# Tief unter dem Gelände: Tunnel statt Einschnitt
	if not _find_tunnels(smooth, over_water):
		return false
	# Wenn die Straße tiefe Einschnitte (außerhalb von Tunneln) oder riesige Brücken bräuchte,
	# lieber keine Straße
	for i in n:
		if (tunnel[i] == 0 and ground[i] - smooth[i] > MAX_CUT) or smooth[i] - ground[i] > MAX_FILL:
			return false
		points[i].y = smooth[i]
	# Brücken: über Wasser und wo die Straße hoch über dem Gelände liegt, plus 12 m Zugabe.
	# Nicht direkt an den Orten (dort sind Kreuzungen) und nicht im Tunnel.
	bridge = PackedByteArray()
	bridge.resize(n)
	var keep_clear := JUNCTION_FLAT + 2
	for i in n:
		if over_water[i] == 1 or smooth[i] - ground[i] > BRIDGE_HEIGHT:
			for j in range(maxi(i - 3, keep_clear), mini(i + 4, n - keep_clear)):
				if tunnel[j] == 0:
					bridge[j] = 1
	bounds = _points_rect().grow(road_width * 0.5 + shoulder_width + MAX_BANK)
	return true


## Tunnel suchen: Kern dort, wo die Fahrbahn mehr als TUNNEL_DEPTH unter dem Gelände liegt,
## nach beiden Seiten verlängert, solange es mehr als PORTAL_DEPTH sind (dort sind die Portale).
## Nahe beieinander liegende Tunnel werden einer. Im Tunnel wird die Fahrbahn gerade
## (gleichmäßige Steigung zwischen den Portalen), wenn sie dabei unter dem Gelände bleibt.
## false = ein Tunnel wäre länger als MAX_TUNNEL_LENGTH.
func _find_tunnels(smooth: PackedFloat32Array, over_water: PackedByteArray) -> bool:
	var n := points.size()
	tunnel = PackedByteArray()
	tunnel.resize(n)
	tunnel_ranges = []
	var keep_clear := JUNCTION_FLAT + 2
	var i := 0
	while i < n:
		if ground[i] - smooth[i] <= TUNNEL_DEPTH or over_water[i] == 1:
			i += 1
			continue
		var a := i
		while a > 0 and ground[a - 1] - smooth[a - 1] > PORTAL_DEPTH and over_water[a - 1] == 0:
			a -= 1
		var b := i
		while b < n - 1 and ground[b + 1] - smooth[b + 1] > PORTAL_DEPTH and over_water[b + 1] == 0:
			b += 1
		# Nicht bis in die Kreuzung: dort davor ein (tiefer) Einschnitt, falls er nicht zu tief ist
		var next := b + 1
		a = maxi(a, keep_clear)
		b = mini(b, n - 1 - keep_clear)
		for j in range(a, b + 1):
			tunnel[j] = 1
		i = next
	# Kurze Lücken (bis 32 m) zwischen zwei Tunneln schließen
	var last_end := -100
	for j in n:
		if tunnel[j] == 1:
			if j - last_end > 1 and j - last_end <= 9:
				for k in range(last_end + 1, j):
					tunnel[k] = 1
			last_end = j
	# Tunnel einsammeln und gerade machen
	var j := 0
	while j < n:
		if tunnel[j] == 0:
			j += 1
			continue
		var a := j
		while j < n and tunnel[j] == 1:
			j += 1
		var b := j - 1
		if (b - a) * POINT_SPACING > MAX_TUNNEL_LENGTH:
			return false
		tunnel_ranges.append(Vector2i(a, b))
		var straight := PackedFloat32Array()
		straight.resize(b - a + 1)
		var fits := true
		for k in range(a, b + 1):
			straight[k - a] = lerpf(smooth[a], smooth[b], float(k - a) / maxf(b - a, 1))
			if ground[k] - straight[k - a] < PORTAL_DEPTH * 0.6:
				fits = false
		if fits:
			for k in range(a, b + 1):
				smooth[k] = straight[k - a]
	return true


func _points_rect() -> Rect2:
	var rect := Rect2(points[0].x, points[0].z, 0.0, 0.0)
	for p in points:
		rect = rect.expand(Vector2(p.x, p.z))
	return rect


# ---------------------------------------------------------------------------
# 4. Mesh: Querschnitt aus 6 Punkten (Schürze, Bankett, Fahrbahn, Fahrbahn, Bankett, Schürze)
# ---------------------------------------------------------------------------

## Mesh-Daten von Punkt first bis last (dort beginnen bzw. enden die Kreuzungen).
## Läuft im Hintergrund.
func build_mesh(first: int, last: int) -> void:
	var n := points.size()
	origin = points[n / 2]
	var half := road_width * 0.5
	var outer := half + shoulder_width
	# Seitlicher Abstand (positiv = links), Höhenversatz und u-Koordinate jedes Querschnittspunkts
	# Der äußerste Punkt liegt schräg tiefer: ein Bankett, das in die Böschung übergeht
	var verge := outer + VERGE_WIDTH
	var side := [verge, outer, half, -half, -outer, -verge]
	var drop := [VERGE_DROP, SHOULDER_DROP, 0.0, 0.0, SHOULDER_DROP, VERGE_DROP]
	var u_coord := [-(verge - half) / road_width, -shoulder_width / road_width, 0.0, 1.0,
		1.0 + shoulder_width / road_width, 1.0 + (verge - half) / road_width]
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var lefts := PackedVector3Array()
	lefts.resize(n)
	for i in n:
		lefts[i] = Vector3.UP.cross(direction_at(i)).normalized()
	# Wie weit ein Punkt überdacht ist (Tunnel): 0 = im Freien, 1 = ab ~8 m hinter dem Portal.
	# Steht für den Shader in UV2.y (kein Regen, kein Schnee).
	var covered := PackedFloat32Array()
	covered.resize(n)
	for r in tunnel_ranges:
		for k in range(r.x, r.y + 1):
			covered[k] = clampf((mini(k - r.x, r.y - k) * POINT_SPACING + 2.0) / 10.0, 0.0, 1.0)
	var tube_half := tube_half_width()
	var distance := 0.0
	for i in range(first, last + 1):
		var left := lefts[i]
		# Querneigung: die Fahrbahn kippt zur Kurveninnenseite, die Normale mit ihr
		var up := (Vector3.UP + left * bank[i]).normalized()
		if i > first:
			distance += points[i].distance_to(points[i - 1])
		for k in 6:
			var offset: float = side[k]
			var height: float = drop[k]
			# Auf Brücken gibt es kein schräges Bankett, dort ist die Fahrbahnplatte
			if bridge[i] == 1 and (k == 0 or k == 5):
				offset = outer if k == 0 else -outer
				height = -0.06
			# Im Tunnel reicht die Fahrbahn bis an die Wand
			if tunnel[i] == 1 and (k == 0 or k == 5):
				offset = tube_half if k == 0 else -tube_half
				height = -0.06
			verts.append(side_point(i, left, offset, height) - origin)
			var normal: Vector3 = up
			if k == 0:
				normal = (up + left * 0.6).normalized()
			elif k == 5:
				normal = (up - left * 0.6).normalized()
			normals.append(normal)
			# Tangente zeigt nach rechts (Richtung wachsender u-Koordinate)
			var right := -left
			tangents.append_array([right.x, right.y, right.z, 1.0])
			uvs.append(Vector2(u_coord[k], distance))
			# UV2.x = 0: normale Straße (Kreuzungsflächen haben hier 1), UV2.y = überdacht
			uv2s.append(Vector2(0.0, covered[i]))
	var indices := PackedInt32Array()
	collision_faces = PackedVector3Array()
	for i in last - first:
		for k in 5:
			var a := i * 6 + k
			var b := (i + 1) * 6 + k
			# Reihenfolge so, dass die Oberseite nach oben zeigt
			indices.append_array([a, b, a + 1, a + 1, b, b + 1])
			if k >= 1 and k <= 3:
				collision_faces.append_array([verts[a] + origin, verts[b] + origin, verts[a + 1] + origin,
					verts[a + 1] + origin, verts[b] + origin, verts[b + 1] + origin])
	mesh_arrays.resize(Mesh.ARRAY_MAX)
	mesh_arrays[Mesh.ARRAY_VERTEX] = verts
	mesh_arrays[Mesh.ARRAY_NORMAL] = normals
	mesh_arrays[Mesh.ARRAY_TANGENT] = tangents
	mesh_arrays[Mesh.ARRAY_TEX_UV] = uvs
	mesh_arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	mesh_arrays[Mesh.ARRAY_INDEX] = indices
	_build_bridges(lefts)
	bridge_arrays = _take_quads()
	_build_rails(first, last, lefts)
	rail_arrays = _take_quads()
	tunnel_lights = PackedVector3Array()
	for r in tunnel_ranges:
		_build_tube(r, lefts)
		_build_portal(r.x, -direction_at(r.x), lefts[r.x])
		_build_portal(r.y, direction_at(r.y), lefts[r.y])
	tunnel_arrays = _take_quads()
	for r in tunnel_ranges:
		_build_lamps(r, lefts)
	lamp_arrays = _take_quads()


# ---------------------------------------------------------------------------
# 5. Brücken: Fahrbahnplatte, Brüstungen und Pfeiler aus Beton
# ---------------------------------------------------------------------------

const DECK_THICKNESS: float = 1.4
const WALL_HEIGHT: float = 0.9
const WALL_THICKNESS: float = 0.3
## Alle wie vielen Punkte (je 4 m) ein Pfeiler steht
const PILLAR_EVERY: int = 6

var _b_verts := PackedVector3Array()
var _b_normals := PackedVector3Array()
var _b_indices := PackedInt32Array()
## Punktfarben (nur Tunnel; leer = keine)
var _b_colors := PackedColorArray()


func _build_bridges(lefts: PackedVector3Array) -> void:
	var n := points.size()
	var outer := road_width * 0.5 + shoulder_width
	var down := Vector3(0.0, -DECK_THICKNESS, 0.0)
	var top := Vector3(0.0, -0.06, 0.0)
	var wall := Vector3(0.0, WALL_HEIGHT, 0.0)
	var i := 0
	while i < n:
		if bridge[i] == 0:
			i += 1
			continue
		var j := i
		while j < n and bridge[j] == 1:
			j += 1
		# Ein Brückenstück reicht von Punkt i bis j-1, einen Punkt Überlappung auf jeder Seite
		for k in range(maxi(i - 1, 0), mini(j, n - 1)):
			for sgn: float in [1.0, -1.0]:
				var normal := ((lefts[k] + lefts[k + 1]) * 0.5 * sgn).normalized()
				var o0 := side_point(k, lefts[k], outer * sgn, 0.0) - origin
				var o1 := side_point(k + 1, lefts[k + 1], outer * sgn, 0.0) - origin
				var w0 := side_point(k, lefts[k], (outer - WALL_THICKNESS) * sgn, 0.0) - origin
				var w1 := side_point(k + 1, lefts[k + 1], (outer - WALL_THICKNESS) * sgn, 0.0) - origin
				# Außenseite: Platte und Brüstung in einem Stück
				_quad(o0 + down, o1 + down, o1 + wall, o0 + wall, normal)
				# Oberkante und Innenseite der Brüstung
				_quad(o0 + wall, o1 + wall, w1 + wall, w0 + wall, Vector3.UP)
				_quad(w0 + top, w1 + top, w1 + wall, w0 + wall, -normal)
				# Die Innenseite hält das Auto auf der Brücke
				collision_faces.append_array([w0 + top + origin, w1 + top + origin, w1 + wall + origin,
					w0 + top + origin, w1 + wall + origin, w0 + wall + origin])
			# Unterseite der Platte
			var a0 := side_point(k, lefts[k], outer, 0.0) - origin + down
			var a1 := side_point(k + 1, lefts[k + 1], outer, 0.0) - origin + down
			var b0 := side_point(k, lefts[k], -outer, 0.0) - origin + down
			var b1 := side_point(k + 1, lefts[k + 1], -outer, 0.0) - origin + down
			_quad(a0, a1, b1, b0, Vector3.DOWN)
		# Pfeiler bis in den Boden
		for k in range(i + 2, j - 2, PILLAR_EVERY):
			var bottom := ground[k] - 3.0
			if points[k].y - DECK_THICKNESS - bottom > 1.5:
				_pillar(points[k] - origin, bottom - origin.y)
		i = j


## Die gesammelten Vierecke als Mesh-Daten abgeben (leer = keine) und neu anfangen
func _take_quads() -> Array:
	var result: Array = []
	if not _b_indices.is_empty():
		result.resize(Mesh.ARRAY_MAX)
		result[Mesh.ARRAY_VERTEX] = _b_verts
		result[Mesh.ARRAY_NORMAL] = _b_normals
		result[Mesh.ARRAY_INDEX] = _b_indices
		if _b_colors.size() == _b_verts.size():
			result[Mesh.ARRAY_COLOR] = _b_colors
	_b_verts = PackedVector3Array()
	_b_normals = PackedVector3Array()
	_b_indices = PackedInt32Array()
	_b_colors = PackedColorArray()
	return result


# ---------------------------------------------------------------------------
# 6. Leitplanken: an hohen Dämmen und außen in engen Kurven (Brücken haben Brüstungen)
# ---------------------------------------------------------------------------

## Leitplanke, wo das Gelände 14 m neben der Straße so viele Meter tiefer liegt ...
const RAIL_DROP: float = 4.0
## ... und außen in Kurven, die enger sind als dieser Radius
const RAIL_RADIUS: float = 45.0
const RAIL_HEIGHT: float = 0.75
## Höhe des Stahlbands
const RAIL_BAND: float = 0.32


func _build_rails(first: int, last: int, lefts: PackedVector3Array) -> void:
	var n := points.size()
	var lakes: Array = world_gen.lakes_near(_points_rect().grow(20.0))
	# Auf dem Bankett, kurz vor dem Rand
	var offset := road_width * 0.5 + shoulder_width - 0.4
	for side: float in [1.0, -1.0]:
		# 1. Wo braucht diese Seite eine Leitplanke?
		var need := PackedByteArray()
		need.resize(n)
		for i in range(first, last + 1):
			if bridge[i] == 1 or tunnel[i] == 1:
				continue
			# Diese Seite ist außen, wenn die Kurve zur anderen Seite geht
			var outside := curvature[i] * side < -1.0 / RAIL_RADIUS
			var beside := points[i] + lefts[i] * side * 14.0
			var drop := points[i].y - world_gen.terrain_height(beside.x, beside.z, lakes)
			if outside or drop > RAIL_DROP:
				need[i] = 1
		_close_gaps(need, 4)
		_drop_short(need, 6)
		# 2. Pfosten an jedem Punkt, dazwischen das Stahlband. An den Enden taucht es ab.
		for i in range(first, last + 1):
			if need[i] == 0:
				continue
			var run_end := need[i - 1] == 0 or need[i + 1] == 0
			var post := side_point(i, lefts[i], side * (offset + 0.12), 0.0) - origin
			_post(post, lefts[i] * side, RAIL_HEIGHT - 0.08)
			if i == last or need[i + 1] == 0:
				continue
			var top0 := 0.3 if run_end else RAIL_HEIGHT
			var top1 := 0.3 if need[i + 2] == 0 else RAIL_HEIGHT
			var a0 := side_point(i, lefts[i], side * offset, maxf(top0 - RAIL_BAND, 0.05))
			var a1 := side_point(i + 1, lefts[i + 1], side * offset, maxf(top1 - RAIL_BAND, 0.05))
			var b0 := side_point(i, lefts[i], side * offset, top0)
			var b1 := side_point(i + 1, lefts[i + 1], side * offset, top1)
			_quad(a0 - origin, a1 - origin, b1 - origin, b0 - origin, -lefts[i] * side)
			# Die Leitplanke hält das Auto auf der Straße (vom Boden bis zur Oberkante)
			var g0 := side_point(i, lefts[i], side * offset, 0.0)
			var g1 := side_point(i + 1, lefts[i + 1], side * offset, 0.0)
			collision_faces.append_array([g0, g1, b1, g0, b1, b0])


# ---------------------------------------------------------------------------
# 7. Tunnel: Röhre, Portale, Deckenlampen
# ---------------------------------------------------------------------------

const WALL_LIGHT := Color(0.74, 0.74, 0.7)
const WALL_STRIPE := Color(0.9, 0.42, 0.08)
const WALL_DARK := Color(0.3, 0.3, 0.31)
const PORTAL_COLOR := Color(0.6, 0.59, 0.55)
const COLLAR_COLOR := Color(0.5, 0.5, 0.47)
## Portal: Rand um die Öffnung (Breite, wie weit er vorsteht) und Stirnwand (seitlich, oben)
const COLLAR_WIDTH: float = 1.3
const COLLAR_DEPTH: float = 1.0
const HEADWALL_SIDE: float = 9.0
const HEADWALL_TOP: float = 4.5


## Halbe Breite der Tunnelröhre (Fahrbahn, Bankett und etwas Abstand)
func tube_half_width() -> float:
	return road_width * 0.5 + shoulder_width + TUBE_CLEARANCE


## Form der Röhre im Querschnitt: [seitlicher Abstand und Höhe, Normale nach innen] von der
## linken Wand unten über den Scheitel bis zur rechten Wand unten (positiv = links)
func _tube_shape() -> Array:
	var w := tube_half_width()
	var rise := TUBE_APEX - TUBE_WALL
	var shape: Array = [[Vector2(w, -0.1), Vector2(-1.0, 0.0)]]
	var steps := 12
	for k in steps + 1:
		var a := PI * k / steps
		var normal := -Vector2(cos(a) * rise, sin(a) * w).normalized()
		shape.append([Vector2(w * cos(a), TUBE_WALL + rise * sin(a)), normal])
	shape.append([Vector2(-w, -0.1), Vector2(1.0, 0.0)])
	return shape


## Querschnitt mit Farben: unten helle Verkleidung, ein farbiger Streifen, darüber Beton.
## Doppelte Punkte an den Farbgrenzen, damit die Grenzen scharf sind.
func _tube_profile() -> Array:
	var w := tube_half_width()
	var result: Array = []  # [Position, Normale, Farbe]
	for sgn: float in [1.0, -1.0]:
		var wall: Array = [[-0.1, WALL_LIGHT], [3.0, WALL_LIGHT], [3.0, WALL_STRIPE], [3.25, WALL_STRIPE],
			[3.25, WALL_DARK], [TUBE_WALL, WALL_DARK]]
		if sgn < 0.0:
			wall.reverse()
		var side: Array = []
		for entry: Array in wall:
			side.append([Vector2(w * sgn, entry[0]), Vector2(-sgn, 0.0), entry[1]])
		if sgn > 0.0:
			result.append_array(side)
			# Gewölbe
			var shape := _tube_shape()
			for k in range(2, shape.size() - 2):
				result.append([shape[k][0], shape[k][1], WALL_DARK])
		else:
			result.append_array(side)
	return result


## Röhre von Portal zu Portal, mit Kollision für die Wände
func _build_tube(r: Vector2i, lefts: PackedVector3Array) -> void:
	var profile := _tube_profile()
	var count := profile.size()
	var base := _b_verts.size()
	for i in range(r.x, r.y + 1):
		var left := lefts[i]
		for entry: Array in profile:
			var pos: Vector2 = entry[0]
			var normal: Vector2 = entry[1]
			_b_verts.append(side_point(i, left, pos.x, pos.y) - origin)
			_b_normals.append((left * normal.x + Vector3.UP * normal.y).normalized())
			_b_colors.append(entry[2])
	for i in r.y - r.x:
		for k in count - 1:
			var a := base + i * count + k
			var b := a + count
			_add_quad_indices(a, b, b + 1, a + 1, _b_normals[a])
	# Kollision: beide Wände bis 2,5 m Höhe
	var w := tube_half_width()
	for i in range(r.x, r.y):
		for sgn: float in [1.0, -1.0]:
			var a0 := side_point(i, lefts[i], w * sgn, -0.1)
			var a1 := side_point(i + 1, lefts[i + 1], w * sgn, -0.1)
			var b0 := side_point(i, lefts[i], w * sgn, 2.5)
			var b1 := side_point(i + 1, lefts[i + 1], w * sgn, 2.5)
			collision_faces.append_array([a0, a1, b1, a0, b1, b0])


## Portal am Punkt p: ein Betonkragen um die Öffnung und eine Stirnwand, die den Hang abfängt.
## outward zeigt aus dem Tunnel hinaus.
func _build_portal(p: int, outward: Vector3, left: Vector3) -> void:
	var shape := _tube_shape()
	var w := tube_half_width()
	var outer_w := w + COLLAR_WIDTH
	var rect_w := w + HEADWALL_SIDE
	var rect_h := TUBE_APEX + HEADWALL_TOP
	var center := points[p] - origin
	# Punkt im Querschnitt (seitlich, Höhe) in einer Ebene „depth“ Meter vor dem Portal
	var at := func(q: Vector2, depth: float) -> Vector3:
		return center + left * q.x + Vector3.UP * q.y + outward * depth
	var inner: Array[Vector2] = []
	var outer: Array[Vector2] = []
	for entry: Array in shape:
		var q: Vector2 = entry[0]
		inner.append(q)
		outer.append(q - (entry[1] as Vector2) * COLLAR_WIDTH)
	var wall_plane := 0.15
	for k in inner.size() - 1:
		var n_in := (shape[k][1] as Vector2)
		var normal_in := (left * n_in.x + Vector3.UP * n_in.y).normalized()
		# Vorderseite des Kragens
		_tquad(at.call(inner[k], COLLAR_DEPTH), at.call(inner[k + 1], COLLAR_DEPTH),
			at.call(outer[k + 1], COLLAR_DEPTH), at.call(outer[k], COLLAR_DEPTH), outward, COLLAR_COLOR)
		# Innenseite (Leibung) und Außenseite des Kragens
		_tquad(at.call(inner[k], 0.0), at.call(inner[k + 1], 0.0),
			at.call(inner[k + 1], COLLAR_DEPTH), at.call(inner[k], COLLAR_DEPTH), normal_in, COLLAR_COLOR)
		_tquad(at.call(outer[k], wall_plane), at.call(outer[k + 1], wall_plane),
			at.call(outer[k + 1], COLLAR_DEPTH), at.call(outer[k], COLLAR_DEPTH), -normal_in, COLLAR_COLOR)
		# Stirnwand: vom Kragen nach außen bis zum Rechteck
		var r0 := _headwall_point(outer[k], outer_w, rect_w, rect_h)
		var r1 := _headwall_point(outer[k + 1], outer_w, rect_w, rect_h)
		_tquad(at.call(outer[k], wall_plane), at.call(outer[k + 1], wall_plane),
			at.call(r1, wall_plane), at.call(r0, wall_plane), outward, PORTAL_COLOR)
		# Ecke oben links/rechts, wo die Wand ins Gewölbe übergeht
		if r0.y < rect_h and r1.y >= rect_h:
			_tquad(at.call(r0, wall_plane), at.call(Vector2(r0.x, rect_h), wall_plane),
				at.call(r1, wall_plane), at.call(r1, wall_plane), outward, PORTAL_COLOR)
		elif r0.y >= rect_h and r1.y < rect_h:
			_tquad(at.call(r0, wall_plane), at.call(Vector2(r1.x, rect_h), wall_plane),
				at.call(r1, wall_plane), at.call(r1, wall_plane), outward, PORTAL_COLOR)
	# Unterhalb der Fahrbahn (bis ins Gelände) und die Ränder der Stirnwand
	for sgn: float in [1.0, -1.0]:
		var a := Vector2(outer_w * sgn, -0.1)
		var b := Vector2(rect_w * sgn, -0.1)
		_tquad(at.call(a, wall_plane), at.call(b, wall_plane), at.call(Vector2(b.x, -2.0), wall_plane),
			at.call(Vector2(a.x, -2.0), wall_plane), outward, PORTAL_COLOR)
		var side_normal := left * sgn
		_tquad(at.call(Vector2(rect_w * sgn, -2.0), wall_plane), at.call(Vector2(rect_w * sgn, rect_h), wall_plane),
			at.call(Vector2(rect_w * sgn, rect_h), -1.5), at.call(Vector2(rect_w * sgn, -2.0), -1.5), side_normal, PORTAL_COLOR)
	_tquad(at.call(Vector2(rect_w, rect_h), wall_plane), at.call(Vector2(-rect_w, rect_h), wall_plane),
		at.call(Vector2(-rect_w, rect_h), -1.5), at.call(Vector2(rect_w, rect_h), -1.5), Vector3.UP, PORTAL_COLOR)
	# Kollision: Stirnwand links und rechts der Öffnung (so fährt niemand in den Hang)
	for sgn: float in [1.0, -1.0]:
		var c0: Vector3 = at.call(Vector2(outer_w * sgn, -0.5), wall_plane) + origin
		var c1: Vector3 = at.call(Vector2(rect_w * sgn, -0.5), wall_plane) + origin
		var c2: Vector3 = at.call(Vector2(rect_w * sgn, 4.0), wall_plane) + origin
		var c3: Vector3 = at.call(Vector2(outer_w * sgn, 4.0), wall_plane) + origin
		collision_faces.append_array([c0, c1, c2, c0, c2, c3])


## Wohin ein Punkt des Kragen-Umrisses auf dem Rand der Stirnwand gehört: Wandteile seitlich
## nach außen, Gewölbeteile senkrecht nach oben (gestreckt auf die Breite der Stirnwand)
func _headwall_point(q: Vector2, outer_w: float, rect_w: float, rect_h: float) -> Vector2:
	if q.y <= TUBE_WALL + 0.01:
		return Vector2(signf(q.x) * rect_w, q.y)
	return Vector2(q.x / outer_w * rect_w, rect_h)


## Leuchtende Lampen unter der Decke und die Stellen für echte Lichter
func _build_lamps(r: Vector2i, lefts: PackedVector3Array) -> void:
	for i in range(r.x + 1, r.y, LAMP_EVERY):
		var left := lefts[i]
		var forward := direction_at(i)
		var c := side_point(i, left, 0.0, TUBE_APEX - 0.12) - origin
		var along := forward * 0.9
		var across := left * 0.22
		_quad(c - along - across, c + along - across, c + along + across, c - along + across, Vector3.DOWN)
		if (i - r.x - 1) % LIGHT_EVERY == 0:
			tunnel_lights.append(c + origin + Vector3.DOWN * 0.6)


## Viereck mit Farbe (für den Tunnel)
func _tquad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, color: Color) -> void:
	var base := _b_verts.size()
	_b_verts.append_array([a, b, c, d])
	_b_normals.append_array([normal, normal, normal, normal])
	_b_colors.append_array([color, color, color, color])
	_add_quad_indices(base, base + 1, base + 2, base + 3, normal)


## Zwei Dreiecke für ein Viereck aus vorhandenen Punkten; die Vorderseite zeigt zu normal
func _add_quad_indices(a: int, b: int, c: int, d: int, normal: Vector3) -> void:
	if (_b_verts[c] - _b_verts[a]).cross(_b_verts[b] - _b_verts[a]).dot(normal) >= 0.0:
		_b_indices.append_array([a, b, c, a, c, d])
	else:
		_b_indices.append_array([a, c, b, a, d, c])


## Lücken bis max_gap Punkte zwischen zwei Leitplanken-Stücken schließen
func _close_gaps(need: PackedByteArray, max_gap: int) -> void:
	var last_on := -1
	for i in need.size():
		if need[i] == 1:
			if last_on >= 0 and i - last_on > 1 and i - last_on <= max_gap + 1:
				for j in range(last_on + 1, i):
					need[j] = 1
			last_on = i


## Stücke kürzer als min_length Punkte weglassen
func _drop_short(need: PackedByteArray, min_length: int) -> void:
	var i := 0
	while i < need.size():
		if need[i] == 0:
			i += 1
			continue
		var j := i
		while j < need.size() and need[j] == 1:
			j += 1
		if j - i < min_length:
			for k in range(i, j):
				need[k] = 0
		i = j


## Viereckiger Pfosten (0,12 m dick) von base aus nach oben
func _post(base: Vector3, out: Vector3, height: float) -> void:
	var w := 0.06
	var along := Vector3.UP.cross(out).normalized()
	var top := Vector3(0.0, height, 0.0)
	for normal: Vector3 in [out, -out, along, -along]:
		var t := Vector3.UP.cross(normal).normalized() * w
		var c := base + normal * w
		_quad(c - t, c + t, c + t + top, c - t + top, normal)


## Punkt neben der Mittellinie (offset positiv = links), mit Querneigung
func side_point(i: int, left: Vector3, offset: float, height: float) -> Vector3:
	return points[i] + left * offset + Vector3(0.0, height - bank[i] * offset, 0.0)


## Viereck mit vier Ecken in Reihenfolge; die Vorderseite zeigt in Richtung normal
func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	var base := _b_verts.size()
	_b_verts.append_array([a, b, c, d])
	_b_normals.append_array([normal, normal, normal, normal])
	if (c - a).cross(b - a).dot(normal) >= 0.0:
		_b_indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	else:
		_b_indices.append_array([base, base + 2, base + 1, base, base + 3, base + 2])


## Eckiger Pfeiler unter der Fahrbahnplatte
func _pillar(center: Vector3, bottom_y: float) -> void:
	var h := 0.8
	var y0 := bottom_y
	var y1 := center.y - DECK_THICKNESS
	for normal: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]:
		var t := Vector3(normal.z, 0.0, -normal.x)
		var c := center + normal * h
		_quad(Vector3(c.x - t.x * h, y0, c.z - t.z * h), Vector3(c.x + t.x * h, y0, c.z + t.z * h),
			Vector3(c.x + t.x * h, y1, c.z + t.z * h), Vector3(c.x - t.x * h, y1, c.z - t.z * h), normal)


## Kommt diese Straße einer anderen näher als distance (Mittellinien, waagerecht)?
## Rund um gemeinsame Orte zählt das nicht, dort ist die Kreuzung (clearance Meter).
func comes_close(other: RoadSegment, distance: float, clearance: float) -> bool:
	if not bounds.intersects(other.bounds):
		return false
	var shared: Array[Vector3] = []
	for a: Vector3 in [start, end]:
		for b: Vector3 in [other.start, other.end]:
			if a.distance_to(b) < 1.0:
				shared.append(a)
	# Eigene Punkte in ein Raster einsortieren (Zellgröße = distance)
	var grid := {}
	for i in points.size():
		var p := points[i]
		if _near_any(p, shared, clearance):
			continue
		var cell := Vector2i(floori(p.x / distance), floori(p.z / distance))
		if not grid.has(cell):
			grid[cell] = []
		grid[cell].append(i)
	var limit := distance * distance
	for q in other.points:
		if _near_any(q, shared, clearance):
			continue
		var cell := Vector2i(floori(q.x / distance), floori(q.z / distance))
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				for i: int in grid.get(cell + Vector2i(dx, dz), []):
					var p := points[i]
					if (p.x - q.x) * (p.x - q.x) + (p.z - q.z) * (p.z - q.z) < limit:
						return true
	return false


func _near_any(p: Vector3, centers: Array[Vector3], radius: float) -> bool:
	for c in centers:
		if Vector2(p.x - c.x, p.z - c.z).length() < radius:
			return true
	return false


## Fahrtrichtung am Punkt i (Mittel aus Richtung davor und danach)
func direction_at(i: int) -> Vector3:
	var a := points[maxi(i - 1, 0)]
	var b := points[mini(i + 1, points.size() - 1)]
	var d := b - a
	d.y = 0.0
	return d.normalized()


## Länge der Straße in Metern
func total_length() -> float:
	return (points.size() - 1) * POINT_SPACING
