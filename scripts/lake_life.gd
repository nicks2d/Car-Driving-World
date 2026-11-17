class_name LakeLife
extends Node3D
## Leben an den Seen (noch ohne Menschen): An Seen nah an einer Straße eine Badestelle (Holzsteg,
## Liegewiese, Kiosk mit Sonnenschirmen) oder ein Campingplatz (Wohnwagen, Zelte, Laternen, nachts
## ein Lagerfeuer mit flackerndem Licht). Zufahrt: Schotterparkplatz an der Straße und ein kurzer
## Weg zum Ufer. Auf jedem See treiben ein paar Segel- und Ruderboote langsam herum, die Segel
## stehen im Wind; im Winter keine Boote. Alles im Code gebaut und nur in der Nähe (Sichtweite).
## Welcher See was bekommt, hängt am Seed; die Stelle am Ufer an der nächsten Straße.

@export var car: Node3D
@export var world_gen: WorldGen
@export var roads: RoadNetwork
@export var weather: Weather
## So weit weg werden Plätze und Boote gebaut bzw. entfernt (Meter)
@export var build_distance: float = 1400.0
## Lagerfeuer: Flammen und Licht nur bis hierher (Meter)
@export var fire_distance: float = 160.0
## Wie schnell Boote treiben (Meter pro Sekunde)
@export var boat_speed: float = 0.6

## Anteile: Badestelle, Campingplatz, nichts (Rest)
const BATH_SHARE: int = 40
const CAMP_SHARE: int = 35
## Die Straße darf höchstens so weit vom Ufer weg sein (Meter)
const MAX_ROAD_DISTANCE: float = 380.0

static var _material: StandardMaterial3D
static var _glow: StandardMaterial3D

var _lakes: Dictionary = {}  # Mittelpunkt -> {"node", "boats", "fire", "light", "lamps"}
var _timer: float = 0.0
var _time: float = 0.0


func _process(delta: float) -> void:
	var started := Time.get_ticks_usec()
	_timed_process(delta)
	FrameCosts.add("Seeleben", started)


func _timed_process(delta: float) -> void:
	if car == null or world_gen == null or roads == null:
		return
	_time += delta
	_animate(delta)
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.7
	# Bezugspunkt ist die Kamera (Fotomodus, freie Kamera), sonst das Auto
	var camera := get_viewport().get_camera_3d()
	var eye := camera.global_position if camera else car.global_position
	var p := Vector2(eye.x, eye.z)
	var wanted := {}
	for lake: WorldGen.Lake in world_gen.lakes_near(Rect2(p - Vector2.ONE * build_distance, Vector2.ONE * build_distance * 2.0), false, false):
		if lake.center.distance_to(p) < build_distance + lake.radius:
			wanted[lake.center] = lake
	for center: Vector2 in _lakes.keys():
		if not wanted.has(center):
			(_lakes[center]["node"] as Node3D).queue_free()
			_lakes.erase(center)
	for center: Vector2 in wanted:
		if not _lakes.has(center):
			var built := _build_lake(wanted[center])
			if not built.is_empty():
				_lakes[center] = built
	_update_night(p)


# ---------------------------------------------------------------------------
# Aufbau
# ---------------------------------------------------------------------------

## Einen See einrichten; leer, wenn die Straßen dort noch nicht berechnet sind (später noch mal)
func _build_lake(lake: WorldGen.Lake) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_gen.hash_cell(roundi(lake.center.x), roundi(lake.center.y), 717)
	var roll := rng.randi_range(0, 99)
	var kind := "bath" if roll < BATH_SHARE else ("camp" if roll < BATH_SHARE + CAMP_SHARE else "")
	var node := Node3D.new()
	add_child(node)
	node.position = Vector3(lake.center.x, lake.level, lake.center.y)
	var entry := {"node": node, "boats": [], "fire": null, "light": null, "lamps": PackedVector3Array()}
	if kind != "":
		var site := _find_site(lake)
		if site.is_empty() and roads.loaded_segments(Rect2(lake.center - Vector2.ONE * (lake.radius + 400.0),
				Vector2.ONE * (lake.radius + 400.0) * 2.0)).is_empty():
			# Die Straßen dort sind noch nicht berechnet: später noch einmal
			node.queue_free()
			return {}
		if not site.is_empty():
			_build_site(lake, site, kind, rng, node, entry)
	_build_boats(lake, rng, node, entry)
	return entry


