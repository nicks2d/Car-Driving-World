class_name RoadSegment
extends RefCounted
## Ein Straßenabschnitt zwischen zwei Orten (Knoten). build() läuft im Hintergrund:
##  1. Wegsuche übers Gelände (A*): steil und Wasser sind teuer, so entstehen am Hang
##     von selbst Serpentinen und in der Ebene weite Bögen.
##  2. Weg glätten (Ecken abrunden) und alle 4 m einen Punkt setzen.
##  3. Höhenprofil glätten und die Steigung begrenzen (Gelände wird später angepasst).
##  4. Mesh-Daten für Fahrbahn und Kollision erzeugen.

# --- Eingaben ---
var world_gen: WorldGen
var key: Vector3i
var start: Vector3
var end: Vector3
var road_width: float = 7.0
var shoulder_width: float = 1.2
var max_grade: float = 0.10
var grid_step: float = 18.0

# --- Ergebnisse ---
## Mittellinie, alle POINT_SPACING Meter ein Punkt, y = Höhe der Fahrbahn
var points: PackedVector3Array
## Geländehöhe unter jedem Punkt (vor der Anpassung)
var ground: PackedFloat32Array
## Rechteck (x/z), in dem die Straße das Gelände beeinflusst
var bounds: Rect2
## false = es gab keinen vernünftigen Weg, hier entsteht keine Straße
var valid: bool = false
var mesh_arrays: Array = []
var collision_faces: PackedVector3Array
## Mittelpunkt, auf den sich die Mesh-Koordinaten beziehen (für Genauigkeit)
var origin: Vector3

const POINT_SPACING: float = 4.0
## So weit kann die Böschung neben der Straße höchstens reichen
const MAX_BANK: float = 45.0
## Höchster erlaubter Unterschied zwischen Fahrbahn und Gelände (sonst keine Straße)
const MAX_CUT: float = 35.0


func build() -> void:
	var path := _find_path()
	if path.size() < 2:
		return
	path = _simplify(path, 6.0)
	for i in 3:
		path = _chaikin(path)
	_resample(path)
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
				penalty += 100000.0 if in_lake else 40.0
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
	for i in n:
		var water := world_gen.water_level_at(points[i].x, points[i].z, lakes)
		if water > WorldGen.NO_WATER:
			smooth[i] = maxf(smooth[i], water + 4.0)
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
	# Wenn die Straße tiefe Schluchten bräuchte, lieber keine Straße
	for i in n:
		if absf(smooth[i] - ground[i]) > MAX_CUT:
			return false
		points[i].y = smooth[i]
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
	var side := [outer, outer, half, -half, -outer, -outer]
	var drop := [-0.7, -0.06, 0.0, 0.0, -0.06, -0.7]
	var u_coord := [-shoulder_width / road_width, -shoulder_width / road_width, 0.0, 1.0,
		1.0 + shoulder_width / road_width, 1.0 + shoulder_width / road_width]
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var distance := 0.0
	for i in n:
		var forward := direction_at(i)
		var left := Vector3.UP.cross(forward).normalized()
		var up := forward.cross(left).normalized()
		if i > 0:
			distance += points[i].distance_to(points[i - 1])
		for k in 6:
			verts.append(points[i] + left * side[k] + Vector3(0.0, drop[k], 0.0) - origin)
			var normal: Vector3 = up
			if k == 0:
				normal = left
			elif k == 5:
				normal = -left
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


## Fahrtrichtung am Punkt i (Mittel aus Richtung davor und danach)
func direction_at(i: int) -> Vector3:
	var a := points[maxi(i - 1, 0)]
	var b := points[mini(i + 1, points.size() - 1)]
	var d := b - a
	d.y = 0.0
	return d.normalized()


## Länge der Straße in Metern
func length() -> float:
	return (points.size() - 1) * POINT_SPACING
