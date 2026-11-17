extends SceneTree
## Welt-Prüfer: sucht Fehler in der erzeugten Welt und nennt sie mit Koordinaten.
##
## Rechnet die Straßen Feld für Feld (4 × 4 km) auf einer großen Fläche (Standard 40 × 40 km um
## den Ursprung), baut für jeden Abschnitt die echte Kollision (wie im Spiel) und für die
## Gelände-Kacheln an den Straßen Stufe 0 mit Bäumen, Büschen und Felsen. Geprüft wird:
## - Fahrbahnen, die sich überschneiden oder ineinanderlaufen (Höhenunterschied < 3,5 m),
##   auch Straßen quer durch eine fremde Kreuzung
## - Leitplanken, Brüstungen, Tunnelwände und Portale, die in oder auf einer Fahrbahn stehen
## - Löcher im Gelände (an Tunneln), durch die man von außen fallen kann: unter die Map oder
##   durch die Decke in die Röhre (Landung auf dem Tunnel-Deckel, dem Sockel vor dem Portal oder der
##   offenen Straße davor ist in Ordnung, wie ein Sturz von der Böschung eines Einschnitts)
## - Bäume, Büsche, Felsen und Häuser auf Straßen oder schwebend
## - Straßen im Wasser (ohne Brücke)
## - kaputte Kreuzungen: Lücke oder Höhensprung zwischen Kreuzungsfläche und Straße
## Ausgabe: Anzahl Stellen je Fehlerart (Stellen = 40-m-Felder), Beispiele mit Foto-Befehl,
## die ganze Liste in screenshots/world_check.txt.
##
## Aufruf (im Projektordner, dauert bei 40 × 40 km etwa 10–20 Minuten):
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s res://tools/world_check.gd
##   ... -- --size=12           nur 12 × 12 km (schneller)
##   ... -- --center=3200,-4060 --size=4   ein Feld um eine bestimmte Stelle

## Höhenunterschied, unter dem zwei Fahrbahnen sich stören (Auto passt nicht dazwischen)
const OVERLAP_HEIGHT: float = 3.5
## So nah an einer Kreuzungsmitte (zusätzlich zu ihrem Radius) dürfen sich ihre Arme nahe kommen
const JUNCTION_ALLOW: float = 30.0
## Gemeinsame Enden (Kreuzung, Anschluss): in diesem Umkreis zählt eine Überschneidung nicht
const SHARED_END_ALLOW: float = 60.0
## Rampen dürfen auf der Autobahn liegen, solange sie außerhalb der Hauptfahrbahn bleiben
## (Abstand von der Autobahnmitte; Randlinie der rechten Spur bei 10,25 m)
const RAMP_ALLOWED_LATERAL: float = 9.6
## Stellen zusammenfassen: Fehler im selben Feld dieser Größe zählen einmal
const PLACE_SIZE: float = 40.0
const TILE: float = 4000.0
const CHUNK: float = 256.0

var main: Node
var roads: RoadNetwork
var world_gen: WorldGen
var mover := Node3D.new()
var tiles: Array[Rect2] = []
var tile_index := -1
var phase := "start"
var t := 0.0
var wait_time := 0.0
## Schon gebaute Abschnitte (Schlüssel -> RoadSegment), damit build_mesh nur einmal läuft
var built: Dictionary = {}
var junctions_built: Dictionary = {}
## Ergebnis: Fehlerart -> {Stelle (Vector2i): [x, z, Text]}
var bad: Dictionary = {}
## Kuppen und Senken (Höhenprofil): je Straßenart größter Knick zwischen zwei 4-m-Stücken (Änderung der
## Steigung) und kleinster Ausrundungs-Halbmesser über 12 m: [Knick, Lage, Halbmesser, Lage]
var vertical: Dictionary = {}
var vertical_seen: Dictionary = {}
var stats := {"segments": 0, "chunks": 0, "trees": 0, "houses": 0, "junctions": 0, "holes": 0}


func _initialize() -> void:
	var size := 40000.0
	var center := Vector2.ZERO
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--size="):
			size = float(arg.trim_prefix("--size=")) * 1000.0
		elif arg.begins_with("--center="):
			var xz := arg.trim_prefix("--center=").split(",")
			center = Vector2(float(xz[0]), float(xz[1]))
	# Felder in Schlangenlinie (der Bezugspunkt springt nie weit, Nachbarn bleiben berechnet)
	var count := maxi(roundi(size / TILE), 1)
	var origin := center - Vector2.ONE * count * TILE * 0.5
	for gz in count:
		for k in count:
			var gx := k if gz % 2 == 0 else count - 1 - k
			tiles.append(Rect2(origin + Vector2(gx, gz) * TILE, Vector2.ONE * TILE))
	print("WELT-PRÜFER: %d Felder à 4 km, Fläche %.0f × %.0f km um %s" % [tiles.size(), count * 4.0, count * 4.0, center])
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	root.add_child(mover)


func _process(delta: float) -> bool:
	t += delta
	# Die Garage hält das Spiel an
	if main.garage and main.garage.is_open:
		main.garage.close(true)
	match phase:
		"start":
			if main.world_is_ready and t > 1.0:
				_take_over()
				_next_tile()
		"wait":
			wait_time += delta
			var tile := tiles[tile_index]
			if not roads.segments_for_rect(tile.grow(80.0)).is_empty():
				_check_tile(tile)
				_next_tile()
			elif fmod(wait_time, 15.0) < delta:
				print("  Feld %d: warte auf Straßen (%.0f s)" % [tile_index + 1, wait_time])
				if wait_time > 40.0:
					_print_missing(tile.grow(80.0))
	return false


## Fehlersuche: welche Abschnitte bzw. Kreuzungen fehlen noch?
func _print_missing(rect: Rect2) -> void:
	var entries: Dictionary = roads.get("_entries")
	var wanted: Dictionary = roads.get("_wanted")
	var shown := 0
	for key: Vector3i in roads.call("_edges_touching", rect):
		var entry: Variant = entries.get(key)
		var state: int = entry.state if entry != null else -1
		if state >= 3:
			continue
		shown += 1
		if shown <= 8:
			print("    fehlt %s: Zustand %d, gewollt %s, laufend %s" % [key, state, wanted.get(key, "-"),
				entry != null and entry.task_id != -1])
	print("    %d Abschnitte unfertig, %d gewollt, %d laufen" % [shown, wanted.size(), roads.get("_running")])
	for key: Vector3i in entries:
		var entry: Variant = entries[key]
		if entry.task_id != -1:
			print("    läuft: %s Zustand %d, von %s nach %s" % [key, entry.state, entry.segment.start.round(), entry.segment.end.round()])
	var villages: Dictionary = roads.get("_villages")
	for cell: Vector2i in villages:
		if villages[cell].task_id != -1:
			print("    Dorf plant noch: %s" % cell)