## Stelle am Ufer an der nächsten Straße (dort, wo wenig Wald steht): {"shore", "out" (Richtung
## vom See weg), "road" (Straßenpunkt), "road_dir"} oder leer
func _find_site(lake: WorldGen.Lake) -> Dictionary:
	var reach := lake.radius + MAX_ROAD_DISTANCE
	var best: Dictionary = {}
	var best_distance := INF
	for pair: Array in roads.loaded_segments(Rect2(lake.center - Vector2.ONE * reach, Vector2.ONE * reach * 2.0)):
		var segment: RoadSegment = pair[1]
		if segment.kind != RoadSegment.Kind.ROAD:
			continue
		for i in range(0, segment.points.size(), 3):
			var q := segment.points[i]
			if segment.bridge[i] == 1 or segment.tunnel[i] == 1:
				continue
			var d := Vector2(q.x, q.z).distance_to(lake.center) - lake.radius
			if d > 40.0 and d < MAX_ROAD_DISTANCE and d < best_distance:
				best_distance = d
				best = {"road": q, "road_dir": segment.direction_at(i)}
	if best.is_empty():
		return {}
	# Am Ufer in Richtung Straße, ±35° die Stelle mit dem wenigsten Wald
	var toward: Vector2 = (Vector2(best["road"].x, best["road"].z) - lake.center).normalized()
	var lakes: Array = world_gen.lakes_near(Rect2(lake.center, Vector2.ONE), false, false)
	var best_forest := INF
	for k in range(-4, 5):
		var direction := toward.rotated(deg_to_rad(k * 9.0))
		var shore := lake.center + direction * (lake.radius + 14.0)
		var h := world_gen.terrain_height(shore.x, shore.y, lakes)
		var forest := world_gen.forest_density(shore.x, shore.y, h, 0.1) + absf(k) * 0.03
		if forest < best_forest:
			best_forest = forest
			best["shore"] = lake.center + direction * lake.radius
			best["out"] = direction
	return best


func _height(x: float, z: float) -> float:
	return world_gen.terrain_height(x, z, world_gen.lakes_near(Rect2(x - 1.0, z - 1.0, 2.0, 2.0), false, false))


