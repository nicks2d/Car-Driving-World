class_name RoadQuery
extends RefCounted
## Schnelle Antwort auf „Wie weit ist die nächste Straße und wie hoch liegt sie?“
## für einen bestimmten Bereich (z. B. eine Gelände-Kachel). Dafür werden alle kurzen
## Straßenstücke in ein grobes Raster einsortiert. Läuft in Hintergrund-Threads.
## Tunnel verändern das Gelände nicht (der Berg bleibt), nur an den Portalen bekommt es
## ein Loch, wo die Röhre herauskommt.

const CELL: float = 24.0
## So weit hinter dem Portal hat das Gelände über der Röhre noch ein Loch (Meter)
const PORTAL_HOLE: float = 4.0
## Bis so weit hinter dem Portal wachsen über dem Tunnel keine Bäume (Meter)
const PORTAL_KEEPOUT: float = 20.0
## Steigung der Felswand hinter dem Portal (Meter Höhe pro Meter in den Berg hinein)
const PORTAL_FACE_SLOPE: float = 3.0

## So weit reicht der Einfluss einer Straße seitlich höchstens
var reach: float
var _a := PackedVector3Array()
var _b := PackedVector3Array()
## Halbe Breite des flachen Teils (Fahrbahn + Bankett) pro Stück
var _core := PackedFloat32Array()
## Querneigung pro Stück (positiv = linke Seite tiefer)
var _bank := PackedFloat32Array()
## 1 = das Stück passt das Gelände an, 0 = nur Sperrzone (Brücken: darunter bleibt das Tal)
var _carves := PackedByteArray()
## 1 = an diesem Ende gilt auch der Halbkreis davor (an Portalen nicht: dort beginnt der Berg)
var _cap_a := PackedByteArray()
var _cap_b := PackedByteArray()
## Portal-Ebene in der Nähe eines Stücks (Punkt, Richtung aus dem Tunnel hinaus; Richtung 0 =
## keine). Hinter der Ebene (im Berg) wird aus der Böschung eine steile Felswand
## (PORTAL_FACE_SLOPE), so bleibt der Berg über dem Portal stehen.
var _plane_p := PackedVector2Array()
var _plane_n := PackedVector2Array()
var _cells: Dictionary = {}  # Vector2i -> Array von Stück-Nummern
## Tunnelstücke: Anfang, Ende, halbe Röhrenbreite, Abstand von a und b zum nächsten Portal
var _t_a := PackedVector3Array()
var _t_b := PackedVector3Array()
var _t_half := PackedFloat32Array()
var _t_portal_a := PackedFloat32Array()
var _t_portal_b := PackedFloat32Array()
var _t_cells: Dictionary = {}  # Vector2i -> Array von Tunnelstück-Nummern


## segments: fertige RoadSegments, pads: Kreuzungen (Mitte x, y, z und Radius als w),
## area: gefragter Bereich
func _init(segments: Array, pads: PackedVector4Array, area: Rect2) -> void:
	reach = 0.0
	var grown := area.grow(RoadSegment.MAX_BANK + 15.0)
	for segment: RoadSegment in segments:
		var core := segment.road_width * 0.5 + segment.shoulder_width + 0.5
		reach = maxf(reach, core + RoadSegment.MAX_BANK)
		var portal_distance := _portal_distances(segment)
		var portals := _portal_planes(segment)
		# Punkte, an denen die Böschung aufhört (Brücke, Tunnel)
		var stops := PackedByteArray()
		stops.resize(segment.points.size())
		for i in segment.points.size():
			stops[i] = 1 if segment.tunnel[i] == 1 or segment.bridge[i] == 1 else 0
		for i in segment.points.size() - 1:
			var in_tunnel := segment.tunnel[i] == 1 and segment.tunnel[i + 1] == 1
			if in_tunnel:
				_add_tunnel_piece(segment.points[i], segment.points[i + 1], segment.tube_half_width(),
					portal_distance[i], portal_distance[i + 1], grown)
				continue
			# Unter Brücken bleibt das Gelände, wie es ist (Fluss, Tal). Dort darf aber auch
			# nichts wachsen, deshalb zählen Brücken trotzdem als Sperrzone.
			var carves := not (segment.bridge[i] == 1 and segment.bridge[i + 1] == 1)
			var piece_bank := (segment.bank[i] + segment.bank[i + 1]) * 0.5
			var plane := _nearest_plane(portals, segment.points[i])
			# Vor Tunnelportalen und Brücken hört die Böschung auf: kein Halbkreis über das Stückende
			# hinaus, sonst ragt dort Gelände über die Fahrbahn, wenn sie auf der Brücke abfällt
			# Kappe: 0 = keine, 1 = Halbkreis, 2 = gerade (breiter, gerader Parkplatz: an jedem
			# Stück, sonst reichen die Halbkreise der inneren Stücke über das Ende hinaus)
			var cap_a := 1 if not _stop_within(segment.points, stops, i, -1, core) else 0
			var cap_b := 1 if not _stop_within(segment.points, stops, i + 1, 1, core) else 0
			if segment.square_ends:
				cap_a = 2
				cap_b = 2
			_add_piece(segment.points[i], segment.points[i + 1], core, piece_bank, carves, grown,
				cap_a, cap_b, plane)
	for pad in pads:
		var center := Vector3(pad.x, pad.y, pad.z)
		reach = maxf(reach, pad.w + RoadSegment.MAX_BANK)
		_add_piece(center, center, pad.w, 0.0, true, grown, 1, 1, [])


