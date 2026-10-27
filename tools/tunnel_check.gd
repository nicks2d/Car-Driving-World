extends SceneTree
## Prüfwerkzeug: Steckt irgendwo Gelände in einer Tunnelröhre?
##
## Lädt die Welt nacheinander an mehreren Stellen (--centers=X,Z;X,Z, Standard: Start und vier
## Punkte 4 km daneben). Für jede Röhre in der Nähe werden alle 4 m an fünf Querpositionen
## (Wände, halb, Mitte) die Kacheln aller Detailstufen genauso berechnet wie im Spiel und
## geprüft, ob die Geländefläche zwischen Fahrbahn und Röhrendecke liegt. Nah am Auto wird
## zusätzlich die echte Kollision per Strahl geprüft. Ausgabe: Anzahl der Stellen je
## Detailstufe und Ursache, dazu Beispiele.
##
## Aufruf (im Projektordner):
##   /Applications/Godot.app/Contents/MacOS/Godot --path . -s res://tools/tunnel_check.gd -- --nowait
##   ... -- --nowait --centers=0,0;6000,-1000

const LATERALS: Array[float] = [-0.95, -0.6, 0.0, 0.6, 0.95]
## Toleranz: so nah an Fahrbahn bzw. Decke zählt noch nicht als „in der Röhre“
const MARGIN: float = 0.2
## Strahlen für die Kollision nur bis zu dieser Entfernung vom Auto (dort gibt es Kollision)
const COLLISION_RANGE: float = 280.0

var main: Node
var centers: Array[Vector2] = [Vector2(0, 0), Vector2(-1562, -8360), Vector2(4000, -4000), Vector2(-4000, 4000),
	Vector2(8000, 0), Vector2(0, 8000)]
var center_index := -1
var phase := "load"
var t := 0.0
var jobs: Dictionary = {}  # Vector3i(x, z, Stufe) -> TerrainChunkJob (oder null = nicht berechenbar)
var checked: Dictionary = {}  # Segment-Schlüssel -> true
var samples := 0
var tunnel_count := 0
var tunnel_length := 0.0
var bad: Dictionary = {}  # "Stufe N: Ursache" -> Anzahl
var bad_points: Dictionary = {}  # Stufe -> {Segment-Index: true} (Stellen, nicht Querpunkte)
var collision_bad := 0
var collision_rays := 0
var examples: Array[String] = []
var unchecked := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--centers="):
			centers.clear()
			for pair in arg.trim_prefix("--centers=").split(";"):
				var xz := pair.split(",")
				centers.append(Vector2(float(xz[0]), float(xz[1])))
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
				center_index + 1, centers.size(), tunnel_count, jobs.size()])
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
	for pair: Array in roads.loaded_segments(Rect2(here - Vector2(2500, 2500), Vector2(5000, 5000))):
		var key: Vector3i = pair[0]
		var segment: RoadSegment = pair[1]
		if segment.tunnel_ranges.is_empty() or checked.has(key):
			continue
		checked[key] = true
		for range_: Vector2i in segment.tunnel_ranges:
			tunnel_count += 1
			tunnel_length += (range_.y - range_.x) * RoadSegment.POINT_SPACING
			for i in range(range_.x, range_.y + 1):
				_check_point(roads, segment, key, i, car_pos)