## Nur noch Straßen berechnen: Gelände, Gras, Verkehr, Wasser stehen still
func _take_over() -> void:
	roads = main.roads
	world_gen = main.world_gen
	for name: String in ["Terrain", "Grass", "Traffic", "Water", "HorizonRing", "Waterfalls", "CarReset"]:
		var node := main.get_node_or_null(name)
		if node:
			node.process_mode = Node.PROCESS_MODE_DISABLED
	roads.target = mover
	roads.mesh_distance = -100000.0  # keine Meshes im Spiel bauen (das macht der Prüfer selbst)
	roads.max_parallel_jobs = maxi(OS.get_processor_count() - 1, 4)
	roads.update_interval = 0.02


func _next_tile() -> void:
	tile_index += 1
	if tile_index >= tiles.size():
		_report()
		quit()
		return
	var c := tiles[tile_index].get_center()
	mover.global_position = Vector3(c.x, 0.0, c.y)
	wait_time = 0.0
	phase = "wait"


# ---------------------------------------------------------------------------
# Ein Feld prüfen
# ---------------------------------------------------------------------------

func _check_tile(tile: Rect2) -> void:
	var started := Time.get_ticks_msec()
	var area := tile.grow(400.0)
	var segments: Array[RoadSegment] = []
	var keys: Array[Vector3i] = []
	for pair: Array in roads.loaded_segments(area):
		keys.append(pair[0])
		segments.append(pair[1])
	var times := PackedInt32Array([Time.get_ticks_msec()])
	_build_meshes(keys, segments)
	# --info=X,Y,Z: Angaben zu einem Abschnitt (Fehlersuche)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--info="):
			var v := arg.trim_prefix("--info=").split(",")
			var wanted := Vector3i(int(v[0]), int(v[1]), int(v[2]))
			for k in keys.size():
				if keys[k] == wanted:
					var seg := segments[k]
					print("INFO %s: %d Punkte, Start %s, Ende %s, Tunnel %s, Brücken %d, rail_gaps %s, keepout %d, extra_r max %.2f" % [
						wanted, seg.points.size(), seg.points[0].round(), seg.points[-1].round(), seg.tunnel_ranges,
						seg.bridge.count(1), str(seg.rail_gaps) + " Deckel %s von %d Flächen" % [seg.shell_faces, seg.collision_faces.size()], seg.rail_keepout.size(),
						Array(seg.extra_right).max() if not seg.extra_right.is_empty() else 0.0])
	# --probe=X,Z,KX,KY,KZ: liegt der Punkt in einer Leitplanken-Sperrzone dieses Abschnitts?
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--probe="):
			var v := arg.trim_prefix("--probe=").split(",")
			var q := Vector3(float(v[0]), 0.0, float(v[1]))
			var wanted := Vector3i(int(v[2]), int(v[3]), int(v[4]))
			for k in keys.size():
				if keys[k] == wanted:
					for zone: Array in segments[k].rail_keepout:
						var line: PackedVector2Array = zone[0]
						var best := INF
						for j in line.size() - 1:
							best = minf(best, Geometry2D.get_closest_point_to_segment(Vector2(q.x, q.z), line[j], line[j + 1]).distance_to(Vector2(q.x, q.z)))
						print("PROBE Zone: %d Punkte von %s bis %s, halbe Breite %.2f, Abstand %.2f" % [line.size(), line[0].round(), line[-1].round(), zone[1], best])
					print("PROBE in Sperrzone: ", segments[k].call("_in_keepout", q))
	# --profile=X,Z: Höhenprofil des nächsten Abschnitts um diese Stelle (Fehlersuche Kuppen)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--profile="):
			var v := arg.trim_prefix("--profile=").split(",")
			var q := Vector2(float(v[0]), float(v[1]))
			if not tile.has_point(q):
				continue
			var best_k := -1
			var best_i := -1
			var best_d := INF
			for k in segments.size():
				for i in segments[k].points.size():
					var d := Vector2(segments[k].points[i].x, segments[k].points[i].z).distance_to(q)
					if d < best_d:
						best_d = d
						best_k = k
						best_i = i
			if best_k >= 0:
				var seg := segments[best_k]
				print("PROFIL %s Punkt %d von %d (flach %d/%d, Fenster %d, Steigung max %.3f)" % [keys[best_k], best_i,
					seg.points.size(), seg.flat_points, seg.flat_end, seg.vertical_window, seg.max_grade])
				for i in range(maxi(best_i - 14, 1), mini(best_i + 15, seg.points.size() - 1)):
					var g0 := (seg.points[i].y - seg.points[i - 1].y) / 4.0
					var g1 := (seg.points[i + 1].y - seg.points[i].y) / 4.0
					print("  %4d  y %8.2f  Steigung %+.3f  Knick %+.3f  Gelände %8.2f  Brücke %d Tunnel %d" % [i, seg.points[i].y,
						g1, g1 - g0, seg.ground[i], seg.bridge[i], seg.tunnel[i]])
	var junctions := _junctions_in(area)
	var index := _point_index(segments)
	times.append(Time.get_ticks_msec())
	_check_overlaps(tile, segments, keys, index, junctions)
	_check_rails(tile, segments, keys, index, junctions)
	_check_water(tile, segments)
	_measure_vertical(segments, keys)
	_check_junctions(tile, junctions)
	times.append(Time.get_ticks_msec())
	var jobs := _terrain_jobs(tile, segments)
	times.append(Time.get_ticks_msec())
	_check_vegetation(tile, jobs, segments, index, junctions)
	times.append(Time.get_ticks_msec())
	_check_houses(tile, segments, index, jobs)
	_check_holes(tile, jobs, segments)
	times.append(Time.get_ticks_msec())
	if "--times" in OS.get_cmdline_user_args():
		print("  Zeiten (ms): Meshes %d, Straßen %d, Gelände %d, Pflanzen %d, Häuser/Löcher %d" % [
			times[1] - times[0], times[2] - times[1], times[3] - times[2], times[4] - times[3], times[5] - times[4]])
	print("Feld %d/%d fertig nach %.0f s Warten + %.1f s Prüfen: %d Abschnitte, %d Kacheln, bisher %d Stellen" % [
		tile_index + 1, tiles.size(), wait_time, (Time.get_ticks_msec() - started) / 1000.0, segments.size(),
		jobs.size(), _total()])