## Liegt ab Punkt i in Richtung step (1 oder -1) innerhalb von distance Metern eine Brücke
## oder ein Tunnel?
func _stop_within(points: PackedVector3Array, stops: PackedByteArray, i: int, step: int, distance: float) -> bool:
	var j := i
	while j >= 0 and j < points.size():
		if stops[j] == 1:
			return true
		if Vector2(points[j].x - points[i].x, points[j].z - points[i].z).length() > distance:
			return false
		j += step
	return false


## Alle Portale eines Abschnitts: [Punkt (x/z), Richtung aus dem Tunnel hinaus]
func _portal_planes(segment: RoadSegment) -> Array:
	var result: Array = []
	for r in segment.tunnel_ranges:
		var d0 := -segment.direction_at(r.x)
		var d1 := segment.direction_at(r.y)
		result.append([Vector2(segment.points[r.x].x, segment.points[r.x].z), Vector2(d0.x, d0.z)])
		result.append([Vector2(segment.points[r.y].x, segment.points[r.y].z), Vector2(d1.x, d1.z)])
	return result


## Das nächste Portal (bis 90 m) zu einem Punkt, leer = keins
func _nearest_plane(portals: Array, p: Vector3) -> Array:
	var best: Array = []
	var best_distance := 90.0
	for portal: Array in portals:
		var d := (portal[0] as Vector2).distance_to(Vector2(p.x, p.z))
		if d < best_distance:
			best_distance = d
			best = portal
	return best


## Abstand jedes Tunnelpunkts zum nächsten Portal (Meter), außerhalb von Tunneln 0
func _portal_distances(segment: RoadSegment) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(segment.points.size())
	var last := segment.points.size() - 1
	for r in segment.tunnel_ranges:
		for k in range(r.x, r.y + 1):
			# Läuft der Tunnel am Abschnittsende weiter, ist dort kein Portal
			var from_start := (k - r.x) * RoadSegment.POINT_SPACING if r.x > 0 else 1e6
			var from_end := (r.y - k) * RoadSegment.POINT_SPACING if r.y < last else 1e6
			result[k] = minf(from_start, from_end)
	return result


func _add_piece(a: Vector3, b: Vector3, core: float, piece_bank: float, carves: bool, area: Rect2,
		cap_a: int, cap_b: int, plane: Array) -> void:
	var box := Rect2(a.x, a.z, 0.0, 0.0).expand(Vector2(b.x, b.z)).grow(core + RoadSegment.MAX_BANK)
	if not box.intersects(area):
		return
	var index := _a.size()
	_a.append(a)
	_b.append(b)
	_core.append(core)
	_bank.append(piece_bank)
	_carves.append(1 if carves else 0)
	_cap_a.append(cap_a)
	_cap_b.append(cap_b)
	_plane_p.append(plane[0] if not plane.is_empty() else Vector2.ZERO)
	_plane_n.append(plane[1] if not plane.is_empty() else Vector2.ZERO)
	_sort_into(_cells, box, index)


func _add_tunnel_piece(a: Vector3, b: Vector3, half: float, portal_a: float, portal_b: float, area: Rect2) -> void:
	# Breit genug für das Band der groben Detailstufen (tunnel_coarse, bis ~23 m)
	var box := Rect2(a.x, a.z, 0.0, 0.0).expand(Vector2(b.x, b.z)).grow(half + 26.0)
	if not box.intersects(area):
		return
	var index := _t_a.size()
	_t_a.append(a)
	_t_b.append(b)
	_t_half.append(half)
	_t_portal_a.append(portal_a)
	_t_portal_b.append(portal_b)
	_sort_into(_t_cells, box, index)


func _sort_into(cells: Dictionary, box: Rect2, index: int) -> void:
	var c0 := Vector2i(floori(box.position.x / CELL), floori(box.position.y / CELL))
	var c1 := Vector2i(floori(box.end.x / CELL), floori(box.end.y / CELL))
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var cell := Vector2i(cx, cz)
			if not cells.has(cell):
				cells[cell] = []
			cells[cell].append(index)


