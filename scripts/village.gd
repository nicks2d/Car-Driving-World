class_name Village
extends RefCounted
## Ein kleines Dorf an einem Ort: 3–8 Häuser (selten 10–12) an den Straßen, die vom Ort
## wegführen, mit Satteldach, Garten und Zaun, ab und zu eine Scheune. Dazu Straßenlaternen
## entlang dieser Straßen und gelbe Ortsschilder an den Ortseingängen.
##
## plan() läuft im Hintergrund (WorkerThreadPool): Lage der Häuser, Mesh (wenige Flächen pro
## Material für das ganze Dorf), Kollision und die Flächen, die das Gelände unter den Häusern
## einebnen (pads, wie bei Kreuzungen). RoadNetwork baut daraus die Knoten. Alles hängt nur vom
## Ort und den Straßen in der Nähe ab: gleicher Seed = gleiches Dorf.

## So weit von der Ortsmitte stehen höchstens Häuser (Meter entlang der Straße)
const REACH: float = 170.0
## Mögliche Bauplätze entlang jeder Straße (Meter ab der Mitte)
const SLOTS: Array[float] = [30.0, 54.0, 78.0, 102.0, 126.0, 150.0]
## Laternen: Abstand entlang der Straße, Höhe, Abstand vom Fahrbahnrand
const LANTERN_SPACING: float = 32.0
const LANTERN_HEIGHT: float = 6.0
## Wandfarben (hell, leicht verschieden), Dachfarben, Scheune
const WALL_COLORS: Array[Color] = [Color("#EFEBE2"), Color("#E8DCC0"), Color("#F2E6B8"), Color("#D9D6D0"),
	Color("#EAD3C6"), Color("#D7DDD6"), Color("#F4F1EA")]
const ROOF_COLORS: Array[Color] = [Color("#8E3B2C"), Color("#A04A32"), Color("#4A4C52"), Color("#6B3A2E"),
	Color("#3B3D42")]
const BARN_WALL := Color("#6E4A30")
const FENCE_COLOR := Color("#8A6A48")
const DOOR_COLOR := Color("#5A3C28")
const BASE_COLOR := Color("#8D8A84")
const FRAME_COLOR := Color("#F7F6F1")
const SHUTTER_COLORS: Array[Color] = [Color("#3E5E3A"), Color("#6B4A2E"), Color("#7A2E2A"), Color("#4C5F73")]

## Eingaben (vor plan() setzen)
var cell: Vector2i
var center: Vector3
var world_gen: WorldGen
## Straßen am Ort: [RoadSegment, true = beginnt hier]
var arms: Array = []
## Alle fertigen Straßen in der Nähe (Häuser halten Abstand) und weitere Sperrflächen
## (Kreuzung, Parkbuchten: x, y, z, Radius)
var segments: Array = []
var obstacles := PackedVector4Array()

## Ergebnis von plan()
## Häuser: {"position" (Mitte am Boden), "basis", "size" (Breite, Wandhöhe, Tiefe), "barn"}
var houses: Array = []
## Gelände unter den Häusern flach (wie Kreuzungen: x, y, z, Radius)
var pads := PackedVector4Array()
## Lampenköpfe der Straßenlaternen (Welt), für echte Lichter in der Nähe des Autos
var lanterns := PackedVector3Array()
## Ortsschilder: [Fuß (Welt), Fahrtrichtung in den Ort hinein]
var signs: Array = []
## Mesh-Flächen relativ zur Ortsmitte: Material-Schlüssel -> Arrays
var surfaces: Dictionary = {}
## Kollision: [Transform3D (Welt), Größe]
var boxes: Array = []
## Bis wohin (Meter ab der Mitte) reicht das Dorf an jeder Straße? (Index wie arms, 0 = keine Häuser)
var reach_per_arm := PackedFloat32Array()

var task_id: int = -1
var mesh_instance: MeshInstance3D
var body: StaticBody3D