## Ein Punkt der Röhre: an fünf Querpositionen, für jede Detailstufe
func _check_point(roads: RoadNetwork, segment: RoadSegment, key: Vector3i, i: int, car_pos: Vector3) -> void:
	var p := segment.points[i]
	var left := Vector3.UP.cross(segment.direction_at(i)).normalized()
	var w := segment.tube_half_width()
	var rise := RoadSegment.TUBE_APEX - RoadSegment.TUBE_WALL
	var world_gen: WorldGen = main.world_gen
	for f in LATERALS:
		var d := f * w
		var q := p + left * d
		# Fahrbahn mit Querneigung (positiv = links)
		var floor_y := p.y - segment.bank[i] * d
		var top_y := p.y + RoadSegment.TUBE_WALL + rise * sqrt(maxf(1.0 - f * f, 0.0))
		samples += 1
		for lod in 4:
			var job := _job(roads, Vector2i(floori(q.x / 256.0), floori(q.z / 256.0)), lod)
			if job == null:
				unchecked += 1
				continue
			var h: float = _surface(job, q.x, q.z)
			if is_nan(h) or h <= floor_y + MARGIN or h >= top_y - MARGIN:
				continue
			# Ursache: Lag das natürliche Gelände so hoch, dass die alte Regel kein Loch gemacht hat?
			var natural := world_gen.terrain_height(q.x, q.z, world_gen.lakes_near(Rect2(q.x - 1, q.z - 1, 2, 2)))
			var cause := "abgesenkt nach Loch-Entscheidung" if natural >= p.y + RoadSegment.TUBE_APEX + 1.0 \
				else ("grobes Raster" if lod > 0 else "sonst")
			var label := "Stufe %d (%d m): %s" % [lod, int(job.spacing), cause]
			bad[label] = bad.get(label, 0) + 1
			var points: Dictionary = bad_points.get(lod, {})
			points["%s/%d" % [key, i]] = true
			bad_points[lod] = points
			if examples.size() < 14:
				examples.append("%s bei %s (quer %.1f m): Gelände %.1f, Fahrbahn %.1f, Decke %.1f, natürlich %.1f, %s" % [
					label, Vector2(q.x, q.z).round(), d, h, floor_y, top_y, natural,
					"Autobahn" if segment.kind == RoadSegment.Kind.HIGHWAY else "Landstraße"])
		# Echte Kollision (nur nah am Auto, dort liegt Stufe 0 mit Kollision)
		if Vector2(q.x - car_pos.x, q.z - car_pos.z).length() < COLLISION_RANGE:
			collision_rays += 1
			var space := (main as Node3D).get_world_3d().direct_space_state
			var query := PhysicsRayQueryParameters3D.create(Vector3(q.x, floor_y + 0.4, q.z), Vector3(q.x, top_y - 0.3, q.z))
			query.hit_from_inside = false
			var hit := space.intersect_ray(query)
			if not hit.is_empty() and _is_terrain(hit["collider"]):
				collision_bad += 1
				if examples.size() < 20:
					examples.append("Kollision bei %s (quer %.1f m): Gelände bei %.1f, Fahrbahn %.1f" % [
						Vector2(q.x, q.z).round(), d, (hit["position"] as Vector3).y, floor_y])


func _is_terrain(collider: Object) -> bool:
	if not collider is Node:
		return false
	for child in (collider as Node).get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape is HeightMapShape3D:
			return true
	return false


## Kachel in einer Detailstufe genauso berechnen wie der TerrainManager (ohne Pflanzen)
func _job(roads: RoadNetwork, coord: Vector2i, lod: int) -> TerrainChunkJob:
	var id := Vector3i(coord.x, coord.y, lod)
	if jobs.has(id):
		return jobs[id]
	var terrain: TerrainManager = main.terrain
	var started := Time.get_ticks_msec()
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
		job.with_vegetation = false
		job.run()
	jobs[id] = job
	if jobs.size() % 25 == 0:
		print("  %d Kacheln berechnet (letzte %d ms)" % [jobs.size(), Time.get_ticks_msec() - started])
	return job


## Höhe der sichtbaren Fläche (wie im Mesh: zwei Dreiecke pro Quadrat), NaN = Loch
func _surface(job: TerrainChunkJob, x: float, z: float) -> float:
	var fx := (x - job.coord.x * job.chunk_size) / job.spacing
	var fz := (z - job.coord.y * job.chunk_size) / job.spacing
	var n := job.grid_size
	var ix := clampi(floori(fx), 0, n - 2)
	var iz := clampi(floori(fz), 0, n - 2)
	var tx := fx - ix
	var tz := fz - iz
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
	print("TUNNEL-PRÜFUNG: %d Röhren, %.1f km, %d Querpunkte geprüft (%d Kachel-Proben nicht berechenbar)" % [
		tunnel_count, tunnel_length / 1000.0, samples, unchecked])
	var total := 0
	for lod in 4:
		var count: int = (bad_points.get(lod, {}) as Dictionary).size()
		total += count
		print("  Stufe %d: %d Stellen mit Gelände in der Röhre" % [lod, count])
	for label: String in bad:
		print("    %s: %d Querpunkte" % [label, bad[label]])
	print("  Kollision (nah am Auto, %d Strahlen): %d Treffer im Gelände" % [collision_rays, collision_bad])
	for line in examples:
		print("  Beispiel: ", line)
	print("ERGEBNIS: %d Stellen im Mesh, %d in der Kollision" % [total, collision_bad])