func _build_site(lake: WorldGen.Lake, site: Dictionary, kind: String, rng: RandomNumberGenerator, node: Node3D,
		entry: Dictionary) -> void:
	var b := MeshBuilder.new()
	var o := node.position
	var shore: Vector2 = site["shore"]
	var out: Vector2 = site["out"]
	var side := Vector2(-out.y, out.x)
	var at := func(along: float, across: float) -> Vector3:
		var q := shore + out * along + side * across
		return Vector3(q.x, _height(q.x, q.y), q.y)
	# Parkplatz an der Straße (Schotter) und Weg zum Ufer
	var road: Vector3 = site["road"]
	var road_dir: Vector3 = site["road_dir"]
	var road_left := Vector3.UP.cross(Vector3(road_dir.x, 0.0, road_dir.z)).normalized()
	var lake_side := road_left if road_left.dot(Vector3(lake.center.x - road.x, 0.0, lake.center.y - road.z)) > 0.0 else -road_left
	var lot := road + lake_side * 13.0
	b.color = Color(0.48, 0.45, 0.4)
	_flat_patch(b, Vector2(lot.x, lot.z), Vector2(road_dir.x, road_dir.z).normalized(), 20.0, 11.0, o)
	var path_start := Vector2(lot.x, lot.z) + Vector2(lake_side.x, lake_side.z) * 5.0
	var path_end := shore + out * 18.0
	var steps := maxi(ceili(path_start.distance_to(path_end) / 4.0), 1)
	var path_dir := (path_end - path_start).normalized()
	var path_side := Vector2(-path_dir.y, path_dir.x) * 1.5
	for k in steps:
		var a0 := path_start.lerp(path_end, float(k) / steps)
		var a1 := path_start.lerp(path_end, float(k + 1) / steps)
		var p00 := a0 - path_side
		var p01 := a0 + path_side
		var p10 := a1 - path_side
		var p11 := a1 + path_side
		b.quad(Vector3(p00.x, _height(p00.x, p00.y) + 0.08, p00.y), Vector3(p01.x, _height(p01.x, p01.y) + 0.08, p01.y),
			Vector3(p11.x, _height(p11.x, p11.y) + 0.08, p11.y), Vector3(p10.x, _height(p10.x, p10.y) + 0.08, p10.y),
			o, Vector2.ZERO, Vector2.ONE)
	if kind == "bath":
		_build_bath(b, lake, at, out, side, rng, o)
	else:
		_build_camp(b, at, out, rng, o, entry)
	var instance := MeshInstance3D.new()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b.arrays())
	instance.mesh = mesh
	instance.material_override = _vertex_material()
	instance.visibility_range_end = build_distance
	node.add_child(instance)


## Badestelle: Liegewiese (hellere Fläche), Holzsteg ins Wasser, Kiosk mit Theke und Schirmen
func _build_bath(b: MeshBuilder, lake: WorldGen.Lake, at: Callable, out: Vector2, side: Vector2,
		rng: RandomNumberGenerator, o: Vector3) -> void:
	var out3 := Vector3(out.x, 0.0, out.y)
	var side3 := Vector3(side.x, 0.0, side.y)
	# Liegewiese: ein heller, frisch gemähter Streifen am Ufer
	b.color = Color(0.42, 0.62, 0.26)
	for k in range(-5, 5):
		for m in 4:
			var c00: Vector3 = at.call(4.0 + m * 5.0, k * 5.0)
			var c10: Vector3 = at.call(9.0 + m * 5.0, k * 5.0)
			var c01: Vector3 = at.call(4.0 + m * 5.0, k * 5.0 + 5.0)
			var c11: Vector3 = at.call(9.0 + m * 5.0, k * 5.0 + 5.0)
			b.quad(c00 + Vector3.UP * 0.05, c10 + Vector3.UP * 0.05, c11 + Vector3.UP * 0.05, c01 + Vector3.UP * 0.05, o, Vector2.ZERO, Vector2.ONE)
	# Holzsteg: Bretter auf Pfählen, 26 m ins Wasser
	var deck_y := lake.level + 0.6
	var start: Vector3 = at.call(2.0, 6.0)
	b.color = Color(0.45, 0.32, 0.2)
	var length := 26.0
	var tip := Vector3(start.x, deck_y, start.z) - out3 * length
	b.box((Vector3(start.x, deck_y, start.z) + tip) * 0.5, Vector3(2.4, 0.15, length), out3, o)
	b.box(tip - out3 * 2.5 + side3 * 2.5, Vector3(7.0, 0.15, 5.0), out3, o)
	b.color = Color(0.3, 0.22, 0.15)
	for k in range(0, int(length) + 1, 4):
		for s: float in [-1.1, 1.1]:
			var post := Vector3(start.x, deck_y, start.z) - out3 * k + side3 * s
			b.box(post + Vector3.DOWN * 1.4, Vector3(0.2, 2.8, 0.2), out3, o)
	# Kiosk: Holzhütte mit Pultdach, Klappe und Theke
	var kiosk: Vector3 = at.call(24.0, -14.0)
	b.color = Color(0.55, 0.4, 0.26)
	b.box(kiosk + Vector3.UP * 1.3, Vector3(4.2, 2.6, 3.2), out3, o)
	b.color = Color(0.25, 0.3, 0.36)
	b.box(kiosk + Vector3.UP * 2.75 - out3 * 0.3, Vector3(4.8, 0.2, 4.2), out3, o)
	b.color = Color(0.95, 0.9, 0.78)
	b.box(kiosk + Vector3.UP * 1.05 - out3 * 1.75, Vector3(3.6, 0.12, 0.5), out3, o)
	b.color = Color(0.9, 0.3, 0.25)
	b.box(kiosk + Vector3.UP * 2.35 - out3 * 2.1, Vector3(4.0, 0.06, 1.2), out3, o)
	# Sonnenschirme: Mast und Schirm (flache Pyramide), bunt
	var colors: Array[Color] = [Color(0.95, 0.3, 0.2), Color(0.2, 0.55, 0.9), Color(0.98, 0.8, 0.2), Color(0.3, 0.75, 0.4)]
	for k in 5:
		var spot: Vector3 = at.call(rng.randf_range(6.0, 18.0), rng.randf_range(-22.0, 22.0))
		b.color = Color(0.85, 0.85, 0.85)
		b.box(spot + Vector3.UP * 1.1, Vector3(0.06, 2.2, 0.06), out3, o)
		b.color = colors[k % colors.size()]
		var top := spot + Vector3.UP * 2.4
		for m in 6:
			var a0 := TAU * m / 6.0
			var a1 := TAU * (m + 1) / 6.0
			b.triangle(top, spot + Vector3(cos(a0) * 1.4, 2.0, sin(a0) * 1.4), spot + Vector3(cos(a1) * 1.4, 2.0, sin(a1) * 1.4), o)


