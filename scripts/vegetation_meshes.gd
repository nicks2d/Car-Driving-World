class_name VegetationMeshes
extends RefCounted
## Baut die Modelle für Bäume, Büsche, Felsen und Gras im Code (keine Downloads nötig).
## Alle Modelle sind 1 Einheit hoch und werden pro Exemplar skaliert.
## Farben stecken in den Punktfarben (Vertex Colors), die Shader färben sie noch leicht um.
## Von Bäumen gibt es drei Versionen: sehr detailliert (nah: Stamm mit Rinde, Äste, viele Blattbüschel
## bzw. Astetagen), mittel (die bisherige nahe Version) und einfach (fern, Rückfall ohne Impostor).
## UV.x = 1 heißt Rinde (Stamm und Äste): foliage.gdshader zeichnet dort Borke.

const TRUNK_COLOR := Color(0.22, 0.16, 0.11)
const NEEDLE_DARK := Color(0.05, 0.11, 0.05)
const NEEDLE_LIGHT := Color(0.13, 0.23, 0.10)
const LEAF_DARK := Color(0.10, 0.18, 0.05)
const LEAF_LIGHT := Color(0.26, 0.38, 0.10)
const REED_GREEN := Color(0.22, 0.32, 0.10)
const REED_TOP := Color(0.42, 0.33, 0.16)

var _verts := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()
var _uvs := PackedVector2Array()
var _indices := PackedInt32Array()
var _rng := RandomNumberGenerator.new()


# ---------------------------------------------------------------------------
# Bäume
# ---------------------------------------------------------------------------

## Sehr detaillierte Fichte (nah): Stamm mit Wurzelanlauf, 12 Astetagen aus je 9–11 hängenden
## Zweigbüscheln (flache, gezackte Kegelstücke), oben eine Spitze
static func conifer_near() -> ArrayMesh:
	var b := VegetationMeshes.new()
	b._rng.seed = 13
	b._cylinder(Vector3.ZERO, 0.03, 0.012, 0.9, 8, TRUNK_COLOR, true)
	b._cylinder(Vector3.ZERO, 0.045, 0.028, 0.06, 8, TRUNK_COLOR.darkened(0.1), true)
	var tiers := 12
	for i in tiers:
		var t := float(i) / (tiers - 1)
		var y := 0.16 + t * 0.7
		var radius := lerpf(0.24, 0.05, t) * b._rng.randf_range(0.9, 1.1)
		var twigs := 11 - roundi(t * 4.0)
		var twist := b._rng.randf() * TAU
		for k in twigs:
			var angle := twist + TAU * k / twigs + b._rng.randf_range(-0.15, 0.15)
			b._twig(Vector3(0.0, y, 0.0), angle, radius * b._rng.randf_range(0.8, 1.1), TAU / twigs * 0.75,
				lerpf(0.09, 0.05, t))
	b._cone(Vector3(0.0, 0.84, 0.0), 0.06, 1.0, 7, NEEDLE_DARK, NEEDLE_LIGHT, 0.2)
	return b._finish()


## Sehr detaillierter Laubbaum (nah): Stamm mit Rinde, 5 Hauptäste mit Seitenästen, Krone aus 16
## kleineren Blattbüscheln an den Astenden (Lücken zwischen ihnen zeigen die Äste)
static func broadleaf_near() -> ArrayMesh:
	var b := VegetationMeshes.new()
	b._rng.seed = 29
	b._cylinder(Vector3.ZERO, 0.04, 0.026, 0.48, 8, TRUNK_COLOR, true)
	b._cylinder(Vector3.ZERO, 0.055, 0.038, 0.05, 8, TRUNK_COLOR.darkened(0.1), true)
	var crown := Vector3(0.0, 0.64, 0.0)
	var tips: Array[Vector3] = []
	for k in 5:
		var angle := TAU * k / 5.0 + b._rng.randf_range(-0.3, 0.3)
		var start := Vector3(0.0, b._rng.randf_range(0.36, 0.48), 0.0)
		var dir := Vector3(cos(angle) * 0.75, 1.0, sin(angle) * 0.75).normalized()
		var length := b._rng.randf_range(0.26, 0.34)
		var tip := start + dir * length
		b._branch(start, tip, 0.017, 0.006)
		tips.append(tip)
		# Ein Seitenast zur Seite
		var side_dir := (dir + Vector3(cos(angle + 1.2), -0.1, sin(angle + 1.2)) * 0.6).normalized()
		var mid := start + dir * length * 0.5
		var side_tip := mid + side_dir * length * 0.55
		b._branch(mid, side_tip, 0.009, 0.004)
		tips.append(side_tip)
	# Blattbüschel: an jedem Astende und dazwischen in der Krone
	for tip in tips:
		b._blob(tip + Vector3(0.0, 0.03, 0.0), Vector3.ONE * b._rng.randf_range(0.1, 0.14), 1, crown, 0.22)
	for k in 6:
		var a := b._rng.randf() * TAU
		var p := crown + Vector3(cos(a) * 0.15, b._rng.randf_range(0.0, 0.22), sin(a) * 0.15)
		b._blob(p, Vector3.ONE * b._rng.randf_range(0.11, 0.15), 1, crown, 0.22)
	return b._finish()


