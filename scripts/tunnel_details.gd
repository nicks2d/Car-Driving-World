class_name TunnelDetails
extends RefCounted
## Ausstattung langer Tunnel (ab 400 m), gebaut zusammen mit der Röhre (RoadSegment.build, im Hintergrund):
##  - Notrufnischen alle 150 m an beiden Wänden: orangefarbene Kabine, darüber ein leuchtendes „SOS“-Schild
##  - grüne Fluchtweg-Schilder alle 50 m an beiden Wänden mit der Entfernung zu beiden Ausgängen
##  - Strahlventilatoren paarweise unter der Decke alle 300 m (drehen sich langsam, im Shader)
##  - Pannenbuchten alle 600 m in Tunneln ab 900 m, abwechselnd links und rechts (die Röhre wird dort
##    breiter, siehe RoadSegment._build_tube)
##  - Tunnelname und Länge auf einer blauen Tafel über jedem Portal
## Alles leuchtet selbst (Material ohne Licht, Punktfarben) und kostet keine echten Lichter. Die Schrift
## sind Label3D, die RoadNetwork beim Einbauen anlegt (labels, name_spots).

const MIN_LENGTH: float = 400.0
const SOS_EVERY: float = 150.0
const SIGN_EVERY: float = 50.0
const FAN_EVERY: float = 300.0
const FAN_FIRST: float = 110.0
const BAY_EVERY: float = 600.0
const BAY_MIN_TUNNEL: float = 900.0
## Pannenbucht: so viel breiter (Meter), so lang voll breit, so lang der schräge Übergang an jedem Ende
const BAY_WIDTH: float = 2.5
const BAY_FULL: float = 40.0
const BAY_TAPER: float = 15.0
## Abstand der Ausstattung zu den Portalen (Meter)
const PORTAL_MARGIN: float = 60.0

const GREEN := Color(0.02, 0.45, 0.16)
const SOS_PANEL := Color(0.95, 0.95, 0.92)
const CABIN := Color(0.85, 0.35, 0.05)
const CABIN_FRAME := Color(0.3, 0.3, 0.3)
const NAME_BLUE := Color(0.02, 0.15, 0.5)
const WHITE := Color(0.95, 0.95, 0.95)

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
## Lage der Ventilatoren (Gehäuse entlang +z), relativ zu segment.origin
var fans: Array[Transform3D] = []
## Beschriftungen: [Text, Lage (relativ zu origin), Basis, Schriftgröße, Farbe]
var labels: Array = []
## Namensschilder über den Portalen: [Lage, Basis, Länge in Metern (0 = unbekannt)]; den Namen setzt
## RoadNetwork (Ortsname der Umgebung)
var name_spots: Array = []
## Für Test-Fotos (DebugTools --tunnelshot): Stellen der Ausstattung [Art, Lage an der Wand, Richtung in den
## Tunnel hinein], Art "sos", "sign", "bay", "fan"; relativ zu segment.origin
var spots: Array = []


## Strecke ab dem Anfang des Bereichs für jeden Punkt des Bereichs (Index i - r.x)
static func along(segment: RoadSegment, r: Vector2i) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(r.y - r.x + 1)
	for i in range(r.x + 1, r.y + 1):
		result[i - r.x] = result[i - r.x - 1] + segment.points[i].distance_to(segment.points[i - 1])
	return result


## Pannenbuchten eines Tunnelbereichs: [Mitte in Metern ab Bereichsanfang, Seite (+1 links, -1 rechts)]
static func bays(segment: RoadSegment, r: Vector2i) -> Array:
	var result: Array = []
	var distances := along(segment, r)
	var length := distances[distances.size() - 1]
	if length < BAY_MIN_TUNNEL:
		return result
	var half := BAY_FULL * 0.5 + BAY_TAPER
	var at := BAY_EVERY * 0.5
	var side := -1.0
	while at < length - half - 150.0:
		if at > half + 150.0:
			result.append([at, side])
		side = -side
		at += BAY_EVERY * 0.5
	return result


