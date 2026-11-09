extends SceneTree
## Prüfwerkzeug: Liegt irgendetwas Sichtbares in einer Tunnelröhre?
##
## Lädt die Welt nacheinander an mehreren Stellen (--centers=X,Z;X,Z, oder --grid=N: N × N
## Stellen auf 40 × 40 km). Für jede Röhre in der Nähe wird alle 4 m an fünf Querpositionen
## (Wände, halb, Mitte) geprüft, ob zwischen Fahrbahn und Röhrendecke liegt:
## - Gelände: Kacheln aller Detailstufen, genauso berechnet wie im Spiel
## - Schürzen: die Streifen, die an den Kachelrändern nach unten hängen (alle Detailstufen)
## - geladene Kacheln: die echten Kacheln im Spiel (auch solche, die vor dem Tunnel gebaut wurden)
## - Horizont-Ring: Fläche (unter fertigen Kacheln 124 m abgesenkt, sonst 4 m) und die Schürze
##   am inneren Rand (bis -400 m), wie sie bei der Durchfahrt liegen; was die Tunnel-Maske
##   (TunnelMask) im Shader wegschneidet, zählt nicht
## - Wasser (Flüsse und Seen), Bäume, Büsche und Felsen
## Nah am Auto wird zusätzlich die echte Kollision per Strahl geprüft. Ausgabe: Anzahl der
## Stellen je Ursache, Beispiele und die längsten Tunnel (für Fotos mit dem Autopiloten).
##
## Aufruf (im Projektordner):
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s res://tools/tunnel_check.gd
##   ... -- --centers=0,0;6000,-1000      oder      ... -- --grid=5      (--nomask: Ring ohne Maske)

const LATERALS: Array[float] = [-0.95, -0.6, 0.0, 0.6, 0.95]
## Toleranz: so nah an Fahrbahn bzw. Decke zählt noch nicht als „in der Röhre“
const MARGIN: float = 0.2
## Strahlen für die Kollision nur bis zu dieser Entfernung vom Auto (dort gibt es Kollision)
const COLLISION_RANGE: float = 280.0
## Horizont-Ring: so weit sinkt er unter fertigen bzw. fehlenden Kacheln (wie terrain.gdshader)
const RING_SINK_LOADED: float = 124.0
const RING_SINK_EMPTY: float = 4.0

var main: Node
var centers: Array[Vector2] = [Vector2(0, 0), Vector2(-1562, -8360), Vector2(4000, -4000), Vector2(-4000, 4000),
	Vector2(8000, 0), Vector2(0, 8000)]
var center_index := -1
var phase := "load"
var t := 0.0
var jobs: Dictionary = {}  # Vector3i(x, z, Stufe) -> TerrainChunkJob (oder null = nicht berechenbar)
var checked: Dictionary = {}  # Segment-Schlüssel -> true
var samples := 0
var tunnels: Array = []  # [Länge, Schlüssel, Anfang, Ende, Autobahn?]
var bad: Dictionary = {}  # Ursache -> {Stelle: true}
var collision_bad := 0
var collision_rays := 0
var examples: Dictionary = {}  # Ursache -> Beispieltext
var unchecked := 0
var ring_mask: TunnelMask


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--centers="):
			centers.clear()
			for pair in arg.trim_prefix("--centers=").split(";"):
				var xz := pair.split(",")
				centers.append(Vector2(float(xz[0]), float(xz[1])))
		elif arg.begins_with("--grid="):
			var n := int(arg.trim_prefix("--grid="))
			centers.clear()
			for gz in n:
				for gx in n:
					centers.append(Vector2(-20000.0 + 40000.0 * (gx + 0.5) / n, -20000.0 + 40000.0 * (gz + 0.5) / n))
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _process(delta: float) -> bool:
	t += delta
	# Die Garage hält das Spiel an (dann käme ein Sprung nie an)
	if main.garage and main.garage.is_open:
		main.garage.close(true)
	match phase:
		"load":
			if main.world_is_ready and t > 2.0:
				_next_center()
		"jump":
			if main.world_is_ready and t > 3.0:
				phase = "check"
			elif fmod(t, 10.0) < delta:
				print("  warte nach Sprung: %.0f s, Welt bereit: %s, Kacheln in Arbeit: %d" % [t, main.world_is_ready, main.terrain.pending_count()])
		"check":
			_check_here()
			print("Prüfstelle %d/%d fertig: %d Röhren, %d Kachel-Berechnungen bisher" % [
				center_index + 1, centers.size(), tunnels.size(), jobs.size()])
			_next_center()
	return false


