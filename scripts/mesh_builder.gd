class_name MeshBuilder
extends RefCounted
## Sammelt Vierecke und Kästen zu Mesh-Daten (für Staumauer, Bogen- und Hängebrücken). Die
## Punkte kommen in Weltkoordinaten und werden relativ zu einem Bezugspunkt gespeichert. Die
## Materialien dazu sind beidseitig (die Drehrichtung der Vierecke ist egal).

var _verts := PackedVector3Array()
var _normals := PackedVector3Array()
var _uvs := PackedVector2Array()
var _indices := PackedInt32Array()
var _colors := PackedColorArray()
## Punktfarbe für alles, was ab jetzt dazukommt (ein Mesh, viele Farben; Material mit
## vertex_color_use_as_albedo)
var color := Color.WHITE


## Viereck a-b-c-d (Weltkoordinaten), relativ zu origin
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, origin: Vector3, uv0: Vector2, uv_size: Vector2) -> void:
	var normal := (b - a).cross(d - a).normalized()
	var base := _verts.size()
	for p: Vector3 in [a, b, c, d]:
		_verts.append(p - origin)
		_normals.append(normal)
		_colors.append(color)
	_uvs.append_array([uv0, uv0 + Vector2(uv_size.x, 0.0), uv0 + uv_size, uv0 + Vector2(0.0, uv_size.y)])
	_indices.append_array([base, base + 2, base + 1, base, base + 3, base + 2])


## Kasten um center (Größe size: x quer, y hoch, z entlang forward)
func box(center: Vector3, size: Vector3, forward: Vector3, origin: Vector3) -> void:
	var f := forward.normalized() * size.z * 0.5
	var r := Vector3.UP.cross(forward).normalized() * size.x * 0.5
	var u := Vector3.UP * size.y * 0.5
	var corners: Array[Vector3] = []
	for k in 8:
		corners.append(center + (r if k & 1 else -r) + (u if k & 2 else -u) + (f if k & 4 else -f))
	for face: Array in [[0, 4, 6, 2], [1, 3, 7, 5], [2, 6, 7, 3], [0, 1, 5, 4], [4, 5, 7, 6], [0, 2, 3, 1]]:
		quad(corners[face[0]], corners[face[1]], corners[face[2]], corners[face[3]], origin, Vector2.ZERO, Vector2.ONE)


func arrays() -> Array:
	if _indices.is_empty():
		return []
	var result: Array = []
	result.resize(Mesh.ARRAY_MAX)
	result[Mesh.ARRAY_VERTEX] = _verts
	result[Mesh.ARRAY_NORMAL] = _normals
	result[Mesh.ARRAY_TEX_UV] = _uvs
	result[Mesh.ARRAY_COLOR] = _colors
	result[Mesh.ARRAY_INDEX] = _indices
	return result


## Dreieck a-b-c (für Zeltwände, Segel, Dächer)
func triangle(a: Vector3, b: Vector3, c: Vector3, origin: Vector3) -> void:
	var normal := (b - a).cross(c - a).normalized()
	var base := _verts.size()
	for p: Vector3 in [a, b, c]:
		_verts.append(p - origin)
		_normals.append(normal)
		_colors.append(color)
	_uvs.append_array([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE])
	_indices.append_array([base, base + 2, base + 1])


## Balken von a nach b (quadratischer Querschnitt mit Kantenlänge thickness), z. B. Seile, Stützen
func beam(a: Vector3, b: Vector3, thickness: float, origin: Vector3) -> void:
	var along := b - a
	if along.length() < 0.01:
		return
	var dir := along.normalized()
	var side := dir.cross(Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT).normalized() * thickness * 0.5
	var up := side.cross(dir).normalized() * thickness * 0.5
	var corners := [a - side - up, a + side - up, a + side + up, a - side + up]
	for k in 4:
		var c0: Vector3 = corners[k]
		var c1: Vector3 = corners[(k + 1) % 4]
		quad(c0, c1, c1 + along, c0 + along, origin, Vector2.ZERO, Vector2.ONE)


func is_empty() -> bool:
	return _indices.is_empty()