func is_empty() -> bool:
	return _a.is_empty() and _t_a.is_empty()


func has_tunnels() -> bool:
	return not _t_a.is_empty()


## Gelände an die Straße anpassen. Gibt (neue Höhe, Nähe zur Straße 0..1) zurück.
## Jedes Straßenstück in der Nähe erlaubt nur einen Höhenbereich: auf der Fahrbahn genau
## ihre Höhe, daneben mit jedem Meter Abstand BANK_SLOPE Meter mehr Spielraum (Böschung).
## Das Gelände muss alle Bereiche gleichzeitig einhalten. So entsteht zwischen zwei
## Serpentinen-Ästen ein durchgehender Hang statt einer senkrechten Stufe.
func carve(x: float, z: float, natural: float) -> Vector2:
	var pieces: Array = _cells.get(Vector2i(floori(x / CELL), floori(z / CELL)), [])
	if pieces.is_empty():
		return Vector2(natural, 0.0)
	var lowest := -INF
	var highest := INF
	var nearest_over := INF
	var road_height := 0.0
	var constrained := false
	for index: int in pieces:
		if _carves[index] == 0:
			continue
		# Wie weit liegt der Punkt hinter der Portal-Ebene (im Berg)?
		var behind := 0.0
		var plane_n := _plane_n[index]
		if plane_n != Vector2.ZERO:
			behind = -(Vector2(x, z) - _plane_p[index]).dot(plane_n)
		var a := _a[index]
		var b := _b[index]
		var abx := b.x - a.x
		var abz := b.z - a.z
		var apx := x - a.x
		var apz := z - a.z
		var len_sq := abx * abx + abz * abz
		var t := 0.0
		var beyond := 0.0
		if len_sq > 0.0001:
			t = (apx * abx + apz * abz) / len_sq
			# Am Portal hört die Böschung an der Portal-Ebene auf (dahinter ist der Berg)
			if (t < 0.0 and _cap_a[index] == 0) or (t > 1.0 and _cap_b[index] == 0):
				continue
			# Gerade Kappe: hinter dem Ende beginnt sofort die Böschung
			if (t < 0.0 and _cap_a[index] == 2) or (t > 1.0 and _cap_b[index] == 2):
				beyond = (-t if t < 0.0 else t - 1.0) * sqrt(len_sq)
			t = clampf(t, 0.0, 1.0)
		var dx := apx - abx * t
		var dz := apz - abz * t
		# Wie weit liegt der Punkt außerhalb des flachen Teils (Fahrbahn + Bankett)?
		var over := sqrt(dx * dx + dz * dz) - _core[index]
		if over > RoadSegment.MAX_BANK:
			continue
		# Seitlicher Abstand zur Mittellinie (positiv = links), für die Querneigung
		var lateral := 0.0
		if len_sq > 0.0001:
			lateral = (dx * abz - dz * abx) / sqrt(len_sq)
		if beyond > 0.0:
			over = maxf(absf(lateral) - _core[index], beyond)
			if over > RoadSegment.MAX_BANK:
				continue
		lateral = clampf(lateral, -_core[index], _core[index])
		# Gelände knapp unter der Fahrbahn, daneben die Böschung
		var target := lerpf(a.y, b.y, t) - _bank[index] * lateral - 0.3
		if behind > 0.0:
			# Im Berg hinter dem Portal: steile Felswand, die Röhre bleibt frei (Loch, tunnel_hole)
			var face := maxf(over, 0.0) * RoadSegment.BANK_SLOPE + behind * PORTAL_FACE_SLOPE
			lowest = maxf(lowest, target - face)
			highest = minf(highest, target + face)
			constrained = true
			continue
		if over < nearest_over:
			nearest_over = over
			road_height = target
		var slack := maxf(over, 0.0) * RoadSegment.BANK_SLOPE
		lowest = maxf(lowest, target - slack)
		highest = minf(highest, target + slack)
	if nearest_over == INF:
		if constrained and lowest <= highest:
			return Vector2(clampf(natural, lowest, highest), 0.0)
		return Vector2(natural, 0.0)
	var proximity := 1.0 - smoothstep(0.0, 5.0, nearest_over)
	# Unter einer Fahrbahn gilt immer deren Höhe: eine Straße darf nie zugeschüttet werden
	if nearest_over <= 0.0:
		return Vector2(road_height, 1.0)
	if lowest > highest:
		# Zwei Straßen wollen Unvereinbares (zu nah übereinander): Mitte nehmen
		return Vector2((lowest + highest) * 0.5, proximity)
	return Vector2(clampf(natural, lowest, highest), proximity)