func _next_center() -> void:
	center_index += 1
	if center_index >= centers.size():
		_report()
		quit()
		return
	t = 0.0
	if center_index == 0 and main.car.global_position.distance_to(Vector3(centers[0].x, main.car.global_position.y, centers[0].y)) < 500.0:
		phase = "check"
		return
	main.jump_to(centers[center_index])
	phase = "jump"


func _check_here() -> void:
	var roads: RoadNetwork = main.roads
	var car_pos: Vector3 = main.car.global_position
	var here := Vector2(car_pos.x, car_pos.z)
	var area := Rect2(here - Vector2(2500, 2500), Vector2(5000, 5000))
	# Tunnel-Maske des Horizont-Rings so, wie sie hier im Spiel liegt
	ring_mask = TunnelMask.new()
	# --nomask: wie früher ohne Maske (zum Vergleich)
	ring_mask.rasterize([] if "--nomask" in OS.get_cmdline_user_args() else roads.loaded_segments(area.grow(4000.0)), here)
	for pair: Array in roads.loaded_segments(area):
		var key: Vector3i = pair[0]
		var segment: RoadSegment = pair[1]
		if segment.tunnel_ranges.is_empty() or checked.has(key):
			continue
		checked[key] = true
		for range_: Vector2i in segment.tunnel_ranges:
			var length := (range_.y - range_.x) * RoadSegment.POINT_SPACING
			tunnels.append([length, key, segment.points[range_.x], segment.points[range_.y],
				segment.kind == RoadSegment.Kind.HIGHWAY])
			var vegetation := _vegetation_near(roads, segment, range_)
			for i in range(range_.x, range_.y + 1):
				_check_point(roads, segment, key, i, car_pos, vegetation)
				if i < range_.y:
					_check_borders(roads, segment, key, i)