## Schilf am Ufer: 34 dünne, fast senkrechte Halme mit braunen Kolben oben (1 Einheit hoch)
static func reed() -> ArrayMesh:
	var b := VegetationMeshes.new()
	b._rng.seed = 41
	for i in 34:
		var angle := b._rng.randf() * TAU
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * b._rng.randf_range(0.0, 0.3)
		var height := b._rng.randf_range(0.6, 1.0)
		var lean := Vector3(cos(angle), 0.0, sin(angle)) * b._rng.randf_range(0.02, 0.1)
		var side := Vector3(-sin(angle), 0.0, cos(angle)) * 0.012
		var top := offset + lean + Vector3(0.0, height, 0.0)
		var base := b._verts.size()
		b._verts.append_array([offset - side, offset + side, top - side * 0.3, top + side * 0.3])
		for k in 4:
			b._normals.append((Vector3(cos(angle), 0.0, sin(angle)) + Vector3.UP * 0.3).normalized())
		b._colors.append_array([REED_GREEN.darkened(0.3), REED_GREEN.darkened(0.3), REED_GREEN, REED_GREEN])
		b._uvs.append_array([Vector2(0, 0), Vector2(0, 0), Vector2(0, 1), Vector2(0, 1)])
		b._indices.append_array([base, base + 2, base + 1, base + 1, base + 2, base + 3,
			base, base + 1, base + 2, base + 1, base + 3, base + 2])
		# Jeder dritte Halm mit Kolben
		if i % 3 == 0:
			b._cylinder(top - Vector3(0.0, 0.12, 0.0), 0.018, 0.016, 0.1, 4, REED_TOP)
	return b._finish()


## Fichte (mittel, fern): Stamm und 7 übereinander liegende, ausgefranste Kegel
static func conifer(detailed: bool) -> ArrayMesh:
	var b := VegetationMeshes.new()
	b._rng.seed = 11
	if detailed:
		b._cylinder(Vector3.ZERO, 0.022, 0.016, 0.3, 6, TRUNK_COLOR, true)
		var tiers := 7
		for i in tiers:
			var t := float(i) / (tiers - 1)
			var bottom := 0.14 + t * 0.66
			var radius := lerpf(0.22, 0.05, t)
			b._cone(Vector3(0.0, bottom, 0.0), radius, bottom + lerpf(0.26, 0.2, t), 12, NEEDLE_DARK, NEEDLE_LIGHT, 0.18)
	else:
		b._cone(Vector3(0.0, 0.12, 0.0), 0.2, 1.0, 7, NEEDLE_DARK, NEEDLE_LIGHT, 0.0)
	return b._finish()


## Laubbaum (mittel, fern): Stamm und eine Krone aus mehreren unregelmäßigen Kugeln
static func broadleaf(detailed: bool) -> ArrayMesh:
	var b := VegetationMeshes.new()
	b._rng.seed = 23
	if detailed:
		b._cylinder(Vector3.ZERO, 0.035, 0.022, 0.5, 6, TRUNK_COLOR, true)
		var crown := Vector3(0.0, 0.62, 0.0)
		b._blob(crown, Vector3(0.3, 0.27, 0.3), 1, crown, 0.18)
		b._blob(crown + Vector3(0.16, 0.08, 0.05), Vector3(0.17, 0.16, 0.17), 0, crown, 0.15)
		b._blob(crown + Vector3(-0.13, 0.1, -0.1), Vector3(0.16, 0.15, 0.16), 0, crown, 0.15)
		b._blob(crown + Vector3(0.02, 0.2, -0.04), Vector3(0.15, 0.13, 0.15), 0, crown, 0.15)
	else:
		var crown := Vector3(0.0, 0.62, 0.0)
		b._cylinder(Vector3.ZERO, 0.03, 0.03, 0.4, 4, TRUNK_COLOR)
		b._blob(crown, Vector3(0.32, 0.3, 0.32), 0, crown, 0.1)
	return b._finish()