## Mesh und Kollision jedes Abschnitts bauen (wie RoadNetwork._start_mesh, im Hintergrund)
func _build_meshes(keys: Array[Vector3i], segments: Array[RoadSegment]) -> void:
	var todo: Array = []
	for k in keys.size():
		var segment := segments[k]
		if built.get(keys[k]) == segment:
			continue
		var first := 0
		var last := segment.points.size() - 1
		if RoadNetwork.is_road_key(keys[k]):
			var at_start := roads.junction_at(Vector2i(keys[k].x, keys[k].y))
			var at_end := roads.junction_at(roads.edge_end_cell(keys[k]))
			if at_start == null or at_end == null:
				continue
			first = at_start.mouth_steps()
			last -= at_end.mouth_steps()
		elif RoadNetwork.is_interchange_key(keys[k]) and RoadNetwork.interchange_part(keys[k]) == 0:
			var interchange := roads.highways.interchange_at(RoadNetwork.highway_axis(keys[k]), keys[k].y, keys[k].x)
			var at_place := roads.junction_at(interchange["cell"])
			if at_place == null:
				continue
			first = at_place.mouth_steps()
		built[keys[k]] = segment
		todo.append([segment, first, last])
	stats["segments"] += todo.size()
	var task := WorkerThreadPool.add_group_task(func(i: int) -> void:
		var item: Array = todo[i]
		(item[0] as RoadSegment).build_mesh(item[1], item[2]), todo.size(), -1, true, "Prüfer: Straßen")
	WorkerThreadPool.wait_for_group_task_completion(task)


## Kreuzungen im Bereich (fertig gebaut, mit Fläche)
func _junctions_in(area: Rect2) -> Array[RoadJunction]:
	var result: Array[RoadJunction] = []
	var size := roads.cell_size
	for cz in range(floori(area.position.y / size), floori(area.end.y / size) + 1):
		for cx in range(floori(area.position.x / size), floori(area.end.x / size) + 1):
			var node: Variant = roads.node_at(Vector2i(cx, cz))
			if node == null:
				continue
			var junction := roads.junction_at(Vector2i(cx, cz))
			if junction == null or junction.arms.is_empty():
				continue
			if not junctions_built.has(Vector2i(cx, cz)) or junctions_built[Vector2i(cx, cz)] != junction:
				if junction.collision_faces.is_empty():
					junction.build()
				junctions_built[Vector2i(cx, cz)] = junction
			result.append(junction)
	return result


## Punkte aller Abschnitte in 20-m-Feldern: Feld -> [[Abschnitt-Nr., Punkt-Nr.], …]
func _point_index(segments: Array[RoadSegment]) -> Dictionary:
	var index := {}
	for s in segments.size():
		var points := segments[s].points
		for i in points.size():
			var cell := Vector2i(floori(points[i].x / 20.0), floori(points[i].z / 20.0))
			if not index.has(cell):
				index[cell] = []
			(index[cell] as Array).append(Vector2i(s, i))
	return index


## Liegt q auf der Fahrfläche (Fahrbahn + Bankett) eines anderen Abschnitts?
## Ergebnis: [Abschnitt-Nr., Punkt-Nr., seitlicher Abstand, Höhe] oder leer
func _surface_hits(q: Vector3, index: Dictionary, segments: Array[RoadSegment], skip: int,
		max_dy: float, shrink: float = 0.0) -> Array:
	var hits: Array = []
	var best: Dictionary = {}  # Abschnitt -> [Abstand, Punkt]
	var cell := Vector2i(floori(q.x / 20.0), floori(q.z / 20.0))
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			for item: Vector2i in index.get(cell + Vector2i(dx, dz), []):
				if item.x == skip:
					continue
				var p := segments[item.x].points[item.y]
				var d := Vector2(p.x - q.x, p.z - q.z).length_squared()
				if not best.has(item.x) or d < best[item.x][0]:
					best[item.x] = [d, item.y]
	for s: int in best:
		var segment := segments[s]
		var j: int = best[s][1]
		var lateral := _lateral(segment, j, q)
		var side := 1.0 if lateral.x > 0.0 else -1.0
		var half := segment.road_width * 0.5 + segment.shoulder_width + segment.extra_at(j, side) - shrink
		if segment.tunnel[j] == 1:
			# Im Tunnel reicht die Fahrfläche bis an die Wand (Wände liegen genau dort)
			half = segment.tube_half_width() - maxf(shrink, 0.3)
		# Über das Ende eines Abschnitts hinaus zählt nur ein kleiner Überstand (dort beginnt die
		# Kreuzung bzw. die Straße, an die er anschließt)
		if absf(lateral.x) > half or lateral.y > 0.5:
			continue
		var y := segment.points[j].y
		if absf(q.y - y) < max_dy:
			hits.append([s, j, lateral.x, y])
	return hits


## Seitlicher Abstand von q zur Mittellinie bei Punkt j (positiv = links) und wie weit q
## längs über das Stück hinausragt (0 = innerhalb)
func _lateral(segment: RoadSegment, j: int, q: Vector3) -> Vector2:
	var p := segment.points[j]
	var forward := segment.direction_at(j)
	var left := Vector3.UP.cross(forward).normalized()
	var rel := q - p
	var along := rel.dot(forward)
	var n := segment.points.size()
	var beyond := 0.0
	if (j == 0 and along < 0.0) or (j == n - 1 and along > 0.0):
		beyond = absf(along)
	return Vector2(rel.dot(left), beyond)


# ---------------------------------------------------------------------------
# 1. Fahrbahnen, die sich überschneiden
# ---------------------------------------------------------------------------