## Ein Punkt der Röhre: an fünf Querpositionen gegen alles Sichtbare
func _check_point(roads: RoadNetwork, segment: RoadSegment, key: Vector3i, i: int, car_pos: Vector3,
		vegetation: Array) -> void:
	var p := segment.points[i]
	var left := Vector3.UP.cross(segment.direction_at(i)).normalized()
	var w := segment.tube_half_width()
	var world_gen: WorldGen = main.world_gen
	var place := "%s/%d" % [key, i]
	var kind := "Autobahn" if segment.kind == RoadSegment.Kind.HIGHWAY else "Landstraße"
	for f in LATERALS:
		var d := f * w
		var q := p + left * d
		var span := _tube_span(segment, i, f)
		var floor_y := span.x
		var top_y := span.y
		samples += 1
		# Gelände in allen Detailstufen
		for lod in 4:
			var job := _job(roads, Vector2i(floori(q.x / 256.0), floori(q.z / 256.0)), lod)
			if job == null:
				unchecked += 1
				continue
			var h: float = _surface(job, q.x, q.z)
			if _inside(h, floor_y, top_y):
				_bad("Gelände Stufe %d" % lod, place, "%s bei %s: Gelände %.1f, Fahrbahn %.1f, Decke %.1f" % [
					kind, Vector2(q.x, q.z).round(), h, floor_y, top_y])
		# Die echte, geladene Kachel (kann vor dem Tunnel gebaut worden sein)
		var chunk: Object = (main.terrain.get("_chunks") as Dictionary).get(Vector2i(floori(q.x / 256.0), floori(q.z / 256.0)))
		if chunk and chunk.get("job"):
			var live: TerrainChunkJob = chunk.get("job")
			var h_live := _surface(live, q.x, q.z)
			if _inside(h_live, floor_y, top_y):
				_bad("geladene Kachel (Stufe %d)" % live.lod, place, "%s bei %s: %.1f zwischen %.1f und %.1f" % [
					kind, Vector2(q.x, q.z).round(), h_live, floor_y, top_y])
		# Horizont-Ring: Fläche und Schürze am inneren Rand, außer wo die Maske sie wegschneidet
		var natural := world_gen.natural_height(q.x, q.z)
		for sink: float in [RING_SINK_LOADED, RING_SINK_EMPTY]:
			var surface := natural - sink
			var hidden_surface := ring_mask.hides(q.x, q.z, surface)
			if _inside(surface, floor_y, top_y) and not hidden_surface:
				_bad("Horizont-Ring Fläche (abgesenkt %d m)" % sink, place, "%s bei %s: Ring %.1f zwischen %.1f und %.1f" % [
					kind, Vector2(q.x, q.z).round(), surface, floor_y, top_y])
			# Die Schürze reicht von der Fläche bis -400 m (abgesenkt): schneidet sie die Röhre?
			var skirt_low := -400.0 - sink
			var crosses := surface > floor_y + MARGIN and skirt_low < top_y - MARGIN
			var y_in_tube := clampf((floor_y + top_y) * 0.5, skirt_low, surface)
			if crosses and not ring_mask.hides(q.x, q.z, y_in_tube):
				_bad("Horizont-Ring Schürze (abgesenkt %d m)" % sink, place, "%s bei %s: Schürze %.0f bis %.0f, Röhre %.1f–%.1f" % [
					kind, Vector2(q.x, q.z).round(), surface, skirt_low, floor_y, top_y])
		# Wasser (Flüsse und Seen)
		var lakes: Array = world_gen.lakes_near(Rect2(q.x - 1, q.z - 1, 2, 2))
		var water := world_gen.water_level_at(q.x, q.z, lakes)
		if water > WorldGen.NO_WATER and _inside(water, floor_y, top_y):
			_bad("Wasser", place, "%s bei %s: Wasser %.1f zwischen %.1f und %.1f" % [
				kind, Vector2(q.x, q.z).round(), water, floor_y, top_y])
		# Echte Kollision (nur nah am Auto, dort liegt Stufe 0 mit Kollision)
		if Vector2(q.x - car_pos.x, q.z - car_pos.z).length() < COLLISION_RANGE:
			collision_rays += 1
			var space := (main as Node3D).get_world_3d().direct_space_state
			var query := PhysicsRayQueryParameters3D.create(Vector3(q.x, floor_y + 0.4, q.z), Vector3(q.x, top_y - 0.3, q.z))
			query.hit_from_inside = false
			var hit := space.intersect_ray(query)
			if not hit.is_empty() and _is_terrain(hit["collider"]):
				collision_bad += 1
				_bad("Kollision", place, "bei %s: Gelände bei %.1f, Fahrbahn %.1f" % [
					Vector2(q.x, q.z).round(), (hit["position"] as Vector3).y, floor_y])
	# Bäume, Büsche und Felsen: steckt ein Stamm- oder Felsfuß in der Röhre?
	for item: Array in vegetation:
		var pos: Vector3 = item[1]
		var rel := pos - p
		if absf(rel.dot(segment.direction_at(i))) > RoadSegment.POINT_SPACING * 0.5:
			continue
		var lateral := rel.dot(left)
		if absf(lateral) > w + 1.5:
			continue
		var span := _tube_span(segment, i, clampf(lateral / w, -1.0, 1.0))
		if pos.y < span.y + 0.3:
			_bad("Pflanze/Fels (%s)" % item[0], place, "%s bei %s: Fuß %.1f, Decke %.1f" % [
				kind, Vector2(pos.x, pos.z).round(), pos.y, span.y])


