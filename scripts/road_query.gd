class_name RoadQuery
extends RefCounted
## Schnelle Antwort auf „Wie weit ist die nächste Straße und wie hoch liegt sie?“
## für einen bestimmten Bereich (z. B. eine Gelände-Kachel). Dafür werden alle kurzen
## Straßenstücke in ein grobes Raster einsortiert. Läuft in Hintergrund-Threads.

const CELL: float = 24.0

## So weit reicht der Einfluss einer Straße seitlich höchstens
var reach: float
var _a := PackedVector3Array()
var _b := PackedVector3Array()
## Halbe Breite des flachen Teils (Fahrbahn + Bankett) pro Stück
var _core := PackedFloat32Array()
var _cells: Dictionary = {}  # Vector2i -> Array von Stück-Nummern


## segments: fertige RoadSegments, pads: Mittelpunkte der Kreuzungen, area: gefragter Bereich
func _init(segments: Array, pads: PackedVector3Array, pad_radius: float, area: Rect2) -> void:
	reach = 0.0
	var grown := area.grow(RoadSegment.MAX_BANK + 15.0)
	for segment: RoadSegment in segments:
		var core := segment.road_width * 0.5 + segment.shoulder_width + 0.5
		reach = maxf(reach, core + RoadSegment.MAX_BANK)
		for i in segment.points.size() - 1:
			_add_piece(segment.points[i], segment.points[i + 1], core, grown)
	for pad in pads:
		reach = maxf(reach, pad_radius + RoadSegment.MAX_BANK)
		_add_piece(pad, pad, pad_radius, grown)


func _add_piece(a: Vector3, b: Vector3, core: float, area: Rect2) -> void:
	var box := Rect2(a.x, a.z, 0.0, 0.0).expand(Vector2(b.x, b.z)).grow(core + RoadSegment.MAX_BANK)
	if not box.intersects(area):
		return
	var index := _a.size()
	_a.append(a)
	_b.append(b)
	_core.append(core)
	var c0 := Vector2i(floori(box.position.x / CELL), floori(box.position.y / CELL))
	var c1 := Vector2i(floori(box.end.x / CELL), floori(box.end.y / CELL))
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var cell := Vector2i(cx, cz)
			if not _cells.has(cell):
				_cells[cell] = []
			_cells[cell].append(index)


func is_empty() -> bool:
	return _a.is_empty()


## Gelände an die Straße anpassen. Gibt (neue Höhe, Nähe zur Straße 0..1) zurück.
func carve(x: float, z: float, natural: float) -> Vector2:
	var pieces: Array = _cells.get(Vector2i(floori(x / CELL), floori(z / CELL)), [])
	if pieces.is_empty():
		return Vector2(natural, 0.0)
	var best_over := INF
	var best_height := 0.0
	for index: int in pieces:
		var a := _a[index]
		var b := _b[index]
		var abx := b.x - a.x
		var abz := b.z - a.z
		var apx := x - a.x
		var apz := z - a.z
		var len_sq := abx * abx + abz * abz
		var t := 0.0
		if len_sq > 0.0001:
			t = clampf((apx * abx + apz * abz) / len_sq, 0.0, 1.0)
		var dx := apx - abx * t
		var dz := apz - abz * t
		# Wie weit liegt der Punkt außerhalb des flachen Teils?
		var over := sqrt(dx * dx + dz * dz) - _core[index]
		if over < best_over:
			best_over = over
			best_height = lerpf(a.y, b.y, t)
	if best_over > RoadSegment.MAX_BANK:
		return Vector2(natural, 0.0)
	# Gelände knapp unter die Fahrbahn legen und mit einer Böschung (ca. 1 : 1,5) anschließen
	var target := best_height - 0.3
	var bank := clampf(absf(natural - target) * 1.5, 2.0, RoadSegment.MAX_BANK)
	var proximity := 1.0 - smoothstep(0.0, 5.0, best_over)
	if best_over <= 0.0:
		return Vector2(target, 1.0)
	return Vector2(lerpf(target, natural, smoothstep(0.0, bank, best_over)), proximity)


## Liegt hier Straße (inklusive kleinem Rand)? Für Bäume und Felsen.
func is_on_road(x: float, z: float, margin: float) -> bool:
	var pieces: Array = _cells.get(Vector2i(floori(x / CELL), floori(z / CELL)), [])
	for index: int in pieces:
		var a := _a[index]
		var b := _b[index]
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var ap := Vector2(x - a.x, z - a.z)
		var t := clampf(ap.dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		if (ap - ab * t).length() < _core[index] + margin:
			return true
	return false
