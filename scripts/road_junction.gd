class_name RoadJunction
extends RefCounted
## Eine Kreuzung an einem Ort. Die Straßen enden `radius` Meter vor der Mitte, dazwischen
## liegt eine eigene Asphaltfläche ohne Markierungen. Ihr Rand verbindet die Straßenränder
## mit runden Bögen (wie Bordsteinkanten), außen herum liegen wie bei der Straße Bankett und
## Böschungskante. An den Straßenenden passen die Punkte genau aufeinander: keine Lücke,
## keine Überlappung.

## Punkte pro Eckbogen
const CORNER_STEPS: int = 10

var center: Vector3
## So weit vor der Mitte enden die Straßen (Meter)
var radius: float
## Ankommende Straßen: [RoadSegment, true = beginnt hier / false = endet hier]
var arms: Array = []
var mesh_instance: MeshInstance3D
var body: StaticBody3D
## Vorfahrt je Arm (gleiche Reihenfolge wie arms): RULE_PRIORITY (Vorfahrtstraße, gelbe Raute),
## RULE_YIELD („Vorfahrt gewähren“) oder RULE_STOP (Stoppschild). Leer bei weniger als drei Straßen.
var rules := PackedByteArray()
## So weit vor der Kreuzungsmitte liegen Haltelinie und Schilder (Meter). Dort endet auch der Weg der
## KI-Autos (Traffic: leg.to = Länge − 26), danach fahren sie die Kurve über die Kreuzung.
const STOP_DISTANCE: float = 26.0
const RULE_PRIORITY: int = 0
const RULE_YIELD: int = 1
const RULE_STOP: int = 2
## Anteil der Nebenstraßen mit Stoppschild (Rest: Vorfahrt gewähren)
const STOP_SHARE: float = 0.3
## Ergebnis von build()
var mesh_arrays: Array = []
var collision_faces := PackedVector3Array()

var _verts := PackedVector3Array()
var _normals := PackedVector3Array()
var _uvs := PackedVector2Array()
var _uv2s := PackedVector2Array()
var _indices := PackedInt32Array()


## Anzahl Straßenpunkte (je 4 m) zwischen Kreuzungsmitte und Straßenende
func mouth_steps() -> int:
	return ceili(radius / RoadSegment.POINT_SPACING)


## Index des Straßenpunkts, an dem die Straße auf die Kreuzung trifft
func mouth_index(arm: Array) -> int:
	var segment: RoadSegment = arm[0]
	return mouth_steps() if arm[1] else segment.points.size() - 1 - mouth_steps()


func build() -> void:
	var segment: RoadSegment = arms[0][0]
	var half := segment.road_width * 0.5
	# Drei Ränder: Asphalt, Bankett, Böschungskante (wie der Querschnitt der Straße)
	var offsets: Array[float] = [half, half + segment.shoulder_width,
		half + segment.shoulder_width + RoadSegment.VERGE_WIDTH]
	var heights: Array[float] = [0.0, RoadSegment.SHOULDER_DROP, RoadSegment.VERGE_DROP]
	# Straßen nach ihrem Winkel sortieren, dann einmal ringsherum gehen
	var sorted := arms.duplicate()
	sorted.sort_custom(func(a: Array, b: Array) -> bool: return _angle(a) < _angle(b))
	var outlines: Array[PackedVector3Array] = []
	# mouth[i] = 1: zwischen Umrisspunkt i und i+1 liegt ein Straßenende (dort kein Rand)
	var mouth := PackedByteArray()
	for level in 3:
		var outline := PackedVector3Array()
		for a in sorted.size():
			var arm: Array = sorted[a]
			var next_arm: Array = sorted[(a + 1) % sorted.size()]
			# Linker und rechter Rand des Straßenendes (von der Kreuzung aus gesehen) ...
			outline.append(_mouth_point(arm, offsets[level], heights[level]))
			outline.append(_mouth_point(arm, -offsets[level], heights[level]))
			# ... dann der Bogen zur nächsten Straße
			outline.append_array(_corner(arm, next_arm, offsets[level], heights[level],
				(offsets[level] - half) * 0.8))
			if level == 0:
				mouth.append(1)
				for i in CORNER_STEPS:
					mouth.append(0)
		outlines.append(outline)
	var count := outlines[0].size()
	# Asphalt: Fächer von der Mitte zum Asphaltrand
	var middle := _add_vertex(center, Vector3.UP, 0.0)
	var first := _verts.size()
	for p in outlines[0]:
		_add_vertex(p, Vector3.UP, 0.0)
	for i in count:
		_triangle(middle, first + i, first + (i + 1) % count, true)
	# Bankett (Schotter) und Böschungskante als Ringe, nur zwischen den Straßen
	for level in 2:
		var inner := _verts.size()
		for p in outlines[level]:
			_add_vertex(p, _ring_normal(p, level), 1.0)
		var outer := _verts.size()
		for p in outlines[level + 1]:
			_add_vertex(p, _ring_normal(p, level + 1), 1.0)
		for i in count:
			if mouth[i] == 1:
				continue
			var j := (i + 1) % count
			_triangle(inner + i, inner + j, outer + j, level == 0)
			_triangle(inner + i, outer + j, outer + i, level == 0)
	var tangents := PackedFloat32Array()
	for i in _verts.size():
		tangents.append_array([1.0, 0.0, 0.0, 1.0])
	mesh_arrays.resize(Mesh.ARRAY_MAX)
	mesh_arrays[Mesh.ARRAY_VERTEX] = _verts
	mesh_arrays[Mesh.ARRAY_NORMAL] = _normals
	mesh_arrays[Mesh.ARRAY_TANGENT] = tangents
	mesh_arrays[Mesh.ARRAY_TEX_UV] = _uvs
	mesh_arrays[Mesh.ARRAY_TEX_UV2] = _uv2s
	mesh_arrays[Mesh.ARRAY_INDEX] = _indices