## Liegt hier Straße (inklusive kleinem Rand)? Für Bäume und Felsen.
## Über Tunneln darf alles wachsen, nur nicht direkt über und neben den Portalen.
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
	var tunnel_pieces: Array = _t_cells.get(Vector2i(floori(x / CELL), floori(z / CELL)), [])
	for index: int in tunnel_pieces:
		var hit := _tunnel_hit(index, x, z)
		if hit.x < _t_half[index] + 6.0 + margin and hit.y < PORTAL_KEEPOUT:
			return true
	return false


## Loch im Gelände für die Tunnelröhre? Ja, wo das Gelände über der Röhre zu dünn ist
## (es würde durch die Röhre ragen) und kurz hinter jedem Portal (dort ginge die
## Geländefläche sonst schräg vor die Öffnung).
func tunnel_hole(x: float, z: float, natural: float) -> bool:
	var pieces: Array = _t_cells.get(Vector2i(floori(x / CELL), floori(z / CELL)), [])
	for index: int in pieces:
		var hit := _tunnel_hit(index, x, z)
		if hit.x > _t_half[index] + 1.0:
			continue
		if hit.y < PORTAL_HOLE or natural < hit.z + RoadSegment.TUBE_APEX + 1.0:
			return true
	return false


## Für grobe Detailstufen: Liegt ein Rasterpunkt bis band Meter neben einer Röhre (band =
## Größe seiner Dreiecke) und darunter als 1 m über dem Scheitel, wird er auf diese Höhe
## gehoben, damit kein Dreieck durch die Röhre schneidet. Nah an den Portalen muss die
## Öffnung frei bleiben: dort stattdessen ein Loch. Ergebnis: (Höhe, Loch 0/1)
func tunnel_coarse(x: float, z: float, h: float, band: float) -> Vector2:
	var hole := 0.0
	var pieces: Array = _t_cells.get(Vector2i(floori(x / CELL), floori(z / CELL)), [])
	for index: int in pieces:
		# Vor dem Portal: Ein grobes Dreieck reicht vom Einschnitt bis in den Berg und würde
		# den Anfang der Röhre zudecken. Deshalb im Streifen der Röhre vor dem Portal ein Loch
		# (dort liegt ohnehin die Fahrbahn, die Hänge daneben bleiben).
		if _in_front_of_portal(index, x, z, band + 1.0):
			hole = 1.0
			continue
		var hit := _tunnel_hit(index, x, z)
		if hit.x > _t_half[index] + 1.0 + band:
			continue
		# Gleich hinter dem Portal im Streifen der Röhre immer ein Loch: Sonst reicht ein grobes
		# Dreieck vom Berg bis vor das Portal und deckt die Öffnung zu
		if hit.y < PORTAL_HOLE + band and hit.x <= _t_half[index] + 1.0:
			hole = 1.0
			continue
		var cover := hit.z + RoadSegment.TUBE_APEX + 1.0
		if h >= cover:
			continue
		if hit.y < PORTAL_HOLE + band:
			hole = 1.0
		else:
			h = cover
	return Vector2(h, hole)


## Liegt der Punkt bis zu depth Meter vor einem Portal, im Streifen der Röhre?
func _in_front_of_portal(index: int, x: float, z: float, depth: float) -> bool:
	var a := _t_a[index]
	var b := _t_b[index]
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var length := ab.length()
	if length < 0.01:
		return false
	var direction := ab / length
	var ap := Vector2(x - a.x, z - a.z)
	var along := ap.dot(direction)
	var side := absf(ap.dot(Vector2(-direction.y, direction.x)))
	if side > _t_half[index] + 1.0:
		return false
	# Das Stück beginnt an einem Portal und der Punkt liegt davor (bzw. hinter dem Ende)
	if _t_portal_a[index] < 0.5 and along < 0.0 and along > -depth:
		return true
	return _t_portal_b[index] < 0.5 and along > length and along < length + depth


## Lage eines Punkts zu einem Tunnelstück: (seitlicher Abstand, Abstand zum Portal,
## Fahrbahnhöhe). Liegt der Punkt vor oder hinter dem Stück, ist der Abstand INF.
func _tunnel_hit(index: int, x: float, z: float) -> Vector3:
	var a := _t_a[index]
	var b := _t_b[index]
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ap := Vector2(x - a.x, z - a.z)
	var t := ap.dot(ab) / maxf(ab.length_squared(), 0.0001)
	# Etwas Überlappung: In Kurven bleibt sonst außen zwischen zwei Stücken ein Keil frei
	if t < -0.15 or t > 1.15:
		return Vector3(INF, INF, 0.0)
	t = clampf(t, 0.0, 1.0)
	return Vector3((ap - ab * t).length(), lerpf(_t_portal_a[index], _t_portal_b[index], t), lerpf(a.y, b.y, t))