func _check_overlaps(tile: Rect2, segments: Array[RoadSegment], keys: Array[Vector3i], index: Dictionary,
		junctions: Array[RoadJunction]) -> void:
	for a in segments.size():
		var seg := segments[a]
		var n := seg.points.size()
		for i in range(0, n, 2):
			var p := seg.points[i]
			if not tile.has_point(Vector2(p.x, p.z)):
				continue
			var left := Vector3.UP.cross(seg.direction_at(i)).normalized()
			for f: float in [-0.8, 0.0, 0.8]:
				var q := p + left * f * seg.road_width * 0.5
				for hit: Array in _surface_hits(q, index, segments, a, OVERLAP_HEIGHT, 0.3):
					var b: int = hit[0]
					if _overlap_allowed(seg, keys[a], segments[b], keys[b], q, hit, junctions):
						continue
					_bad("Fahrbahnen überschneiden sich", q, "%s (%s) und %s (%s), Höhen %.1f / %.1f" % [
						_kind(keys[a]), keys[a], _kind(keys[b]), keys[b], q.y, hit[3]])
			# Durch eine fremde Kreuzung?
			for junction in junctions:
				var c := junction.center
				if Vector2(p.x - c.x, p.z - c.z).length() > junction.radius - 1.0 or absf(p.y - c.y) > OVERLAP_HEIGHT:
					continue
				if _is_arm(junction, seg):
					continue
				_bad("Straße durch fremde Kreuzung", p, "%s (%s) durch Kreuzung bei %s" % [
					_kind(keys[a]), keys[a], Vector2(c.x, c.z).round()])


## Seitlicher Abstand von q zur eigenen Mittellinie (Abschnitt a)
func _own_lateral(index: Dictionary, segments: Array[RoadSegment], a: int, q: Vector3) -> float:
	var best := -1
	var best_d := INF
	var cell := Vector2i(floori(q.x / 20.0), floori(q.z / 20.0))
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			for item: Vector2i in index.get(cell + Vector2i(dx, dz), []):
				if item.x != a:
					continue
				var p := segments[a].points[item.y]
				var d := Vector2(p.x - q.x, p.z - q.z).length_squared()
				if d < best_d:
					best_d = d
					best = item.y
	return _lateral(segments[a], best, q).x if best >= 0 else NAN


func _is_arm(junction: RoadJunction, segment: RoadSegment) -> bool:
	# Nach Schlüssel vergleichen: vergessene Abschnitte werden als neue Objekte neu berechnet
	for arm: Array in junction.arms:
		if (arm[0] as RoadSegment).key == segment.key:
			return true
	return false


## Gewollte Berührungen: an gemeinsamen Enden (Kreuzung, Anschluss), Rampen im
## Zusatzstreifen der Autobahn, Rampen am Zubringer
func _overlap_allowed(sa: RoadSegment, ka: Vector3i, sb: RoadSegment, kb: Vector3i, q: Vector3, hit: Array,
		junctions: Array[RoadJunction]) -> bool:
	var q2 := Vector2(q.x, q.z)
	for ea: Vector3 in [sa.points[0], sa.points[sa.points.size() - 1]]:
		for eb: Vector3 in [sb.points[0], sb.points[sb.points.size() - 1]]:
			var e2 := Vector2((ea.x + eb.x) * 0.5, (ea.z + eb.z) * 0.5)
			if Vector2(ea.x, ea.z).distance_to(Vector2(eb.x, eb.z)) < 40.0 and q2.distance_to(e2) < SHARED_END_ALLOW:
				return true
	# Beide Arme derselben Kreuzung: nah an der Kreuzung erlaubt
	for junction in junctions:
		if _is_arm(junction, sa) and _is_arm(junction, sb):
			if q2.distance_to(Vector2(junction.center.x, junction.center.z)) < junction.radius + JUNCTION_ALLOW:
				return true
	var ramp_a := not RoadNetwork.is_road_key(ka) and not RoadNetwork.is_highway_key(ka)
	var ramp_b := not RoadNetwork.is_road_key(kb) and not RoadNetwork.is_highway_key(kb)
	# Rampe (Anschlussstelle oder Raststätte) auf ihrer Autobahn: nur außerhalb der Hauptfahrbahn
	for pair: Array in [[sa, ka, sb, kb, ramp_a, hit[2]], [sb, kb, sa, ka, ramp_b, NAN]]:
		var ramp_key: Vector3i = pair[1]
		var highway_key: Vector3i = pair[3]
		if not pair[4] or not RoadNetwork.is_highway_key(highway_key):
			continue
		if RoadNetwork.highway_axis(ramp_key) != RoadNetwork.highway_axis(highway_key) or ramp_key.y != highway_key.y:
			continue
		var highway: RoadSegment = pair[2]
		var lateral: float = pair[5]
		if is_nan(lateral):
			# q liegt auf der Rampe: Abstand zur Autobahnmitte nachrechnen
			var j := _nearest(highway, q)
			lateral = _lateral(highway, j, q).x
		if absf(lateral) >= RAMP_ALLOWED_LATERAL:
			return true
	# Rampen derselben Anschlussstelle bzw. Raststätte untereinander und mit dem Zubringer:
	# erlaubt nahe an den Enden der Rampe (dort treffen sie sich)
	if ramp_a and ramp_b and ka.x == kb.x and ka.y == kb.y:
		for s: RoadSegment in [sa, sb]:
			for e: Vector3 in [s.points[0], s.points[s.points.size() - 1]]:
				if q2.distance_to(Vector2(e.x, e.z)) < SHARED_END_ALLOW + 20.0:
					return true
	return false


func _nearest(segment: RoadSegment, q: Vector3) -> int:
	var best := 0
	var best_d := INF
	for i in segment.points.size():
		var d := Vector2(segment.points[i].x - q.x, segment.points[i].z - q.z).length_squared()
		if d < best_d:
			best_d = d
			best = i
	return best


# ---------------------------------------------------------------------------
# 2. Leitplanken, Brüstungen, Tunnelwände und Portale in einer Fahrbahn
# ---------------------------------------------------------------------------

