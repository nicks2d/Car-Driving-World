class_name LotMesh
extends RefCounted
## Sammelt die Ausstattung einer Raststätte (Markierungen, Inseln mit Bordstein, Gehwege,
## Leitplanke, Laternen, Bänke, Baumstämme) und baut daraus ein Mesh mit einer Fläche pro
## Material (wenige Draw Calls). Lage in Parkplatz-Koordinaten: along in Fahrtrichtung t,
## across von der Autobahn weg r, beides in Metern ab der Ecke o (Bezugspunkt des Meshes).
## Inseln, Gehwege und Leitplanke bekommen Kollisionsformen im übergebenen StaticBody3D.

var _o: Vector3
var _t: Vector3
var _r: Vector3
## Je Material: [Punkte, Normalen, Indizes]
var _parts: Dictionary = {}


func _init(origin: Vector3, travel: Vector3, side: Vector3) -> void:
	_o = origin
	_t = travel
	_r = side


func point(along: float, across: float, y: float) -> Vector3:
	return _o + _t * along + _r * across + Vector3.UP * y


## Weiße Markierung: flaches Rechteck (Länge la in Richtung angle, Breite lc) knapp über dem Asphalt
func rect(along: float, across: float, la: float, lc: float, angle: float, y: float) -> void:
	var u := _t * cos(angle) + _r * sin(angle)
	var v := -_t * sin(angle) + _r * cos(angle)
	var c := point(along, across, y)
	var hu := u * la * 0.5
	var hv := v * lc * 0.5
	_quad("line", c - hu - hv, c + hu - hv, c + hu + hv, c - hu + hv, Vector3.UP)


## Pfeil in Fahrtrichtung (Schaft 3 m, Spitze bei along + 1,5)
func arrow(along: float, across: float) -> void:
	rect(along, across, 3.0, 0.2, 0.0, 0.015)
	for s: float in [1.0, -1.0]:
		var dir := Vector2(-cos(0.6), s * sin(0.6))
		rect(along + 1.5 + dir.x * 0.6, across + dir.y * 0.6, 1.2, 0.2, atan2(dir.y, dir.x), 0.015)


## Erhöhter Block (Insel, Gehweg): oben Material top_key, Seiten Bordstein, mit Kollision
func block(along: float, across: float, la: float, lc: float, angle: float, height: float, top_key: String,
		body: StaticBody3D) -> void:
	box(along, across, la, lc, angle, 0.0, height, top_key, "curb")
	_collision(body, along, across, la, lc, angle, 0.0, height)


## Kasten von y0 bis y1 (Oberseite top_key, Seiten side_key, leer = wie oben)
func box(along: float, across: float, la: float, lc: float, angle: float, y0: float, y1: float, top_key: String,
		side_key: String = "") -> void:
	var u := _t * cos(angle) + _r * sin(angle)
	var v := -_t * sin(angle) + _r * cos(angle)
	_box_at(point(along, across, 0.0), u, v, la, lc, y0, y1, top_key, side_key if side_key != "" else top_key)


## Senkrechter Pfosten (quadratisch) ab foot (Mesh-Koordinaten)
func post(foot: Vector3, thickness: float, height: float, key: String) -> void:
	_box_at(foot, _t, _r, thickness, thickness, 0.0, height, key, key)


## Leitplanke längs bei across von along a0 bis a1, Pfosten alle 4 m, mit Kollision
func rail(a0: float, a1: float, across: float, body: StaticBody3D) -> void:
	box((a0 + a1) * 0.5, across, a1 - a0, 0.08, 0.0, 0.45, 0.75, "steel")
	var a := a0
	while a <= a1:
		box(a, across + 0.1, 0.12, 0.12, 0.0, 0.0, 0.72, "steel")
		a += 4.0
	_collision(body, (a0 + a1) * 0.5, across, a1 - a0, 0.3, 0.0, 0.0, 0.8)


## Laterne: Mast 7 m, Ausleger in Richtung arm (+1 = weg von der Autobahn), Leuchte
func lantern(along: float, across: float, arm: float) -> void:
	box(along, across, 0.16, 0.16, 0.0, 0.0, 7.0, "steel")
	box(along, across + arm * 0.6, 0.18, 1.3, 0.0, 6.9, 7.0, "steel")
	box(along, across + arm * 1.2, 0.35, 0.9, 0.0, 6.79, 6.91, "lamp_glow")


## Mesh mit einer Fläche pro Material (Materialien von network._sign_material)
func commit(network: Node) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	for key: String in _parts:
		var part: Array = _parts[key]
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = part[0]
		arrays[Mesh.ARRAY_NORMAL] = part[1]
		arrays[Mesh.ARRAY_INDEX] = part[2]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, network.call("_sign_material", key))
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	return instance


func _box_at(foot: Vector3, u: Vector3, v: Vector3, la: float, lc: float, y0: float, y1: float, top_key: String,
		side_key: String) -> void:
	var hu := u * la * 0.5
	var hv := v * lc * 0.5
	var lo := Vector3.UP * y0
	var hi := Vector3.UP * y1
	var corners: Array[Vector3] = [foot - hu - hv, foot + hu - hv, foot + hu + hv, foot - hu + hv]
	_quad(top_key, corners[0] + hi, corners[1] + hi, corners[2] + hi, corners[3] + hi, Vector3.UP)
	for k in 4:
		var a := corners[k]
		var b := corners[(k + 1) % 4]
		var normal := ((a + b) * 0.5 - foot).normalized()
		_quad(side_key, a + lo, b + lo, b + hi, a + hi, normal)


func _quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	if not _parts.has(key):
		_parts[key] = [PackedVector3Array(), PackedVector3Array(), PackedInt32Array()]
	var part: Array = _parts[key]
	var verts: PackedVector3Array = part[0]
	var normals: PackedVector3Array = part[1]
	var indices: PackedInt32Array = part[2]
	var base := verts.size()
	verts.append_array([a, b, c, d])
	normals.append_array([normal, normal, normal, normal])
	# Godot: Vorderseite im Uhrzeigersinn (von der Seite der Normale aus gesehen)
	if (c - a).cross(b - a).dot(normal) >= 0.0:
		indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	else:
		indices.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
	part[0] = verts
	part[1] = normals
	part[2] = indices


func _collision(body: StaticBody3D, along: float, across: float, la: float, lc: float, angle: float, y0: float,
		y1: float) -> void:
	var u := _t * cos(angle) + _r * sin(angle)
	var v := -_t * sin(angle) + _r * cos(angle)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(la, y1 - y0, lc)
	shape.shape = box_shape
	shape.transform = Transform3D(Basis(u, Vector3.UP, v), point(along, across, (y0 + y1) * 0.5))
	body.add_child(shape)