## Wie viel breiter die Röhre an dieser Stelle (Meter ab Bereichsanfang) auf dieser Seite ist
static func widen(bay_list: Array, at: float, side: float) -> float:
	var result := 0.0
	for bay: Array in bay_list:
		if bay[1] != side:
			continue
		var off := absf(at - float(bay[0]))
		if off < BAY_FULL * 0.5:
			result = BAY_WIDTH
		elif off < BAY_FULL * 0.5 + BAY_TAPER:
			result = maxf(result, BAY_WIDTH * (1.0 - (off - BAY_FULL * 0.5) / BAY_TAPER))
	return result


## Ausstattung für einen Tunnelbereich bauen. bay_list aus bays(), lefts wie in RoadSegment.build
func build(segment: RoadSegment, r: Vector2i, lefts: PackedVector3Array, bay_list: Array) -> void:
	var distances := along(segment, r)
	var length := distances[distances.size() - 1]
	var n := segment.points.size()
	var has_start := r.x > 0
	var has_end := r.y < n - 1
	if length < MIN_LENGTH:
		return
	var w := segment.tube_half_width()
	# Namensschilder über den Portalen
	if has_start:
		_name_plate(segment, r.x, -segment.direction_at(r.x), lefts[r.x], length if has_end else 0.0)
	if has_end:
		_name_plate(segment, r.y, segment.direction_at(r.y), lefts[r.y], length if has_start else 0.0)
	# Schilder, Nischen, Ventilatoren entlang der Röhre
	for bay: Array in bay_list:
		var k := 0
		while k < distances.size() - 1 and distances[k] < float(bay[0]):
			k += 1
		var side: float = bay[1]
		var i := r.x + k
		spots.append(["bay", segment.side_point(i, lefts[i], (w + BAY_WIDTH) * side, 0.0) - segment.origin,
			-lefts[i] * side])
	var next_sign := SIGN_EVERY
	var next_fan := FAN_FIRST
	for k in range(1, distances.size()):
		var i := r.x + k
		var at := distances[k]
		if at < PORTAL_MARGIN or at > length - PORTAL_MARGIN:
			if at >= next_sign:
				next_sign += SIGN_EVERY
			continue
		if at >= next_fan:
			next_fan += FAN_EVERY
			_fan_pair(segment, i, lefts[i])
			spots.append(["fan", segment.side_point(i, lefts[i], w, 0.0) - segment.origin, -lefts[i]])
		if at < next_sign:
			continue
		next_sign += SIGN_EVERY
		var step := roundi(at / SIGN_EVERY)
		for side: float in [1.0, -1.0]:
			# Nicht in einer Pannenbucht (dort ist die Wand weiter weg)
			if widen(bay_list, at, side) > 0.0:
				continue
			var wall := segment.side_point(i, lefts[i], (w - 0.02) * side, 0.0) - segment.origin
			var inward := -lefts[i] * side
			spots.append(["sos" if step % 3 == 0 else "sign", wall, inward])
			if step % 3 == 0:
				_sos_niche(wall, inward)
			else:
				var to_start := at if has_start else -1.0
				var to_end := length - at if has_end else -1.0
				_escape_sign(wall, inward, segment.direction_at(i), to_start, to_end)


## Mesh aller leuchtenden Teile (Punktfarben, ohne Licht zu zeichnen)
func mesh_arrays() -> Array:
	if verts.is_empty():
		return []
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	return arrays


## Notrufnische: orangefarbene Kabine (0,9 × 2,1 m, 15 cm vor der Wand) mit dunklem Rahmen, darüber das
## leuchtende SOS-Schild
func _sos_niche(wall: Vector3, inward: Vector3) -> void:
	var right := inward.cross(Vector3.UP).normalized()
	_panel(wall + Vector3.UP * 1.1 + inward * 0.06, right, inward, 1.05, 2.3, CABIN_FRAME)
	_panel(wall + Vector3.UP * 1.1 + inward * 0.08, right, inward, 0.9, 2.1, CABIN)
	var sign_center := wall + Vector3.UP * 2.75 + inward * 0.1
	_panel(sign_center, right, inward, 0.9, 0.45, SOS_PANEL)
	labels.append(["SOS", sign_center + inward * 0.012, Basis.looking_at(-inward), 70, Color(0.85, 0.08, 0.05)])


