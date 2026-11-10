class_name TrafficSigns
extends RefCounted
## Baut die Tempolimit- und Warnschilder eines Straßenabschnitts (segment.limit_signs von
## SpeedLimits) als ein Mesh mit Punktfarben (Pfosten, Schildflächen) und Beschriftungen:
## - limit: rund, weiß mit rotem Rand, Zahl (Zeichen 274), optional Zusatzschild „bei Nässe“
## - end_limit: Aufhebung, grauer Rand, Zahl und schräger Balken (Zeichen 278)
## - end_all: „Ende aller Streckenverbote“, fünf schräge Linien (Zeichen 282)
## - curve_left, curve_right, double_curve: rot umrandetes Dreieck mit Pfeil (Zeichen 103/105)
## Landstraße rechts, Autobahn beidseitig (rechts und im Mittelstreifen), Schild zum Verkehr hin.

const WHITE := Color(0.82, 0.82, 0.8)
const RED := Color(0.55, 0.03, 0.03)
const GREY := Color(0.3, 0.3, 0.3)
const BLACK := Color(0.02, 0.02, 0.02)
const BACK := Color(0.25, 0.26, 0.27)

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
## Beschriftungen: [Text, Mitte, Basis, Schriftgröße, Farbe]
var labels: Array = []


## Alle Schilder des Abschnitts (Koordinaten relativ zu segment.origin)
func build(segment: RoadSegment) -> void:
	var highway := segment.kind == RoadSegment.Kind.HIGHWAY
	var radius := 0.42 if highway else 0.32
	var height := 2.3 if highway else 2.0
	for entry: Array in segment.limit_signs:
		var i: int = entry[0]
		var d: int = entry[1]
		var travel := segment.direction_at(i) * float(d)
		travel.y = 0.0
		travel = travel.normalized()
		var right := travel.cross(Vector3.UP).normalized()
		var side := 1.0 if d > 0 else -1.0
		var outer := segment.road_width * 0.5 + segment.shoulder_width + 0.8 + segment.extra_at(i, -side)
		var spots: Array[float] = [outer]
		if highway:
			spots.append(-segment.road_width * 0.5 + 1.0)
		for lateral in spots:
			var foot := segment.points[i] - segment.origin + right * lateral
			_sign(foot, travel, right, height, radius, entry)


func _sign(foot: Vector3, travel: Vector3, right: Vector3, height: float, radius: float, entry: Array) -> void:
	var kind: String = entry[2]
	var value: int = entry[3]
	var wet: bool = entry[4]
	var center := foot + Vector3.UP * height
	var front := -travel
	var facing := Basis.looking_at(travel)
	var warning := kind.begins_with("curve") or kind == "double_curve"
	# Warndreieck (Umkreisradius 1,25 × radius) mit 8 cm Abstand über dem runden Schild
	var tri_center := center + Vector3.UP * (radius * 1.625 + 0.08)
	var top := tri_center if warning else center + Vector3.UP * radius
	# Pfosten (vierkant) vom Boden bis über das Schild
	_box(foot + Vector3.UP * (top.y - foot.y) * 0.5 + travel * 0.06, Vector3(0.07, top.y - foot.y, 0.07), right, BACK)
	if warning:
		_triangle(tri_center, radius * 1.25, right, front, RED, 0.0)
		_triangle(tri_center, radius * 0.95, right, front, WHITE, 0.004)
		_curve_arrow(tri_center - Vector3.UP * radius * 0.12, radius * 0.5, right, front, kind)
		_triangle(tri_center - front * 0.01, radius * 1.25, right, -front, BACK, 0.0)
		return
	match kind:
		"limit":
			_disc(center, radius, right, front, RED, 0.0)
			_disc(center, radius * 0.78, right, front, WHITE, 0.004)
			labels.append([str(value), center + front * 0.012, facing, _digit_size(value, radius), BLACK])
			if wet:
				var plate := center - Vector3.UP * (radius + 0.2)
				_rect(plate, radius * 2.3, 0.3, 0.0, right, front, WHITE, 0.0)
				labels.append(["bei Nässe", plate + front * 0.012, facing, roundi(radius * 100.0), BLACK])
		"end_limit":
			_disc(center, radius, right, front, GREY, 0.0)
			_disc(center, radius * 0.94, right, front, WHITE, 0.004)
			labels.append([str(value), center + front * 0.012, facing, _digit_size(value, radius), GREY])
			_rect(center, radius * 1.9, radius * 0.12, -PI * 0.25, right, front, GREY, 0.016)
		"end_all":
			_disc(center, radius, right, front, WHITE, 0.0)
			for k in 5:
				var offset := (k - 2) * radius * 0.22
				var shift := right * offset * 0.7071 + Vector3.UP * offset * 0.7071
				_rect(center + shift, radius * 1.7 * sqrt(maxf(1.0 - pow(offset / radius, 2.0), 0.0)), radius * 0.05,
					-PI * 0.25, right, front, BLACK, 0.006)
	# Rückseite (Blech)
	_disc(center - front * 0.01, radius, right, -front, BACK, 0.0)


