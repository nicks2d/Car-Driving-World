class_name RoadSegment
extends RefCounted
## Ein Straßenabschnitt zwischen zwei Orten (Knoten). build() läuft im Hintergrund:
##  1. Wegsuche übers Gelände (A*): steil und Wasser sind teuer, so entstehen am Hang
##     von selbst Serpentinen und in der Ebene weite Bögen.
##  2. Weg glätten (Ecken abrunden) und alle 4 m einen Punkt setzen.
##  3. Höhenprofil glätten und die Steigung begrenzen (Gelände wird später angepasst).
##  4. Mesh-Daten für Fahrbahn und Kollision erzeugen.

# Rasterpunkte sind durchnummeriert (Zeile * Breite + Spalte). Die Ganzzahl-Divisionen
# in diesem Skript sind deshalb gewollt.
@warning_ignore_start("integer_division")

# --- Eingaben ---
var world_gen: WorldGen
var key: Vector3i
var start: Vector3
var end: Vector3
var road_width: float = 9.0
var shoulder_width: float = 1.5
var max_grade: float = 0.10
var grid_step: float = 18.0

# --- Ergebnisse ---
## Mittellinie, alle POINT_SPACING Meter ein Punkt, y = Höhe der Fahrbahn
var points: PackedVector3Array
## Geländehöhe unter jedem Punkt (vor der Anpassung)
var ground: PackedFloat32Array
## 1 = an diesem Punkt ist die Straße eine Brücke (über Wasser oder hoch über dem Gelände)
var bridge: PackedByteArray
## Rechteck (x/z), in dem die Straße das Gelände beeinflusst
var bounds: Rect2
## false = es gab keinen vernünftigen Weg, hier entsteht keine Straße
var valid: bool = false
var mesh_arrays: Array = []
## Mesh-Daten für Brücken (Beton): Fahrbahnplatte, Brüstungen, Pfeiler. Leer = keine Brücke.
var bridge_arrays: Array = []
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
## Ab so vielen Metern über dem Gelände wird statt eines Damms eine Brücke gebaut
const BRIDGE_HEIGHT: float = 7.0


func build() -> void:
	var path := _find_path()
	if path.size() < 2:
		return
	# Nur leicht vereinfachen: sonst werden die sanften Kehren der Wegsuche wieder zu Ecken
	path = _simplify(path, 2.5)
	for i in 3:
		path = _chaikin(path)
	_resample(path)
	_relax(4)
	if not _make_profile():
		return
	_build_mesh()
	valid = true


# ---------------------------------------------------------------------------
# 1. Wegsuche (A*) auf einem Raster zwischen Start und Ziel
# ---------------------------------------------------------------------------

func _find_path() -> PackedVector2Array:
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
			# In den ersten und letzten 300 m soll die Straße in einem Kegel von etwa ±45° um die
			# Richtung zum anderen Ort bleiben. Die Nachbarn eines Orts liegen in vier
			# verschiedenen Richtungen, so kreuzen sich seine Straßen nicht gegenseitig.
			var from_a := p - a
			var from_b := p - b
			if from_a.length() < 300.0 and from_a.length() > 1.0 and from_a.normalized().dot(dir_u) < 0.72:
				penalty += 300.0
			if from_b.length() < 300.0 and from_b.length() > 1.0 and from_b.normalized().dot(-dir_u) < 0.72:
				penalty += 300.0
			extra[i] = penalty

	var start_index := roundi(half_width / grid_step) * nu + roundi(margin / grid_step)
	var goal_u := roundi((margin + length) / grid_step)
	var goal_index := roundi(half_width / grid_step) * nu + mini(goal_u, nu - 1)

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
			# Scharfe Knicke kosten extra: eine Kehre muss aus mehreren sanften Knicken bestehen,
			# sonst würden die beiden Straßenhälften übereinander liegen
			var turn_cos := incoming.dot(move_dirs[m])
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
	path[0] = a
	path[path.size() - 1] = b
	return path


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