var _query: RoadQuery
var _lakes: Array = []
## Pro Material eine Fläche im Bau
var _data: Dictionary = {}  # Schlüssel -> Surface


## Eine Mesh-Fläche im Bau (eigene Klasse, damit die Packed-Arrays an Ort und Stelle wachsen;
## aus einem Array geholt wären sie nur Kopien)
class Surface:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()


func plan() -> void:
	var rect := Rect2(center.x - REACH - 60.0, center.z - REACH - 60.0, (REACH + 60.0) * 2.0, (REACH + 60.0) * 2.0)
	_query = RoadQuery.new(segments, obstacles, rect)
	_lakes = world_gen.lakes_near(rect)
	var rng := RandomNumberGenerator.new()
	rng.seed = world_gen.hash_cell(cell.x, cell.y, 2207)
	var wanted := rng.randi_range(3, 8)
	if rng.randf() < 0.1:
		wanted = rng.randi_range(10, 12)
	reach_per_arm.resize(arms.size())
	# Bauplätze: nah an der Mitte zuerst, mit etwas Zufall
	var candidates: Array = []
	for a in arms.size():
		for slot in SLOTS:
			for side: float in [1.0, -1.0]:
				candidates.append([slot + rng.randf_range(-5.0, 5.0), a, side, slot + rng.randf() * 45.0])
	candidates.sort_custom(func(x: Array, y: Array) -> bool: return x[3] < y[3])
	for candidate: Array in candidates:
		if houses.size() >= wanted:
			break
		_try_house(candidate[0], candidate[1], candidate[2], rng)
	# Gelände mit den Häusern (für Zäune, Laternen und Schilder)
	var all_pads := obstacles.duplicate()
	all_pads.append_array(pads)
	_query = RoadQuery.new(segments, all_pads, rect)
	for house: Dictionary in houses:
		_build_house(house, rng)
	for a in arms.size():
		if reach_per_arm[a] > 0.0:
			_add_lanterns(a)
			_add_sign(a)
	_finish_surfaces()


## Haus an Straße a, Abstand along von der Mitte, Seite side (+1 = links der Richtung nach außen)
func _try_house(along: float, a: int, side: float, rng: RandomNumberGenerator) -> void:
	var arm: Array = arms[a]
	var segment: RoadSegment = arm[0]
	var n := segment.points.size()
	# Nicht weiter als bis zur Hälfte der Straße (dort beginnt das nächste Dorf)
	if along > segment.total_length() * 0.5 - 30.0:
		return
	var step := roundi(along / RoadSegment.POINT_SPACING)
	var i: int = step if arm[1] else n - 1 - step
	if i < 1 or i > n - 2 or segment.bridge[i] == 1 or segment.tunnel[i] == 1:
		return
	var outward := segment.direction_at(i) * (1.0 if arm[1] else -1.0)
	outward.y = 0.0
	outward = outward.normalized()
	var left := Vector3.UP.cross(outward).normalized()
	var barn := along > 70.0 and rng.randf() < 0.14
	var width := 16.0 if barn else rng.randf_range(8.0, 12.0)
	var depth := 11.0 if barn else rng.randf_range(7.0, 10.0)
	var wall := 5.0 if barn else (3.0 if rng.randf() < 0.45 else 5.6)
	var garden := rng.randf_range(4.0, 8.0)
	var road_edge := segment.road_width * 0.5 + segment.shoulder_width + RoadSegment.VERGE_WIDTH
	var setback := road_edge + garden + depth * 0.5
	var p := segment.points[i]
	var c := p + left * side * setback
	# Front zeigt zur Straße
	var front := -left * side
	var house_basis := Basis(Vector3.UP.cross(front).normalized(), Vector3.UP, front)
	var radius := Vector2(width, depth).length() * 0.5 + 0.8
	# Nicht auf Straßen, Bankett, Kreuzungen, Parkbuchten, anderen Häusern oder im Wasser
	for other: Dictionary in houses:
		var o: Vector3 = other["position"]
		if Vector2(o.x - c.x, o.z - c.z).length() < radius + other["radius"] + 3.0:
			return
	var corners: Array[Vector3] = [c]
	for sx: float in [-0.5, 0.5]:
		for sz: float in [-0.5, 0.5]:
			corners.append(c + house_basis.x * width * sx * 1.15 + house_basis.z * depth * sz * 1.15)
	var natural_center := world_gen.terrain_height(c.x, c.z, _lakes)
	var ground := _query.carve(c.x, c.z, natural_center).x
	for q in corners:
		if _query.is_on_road(q.x, q.z, 1.5):
			return
		var water := world_gen.water_level_at(q.x, q.z, _lakes)
		if water > WorldGen.NO_WATER and water > ground - 2.0:
			return
		# Zu steil: Ecke liegt viel höher oder tiefer als die Mitte
		var h := _query.carve(q.x, q.z, world_gen.terrain_height(q.x, q.z, _lakes)).x
		if absf(h - ground) > 3.0:
			return
	houses.append({"position": Vector3(c.x, ground, c.z), "basis": house_basis, "size": Vector3(width, wall, depth),
		"barn": barn, "radius": radius, "garden": garden})
	# Gelände: 0,3 m unter dem Pad-Wert (wie bei Kreuzungen), also genau auf ground
	pads.append(Vector4(c.x, ground + 0.3, c.z, radius))
	reach_per_arm[a] = maxf(reach_per_arm[a], along + depth * 0.5)