## Busch: zwei kleine Laub-Kugeln am Boden
static func bush() -> ArrayMesh:
	var b := VegetationMeshes.new()
	b._rng.seed = 37
	var center := Vector3(0.0, 0.35, 0.0)
	b._blob(center, Vector3(0.6, 0.45, 0.6), 0, center, 0.2)
	b._blob(center + Vector3(0.3, 0.05, 0.2), Vector3(0.4, 0.35, 0.4), 0, center, 0.2)
	return b._finish()


## Fels: unregelmäßig verformte, etwas flache Kugel (seed = Form)
static func rock(seed_value: int) -> ArrayMesh:
	var b := VegetationMeshes.new()
	b._rng.seed = seed_value
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 1.6
	var start := b._verts.size()
	b._icosphere(Vector3(0.0, 0.25, 0.0), Vector3(0.5, 0.35, 0.5), 2, Color(0.5, 0.5, 0.5))
	# Punkte unregelmäßig nach innen/außen schieben, Unterseite flach
	for i in range(start, b._verts.size()):
		var v := b._verts[i]
		var dir := (v - Vector3(0.0, 0.25, 0.0)).normalized()
		v += dir * noise.get_noise_3dv(dir * 2.0) * 0.18
		v.y = maxf(v.y, 0.0)
		b._verts[i] = v
	b._recalculate_normals(start)
	return b._finish()


# ---------------------------------------------------------------------------
# Gras
# ---------------------------------------------------------------------------

## Grasbüschel aus einzelnen, leicht gebogenen Halmen. UV.y = Höhe am Halm (für Wind und Farbe)
static func grass_clump() -> ArrayMesh:
	var b := VegetationMeshes.new()
	b._rng.seed = 5
	for i in 14:
		var angle := b._rng.randf() * TAU
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * b._rng.randf_range(0.0, 0.18)
		var height := b._rng.randf_range(0.55, 1.0)
		var lean := Vector3(cos(angle + 1.0), 0.0, sin(angle + 1.0)) * b._rng.randf_range(0.08, 0.3)
		var side := Vector3(-sin(angle), 0.0, cos(angle)) * 0.022
		var base := b._verts.size()
		var mid := offset + lean * 0.4 + Vector3(0.0, height * 0.55, 0.0)
		var tip := offset + lean + Vector3(0.0, height, 0.0)
		b._verts.append_array([offset - side, offset + side, mid - side * 0.6, mid + side * 0.6, tip])
		for k in 5:
			b._normals.append(Vector3.UP)
			b._colors.append(Color.WHITE)
		b._uvs.append_array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 0.55), Vector2(1, 0.55), Vector2(0.5, 1.0)])
		b._indices.append_array([base, base + 2, base + 1, base + 1, base + 2, base + 3, base + 2, base + 4, base + 3])
	return b._finish()


# ---------------------------------------------------------------------------
# Bausteine
# ---------------------------------------------------------------------------

## Dreieck (a, b, c) so einfügen, dass die Vorderseite in Richtung outward zeigt
func _tri(a: int, b: int, c: int, outward: Vector3) -> void:
	if (_verts[c] - _verts[a]).cross(_verts[b] - _verts[a]).dot(outward) >= 0.0:
		_indices.append_array([a, b, c])
	else:
		_indices.append_array([a, c, b])


func _cylinder(base: Vector3, r_bottom: float, r_top: float, height: float, sides: int, color: Color,
		bark: bool = false) -> void:
	var start := _verts.size()
	var u := 1.0 if bark else 0.0
	for i in sides:
		var angle := TAU * i / sides
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		_verts.append_array([base + dir * r_bottom, base + dir * r_top + Vector3(0.0, height, 0.0)])
		_normals.append_array([dir, dir])
		_colors.append_array([color.darkened(0.2), color])
		_uvs.append_array([Vector2(u, 0.0), Vector2(u, 1.0)])
	for i in sides:
		var a := start + i * 2
		var b := start + ((i + 1) % sides) * 2
		var outward := _normals[a]
		_tri(a, b, a + 1, outward)
		_tri(b, b + 1, a + 1, outward)