## Campingplatz: Wohnwagen, Zelte, Laternen und eine Feuerstelle (Flammen und Licht kommen nachts)
func _build_camp(b: MeshBuilder, at: Callable, out: Vector2, rng: RandomNumberGenerator, o: Vector3,
		entry: Dictionary) -> void:
	var out3 := Vector3(out.x, 0.0, out.y)
	var stripes: Array[Color] = [Color(0.2, 0.45, 0.75), Color(0.75, 0.25, 0.2), Color(0.25, 0.55, 0.35), Color(0.55, 0.5, 0.25)]
	for k in rng.randi_range(3, 5):
		var spot: Vector3 = at.call(rng.randf_range(16.0, 34.0), -26.0 + k * 13.0 + rng.randf_range(-2.0, 2.0))
		var facing := out3.rotated(Vector3.UP, rng.randf_range(-0.4, 0.4))
		b.color = Color(0.93, 0.93, 0.9)
		b.box(spot + Vector3.UP * 1.55, Vector3(2.3, 2.1, 5.8), facing, o)
		b.color = stripes[k % stripes.size()]
		b.box(spot + Vector3.UP * 1.25, Vector3(2.34, 0.25, 5.84), facing, o)
		b.color = Color(0.15, 0.18, 0.22)
		b.box(spot + Vector3.UP * 1.9 + Vector3.UP.cross(facing) * 1.16, Vector3(0.05, 0.6, 1.6), facing, o)
		b.color = Color(0.1, 0.1, 0.1)
		for s: float in [-1.0, 1.0]:
			b.box(spot + Vector3.UP * 0.35 + Vector3.UP.cross(facing).normalized() * s * 1.0, Vector3(0.25, 0.7, 0.7), facing, o)
	var tent_colors: Array[Color] = [Color(0.9, 0.5, 0.15), Color(0.2, 0.6, 0.35), Color(0.25, 0.4, 0.8), Color(0.85, 0.2, 0.25)]
	for k in rng.randi_range(4, 6):
		var spot: Vector3 = at.call(rng.randf_range(5.0, 13.0), -24.0 + k * 9.0 + rng.randf_range(-2.0, 2.0))
		var facing := out3.rotated(Vector3.UP, rng.randf_range(-0.6, 0.6))
		var across := Vector3.UP.cross(facing).normalized() * 1.2
		var front := facing * 1.4
		var ridge := Vector3.UP * 1.3
		b.color = tent_colors[k % tent_colors.size()]
		b.quad(spot - front + across, spot + front + across, spot + front + ridge, spot - front + ridge, o, Vector2.ZERO, Vector2.ONE)
		b.quad(spot - front - across, spot - front + ridge, spot + front + ridge, spot + front - across, o, Vector2.ZERO, Vector2.ONE)
		b.color = tent_colors[k % tent_colors.size()].darkened(0.25)
		b.triangle(spot + front + across, spot + front - across, spot + front + ridge, o)
		b.triangle(spot - front - across, spot - front + across, spot - front + ridge, o)
	# Laternen am Weg (Leuchten über _glow, nachts hell)
	for k in 4:
		var foot: Vector3 = at.call(10.0 + k * 7.0, 32.0 - k * 5.0)
		b.color = Color(0.15, 0.15, 0.15)
		b.box(foot + Vector3.UP * 1.4, Vector3(0.1, 2.8, 0.1), out3, o)
		entry["lamps"].append(foot + Vector3.UP * 2.9)
	# Feuerstelle: Steinring und Holzscheite
	var fire: Vector3 = at.call(9.0, -2.0)
	b.color = Color(0.45, 0.44, 0.42)
	for m in 8:
		var a := TAU * m / 8.0
		b.box(fire + Vector3(cos(a) * 0.9, 0.12, sin(a) * 0.9), Vector3(0.35, 0.25, 0.3), Vector3(cos(a), 0.0, sin(a)), o)
	b.color = Color(0.3, 0.18, 0.1)
	for m in 3:
		var a := TAU * m / 3.0 + 0.4
		b.box(fire + Vector3.UP * 0.18, Vector3(0.14, 0.14, 1.1), Vector3(cos(a), 0.0, sin(a)), o)
	entry["fire_at"] = fire