## Höhe des fertigen Geländes (mit Straßen und Häusern)
func _ground(x: float, z: float) -> float:
	return _query.carve(x, z, world_gen.terrain_height(x, z, _lakes)).x


func _build_house(house: Dictionary, rng: RandomNumberGenerator) -> void:
	var b: Basis = house["basis"]
	var size: Vector3 = house["size"]
	var base: Vector3 = house["position"]
	var barn: bool = house["barn"]
	var w := size.x
	var h := size.y
	var d := size.z
	var wall_color := BARN_WALL if barn else WALL_COLORS[rng.randi() % WALL_COLORS.size()]
	var roof_color := ROOF_COLORS[rng.randi() % ROOF_COLORS.size()] if not barn else Color("#55585E")
	# Sockel (reicht in den Boden, falls das Gelände nicht ganz flach ist) und Wände
	_box("wall", base + Vector3.UP * -0.6, b, Vector3(w + 0.2, 1.6, d + 0.2), BASE_COLOR)
	_box("wall", base + Vector3.UP * (0.2 + h * 0.5), b, Vector3(w, h, d), wall_color)
	# Satteldach: First längs (über die Breite) oder quer
	var ridge_along := barn or rng.randf() < 0.7
	var span := d if ridge_along else w
	var length := w if ridge_along else d
	var pitch := deg_to_rad(rng.randf_range(35.0, 45.0)) if not barn else deg_to_rad(30.0)
	var rise := span * 0.5 * tan(pitch)
	var eave := base + Vector3.UP * (0.2 + h)
	var along_axis := b.x if ridge_along else b.z
	var across_axis := b.z if ridge_along else -b.x
	_gable_roof(eave, along_axis, across_axis, length, span, rise, roof_color, wall_color)
	# Kollision: vom Fuß des Sockels (1,4 m im Boden, falls das Gelände an einer Ecke abfällt)
	# bis zur Traufe plus halbes Dach
	var top := 0.2 + h + rise * 0.5
	boxes.append([Transform3D(b, base + Vector3.UP * (top - 1.4) * 0.5), Vector3(w, top + 1.4, d)])
	if barn:
		# Großes Tor vorne
		_quad_on_wall("wall", base, b, Vector3.BACK, w, d, 0.0, 0.2 + 1.8, 4.0, 3.6, DOOR_COLOR)
		return
	# Haustür vorne in der Mitte, Fenster auf allen Seiten, ein oder zwei Geschosse
	_quad_on_wall("wall", base, b, Vector3.BACK, w, d, rng.randf_range(-1.5, 1.5), 0.2 + 1.05, 1.0, 2.1, DOOR_COLOR)
	var floors := 1 if h < 4.0 else 2
	# Fensterrahmen weiß (bei weißen Häusern in Holzfarbe), manche Häuser mit Fensterläden
	var frame_color := FRAME_COLOR if wall_color.get_luminance() < 0.85 else DOOR_COLOR
	var shutters := rng.randf() < 0.4
	var shutter_color := SHUTTER_COLORS[rng.randi() % SHUTTER_COLORS.size()]
	for face: Vector3 in [Vector3.BACK, Vector3.FORWARD, Vector3.RIGHT, Vector3.LEFT]:
		var face_width := w if face.z != 0.0 else d
		var count := maxi(floori((face_width - 1.6) / 2.6), 1)
		for level in floors:
			var y := 0.2 + 1.5 + level * 2.7
			for k in count:
				var x := (k - (count - 1) * 0.5) * 2.6
				# Vorne unten nicht vor die Tür
				if face == Vector3.BACK and level == 0 and absf(x) < 1.6:
					continue
				var lit := rng.randf() < 0.35
				_quad_on_wall("wall", base, b, face, w, d, x, y, 1.26, 1.41, frame_color, 0.02)
				_quad_on_wall("window_lit" if lit else "window", base, b, face, w, d, x, y, 1.1, 1.25, Color.WHITE)
				if shutters:
					for s: float in [-1.0, 1.0]:
						_quad_on_wall("wall", base, b, face, w, d, x + s * 0.92, y, 0.5, 1.3, shutter_color, 0.025)
	# Garten mit Zaun (nicht immer)
	if rng.randf() < 0.7:
		_fence(house)