## Fluchtweg-Schild: grüne Tafel 1,9 × 0,42 m auf 1,6 m Höhe, flach an der Wand, mit den Entfernungen zu den
## Ausgängen in beide Richtungen (Pfeile entlang der Röhre). Unbekannte Richtung (Tunnel geht im nächsten
## Abschnitt weiter): -1, dann nur die andere.
func _escape_sign(wall: Vector3, inward: Vector3, forward: Vector3, to_start: float, to_end: float) -> void:
	var basis := Basis.looking_at(-inward)
	var center := wall + Vector3.UP * 1.6 + inward * 0.03
	_panel(center, basis.x, inward, 1.9, 0.42, GREEN)
	# basis.x zeigt nach rechts auf dem Schild: entlang oder gegen die Fahrtrichtung der Straßenpunkte
	var right_is_end := basis.x.dot(forward) > 0.0
	var right_distance := to_end if right_is_end else to_start
	var left_distance := to_start if right_is_end else to_end
	var parts: Array[String] = []
	if left_distance >= 0.0:
		parts.append("← %d m" % roundi(left_distance))
	parts.append("|")
	if right_distance >= 0.0:
		parts.append("%d m →" % roundi(right_distance))
	labels.append(["  ".join(parts), center + inward * 0.012, basis, 30, WHITE])


## Zwei Strahlventilatoren nebeneinander unter der Decke, Achse entlang der Röhre
func _fan_pair(segment: RoadSegment, i: int, left: Vector3) -> void:
	var forward := segment.direction_at(i)
	for side: float in [1.0, -1.0]:
		var center := segment.side_point(i, left, 1.45 * side, RoadSegment.TUBE_APEX - 1.05) - segment.origin
		fans.append(Transform3D(Basis.looking_at(-forward, Vector3.UP), center))


## Blaue Tafel über dem Portal (außen an der Stirnwand), Name und Länge setzt RoadNetwork
func _name_plate(segment: RoadSegment, p: int, outward: Vector3, left: Vector3, length: float) -> void:
	var center := segment.points[p] - segment.origin + Vector3.UP * (RoadSegment.TUBE_APEX + 1.9) \
		+ outward * (RoadSegment.COLLAR_DEPTH + 0.05)
	var right := outward.cross(Vector3.UP).normalized()
	_panel(center, right, outward, 6.0, 1.5, NAME_BLUE)
	_panel(center + outward * 0.005, right, outward, 5.8, 1.3, WHITE)
	_panel(center + outward * 0.01, right, outward, 5.6, 1.1, NAME_BLUE)
	name_spots.append([center + outward * 0.02, Basis.looking_at(-outward), length])


## Rechteck (Breite × Höhe) in der Ebene quer zu front, Vorderseite zu front
func _panel(center: Vector3, right: Vector3, front: Vector3, width: float, height: float, color: Color) -> void:
	var u := right.normalized() * width * 0.5
	var v := Vector3.UP * height * 0.5
	_tri(center - u - v, center + u - v, center + u + v, front, color)
	_tri(center - u - v, center + u + v, center - u + v, front, color)


func _tri(a: Vector3, b: Vector3, c: Vector3, normal: Vector3, color: Color) -> void:
	if (c - a).cross(b - a).dot(normal) >= 0.0:
		verts.append_array([a, b, c])
	else:
		verts.append_array([a, c, b])
	normals.append_array([normal, normal, normal])
	colors.append_array([color, color, color])


# ---------------------------------------------------------------------------
# Ventilator-Meshes (einmal gebaut, für alle Tunnel)
# ---------------------------------------------------------------------------