## Flache Fläche (Rechteck) auf dem Gelände: Mitte, Längsrichtung, Länge und Breite
func _flat_patch(b: MeshBuilder, center: Vector2, along: Vector2, length: float, width: float, o: Vector3) -> void:
	var across := Vector2(-along.y, along.x)
	for k in 4:
		for m in 2:
			var c := [center + along * (k * 0.25 - 0.5) * length + across * (m * 0.5 - 0.5) * width,
				center + along * ((k + 1) * 0.25 - 0.5) * length + across * (m * 0.5 - 0.5) * width,
				center + along * ((k + 1) * 0.25 - 0.5) * length + across * ((m + 1) * 0.5 - 0.5) * width,
				center + along * (k * 0.25 - 0.5) * length + across * ((m + 1) * 0.5 - 0.5) * width]
			var v: Array[Vector3] = []
			for q: Vector2 in c:
				v.append(Vector3(q.x, _height(q.x, q.y) + 0.1, q.y))
			b.quad(v[0], v[1], v[2], v[3], o, Vector2.ZERO, Vector2.ONE)


## Boote: Segelboote (Rumpf, Mast, Segel) und Ruderboote, jedes treibt auf einem Kreis
func _build_boats(lake: WorldGen.Lake, rng: RandomNumberGenerator, node: Node3D, entry: Dictionary) -> void:
	for k in rng.randi_range(2, 5):
		var sail := rng.randf() < 0.55
		var b := MeshBuilder.new()
		var length := 5.5 if sail else 3.6
		b.color = Color(0.92, 0.92, 0.9) if sail else Color(0.55, 0.36, 0.22)
		# Rumpf: spitzer Bug, flacher Boden
		var half := length * 0.5
		var w := 0.9 if sail else 0.65
		var deck := 0.45
		var bow := Vector3(0, deck, half)
		var pts := [Vector3(-w, deck, -half), Vector3(w, deck, -half), Vector3(w, deck, half * 0.4), bow, Vector3(-w, deck, half * 0.4)]
		var keel := [Vector3(-w * 0.6, -0.2, -half), Vector3(w * 0.6, -0.2, -half), Vector3(w * 0.5, -0.2, half * 0.3), Vector3(0, 0.1, half), Vector3(-w * 0.5, -0.2, half * 0.3)]
		for m in 5:
			b.quad(pts[m], pts[(m + 1) % 5], keel[(m + 1) % 5], keel[m], Vector3.ZERO, Vector2.ZERO, Vector2.ONE)
		b.color = b.color.darkened(0.3)
		b.triangle(pts[0], pts[1], pts[2], Vector3.ZERO)
		b.triangle(pts[0], pts[2], pts[4], Vector3.ZERO)
		b.triangle(pts[4], pts[2], pts[3], Vector3.ZERO)
		var boat := Node3D.new()
		var hull := MeshInstance3D.new()
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b.arrays())
		hull.mesh = mesh
		hull.material_override = _vertex_material()
		boat.add_child(hull)
		var sail_node: Node3D = null
		if sail:
			# Mast und dreieckiges Segel (dreht sich mit dem Wind)
			sail_node = Node3D.new()
			sail_node.position = Vector3(0, deck, half * 0.15)
			var s := MeshBuilder.new()
			s.color = Color(0.75, 0.75, 0.75)
			s.box(Vector3(0, 3.0, 0), Vector3(0.1, 6.0, 0.1), Vector3.BACK, Vector3.ZERO)
			s.color = Color(0.97, 0.96, 0.92) if rng.randf() < 0.7 else Color(0.9, 0.35, 0.3)
			s.triangle(Vector3(0, 0.6, 0), Vector3(0, 6.0, 0), Vector3(0, 0.6, -2.6), Vector3.ZERO)
			var sail_mesh := MeshInstance3D.new()
			var smesh := ArrayMesh.new()
			smesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, s.arrays())
			sail_mesh.mesh = smesh
			sail_mesh.material_override = _vertex_material()
			sail_node.add_child(sail_mesh)
			boat.add_child(sail_node)
		node.add_child(boat)
		var circle_center := Vector2.from_angle(rng.randf() * TAU) * lake.radius * rng.randf_range(0.0, 0.45)
		(entry["boats"] as Array).append({"node": boat, "sail": sail_node, "center": circle_center,
			"radius": rng.randf_range(lake.radius * 0.15, lake.radius * 0.4), "phase": rng.randf() * TAU,
			"direction": 1.0 if rng.randf() < 0.5 else -1.0})