## Vorfahrt festlegen (deterministisch aus der Form der Kreuzung): Die beiden Straßen, die am geradesten
## durch die Kreuzung gehen, sind die Vorfahrtstraße, alle anderen müssen warten; davon bekommen etwa
## 30 % ein Stoppschild (Zufall aus Lage und Richtung, also bei jedem Start gleich).
func compute_rules() -> void:
	rules.clear()
	if arms.size() < 3:
		return
	var best := INF
	var pair := Vector2i(0, 1)
	for i in arms.size():
		for j in range(i + 1, arms.size()):
			var straight := outward(arms[i]).dot(outward(arms[j]))
			if straight < best:
				best = straight
				pair = Vector2i(i, j)
	rules.resize(arms.size())
	for k in arms.size():
		if k == pair.x or k == pair.y:
			rules[k] = RULE_PRIORITY
			continue
		var angle := roundi(rad_to_deg(_angle(arms[k])))
		var mix := (roundi(center.x) * 73856093) ^ (roundi(center.z) * 19349663) ^ (angle * 83492791)
		rules[k] = RULE_STOP if absi(mix) % 100 < roundi(STOP_SHARE * 100.0) else RULE_YIELD


## Index des Arms für diese Straße, wenn man auf ihr zur Kreuzung fährt (-1 = keiner).
## forward: Fahrt in Richtung der Straßenpunkte (kommt am Ende der Straße an).
func arm_of(segment: RoadSegment, forward: bool) -> int:
	for k in arms.size():
		if arms[k][0] == segment and arms[k][1] == not forward:
			return k
	return -1


## Vorfahrtregel für diesen Arm (RULE_PRIORITY, wenn es keine Regeln gibt)
func rule_of(arm_index: int) -> int:
	if arm_index < 0 or arm_index >= rules.size():
		return RULE_PRIORITY
	return rules[arm_index]


## Richtung, in die die Straße die Kreuzung verlässt (waagerecht)
func outward(arm: Array) -> Vector3:
	return _outward(arm)


## Richtung, in die die Straße die Kreuzung verlässt (waagerecht)
func _outward(arm: Array) -> Vector3:
	var segment: RoadSegment = arm[0]
	var direction := segment.direction_at(mouth_index(arm))
	return direction if arm[1] else -direction


## Winkel der Straße um die Kreuzungsmitte
func _angle(arm: Array) -> float:
	var d := _outward(arm)
	return Vector2(d.x, d.z).angle()