func _check_rails(tile: Rect2, segments: Array[RoadSegment], keys: Array[Vector3i], index: Dictionary,
		junctions: Array[RoadJunction]) -> void:
	for a in segments.size():
		var faces := segments[a].collision_faces
		for f in range(0, faces.size(), 3):
			var p0 := faces[f]
			var p1 := faces[f + 1]
			var p2 := faces[f + 2]
			var normal := (p1 - p0).cross(p2 - p0)
			if normal.length_squared() < 0.0001 or absf(normal.normalized().y) > 0.3:
				continue  # waagerecht: Fahrbahn
			# Unterkante der senkrechten Fläche abtasten
			var low := p0
			var other := p1
			for v: Vector3 in [p1, p2]:
				if v.y < low.y:
					low = v
			for v: Vector3 in [p0, p1, p2]:
				if v != low and absf(v.y - low.y) < 0.5:
					other = v
			var height := maxf(maxf(p0.y, p1.y), p2.y) - low.y
			var kind := "Leitplanke/Brüstung in Fahrbahn" if height < 1.6 else "Tunnelwand/Portal in Fahrbahn"
			var length := Vector2(other.x - low.x, other.z - low.z).length()
			var steps := maxi(ceili(length / 1.0), 1)
			for s in steps + 1:
				var q := low.lerp(other, float(s) / steps) + Vector3.UP * 0.2
				if not tile.has_point(Vector2(q.x, q.z)):
					continue
				# In einer fremden Fahrbahn (Fahrstreifen, nicht Bankett). Hier gibt es keine
				# Ausnahmen: auch am Anschluss einer Rampe darf keine Leitplanke auf der Fahrbahn stehen.
				for hit: Array in _surface_hits(q, index, segments, a, 1.5, segments[0].shoulder_width + 0.3):
					var b: int = hit[0]
					var own := _own_lateral(index, segments, a, q)
					# Mittelleitplanke der Autobahn läuft im nächsten Abschnitt weiter
					if RoadNetwork.is_highway_key(keys[a]) and RoadNetwork.is_highway_key(keys[b]) \
							and keys[a].z == keys[b].z and keys[a].y == keys[b].y and absf(own) < 1.5:
						continue
					_bad(kind, q, "von %s (%s, %.1f m neben der Mitte) in %s (%s, %.1f m neben der Mitte), Höhe %.1f" % [
						_kind(keys[a]), keys[a], own, _kind(keys[b]), keys[b], hit[2], q.y])
				# … oder auf einer fremden Kreuzung
				for junction in junctions:
					if _is_arm(junction, segments[a]):
						continue
					var c := junction.center
					if Vector2(q.x - c.x, q.z - c.z).length() < junction.radius - 1.0 and absf(q.y - c.y) < 1.5:
						_bad(kind, q, "von %s (%s) auf Kreuzung bei %s" % [_kind(keys[a]), keys[a], Vector2(c.x, c.z).round()])


# ---------------------------------------------------------------------------
# 3. Straßen im Wasser
# ---------------------------------------------------------------------------

## Höhenprofile messen (nicht als Fehler gezählt): größter Steigungswechsel pro 4 m und kleinster
## Kuppen-/Wannenhalbmesser über 12 m, ohne Tunnel und Brücken-Enden (dort zählt die Fahrbahn genauso)
func _measure_vertical(segments: Array[RoadSegment], keys: Array[Vector3i]) -> void:
	for k in segments.size():
		var seg := segments[k]
		if vertical_seen.has(keys[k]) or seg.kind == RoadSegment.Kind.RAMP:
			continue
		vertical_seen[keys[k]] = true
		var kind := "Autobahn" if seg.kind == RoadSegment.Kind.HIGHWAY else "Landstraße"
		var entry: Array = vertical.get(kind, [0.0, Vector3.ZERO, INF, Vector3.ZERO, 0, 0, 0])
		var n := seg.points.size()
		var grades := PackedFloat32Array()
		grades.resize(n - 1)
		for i in n - 1:
			var a := seg.points[i]
			var b := seg.points[i + 1]
			grades[i] = (b.y - a.y) / maxf(Vector2(b.x - a.x, b.z - a.z).length(), 0.01)
		for i in range(1, n - 1):
			var kink := absf(grades[i] - grades[i - 1])
			entry[4] = int(entry[4]) + 1
			# Halbmesser unter 400 m bzw. 1000 m (über 12 m gemessen)
			if i + 2 < n - 1:
				var bend := absf(grades[i + 2] - grades[i - 1])
				if bend > 12.0 / 400.0:
					entry[5] = int(entry[5]) + 1
				if bend > 12.0 / 1000.0:
					entry[6] = int(entry[6]) + 1
			if kink > float(entry[0]):
				entry[0] = kink
				entry[1] = seg.points[i]
			if i + 2 < n - 1:
				var change := absf(grades[i + 2] - grades[i - 1])
				if change > 0.0001:
					var radius := 12.0 / change
					if radius < float(entry[2]):
						entry[2] = radius
						entry[3] = seg.points[i]
		vertical[kind] = entry


func _check_water(tile: Rect2, segments: Array[RoadSegment]) -> void:
	for seg in segments:
		var lakes: Array = world_gen.lakes_near(seg.bounds.grow(30.0))
		for i in range(0, seg.points.size(), 2):
			var p := seg.points[i]
			if not tile.has_point(Vector2(p.x, p.z)) or seg.bridge[i] == 1 or seg.tunnel[i] == 1:
				continue
			if not seg.on_dam.is_empty() and seg.on_dam[i] == 1:
				continue
			var water := world_gen.water_level_at(p.x, p.z, lakes)
			if water > WorldGen.NO_WATER and water > p.y - 0.2:
				_bad("Straße im Wasser", p, "%s (%s): Wasser %.1f, Fahrbahn %.1f" % [_kind(seg.key), seg.key, water, p.y])


# ---------------------------------------------------------------------------
# 4. Kreuzungen: passt jeder Arm an die Kreuzungsfläche?
# ---------------------------------------------------------------------------