## Ast als schräger Kegelstumpf (5 Seiten) von a nach b, mit Rinde
func _branch(a: Vector3, b: Vector3, r_a: float, r_b: float) -> void:
	var axis := (b - a).normalized()
	var side := axis.cross(Vector3.UP if absf(axis.y) < 0.95 else Vector3.RIGHT).normalized()
	var up := side.cross(axis).normalized()
	var start := _verts.size()
	var sides := 5
	for i in sides:
		var angle := TAU * i / sides
		var dir := side * cos(angle) + up * sin(angle)
		_verts.append_array([a + dir * r_a, b + dir * r_b])
		_normals.append_array([dir, dir])
		_colors.append_array([TRUNK_COLOR.darkened(0.1), TRUNK_COLOR])
		_uvs.append_array([Vector2(1.0, 0.0), Vector2(1.0, 1.0)])
	for i in sides:
		var p := start + i * 2
		var q := start + ((i + 1) % sides) * 2
		_tri(p, q, p + 1, _normals[p])
		_tri(q, q + 1, p + 1, _normals[p])


## Zweigbüschel einer Fichten-Etage: flaches, gezacktes Kegelstück vom Stamm (Höhe y) nach außen,
## hängt zur Spitze hin nach unten. angle = Richtung, spread = Breite (Winkel), thickness = Dicke oben
func _twig(center: Vector3, angle: float, length: float, spread: float, thickness: float) -> void:
	var start := _verts.size()
	var root := center + Vector3(0.0, thickness, 0.0)
	_verts.append(root)
	_normals.append(Vector3.UP)
	_colors.append(NEEDLE_DARK)
	_uvs.append(Vector2(0.0, 0.5))
	var steps := 4
	for k in steps + 1:
		var a := angle - spread * 0.5 + spread * k / steps
		var dir := Vector3(cos(a), 0.0, sin(a))
		var reach := length * (1.0 if k % 2 == 0 else 0.82) * _rng.randf_range(0.9, 1.05)
		var droop := -length * (0.38 if k % 2 == 0 else 0.25)
		_verts.append(center + dir * reach + Vector3(0.0, droop, 0.0))
		_normals.append((dir + Vector3(0.0, 0.8, 0.0)).normalized())
		_colors.append(NEEDLE_DARK.lerp(NEEDLE_LIGHT, _rng.randf_range(0.35, 0.9)))
		_uvs.append(Vector2(0.0, 0.0))
	# Unterseite: Punkt unter der Wurzel
	var below := _verts.size()
	_verts.append(center - Vector3(0.0, thickness * 0.5, 0.0))
	_normals.append(Vector3.DOWN)
	_colors.append(NEEDLE_DARK.darkened(0.35))
	_uvs.append(Vector2(0.0, 0.0))
	var out := Vector3(cos(angle), 0.4, sin(angle))
	for k in steps:
		_tri(start, start + 1 + k, start + 2 + k, out)
		_tri(below, start + 1 + k, start + 2 + k, Vector3.DOWN)


## Kegel mit ausgefranstem unteren Rand (Nadelbaum-Etage), mit Unterseite
func _cone(base: Vector3, radius: float, top_y: float, sides: int, dark: Color, light: Color, jag: float) -> void:
	var start := _verts.size()
	var apex := Vector3(0.0, top_y, 0.0)
	_verts.append(apex)
	_normals.append(Vector3.UP)
	_colors.append(light)
	_uvs.append(Vector2(0.5, 1.0))
	var center_below := base + Vector3(0.0, 0.03, 0.0)
	_verts.append(center_below)
	_normals.append(Vector3.DOWN)
	_colors.append(dark.darkened(0.3))
	_uvs.append(Vector2(0.5, 0.0))
	for i in sides:
		var angle := TAU * i / sides + _rng.randf_range(-0.15, 0.15)
		var r := radius * (1.0 + _rng.randf_range(-jag, jag))
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		# Jede zweite Spitze hängt etwas tiefer: wirkt wie Zweige
		var droop := -radius * 0.25 if i % 2 == 0 else 0.0
		_verts.append(base + dir * r + Vector3(0.0, droop, 0.0))
		# Weiche Normale schräg nach außen oben: das Licht fällt sanft über den Baum
		_normals.append((dir + Vector3(0.0, 0.7, 0.0)).normalized())
		_colors.append(dark.lerp(light, _rng.randf_range(0.3, 0.8)))
		_uvs.append(Vector2(float(i) / sides, 0.0))
	for i in sides:
		var a := start + 2 + i
		var b := start + 2 + (i + 1) % sides
		var dir := Vector3(_verts[a].x + _verts[b].x, 0.0, _verts[a].z + _verts[b].z).normalized()
		_tri(start, a, b, dir + Vector3.UP * 0.3)
		_tri(start + 1, a, b, Vector3.DOWN)