## Chaikin: schneidet jede Ecke ab, der Weg wird mit jeder Runde runder
func _chaikin(path: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array([path[0]])
	for i in path.size() - 1:
		var p := path[i]
		var q := path[i + 1]
		result.append(p.lerp(q, 0.25))
		result.append(p.lerp(q, 0.75))
	result.append(path[path.size() - 1])
	return result


## Jeden Punkt etwas in die Mitte seiner Nachbarn ziehen: Kurven werden runder
func _relax(rounds: int) -> void:
	for r in rounds:
		var smoothed := points.duplicate()
		for i in range(1, points.size() - 1):
			smoothed[i] = points[i - 1] * 0.25 + points[i] * 0.5 + points[i + 1] * 0.25
		points = smoothed


## Gleichmäßig alle POINT_SPACING Meter einen Punkt setzen
func _resample(path: PackedVector2Array) -> void:
	points = PackedVector3Array()
	var carry := 0.0
	points.append(Vector3(path[0].x, 0.0, path[0].y))
	for i in path.size() - 1:
		var a := path[i]
		var b := path[i + 1]
		var seg_len := a.distance_to(b)
		var t := POINT_SPACING - carry
		while t <= seg_len:
			var p := a.lerp(b, t / seg_len)
			points.append(Vector3(p.x, 0.0, p.y))
			t += POINT_SPACING
		carry = seg_len - (t - POINT_SPACING)
	var last := path[path.size() - 1]
	if Vector2(points[points.size() - 1].x, points[points.size() - 1].z).distance_to(last) > 0.5:
		points.append(Vector3(last.x, 0.0, last.y))


# ---------------------------------------------------------------------------
# 3. Höhenprofil
# ---------------------------------------------------------------------------

func _make_profile() -> bool:
	var n := points.size()
	var lakes: Array = world_gen.lakes_near(_points_rect())
	ground = PackedFloat32Array()
	ground.resize(n)
	for i in n:
		ground[i] = world_gen.terrain_height(points[i].x, points[i].z, lakes)
	# Gleitender Mittelwert über ±32 m: kleine Buckel verschwinden
	var smooth := PackedFloat32Array()
	smooth.resize(n)
	var window := 8
	for i in n:
		var total := 0.0
		var count := 0
		for j in range(maxi(i - window, 0), mini(i + window, n - 1) + 1):
			total += ground[j]
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
	# Anfang und Ende liegen genau auf den Orten
	smooth[0] = start.y
	smooth[n - 1] = end.y
	# Steigung begrenzen: vorwärts und rückwärts durchgehen
	var max_step := max_grade * POINT_SPACING
	for i in range(1, n):
		smooth[i] = clampf(smooth[i], smooth[i - 1] - max_step, smooth[i - 1] + max_step)
	smooth[n - 1] = end.y
	for i in range(n - 2, -1, -1):
		smooth[i] = clampf(smooth[i], smooth[i + 1] - max_step, smooth[i + 1] + max_step)
	smooth[0] = start.y
	# Wenn die Straße tiefe Schluchten oder riesige Brücken bräuchte, lieber keine Straße
	for i in n:
		if ground[i] - smooth[i] > MAX_CUT or smooth[i] - ground[i] > MAX_FILL:
			return false
		points[i].y = smooth[i]
	# Brücken: über Wasser und wo die Straße hoch über dem Gelände liegt, plus 12 m Zugabe.
	# Nicht direkt an den Orten (dort sind Kreuzungen).
	bridge = PackedByteArray()
	bridge.resize(n)
	for i in n:
		if over_water[i] == 1 or smooth[i] - ground[i] > BRIDGE_HEIGHT:
			for j in range(maxi(i - 3, 4), mini(i + 4, n - 4)):
				bridge[j] = 1
	bounds = _points_rect().grow(road_width * 0.5 + shoulder_width + MAX_BANK)
	return true


func _points_rect() -> Rect2:
	var rect := Rect2(points[0].x, points[0].z, 0.0, 0.0)
	for p in points:
		rect = rect.expand(Vector2(p.x, p.z))
	return rect


# ---------------------------------------------------------------------------
# 4. Mesh: Querschnitt aus 6 Punkten (Schürze, Bankett, Fahrbahn, Fahrbahn, Bankett, Schürze)
# ---------------------------------------------------------------------------

func _build_mesh() -> void:
	var n := points.size()
	origin = points[n / 2]
	var half := road_width * 0.5
	var outer := half + shoulder_width
	# Seitlicher Abstand (positiv = links), Höhenversatz und u-Koordinate jedes Querschnittspunkts
	# Der äußerste Punkt liegt schräg tiefer: ein Bankett, das in die Böschung übergeht
	var verge := outer + 1.8
	var side := [verge, outer, half, -half, -outer, -verge]
	var drop := [-1.3, -0.06, 0.0, 0.0, -0.06, -1.3]
	var u_coord := [-(verge - half) / road_width, -shoulder_width / road_width, 0.0, 1.0,
		1.0 + shoulder_width / road_width, 1.0 + (verge - half) / road_width]
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var lefts := PackedVector3Array()
	var distance := 0.0
	var turns := _turn_radii()
	for i in n:
		var forward := direction_at(i)
		var left := Vector3.UP.cross(forward).normalized()
		var up := forward.cross(left).normalized()
		if i > 0:
			distance += points[i].distance_to(points[i - 1])
		lefts.append(left)
		# In sehr engen Kurven die Innenseite schmaler machen, sonst überschlägt sich das Band
		var inner_limit := absf(turns[i]) * 0.85
		for k in 6:
			var offset: float = side[k]
			var height: float = drop[k]
			# Auf Brücken gibt es kein schräges Bankett, dort ist die Fahrbahnplatte
			if bridge[i] == 1 and (k == 0 or k == 5):
				offset = outer if k == 0 else -outer
				height = -0.06
			if turns[i] > 0.0 and offset > 0.0:
				offset = minf(offset, inner_limit)
			elif turns[i] < 0.0 and offset < 0.0:
				offset = maxf(offset, -inner_limit)
			verts.append(points[i] + left * offset + Vector3(0.0, height, 0.0) - origin)
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
	var indices := PackedInt32Array()
	collision_faces = PackedVector3Array()
	for i in n - 1:
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
	mesh_arrays[Mesh.ARRAY_INDEX] = indices
	_build_bridges(lefts)


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
			var p0 := points[k] - origin
			var p1 := points[k + 1] - origin
			for sgn: float in [1.0, -1.0]:
				var l0: Vector3 = lefts[k] * sgn
				var l1: Vector3 = lefts[k + 1] * sgn
				var normal := ((l0 + l1) * 0.5).normalized()
				var o0 := p0 + l0 * outer
				var o1 := p1 + l1 * outer
				var w0 := p0 + l0 * (outer - WALL_THICKNESS)
				var w1 := p1 + l1 * (outer - WALL_THICKNESS)
				# Außenseite: Platte und Brüstung in einem Stück
				_quad(o0 + down, o1 + down, o1 + wall, o0 + wall, normal)
				# Oberkante und Innenseite der Brüstung
				_quad(o0 + wall, o1 + wall, w1 + wall, w0 + wall, Vector3.UP)
				_quad(w0 + top, w1 + top, w1 + wall, w0 + wall, -normal)
				# Die Innenseite hält das Auto auf der Brücke
				collision_faces.append_array([w0 + top + origin, w1 + top + origin, w1 + wall + origin,
					w0 + top + origin, w1 + wall + origin, w0 + wall + origin])
			# Unterseite der Platte
			var a0 := p0 + lefts[k] * outer + down
			var a1 := p1 + lefts[k + 1] * outer + down
			var b0 := p0 - lefts[k] * outer + down
			var b1 := p1 - lefts[k + 1] * outer + down
			_quad(a0, a1, b1, b0, Vector3.DOWN)
		# Pfeiler bis in den Boden
		for k in range(i + 2, j - 2, PILLAR_EVERY):
			var bottom := ground[k] - 3.0
			if points[k].y - DECK_THICKNESS - bottom > 1.5:
				_pillar(points[k] - origin, bottom - origin.y)
		i = j
	if _b_indices.is_empty():
		return
	bridge_arrays.resize(Mesh.ARRAY_MAX)
	bridge_arrays[Mesh.ARRAY_VERTEX] = _b_verts
	bridge_arrays[Mesh.ARRAY_NORMAL] = _b_normals
	bridge_arrays[Mesh.ARRAY_INDEX] = _b_indices


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


## Kurvenradius an jedem Punkt (kleinster Wert der Umgebung).
## Positiv = Linkskurve, negativ = Rechtskurve, sehr groß = gerade.
func _turn_radii() -> PackedFloat32Array:
	var n := points.size()
	var raw := PackedFloat32Array()
	raw.resize(n)
	raw.fill(100000.0)
	for i in range(1, n - 1):
		var d_prev := points[i] - points[i - 1]
		var d_next := points[i + 1] - points[i]
		d_prev.y = 0.0
		d_next.y = 0.0
		var angle := d_prev.angle_to(d_next)
		var radius := POINT_SPACING / maxf(angle, 0.0001)
		raw[i] = radius if d_prev.cross(d_next).y > 0.0 else -radius
	var result := PackedFloat32Array()
	result.resize(n)
	for i in n:
		var tightest := raw[i]
		for j in range(maxi(i - 2, 0), mini(i + 3, n)):
			if absf(raw[j]) < absf(tightest):
				tightest = raw[j]
		result[i] = tightest
	return result


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