## Schürzen: wo eine Querlinie der Röhre einen Kachelrand kreuzt, hängt dort in jeder
## Detailstufe ein Streifen von der Geländekante nach unten
func _check_borders(roads: RoadNetwork, segment: RoadSegment, key: Vector3i, i: int) -> void:
	var left0 := Vector3.UP.cross(segment.direction_at(i)).normalized()
	var left1 := Vector3.UP.cross(segment.direction_at(i + 1)).normalized()
	var w := segment.tube_half_width()
	for f in LATERALS:
		var q0 := segment.points[i] + left0 * f * w
		var q1 := segment.points[i + 1] + left1 * f * w
		for axis in 2:
			var a := q0.x if axis == 0 else q0.z
			var b := q1.x if axis == 0 else q1.z
			var border := ceilf(minf(a, b) / 256.0) * 256.0
			if border > maxf(a, b) or is_equal_approx(a, b):
				continue
			var s := (border - a) / (b - a)
			var q := q0.lerp(q1, s)
			var span0 := _tube_span(segment, i, f)
			var span1 := _tube_span(segment, i + 1, f)
			var floor_y := lerpf(span0.x, span1.x, s)
			var top_y := lerpf(span0.y, span1.y, s)
			# Beide Kacheln am Rand haben dort eine Schürze
			for side: float in [-1.0, 1.0]:
				var probe := q + (Vector3(side, 0, 0) if axis == 0 else Vector3(0, 0, side)) * 0.01
				for lod in 4:
					var job := _job(roads, Vector2i(floori(probe.x / 256.0), floori(probe.z / 256.0)), lod)
					if job == null:
						continue
					var h := _surface(job, q.x, q.z)
					if is_nan(h):
						continue
					var bottom := job.skirt_bottom_at(q.x, q.z)
					if bottom < top_y - MARGIN and h > floor_y + MARGIN:
						_bad("Schürze Stufe %d" % lod, "%s/%d" % [key, i], "bei %s: Kante %.1f, unten %.1f, Röhre %.1f–%.1f" % [
							Vector2(q.x, q.z).round(), h, bottom, floor_y, top_y])


## Fahrbahn- und Deckenhöhe an Punkt i bei Querlage f (-1 bis 1 der halben Röhrenbreite)
func _tube_span(segment: RoadSegment, i: int, f: float) -> Vector2:
	var p := segment.points[i]
	var d := f * segment.tube_half_width()
	var rise := RoadSegment.TUBE_APEX - RoadSegment.TUBE_WALL
	return Vector2(p.y - segment.bank[i] * d, p.y + RoadSegment.TUBE_WALL + rise * sqrt(maxf(1.0 - f * f, 0.0)))


func _inside(h: float, floor_y: float, top_y: float) -> bool:
	return not is_nan(h) and h > floor_y + MARGIN and h < top_y - MARGIN


func _bad(cause: String, place: String, example: String) -> void:
	var places: Dictionary = bad.get(cause, {})
	places[place] = true
	bad[cause] = places
	if not examples.has(cause):
		examples[cause] = example


## Bäume, Büsche und Felsen der Kacheln entlang eines Tunnels: [Art, Fußpunkt]
func _vegetation_near(roads: RoadNetwork, segment: RoadSegment, range_: Vector2i) -> Array:
	var result: Array = []
	var coords := {}
	for i in range(range_.x, range_.y + 1):
		coords[Vector2i(floori(segment.points[i].x / 256.0), floori(segment.points[i].z / 256.0))] = true
	for coord: Vector2i in coords:
		var job := _job(roads, coord, 0, true)
		if job == null:
			continue
		for kind: String in job.vegetation:
			var data: PackedFloat32Array = job.vegetation[kind]
			# Positionen liegen relativ zur Kachel
			for k in range(0, data.size(), 16):
				result.append([kind, Vector3(data[k + 3] + coord.x * job.chunk_size, data[k + 7],
					data[k + 11] + coord.y * job.chunk_size)])
	return result


func _is_terrain(collider: Object) -> bool:
	if not collider is Node:
		return false
	for child in (collider as Node).get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape is HeightMapShape3D:
			return true
	return false