func _check_junctions(tile: Rect2, junctions: Array[RoadJunction]) -> void:
	for junction in junctions:
		var c := junction.center
		if not tile.has_point(Vector2(c.x, c.z)):
			continue
		stats["junctions"] += 1
		var faces := junction.collision_faces
		for arm: Array in junction.arms:
			var seg: RoadSegment = arm[0]
			var m := junction.mouth_index(arm)
			var p := seg.points[m]
			var left := Vector3.UP.cross(seg.direction_at(m)).normalized()
			var inward := Vector3(c.x - p.x, 0.0, c.z - p.z).normalized()
			for f: float in [-0.9, 0.0, 0.9]:
				# Knapp vor dem Ende der Straße muss die Kreuzungsfläche beginnen
				var q := p + left * f * seg.road_width * 0.5 + inward * 0.4
				var h := _height_in_faces(faces, q)
				if is_nan(h):
					_bad("Kreuzung: Lücke zwischen Straße und Kreuzung", q, "Kreuzung bei %s, Arm %s" % [
						Vector2(c.x, c.z).round(), seg.key])
				elif absf(h - (p.y + seg.bank[m] * f * seg.road_width * 0.5)) > 0.25:
					_bad("Kreuzung: Höhensprung", q, "Kreuzung bei %s, Arm %s: Kreuzung %.2f, Straße %.2f" % [
						Vector2(c.x, c.z).round(), seg.key, h, p.y])


## Höhe der Dreiecksfläche bei q (von oben gesehen), NaN = nicht darin
func _height_in_faces(faces: PackedVector3Array, q: Vector3) -> float:
	var best := NAN
	for f in range(0, faces.size(), 3):
		var hit: Variant = Geometry3D.segment_intersects_triangle(q + Vector3.UP * 30.0, q - Vector3.UP * 30.0,
			faces[f], faces[f + 1], faces[f + 2])
		if hit != null and (is_nan(best) or absf((hit as Vector3).y - q.y) < absf(best - q.y)):
			best = (hit as Vector3).y
	return best


# ---------------------------------------------------------------------------
# 5. Gelände-Kacheln an den Straßen (Stufe 0, mit Bäumen, Büschen, Felsen)
# ---------------------------------------------------------------------------

func _terrain_jobs(tile: Rect2, segments: Array[RoadSegment]) -> Array[TerrainChunkJob]:
	var coords := {}
	for seg in segments:
		for i in range(0, seg.points.size(), 4):
			var p := seg.points[i]
			for o: Vector2 in [Vector2.ZERO, Vector2(30, 0), Vector2(-30, 0), Vector2(0, 30), Vector2(0, -30)]:
				var q := Vector2(p.x, p.z) + o
				var coord := Vector2i(floori(q.x / CHUNK), floori(q.y / CHUNK))
				# Kachel gehört zu dem Feld, in dem ihre Mitte liegt
				if tile.has_point((Vector2(coord) + Vector2(0.5, 0.5)) * CHUNK):
					coords[coord] = true
	var jobs: Array[TerrainChunkJob] = []
	var terrain: TerrainManager = main.terrain
	for coord: Vector2i in coords:
		var road_data := roads.segments_for_rect(Rect2(Vector2(coord) * CHUNK, Vector2.ONE * CHUNK))
		if road_data.is_empty():
			continue
		var job := TerrainChunkJob.new()
		job.world_gen = world_gen
		job.coord = coord
		job.lod = 0
		job.spacing = terrain.lod_spacings[0]
		job.chunk_size = terrain.chunk_size
		job.road_segments = road_data["segments"]
		job.road_pads = road_data["pads"]
		job.with_vegetation = true
		job.tree_spacing = terrain.tree_spacing
		job.rock_spacing = terrain.rock_spacing
		jobs.append(job)
	stats["chunks"] += jobs.size()
	var task := WorkerThreadPool.add_group_task(func(i: int) -> void: jobs[i].run(), jobs.size(), -1, true, "Prüfer: Gelände")
	WorkerThreadPool.wait_for_group_task_completion(task)
	return jobs


## Höhe der sichtbaren Fläche (zwei Dreiecke pro Quadrat, wie im Mesh); NaN = Loch
func _surface(job: TerrainChunkJob, x: float, z: float, holes: bool = true) -> float:
	var fx := (x - job.coord.x * job.chunk_size) / job.spacing
	var fz := (z - job.coord.y * job.chunk_size) / job.spacing
	var n := job.grid_size
	var ix := clampi(floori(fx), 0, n - 2)
	var iz := clampi(floori(fz), 0, n - 2)
	var tx := clampf(fx - ix, 0.0, 1.0)
	var tz := clampf(fz - iz, 0.0, 1.0)
	var a := iz * n + ix
	var corners := PackedInt32Array([a, a + 1, a + n]) if tx + tz <= 1.0 else PackedInt32Array([a + 1, a + n + 1, a + n])
	if holes and not job.collision_heights.is_empty():
		for c in corners:
			if is_nan(job.collision_heights[c]):
				return NAN
	var hs := job.heights
	if tx + tz <= 1.0:
		return hs[a] + (hs[a + 1] - hs[a]) * tx + (hs[a + n] - hs[a]) * tz
	return hs[a + n + 1] + (hs[a + n] - hs[a + n + 1]) * (1.0 - tx) + (hs[a + 1] - hs[a + n + 1]) * (1.0 - tz)


func _check_vegetation(tile: Rect2, jobs: Array[TerrainChunkJob], segments: Array[RoadSegment], index: Dictionary,
		junctions: Array[RoadJunction]) -> void:
	for job in jobs:
		for kind: String in job.vegetation:
			var data: PackedFloat32Array = job.vegetation[kind]
			var label := "Fels" if kind.begins_with("rock") else ("Busch" if kind == "bush" else "Baum")
			for k in range(0, data.size(), 16):
				stats["trees"] += 1
				var x := data[k + 3] + job.coord.x * job.chunk_size
				var z := data[k + 11] + job.coord.y * job.chunk_size
				var foot := Vector3(x, data[k + 7], z)
				var scale := Vector2(data[k], data[k + 2]).length()
				# Stamm bzw. Fels steht auf einer Fahrfläche (Krone darf überhängen)
				var reach := 0.3 if label == "Baum" else scale * 0.5
				for hit: Array in _surface_hits(foot, index, segments, -1, 4.0, -reach):
					_bad("%s auf Straße" % label, foot, "%s bei Höhe %.1f, Straße %s %.1f" % [
						kind, foot.y, segments[hit[0]].key, hit[3]])
					break
				for junction in junctions:
					var c := junction.center
					if Vector2(x - c.x, z - c.z).length() < junction.radius + reach and absf(foot.y - c.y) < 4.0:
						_bad("%s auf Straße" % label, foot, "%s auf Kreuzung bei %s" % [kind, Vector2(c.x, c.z).round()])
				# Schwebt: Fuß über dem Gelände (Stämme stehen 0,3 m tiefer, Felsen tiefer)
				var ground := _surface(job, x, z)
				if not is_nan(ground) and foot.y > ground + 0.15:
					_bad("%s schwebt" % label, foot, "%s: Fuß %.2f, Gelände %.2f" % [kind, foot.y, ground])