## Punkt am Straßenende. offset positiv = links, von der Kreuzung aus gesehen.
## Genau derselbe Punkt wie im Querschnitt der Straße, deshalb passt alles nahtlos.
func _mouth_point(arm: Array, offset: float, height: float) -> Vector3:
	var segment: RoadSegment = arm[0]
	var i := mouth_index(arm)
	var left := Vector3.UP.cross(segment.direction_at(i)).normalized()
	return segment.side_point(i, left, offset if arm[1] else -offset, height)


## Rand zwischen zwei benachbarten Straßen: vom rechten Rand der einen zum linken Rand der
## nächsten. Liefert die Punkte dazwischen (ohne Anfang und Ende).
func _corner(from_arm: Array, to_arm: Array, offset: float, height: float, bulge: float) -> PackedVector3Array:
	var s := _mouth_point(from_arm, -offset, height)
	var e := _mouth_point(to_arm, offset, height)
	var s2 := Vector2(s.x, s.z)
	var e2 := Vector2(e.x, e.z)
	var wedge := wrapf(_angle(to_arm) - _angle(from_arm), 0.0, TAU)
	if from_arm == to_arm:
		wedge = TAU
	var result := PackedVector3Array()
	if wedge < deg_to_rad(170.0):
		# Runde Ecke (Bezier-Kurve). Stützpunkt ist die Stelle, an der sich die beiden
		# Straßenränder treffen würden. Liegt die nicht zwischen Mitte und Straßenenden,
		# wird der Rand einfach gerade.
		var a := Vector2(_outward(from_arm).x, _outward(from_arm).z)
		var b := Vector2(_outward(to_arm).x, _outward(to_arm).z)
		var control := (s2 + e2) * 0.5
		var denom := a.cross(b)
		if absf(denom) > 0.0001:
			var u := (e2 - s2).cross(b) / denom
			var v := (e2 - s2).cross(a) / denom
			if u < 0.0 and v < 0.0:
				control = s2 + a * u
		for i in range(1, CORNER_STEPS):
			var t := float(i) / CORNER_STEPS
			var p := s2 * (1.0 - t) * (1.0 - t) + control * 2.0 * (1.0 - t) * t + e2 * t * t
			result.append(Vector3(p.x, lerpf(s.y, e.y, t), p.y))
	else:
		# Sehr weiter Winkel (oder Sackgasse): Kreisbogen um die Mitte
		var c2 := Vector2(center.x, center.z)
		var start_angle := (s2 - c2).angle()
		var sweep := wrapf((e2 - c2).angle() - start_angle, 0.0, TAU)
		var rs := s2.distance_to(c2)
		var re := e2.distance_to(c2)
		for i in range(1, CORNER_STEPS):
			var t := float(i) / CORNER_STEPS
			var r := lerpf(rs, re, t) + sin(PI * t) * bulge
			var p := c2 + Vector2.from_angle(start_angle + sweep * t) * r
			result.append(Vector3(p.x, lerpf(s.y, e.y, t), p.y))
	return result


## Normale der Ringe: Bankett flach, Böschungskante nach außen geneigt
func _ring_normal(p: Vector3, level: int) -> Vector3:
	if level < 2:
		return Vector3.UP
	var out := Vector3(p.x - center.x, 0.0, p.z - center.z).normalized()
	return (Vector3.UP + out * 0.6).normalized()


## gravel: 0 = Asphalt, 1 = Schotter (UV2.x = 1 sagt dem Straßen-Shader: Kreuzungsfläche)
func _add_vertex(p: Vector3, normal: Vector3, gravel: float) -> int:
	var local := p - center
	_verts.append(local)
	_normals.append(normal)
	# Textur in Metern; so, dass die Normal-Map richtig herum liegt (siehe Tangente)
	var segment: RoadSegment = arms[0][0]
	_uvs.append(Vector2(local.x / segment.road_width, -local.z))
	_uv2s.append(Vector2(1.0, gravel))
	return _verts.size() - 1


## Dreieck mit Vorderseite nach oben; solid = auch für die Kollision
func _triangle(a: int, b: int, c: int, solid: bool) -> void:
	if (_verts[c] - _verts[a]).cross(_verts[b] - _verts[a]).dot(Vector3.UP) >= 0.0:
		_indices.append_array([a, b, c])
	else:
		_indices.append_array([a, c, b])
	if solid:
		collision_faces.append_array([_verts[a] + center, _verts[b] + center, _verts[c] + center])