# ---------------------------------------------------------------------------
# Bewegung, Nacht
# ---------------------------------------------------------------------------

func _animate(delta: float) -> void:
	var winter := weather != null and weather.season == Weather.Season.WINTER
	var wind := Vector2(1.0, 0.35).normalized()
	for entry: Dictionary in _lakes.values():
		for boat: Dictionary in entry["boats"]:
			var node: Node3D = boat["node"]
			node.visible = not winter
			if winter:
				continue
			var radius: float = boat["radius"]
			boat["phase"] = float(boat["phase"]) + delta * boat_speed / radius * float(boat["direction"])
			var phase: float = boat["phase"]
			var center: Vector2 = boat["center"]
			var q := center + Vector2(cos(phase), sin(phase)) * radius
			node.position = Vector3(q.x, sin(_time * 1.3 + phase * 3.0) * 0.06, q.y)
			var heading := Vector2(-sin(phase), cos(phase)) * float(boat["direction"])
			node.rotation = Vector3(sin(_time * 0.9 + phase) * 0.03, atan2(heading.x, heading.y), sin(_time * 1.1) * 0.04)
			var sail: Node3D = boat["sail"]
			if sail:
				# Das Segel steht quer zum Wind, so weit das Boot es zulässt
				var relative := wind.angle_to(heading)
				sail.rotation.y = clampf(relative * 0.5, -1.2, 1.2)
	# Lagerfeuer flackern
	for entry: Dictionary in _lakes.values():
		var light: OmniLight3D = entry["light"]
		if light and light.visible:
			light.light_energy = 2.2 + sin(_time * 13.0) * 0.4 + sin(_time * 7.3) * 0.5 + sin(_time * 23.0) * 0.25