func _check_houses(tile: Rect2, segments: Array[RoadSegment], index: Dictionary, jobs: Array[TerrainChunkJob]) -> void:
	var by_coord := {}
	for job in jobs:
		by_coord[job.coord] = job
	for village: Village in (roads.get("_villages") as Dictionary).values():
		if village.task_id != -1 or not tile.has_point(Vector2(village.center.x, village.center.z)):
			continue
		for house: Dictionary in village.houses:
			stats["houses"] += 1
			var c: Vector3 = house["position"]
			var b: Basis = house["basis"]
			var size: Vector3 = house["size"]
			for sx: float in [-0.5, 0.5]:
				for sz: float in [-0.5, 0.5]:
					var q := c + b.x * size.x * sx + b.z * size.z * sz
					var hits := _surface_hits(q, index, segments, -1, 4.0)
					if not hits.is_empty():
						_bad("Haus auf Straße", q, "Haus bei %s in %s" % [Vector2(c.x, c.z).round(), segments[hits[0][0]].key])
					var job: TerrainChunkJob = by_coord.get(Vector2i(floori(q.x / CHUNK), floori(q.z / CHUNK)))
					if job == null:
						job = _single_job(Vector2i(floori(q.x / CHUNK), floori(q.z / CHUNK)))
						by_coord[job.coord] = job
					var ground := _surface(job, q.x, q.z)
					# Der Sockel reicht 1,4 m in den Boden (Village._build_house): mehr Luft darunter = schwebt
					if not is_nan(ground) and ground < c.y - 1.4:
						_bad("Haus schwebt", q, "Haus bei %s: Ecke über Gelände %.1f m" % [Vector2(c.x, c.z).round(), c.y - ground])


func _single_job(coord: Vector2i) -> TerrainChunkJob:
	var terrain: TerrainManager = main.terrain
	var road_data := roads.segments_for_rect(Rect2(Vector2(coord) * CHUNK, Vector2.ONE * CHUNK))
	var job := TerrainChunkJob.new()
	job.world_gen = world_gen
	job.coord = coord
	job.lod = 0
	job.spacing = terrain.lod_spacings[0]
	job.chunk_size = terrain.chunk_size
	job.road_segments = road_data.get("segments", [])
	job.road_pads = road_data.get("pads", PackedVector4Array())
	job.run()
	return job


# ---------------------------------------------------------------------------
# 6. Löcher im Gelände, durch die man von außen fallen kann
# ---------------------------------------------------------------------------

func _check_holes(tile: Rect2, jobs: Array[TerrainChunkJob], segments: Array[RoadSegment]) -> void:
	# Alle Kollisionsflächen der Abschnitte mit Tunnel, nach 8-m-Feldern sortiert
	var faces := PackedVector3Array()
	# 1 = Fläche gehört zu einem Tunnel-Deckel (dort zu landen ist in Ordnung)
	var shell := PackedByteArray()
	for seg in segments:
		if not seg.tunnel_ranges.is_empty():
			var first := faces.size()
			faces.append_array(seg.collision_faces)
			shell.resize(faces.size())
			var range_: Variant = seg.get("shell_faces")
			if range_ is Vector2i:
				for f in range((range_ as Vector2i).x, (range_ as Vector2i).y):
					shell[first + f] = 1
	if faces.is_empty():
		return
	var face_index := {}
	for f in range(0, faces.size(), 3):
		var lo := Vector2(minf(minf(faces[f].x, faces[f + 1].x), faces[f + 2].x), minf(minf(faces[f].z, faces[f + 1].z), faces[f + 2].z))
		var hi := Vector2(maxf(maxf(faces[f].x, faces[f + 1].x), faces[f + 2].x), maxf(maxf(faces[f].z, faces[f + 1].z), faces[f + 2].z))
		for cz in range(floori(lo.y / 8.0), floori(hi.y / 8.0) + 1):
			for cx in range(floori(lo.x / 8.0), floori(hi.x / 8.0) + 1):
				var cell := Vector2i(cx, cz)
				if not face_index.has(cell):
					face_index[cell] = PackedInt32Array()
				var list: PackedInt32Array = face_index[cell]
				list.append(f)
				face_index[cell] = list
	for job in jobs:
		var holes := job.collision_heights
		if holes.is_empty():
			continue
		var n := job.grid_size
		for iz in n - 1:
			for ix in n - 1:
				var a := iz * n + ix
				var corners := [a, a + 1, a + n, a + n + 1]
				var any_hole := false
				for c: int in corners:
					if is_nan(holes[c]):
						any_hole = true
				if not any_hole:
					continue
				# Mitte beider Dreiecke des Quadrats
				for tri: Vector2 in [Vector2(0.33, 0.33), Vector2(0.67, 0.67)]:
					var x := job.coord.x * job.chunk_size + (ix + tri.x) * job.spacing
					var z := job.coord.y * job.chunk_size + (iz + tri.y) * job.spacing
					if not tile.has_point(Vector2(x, z)):
						continue
					var tri_corners := [a, a + 1, a + n] if tri.x < 0.5 else [a + 1, a + n + 1, a + n]
					var hole := false
					for c: int in tri_corners:
						if is_nan(holes[c]):
							hole = true
					if not hole:
						continue
					stats["holes"] += 1
					# Wo würde man landen, wenn man hier durchs Loch fällt?
					var top := _surface(job, x, z, false)
					var landing := -INF
					var on_shell := false
					for f: int in face_index.get(Vector2i(floori(x / 8.0), floori(z / 8.0)), PackedInt32Array()):
						var hit: Variant = Geometry3D.segment_intersects_triangle(Vector3(x, top + 30.0, z), Vector3(x, top - 200.0, z),
							faces[f], faces[f + 1], faces[f + 2])
						if hit != null and (hit as Vector3).y > landing:
							landing = (hit as Vector3).y
							on_shell = shell[f] == 1
					if landing == -INF:
						_bad("Loch im Gelände: Fall unter die Map", Vector3(x, top, z), "Gelände %.1f, darunter nichts%s" % [
							top, _tube_info(segments, Vector3(x, top, z))])
					elif not on_shell and _inside_tube(segments, Vector3(x, landing, z)):
						_bad("Loch im Gelände: Fall in die Röhre", Vector3(x, top, z), "Gelände %.1f, Landung %.1f%s" % [
							top, landing, _tube_info(segments, Vector3(x, top, z))])