## Satteldach: zwei schräge Flächen, dazu die dreieckigen Giebel in Wandfarbe
func _gable_roof(eave: Vector3, along: Vector3, across: Vector3, length: float, span: float, rise: float,
		roof_color: Color, wall_color: Color) -> void:
	var over := 0.45
	var half_l := length * 0.5 + over
	var half_s := span * 0.5 + over
	var top := eave + Vector3.UP * rise
	# Traufe etwas tiefer, weil das Dach übersteht
	var drop := over * rise / (span * 0.5)
	for s: float in [1.0, -1.0]:
		var low := eave + across * half_s * s + Vector3.DOWN * drop
		var a := low - along * half_l
		var b := low + along * half_l
		var c := top + along * half_l
		var d := top - along * half_l
		var normal := (across * s * rise + Vector3.UP * span * 0.5).normalized()
		if s > 0.0:
			_quad("roof", a, b, c, d, normal, roof_color)
		else:
			_quad("roof", b, a, d, c, normal, roof_color)
	# Giebel
	for e: float in [1.0, -1.0]:
		var mid := eave + along * length * 0.5 * e
		var p1 := mid + across * span * 0.5
		var p2 := mid - across * span * 0.5
		var p3 := mid + Vector3.UP * rise
		if e > 0.0:
			_triangle("wall", p1, p2, p3, along, wall_color)
		else:
			_triangle("wall", p2, p1, p3, -along, wall_color)


## Fenster oder Tür als Rechteck auf einer Wand. face: Seite im Hauskoordinaten (BACK = vorne,
## zur Straße), x = seitlich auf der Wand, y = Mitte über dem Boden.
func _quad_on_wall(key: String, base: Vector3, b: Basis, face: Vector3, w: float, d: float, x: float, y: float,
		size_x: float, size_y: float, color: Color, lift: float = 0.03) -> void:
	var normal := b * face
	var half_depth := (d if face.z != 0.0 else w) * 0.5 + lift
	# Rechts aus Sicht von jemandem, der auf die Wand schaut
	var side := b * Vector3.UP.cross(face)
	var mid := base + normal * half_depth + Vector3.UP * y + side * x
	var hx := side * size_x * 0.5
	var hy := Vector3.UP * size_y * 0.5
	_quad(key, mid - hx - hy, mid + hx - hy, mid + hx + hy, mid - hx + hy, normal, color)