## Unregelmäßige Laub-Kugel; Normalen zeigen vom Kronenmittelpunkt weg (weiche Beleuchtung)
func _blob(center: Vector3, size: Vector3, subdivisions: int, crown_center: Vector3, jitter: float) -> void:
	var start := _verts.size()
	_icosphere(center, size, subdivisions, LEAF_DARK)
	for i in range(start, _verts.size()):
		var v := _verts[i]
		var dir := (v - center).normalized()
		v += dir * _rng.randf_range(-jitter, jitter) * size.x
		_verts[i] = v
		_normals[i] = (v - crown_center + Vector3(0.0, 0.05, 0.0)).normalized()
		# Oben und außen heller, unten dunkler
		var light_amount := clampf(0.5 + _normals[i].y * 0.4 + _rng.randf_range(-0.15, 0.15), 0.0, 1.0)
		_colors[i] = LEAF_DARK.lerp(LEAF_LIGHT, light_amount)


## Ikosaeder (20 Dreiecke), optional verfeinert, gestreckt auf size
func _icosphere(center: Vector3, size: Vector3, subdivisions: int, color: Color) -> void:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var points: Array[Vector3] = [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var faces: Array[Vector3i] = [
		Vector3i(0, 11, 5), Vector3i(0, 5, 1), Vector3i(0, 1, 7), Vector3i(0, 7, 10), Vector3i(0, 10, 11),
		Vector3i(1, 5, 9), Vector3i(5, 11, 4), Vector3i(11, 10, 2), Vector3i(10, 7, 6), Vector3i(7, 1, 8),
		Vector3i(3, 9, 4), Vector3i(3, 4, 2), Vector3i(3, 2, 6), Vector3i(3, 6, 8), Vector3i(3, 8, 9),
		Vector3i(4, 9, 5), Vector3i(2, 4, 11), Vector3i(6, 2, 10), Vector3i(8, 6, 7), Vector3i(9, 8, 1)]
	for i in points.size():
		points[i] = points[i].normalized()
	for s in subdivisions:
		var new_faces: Array[Vector3i] = []
		var midpoints := {}
		for f in faces:
			var ab := _midpoint(points, midpoints, f.x, f.y)
			var bc := _midpoint(points, midpoints, f.y, f.z)
			var ca := _midpoint(points, midpoints, f.z, f.x)
			new_faces.append_array([Vector3i(f.x, ab, ca), Vector3i(f.y, bc, ab), Vector3i(f.z, ca, bc), Vector3i(ab, bc, ca)])
		faces = new_faces
	var start := _verts.size()
	for p in points:
		_verts.append(center + p * size)
		_normals.append(p)
		_colors.append(color)
		_uvs.append(Vector2(0.5, p.y * 0.5 + 0.5))
	for f in faces:
		var outward := points[f.x] + points[f.y] + points[f.z]
		_tri(start + f.x, start + f.y, start + f.z, outward)


func _midpoint(points: Array[Vector3], cache: Dictionary, a: int, b: int) -> int:
	var key := Vector2i(mini(a, b), maxi(a, b))
	if cache.has(key):
		return cache[key]
	points.append(((points[a] + points[b]) * 0.5).normalized())
	cache[key] = points.size() - 1
	return points.size() - 1


## Normalen aus den angrenzenden Dreiecken neu berechnen (nach dem Verformen)
func _recalculate_normals(start: int) -> void:
	var sums := PackedVector3Array()
	sums.resize(_verts.size() - start)
	for i in range(0, _indices.size(), 3):
		var a := _indices[i]
		var b := _indices[i + 1]
		var c := _indices[i + 2]
		if a < start:
			continue
		var n := (_verts[c] - _verts[a]).cross(_verts[b] - _verts[a])
		sums[a - start] += n
		sums[b - start] += n
		sums[c - start] += n
	for i in sums.size():
		_normals[start + i] = sums[i].normalized()


func _finish() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_INDEX] = _indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