## Kachel in einer Detailstufe genauso berechnen wie der TerrainManager
func _job(roads: RoadNetwork, coord: Vector2i, lod: int, vegetation: bool = false) -> TerrainChunkJob:
	var id := Vector3i(coord.x, coord.y, lod + (10 if vegetation else 0))
	if jobs.has(id):
		return jobs[id]
	var terrain: TerrainManager = main.terrain
	var road_data := roads.segments_for_rect(Rect2(coord.x * 256.0, coord.y * 256.0, 256.0, 256.0))
	var job: TerrainChunkJob = null
	if not road_data.is_empty():
		job = TerrainChunkJob.new()
		job.world_gen = main.world_gen
		job.coord = coord
		job.lod = lod
		job.spacing = terrain.lod_spacings[lod]
		job.chunk_size = terrain.chunk_size
		job.road_segments = road_data["segments"]
		job.road_pads = road_data["pads"]
		job.with_vegetation = vegetation
		job.tree_spacing = terrain.tree_spacing
		job.rock_spacing = terrain.rock_spacing
		job.run()
	jobs[id] = job
	if jobs.size() % 50 == 0:
		print("  %d Kacheln berechnet" % jobs.size())
	return job


## Höhe der sichtbaren Fläche (wie im Mesh: zwei Dreiecke pro Quadrat), NaN = Loch
func _surface(job: TerrainChunkJob, x: float, z: float) -> float:
	var fx := (x - job.coord.x * job.chunk_size) / job.spacing
	var fz := (z - job.coord.y * job.chunk_size) / job.spacing
	var n := job.grid_size
	var ix := clampi(floori(fx), 0, n - 2)
	var iz := clampi(floori(fz), 0, n - 2)
	var tx := clampf(fx - ix, 0.0, 1.0)
	var tz := clampf(fz - iz, 0.0, 1.0)
	var a := iz * n + ix
	var corners := PackedInt32Array([a, a + 1, a + n]) if tx + tz <= 1.0 else PackedInt32Array([a + 1, a + n + 1, a + n])
	var holes := job.collision_heights
	if not holes.is_empty():
		for c in corners:
			if is_nan(holes[c]):
				return NAN
	var hs := job.heights
	if tx + tz <= 1.0:
		return hs[a] + (hs[a + 1] - hs[a]) * tx + (hs[a + n] - hs[a]) * tz
	return hs[a + n + 1] + (hs[a + n] - hs[a + n + 1]) * (1.0 - tx) + (hs[a + 1] - hs[a + n + 1]) * (1.0 - tz)


func _report() -> void:
	var total_length := 0.0
	for tunnel: Array in tunnels:
		total_length += tunnel[0]
	print("TUNNEL-PRÜFUNG: %d Röhren, %.1f km, %d Querpunkte geprüft (%d Kachel-Proben nicht berechenbar)" % [
		tunnels.size(), total_length / 1000.0, samples, unchecked])
	var total := 0
	var causes := bad.keys()
	causes.sort()
	for cause: String in causes:
		var count: int = (bad[cause] as Dictionary).size()
		total += count
		print("  %s: %d Stellen   (z. B. %s)" % [cause, count, examples[cause]])
	print("  Kollision (nah am Auto, %d Strahlen): %d Treffer im Gelände" % [collision_rays, collision_bad])
	tunnels.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	for highway: bool in [false, true]:
		var shown := 0
		for tunnel: Array in tunnels:
			if tunnel[4] != highway or shown >= 3:
				continue
			shown += 1
			var a: Vector3 = tunnel[2]
			var b: Vector3 = tunnel[3]
			print("  Langer Tunnel (%s): %.0f m, %s, von %s nach %s" % ["Autobahn" if highway else "Landstraße",
				tunnel[0], tunnel[1], Vector2(a.x, a.z).round(), Vector2(b.x, b.z).round()])
	print("ERGEBNIS: %d Stellen mit Sichtbarem in der Röhre, %d in der Kollision" % [total, collision_bad])