## Zaun um den Garten: Pfosten alle 2 m, zwei Latten, vorne ein Tor (Lücke)
func _fence(house: Dictionary) -> void:
	var b: Basis = house["basis"]
	var size: Vector3 = house["size"]
	var base: Vector3 = house["position"]
	var garden: float = house["garden"]
	var hx := size.x * 0.5 + 3.0
	var back := -size.z * 0.5 - 3.5
	var front := size.z * 0.5 + garden - 1.0
	var corners: Array[Vector2] = [Vector2(-hx, front), Vector2(hx, front), Vector2(hx, back), Vector2(-hx, back)]
	for e in 4:
		var from := corners[e]
		var to := corners[(e + 1) % 4]
		var length := from.distance_to(to)
		var steps := maxi(ceili(length / 2.0), 1)
		var previous := Vector3.INF
		for k in steps + 1:
			var t := float(k) / steps
			var local := from.lerp(to, t)
			# Tor vorne in der Mitte
			if e == 0 and absf(local.x) < 0.8:
				previous = Vector3.INF
				continue
			var world := base + b.x * local.x + b.z * local.y
			if _query.is_on_road(world.x, world.z, 0.3) or _in_other_house(world, house):
				previous = Vector3.INF
				continue
			world.y = _ground(world.x, world.z)
			_box("wall", world + Vector3.UP * 0.45, Basis(), Vector3(0.1, 1.2, 0.1), FENCE_COLOR)
			if previous != Vector3.INF:
				var mid := (previous + world) * 0.5
				var dir := world - previous
				var rail_basis := Basis.looking_at(dir.normalized()) if dir.length() > 0.01 else Basis()
				for y: float in [0.35, 0.8]:
					_box("wall", mid + Vector3.UP * y, rail_basis, Vector3(0.05, 0.08, dir.length()), FENCE_COLOR)
			previous = world


func _in_other_house(p: Vector3, own: Dictionary) -> bool:
	for house: Dictionary in houses:
		if house == own:
			continue
		var o: Vector3 = house["position"]
		if Vector2(o.x - p.x, o.z - p.z).length() < house["radius"]:
			return true
	return false


## Laternen auf der rechten Seite (von der Mitte nach außen), bis zum letzten Haus
func _add_lanterns(a: int) -> void:
	var arm: Array = arms[a]
	var segment: RoadSegment = arm[0]
	var n := segment.points.size()
	var along := 18.0
	while along <= reach_per_arm[a] + 10.0:
		var step := roundi(along / RoadSegment.POINT_SPACING)
		var i: int = step if arm[1] else n - 1 - step
		along += LANTERN_SPACING
		if i < 1 or i > n - 2 or segment.bridge[i] == 1:
			continue
		var outward := segment.direction_at(i) * (1.0 if arm[1] else -1.0)
		outward.y = 0.0
		var right := outward.normalized().cross(Vector3.UP).normalized()
		var foot := segment.points[i] + right * (segment.road_width * 0.5 + segment.shoulder_width + 0.6)
		if _in_other_house(foot, {}):
			continue
		foot.y = _ground(foot.x, foot.z)
		_box("wall", foot + Vector3.UP * (LANTERN_HEIGHT * 0.5 - 0.3), Basis(), Vector3(0.14, LANTERN_HEIGHT + 0.6, 0.14),
			Color("#6F747A"))
		var arm_basis := Basis.looking_at(-right)
		_box("wall", foot - right * 0.7 + Vector3.UP * LANTERN_HEIGHT, arm_basis, Vector3(0.08, 0.08, 1.4), Color("#6F747A"))
		var head := foot - right * 1.35 + Vector3.UP * (LANTERN_HEIGHT - 0.08)
		_box("lamp", head, arm_basis, Vector3(0.32, 0.12, 0.6), Color.WHITE)
		lanterns.append(head + Vector3.DOWN * 0.2)