static var _housing: ArrayMesh
static var _rotor: ArrayMesh


## Gehäuse: offenes Rohr (Halbmesser 0,55 m, 4 m lang) mit zwei Halteblechen nach oben
static func housing_mesh() -> ArrayMesh:
	if _housing:
		return _housing
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 18
	for side: float in [1.0, -1.0]:
		var radius := 0.55 if side > 0.0 else 0.52
		for k in steps:
			var a0 := TAU * k / steps
			var a1 := TAU * (k + 1) / steps
			var p0 := Vector3(cos(a0), sin(a0), 0.0) * radius
			var p1 := Vector3(cos(a1), sin(a1), 0.0) * radius
			var n0 := Vector3(cos(a0), sin(a0), 0.0) * side
			var n1 := Vector3(cos(a1), sin(a1), 0.0) * side
			var quad: Array[Vector3] = [p0 + Vector3.BACK * 2.0, p1 + Vector3.BACK * 2.0, p1 + Vector3.FORWARD * 2.0,
				p0 + Vector3.FORWARD * 2.0]
			var quad_normals: Array[Vector3] = [n0, n1, n1, n0]
			var order: Array = [0, 1, 2, 0, 2, 3] if side > 0.0 else [0, 2, 1, 0, 3, 2]
			for index in order:
				tool.set_normal(quad_normals[index])
				tool.add_vertex(quad[index])
	# Halterungen: zwei Bleche vom Rohr zur Decke
	for z: float in [-1.2, 1.2]:
		for face: float in [1.0, -1.0]:
			var x := 0.03 * face
			var corners: Array[Vector3] = [Vector3(x, 0.5, z - 0.2), Vector3(x, 0.5, z + 0.2), Vector3(x, 0.95, z + 0.2),
				Vector3(x, 0.95, z - 0.2)]
			var order: Array = [0, 2, 1, 0, 3, 2] if face > 0.0 else [0, 1, 2, 0, 2, 3]
			for index in order:
				tool.set_normal(Vector3(face, 0.0, 0.0))
				tool.add_vertex(corners[index])
	_housing = tool.commit()
	return _housing


## Läufer: Nabe und 6 schräge Blätter in der x-y-Ebene, je einer an beiden Enden des Rohrs
static func rotor_mesh() -> ArrayMesh:
	if _rotor:
		return _rotor
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z: float in [-1.6, 1.6]:
		for blade in 6:
			var a := TAU * blade / 6.0
			var dir := Vector3(cos(a), sin(a), 0.0)
			var across := Vector3(-sin(a), cos(a), 0.0)
			var base := Vector3(0.0, 0.0, z)
			var corners: Array[Vector3] = [base + dir * 0.1 - across * 0.06, base + dir * 0.5 - across * 0.1 + Vector3(0, 0, 0.04),
				base + dir * 0.5 + across * 0.1 - Vector3(0, 0, 0.04), base + dir * 0.1 + across * 0.06]
			for order: Array in [[0, 1, 2, 0, 2, 3], [0, 2, 1, 0, 3, 2]]:
				for index in order:
					tool.set_normal(Vector3.BACK if order[1] == 1 else Vector3.FORWARD)
					tool.add_vertex(corners[index])
		# Nabe als Achteck
		for k in 8:
			var a0 := TAU * k / 8.0
			var a1 := TAU * (k + 1) / 8.0
			for face: float in [1.0, -1.0]:
				var c := Vector3(0.0, 0.0, z)
				var p0 := c + Vector3(cos(a0), sin(a0), 0.0) * 0.13
				var p1 := c + Vector3(cos(a1), sin(a1), 0.0) * 0.13
				tool.set_normal(Vector3(0, 0, face))
				if face > 0.0:
					tool.add_vertex(c)
					tool.add_vertex(p1)
					tool.add_vertex(p0)
				else:
					tool.add_vertex(c)
					tool.add_vertex(p0)
					tool.add_vertex(p1)
	_rotor = tool.commit()
	return _rotor