## Liegt der Punkt unter dem Dach einer Röhre (hinter dem Portal, zwischen den Wänden)?
func _inside_tube(segments: Array[RoadSegment], q: Vector3) -> bool:
	for seg in segments:
		for r in seg.tunnel_ranges:
			for i in range(r.x, r.y):
				var a := seg.points[i]
				var b := seg.points[i + 1]
				var ab := Vector2(b.x - a.x, b.z - a.z)
				var t := Vector2(q.x - a.x, q.z - a.z).dot(ab) / maxf(ab.length_squared(), 0.0001)
				if t < 0.0 or t > 1.0:
					continue
				var p := a.lerp(b, t)
				# Die ersten Meter hinter einem Portal gehören zur Mündung (dort landet man vorn an der
				# Öffnung, nicht unter dem Dach)
				var from_portal := INF
				if r.x > 0:
					from_portal = (i - r.x + t) * RoadSegment.POINT_SPACING
				if r.y < seg.points.size() - 1:
					from_portal = minf(from_portal, (r.y - i - t) * RoadSegment.POINT_SPACING)
				if from_portal < 1.0:
					continue
				var lateral := Vector2(q.x - p.x, q.z - p.z).length()
				if lateral < seg.tube_half_width() and q.y < p.y + RoadSegment.TUBE_APEX and q.y > p.y - 1.0:
					return true
	return false


## Lage eines Punkts zur nächsten Röhre (Fehlersuche): seitlich, Abstand zum Portal, Fahrbahnhöhe
func _tube_info(segments: Array[RoadSegment], q: Vector3) -> String:
	var best := ""
	var best_d := INF
	for seg in segments:
		for r in seg.tunnel_ranges:
			for i in range(r.x, r.y + 1):
				var d := Vector2(seg.points[i].x - q.x, seg.points[i].z - q.z).length()
				if d < best_d:
					best_d = d
					var portal := INF
					if r.x > 0:
						portal = minf(portal, (i - r.x) * RoadSegment.POINT_SPACING)
					if r.y < seg.points.size() - 1:
						portal = minf(portal, (r.y - i) * RoadSegment.POINT_SPACING)
					best = " (Röhre %s Punkt %d/%d: seitlich %.1f m, Portal %.0f m, Fahrbahn %.1f, halbe Breite %.1f)" % [
						seg.key, i, seg.points.size(), _lateral(seg, i, q).x, portal, seg.points[i].y, seg.tube_half_width()]
	return best


# ---------------------------------------------------------------------------
# Ergebnis
# ---------------------------------------------------------------------------

func _kind(key: Vector3i) -> String:
	if RoadNetwork.is_road_key(key):
		return "Landstraße"
	if RoadNetwork.is_highway_key(key):
		return "Autobahn"
	if RoadNetwork.is_rest_key(key):
		return "Raststätte"
	return "Zubringer" if RoadNetwork.interchange_part(key) == 0 else "Rampe"


func _bad(cause: String, at: Vector3, text: String) -> void:
	var places: Dictionary = bad.get(cause, {})
	var place := Vector2i(floori(at.x / PLACE_SIZE), floori(at.z / PLACE_SIZE))
	if not places.has(place):
		places[place] = [at.x, at.z, text]
	bad[cause] = places


func _total() -> int:
	var total := 0
	for cause: String in bad:
		total += (bad[cause] as Dictionary).size()
	return total


func _report() -> void:
	var lines: PackedStringArray = []
	lines.append("WELT-PRÜFUNG: %d Felder, %d Abschnitte, %d Kreuzungen, %d Kacheln, %d Pflanzen/Felsen, %d Häuser, %d Loch-Dreiecke" % [
		tiles.size(), stats["segments"], stats["junctions"], stats["chunks"], stats["trees"], stats["houses"], stats["holes"]])
	var causes := bad.keys()
	causes.sort()
	for cause: String in causes:
		var places: Dictionary = bad[cause]
		lines.append("  %s: %d Stellen" % [cause, places.size()])
	var full := lines.duplicate()
	for cause: String in causes:
		var places: Dictionary = bad[cause]
		var shown := 0
		full.append("")
		full.append("%s (%d):" % [cause, places.size()])
		for place: Vector2i in places:
			var entry: Array = places[place]
			var line := "  (%d, %d) %s   Foto: --pos=%d,%d --cam=%d,%d,25 --lookat=%d,%d,1" % [
				entry[0], entry[1], entry[2], entry[0], entry[1], entry[0] + 25, entry[1] + 25, entry[0], entry[1]]
			full.append(line)
			if shown < 4:
				lines.append(line)
				shown += 1
	for kind: String in vertical:
		var entry: Array = vertical[kind]
		var line := "KUPPEN %s: größter Knick %.3f (Steigungswechsel pro 4 m) bei %s, kleinster Halbmesser %.0f m bei %s; Halbmesser unter 400 m an %.2f %%, unter 1000 m an %.2f %% der Punkte" % [
			kind, entry[0], (entry[1] as Vector3).round(), entry[2], (entry[3] as Vector3).round(),
			100.0 * int(entry[5]) / maxi(int(entry[4]), 1), 100.0 * int(entry[6]) / maxi(int(entry[4]), 1)]
		lines.append(line)
		full.append(line)
	lines.append("ERGEBNIS: %d Stellen" % _total())
	for line in lines:
		print(line)
	var path := ProjectSettings.globalize_path("res://screenshots/world_check.txt")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("\n".join(full) + "\n")
	print("Ganze Liste: ", path)