## Wie weit (Meter ab der Ortsmitte entlang dieses Abschnitts) steht das Ortsschild?
## -1 = an diesem Abschnitt keins (keine Häuser an dieser Straße)
func sign_reach(segment: RoadSegment) -> float:
	if task_id != -1:
		return -1.0
	for a in arms.size():
		if arms[a][0] == segment and a < reach_per_arm.size() and reach_per_arm[a] > 0.0:
			return minf(reach_per_arm[a] + 18.0, segment.total_length() * 0.5 - 10.0)
	return -1.0


## Ortsschild am Ortseingang, rechts für den Verkehr, der in den Ort hineinfährt
func _add_sign(a: int) -> void:
	var arm: Array = arms[a]
	var segment: RoadSegment = arm[0]
	var n := segment.points.size()
	var along := minf(reach_per_arm[a] + 18.0, segment.total_length() * 0.5 - 10.0)
	var step := roundi(along / RoadSegment.POINT_SPACING)
	var i: int = step if arm[1] else n - 1 - step
	if i < 1 or i > n - 2 or segment.bridge[i] == 1 or segment.tunnel[i] == 1:
		return
	var inward := segment.direction_at(i) * (-1.0 if arm[1] else 1.0)
	inward.y = 0.0
	inward = inward.normalized()
	var right := inward.cross(Vector3.UP).normalized()
	var foot := segment.points[i] + right * (segment.road_width * 0.5 + segment.shoulder_width + 0.8)
	foot.y = _ground(foot.x, foot.z)
	signs.append([foot, inward])


func _box(key: String, at: Vector3, b: Basis, size: Vector3, color: Color) -> void:
	var h := size * 0.5
	for axis in 3:
		for s: float in [1.0, -1.0]:
			var n := Vector3.ZERO
			n[axis] = s
			var u := Vector3.ZERO
			u[(axis + 1) % 3] = 1.0
			var v := Vector3.ZERO
			v[(axis + 2) % 3] = 1.0
			var corners: Array[Vector3] = []
			for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var local := n * h + u * h * c.x + v * h * c.y
				corners.append(at + b * local)
			var normal := (b * n).normalized()
			if s > 0.0:
				_quad(key, corners[0], corners[1], corners[2], corners[3], normal, color)
			else:
				_quad(key, corners[0], corners[3], corners[2], corners[1], normal, color)


## Viereck a-b-c-d (gegen den Uhrzeigersinn von vorne gesehen), Punkte in Weltkoordinaten
func _quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, color: Color) -> void:
	var surface := _surface(key)
	var first := surface.verts.size()
	for p: Vector3 in [a, b, c, d]:
		surface.verts.append(p - center)
		surface.normals.append(normal)
		surface.colors.append(color)
	# Godot zeichnet Dreiecke im Uhrzeigersinn als Vorderseite
	surface.indices.append_array([first, first + 2, first + 1, first, first + 3, first + 2])


## Dreieck a-b-c (gegen den Uhrzeigersinn von vorne gesehen)
func _triangle(key: String, a: Vector3, b: Vector3, c: Vector3, normal: Vector3, color: Color) -> void:
	var surface := _surface(key)
	var first := surface.verts.size()
	for p: Vector3 in [a, b, c]:
		surface.verts.append(p - center)
		surface.normals.append(normal)
		surface.colors.append(color)
	surface.indices.append_array([first, first + 2, first + 1])


func _surface(key: String) -> Surface:
	if not _data.has(key):
		_data[key] = Surface.new()
	return _data[key]


func _finish_surfaces() -> void:
	for key: String in _data:
		var surface: Surface = _data[key]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = surface.verts
		arrays[Mesh.ARRAY_NORMAL] = surface.normals
		arrays[Mesh.ARRAY_COLOR] = surface.colors
		arrays[Mesh.ARRAY_INDEX] = surface.indices
		surfaces[key] = arrays
	_data.clear()