func _update_night(p: Vector2) -> void:
	var day_night := get_tree().get_first_node_in_group("day_night") as DayNight
	var night := day_night != null and day_night.sun_direction().y < sin(deg_to_rad(2.0))
	if _glow:
		_glow.emission_energy_multiplier = 6.0 if night else 0.3
	for entry: Dictionary in _lakes.values():
		if not entry.has("fire_at"):
			continue
		var fire_at: Vector3 = entry["fire_at"]
		var near := night and Vector2(fire_at.x, fire_at.z).distance_to(p) < fire_distance
		if near and entry["fire"] == null:
			var fire := _make_fire()
			(entry["node"] as Node3D).add_child(fire)
			fire.global_position = fire_at + Vector3.UP * 0.2
			var light := OmniLight3D.new()
			light.light_color = Color(1.0, 0.6, 0.25)
			light.omni_range = 14.0
			light.shadow_enabled = false
			(entry["node"] as Node3D).add_child(light)
			light.global_position = fire_at + Vector3.UP * 1.0
			entry["fire"] = fire
			entry["light"] = light
		elif not near and entry["fire"] != null:
			(entry["fire"] as Node3D).queue_free()
			(entry["light"] as Node3D).queue_free()
			entry["fire"] = null
			entry["light"] = null
		# Laternen: kleine leuchtende Köpfe (einmal gebaut)
		if not entry.has("lamp_node") and not (entry["lamps"] as PackedVector3Array).is_empty():
			var b := MeshBuilder.new()
			for head: Vector3 in entry["lamps"]:
				b.box(head, Vector3(0.3, 0.35, 0.3), Vector3.BACK, (entry["node"] as Node3D).position)
			var instance := MeshInstance3D.new()
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b.arrays())
			instance.mesh = mesh
			instance.material_override = _glow_material()
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			(entry["node"] as Node3D).add_child(instance)
			entry["lamp_node"] = instance


## Flammen: additive Partikel, unten gelb, oben rot, steigen auf
func _make_fire() -> GPUParticles3D:
	var fire := GPUParticles3D.new()
	fire.amount = 40
	fire.lifetime = 0.7
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.35
	process.direction = Vector3.UP
	process.spread = 12.0
	process.initial_velocity_min = 0.8
	process.initial_velocity_max = 1.8
	process.gravity = Vector3(0, 0.6, 0)
	process.scale_min = 0.6
	process.scale_max = 1.2
	var colors := Gradient.new()
	colors.set_color(0, Color(1.0, 0.85, 0.35, 1.0))
	colors.set_color(1, Color(0.8, 0.1, 0.02, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = colors
	process.color_ramp = ramp
	fire.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.45, 0.6)
	var material := StandardMaterial3D.new()
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad.material = material
	fire.draw_pass_1 = quad
	return fire


static func _vertex_material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.vertex_color_is_srgb = true
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_material.roughness = 0.85
	return _material


static func _glow_material() -> StandardMaterial3D:
	if _glow == null:
		_glow = StandardMaterial3D.new()
		_glow.albedo_color = Color(1.0, 0.85, 0.55)
		_glow.emission_enabled = true
		_glow.emission = Color(1.0, 0.8, 0.5)
		_glow.emission_energy_multiplier = 0.3
	return _glow