## Pfeil im Warnschild: Kurve links/rechts oder Doppelkurve (aus drei bzw. vier Balken)
func _curve_arrow(center: Vector3, size: float, right: Vector3, front: Vector3, kind: String) -> void:
	var w := size * 0.16
	var turn := 1.0 if kind == "curve_right" else -1.0
	if kind == "double_curve":
		_rect(center - Vector3.UP * size * 0.5, size * 0.5, w, PI * 0.5, right, front, BLACK, 0.008)
		_rect(center + right * size * 0.15, size * 0.55, w, PI * 0.25, right, front, BLACK, 0.008)
		_rect(center + right * size * 0.3 + Vector3.UP * size * 0.45, size * 0.45, w, PI * 0.75, right, front, BLACK, 0.008)
		_triangle(center + right * size * 0.05 + Vector3.UP * size * 0.75, size * 0.3, right, front, BLACK, 0.008)
		return
	_rect(center - Vector3.UP * size * 0.3, size * 0.8, w, PI * 0.5, right, front, BLACK, 0.008)
	_rect(center + right * turn * size * 0.18 + Vector3.UP * size * 0.25, size * 0.5, w, PI * 0.5 - turn * PI * 0.25,
		right, front, BLACK, 0.008)
	_triangle(center + right * turn * size * 0.42 + Vector3.UP * size * 0.5, size * 0.32, right, front, BLACK, 0.008)


## Schriftgröße der Zahl: dreistellige etwas kleiner, damit sie in den weißen Kreis passen
func _digit_size(value: int, radius: float) -> int:
	return roundi(radius * (160.0 if value >= 100 else 220.0))


## Kreisscheibe in der Ebene (right, oben), Vorderseite in Richtung front, ahead Meter davor
func _disc(center: Vector3, radius: float, right: Vector3, front: Vector3, color: Color, ahead: float) -> void:
	var c := center + front * ahead
	var steps := 24
	for k in steps:
		var a0 := TAU * k / steps
		var a1 := TAU * (k + 1) / steps
		var p0 := c + (right * cos(a0) + Vector3.UP * sin(a0)) * radius
		var p1 := c + (right * cos(a1) + Vector3.UP * sin(a1)) * radius
		_tri(c, p0, p1, front, color)


## Gleichseitiges Dreieck mit der Spitze oben (Umkreisradius size)
func _triangle(center: Vector3, size: float, right: Vector3, front: Vector3, color: Color, ahead: float) -> void:
	var c := center + front * ahead
	var corners: Array[Vector3] = []
	for k in 3:
		var a := PI * 0.5 + TAU * k / 3.0
		corners.append(c + (right * cos(a) + Vector3.UP * sin(a)) * size)
	_tri(corners[0], corners[1], corners[2], front, color)


## Rechteck (Länge length in Richtung angle, gemessen von right nach oben)
func _rect(center: Vector3, length: float, width: float, angle: float, right: Vector3, front: Vector3, color: Color,
		ahead: float) -> void:
	var u := (right * cos(angle) + Vector3.UP * sin(angle)) * length * 0.5
	var v := (right * -sin(angle) + Vector3.UP * cos(angle)) * width * 0.5
	var c := center + front * ahead
	_tri(c - u - v, c + u - v, c + u + v, front, color)
	_tri(c - u - v, c + u + v, c - u + v, front, color)


## Vierkant-Pfosten (Breite size.x, Höhe size.y) um center
func _box(center: Vector3, size: Vector3, right: Vector3, color: Color) -> void:
	var forward := right.cross(Vector3.UP).normalized()
	var h := Vector3.UP * size.y * 0.5
	for axis: Vector3 in [right, -right, forward, -forward]:
		var u := axis.cross(Vector3.UP).normalized() * size.x * 0.5
		var c := center + axis * size.x * 0.5
		_tri(c - u - h, c + u - h, c + u + h, axis, color)
		_tri(c - u - h, c + u + h, c - u + h, axis, color)


## Dreieck mit der Vorderseite in Richtung normal (Godot: im Uhrzeigersinn von vorne)
func _tri(a: Vector3, b: Vector3, c: Vector3, normal: Vector3, color: Color) -> void:
	if (c - a).cross(b - a).dot(normal) >= 0.0:
		verts.append_array([a, b, c])
	else:
		verts.append_array([a, c, b])
	normals.append_array([normal, normal, normal])
	colors.append_array([color, color, color])


func mesh() -> ArrayMesh:
	var result := ArrayMesh.new()
	if verts.is_empty():
		return result
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result
