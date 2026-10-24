class_name Viewpoints
extends Node
## Aussichtspunkte: An manchen Landstraßen liegt eine kleine Parkbucht mit Schild und Bank an
## einer besonderen Stelle (hoch über dem Tal, am Seeufer oder auf der Passhöhe).
## Welche Straße einen hat, entscheidet der Seed (has_spot). Wo genau, sucht der
## Straßenabschnitt nach seiner Berechnung im Hintergrund aus (find_spot), Parkbucht und
## Gelände baut RoadNetwork. Hält man dort an, ist der Punkt entdeckt (gespeichert in
## user://), die Karte zeigt entdeckte mit Kamera, die übrigen in der Nähe mit „?“.

@export var roads: RoadNetwork
@export var car: Car
## So nah an der Parkbucht (Meter) und so langsam (km/h) gilt ein Aussichtspunkt als entdeckt
@export var discover_radius: float = 25.0
@export var discover_speed_kmh: float = 5.0
## Bis zu dieser Entfernung vom Auto zeigt die Karte Aussichtspunkte
@export var map_radius: float = 6000.0

## Anteil der Landstraßen mit Aussichtspunkt
const CHANCE: float = 0.22
## Eine „Gegend“ sind 6 × 6 Ortszellen (7,2 km)
const REGION_CELLS: int = 6
const SAVE_PATH := "user://aussichtspunkte.cfg"
const KIND_NAMES := {"view": "Aussicht", "lake": "Seeufer", "pass": "Passhöhe"}
## Parkbucht: halbe Länge der vollen Breite (danach läuft sie über 12 m schräg aus) und Breite
const BAY_HALF_LENGTH: float = 16.0
const BAY_WIDTH: float = 7.0
## Abstand zu den Enden des Abschnitts (Punkte à 4 m, dort sind Kreuzungen)
const END_MARGIN: int = 35

## Für die Karte: [{"id", "position" (x/z), "found"}] rund ums Auto
var map_spots: Array = []

var _found: Dictionary = {}  # id -> {"name", "kind", "x", "z", "time", "photo"}
var _timer: float = 0.0
var _map_timer: float = 0.0


## Hat diese Landstraße einen Aussichtspunkt? (nur aus dem Seed)
static func has_spot(world_gen: WorldGen, key: Vector3i) -> bool:
	if not RoadNetwork.is_road_key(key):
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = world_gen.hash_cell(key.x, key.y, 404 + key.z)
	return rng.randf() < CHANCE


static func spot_id(key: Vector3i) -> String:
	return "%d,%d,%d" % [key.x, key.y, key.z]


## Abstand der Buchtmitte zur Straßenmitte
static func bay_offset(segment: RoadSegment) -> float:
	return segment.road_width * 0.5 + segment.shoulder_width - 0.5 + BAY_WIDTH * 0.5


## Beste Stelle auf einem berechneten Abschnitt (läuft im Hintergrund, nach dem Bauen):
## {"index", "side" (+1 rechts, -1 links der Punktrichtung), "kind", "center", "look"}.
## Seeufer vor Passhöhe vor Aussicht; leer, wenn nirgends Platz ist.
static func find_spot(segment: RoadSegment) -> Dictionary:
	var points := segment.points
	var n := points.size()
	if n < END_MARGIN * 2 + 10:
		return {}
	var world_gen := segment.world_gen
	var lakes: Array = world_gen.lakes_near(segment.bounds.grow(700.0))
	var offset := bay_offset(segment)
	var best: Dictionary = {}
	var best_score := -INF
	for i in range(END_MARGIN, n - END_MARGIN, 4):
		if not _bay_fits(segment, i):
			continue
		# Passhöhe: höchster Punkt weit und breit, 400 m davor und danach je 30 m tiefer
		var crest := points[i].y - points[maxi(i - 100, 0)].y > 30.0 and points[i].y - points[mini(i + 100, n - 1)].y > 30.0
		for k in range(maxi(i - 25, 0), mini(i + 26, n)):
			if points[k].y > points[i].y:
				crest = false
		var right := segment.direction_at(i).cross(Vector3.UP).normalized()
		for side: float in [1.0, -1.0]:
			var s := right * side
			var center := points[i] + s * offset
			var ground := world_gen.terrain_height(center.x, center.z, lakes)
			if absf(ground - points[i].y) > 5.0 or world_gen.water_level_at(center.x, center.z, lakes) > WorldGen.NO_WATER:
				continue
			# Ufer: Wasser bis 120 m neben der Bucht
			var shore := 0.0
			for d: float in [30.0, 60.0, 90.0, 120.0]:
				var q := center + s * d
				if world_gen.water_level_at(q.x, q.z, lakes) > WorldGen.NO_WATER:
					shore = 200.0 - d
					break
			# Aussicht: wie weit fällt das Land in Blickrichtung ab? (Fächer ±40°, 150–600 m)
			var drop := 0.0
			for angle: float in [-0.7, 0.0, 0.7]:
				var direction := s.rotated(Vector3.UP, angle)
				for d: float in [150.0, 300.0, 600.0]:
					var q := center + direction * d
					drop += points[i].y - world_gen.terrain_height(q.x, q.z, lakes)
			drop /= 9.0
			var kind := "view"
			var score := drop
			if shore > 0.0:
				kind = "lake"
				score = 1000.0 + shore + drop
			elif crest:
				kind = "pass"
				score = 500.0 + drop
			if score > best_score:
				best_score = score
				best = {"index": i, "side": side, "kind": kind, "center": center, "look": s}
	return best


## Passt an Punkt i eine Bucht? Keine Brücke, kein Tunnel, keine enge Kurve, nicht zu steil.
static func _bay_fits(segment: RoadSegment, i: int) -> bool:
	for j in range(i - 7, i + 8):
		if segment.bridge[j] == 1 or segment.tunnel[j] == 1 or absf(segment.curvature[j]) > 1.0 / 250.0:
			return false
		if absf(segment.points[j + 1].y - segment.points[j].y) > RoadSegment.POINT_SPACING * 0.06:
			return false
	return true


## Flache Stellen fürs Gelände (wie Kreuzungen): drei Kreise entlang der Bucht,
## je (x, y, z, Radius)
static func bay_pads(segment: RoadSegment) -> PackedVector4Array:
	var result := PackedVector4Array()
	var i0: int = segment.viewpoint["index"]
	var side: float = segment.viewpoint["side"]
	var offset := bay_offset(segment)
	for j: int in [i0 - 3, i0, i0 + 3]:
		var right := segment.direction_at(j).cross(Vector3.UP).normalized() * side
		var p := segment.points[j] + right * offset
		# Querneigung der Straße fortsetzen
		p.y = segment.points[j].y + segment.bank[j] * side * offset
		result.append(Vector4(p.x, p.y, p.z, BAY_WIDTH * 0.5 + 5.0))
	return result


func _ready() -> void:
	# Die Karte braucht die Punkte auch, wenn das Spiel angehalten ist (große Karte)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()


func _process(delta: float) -> void:
	if roads == null or car == null or roads.world_gen == null:
		return
	_timer -= delta
	if _timer <= 0.0 and not get_tree().paused:
		_timer = 0.25
		_check_discovery()
	_map_timer -= delta
	if _map_timer <= 0.0:
		_map_timer = 2.0
		_update_map_spots()


## Name eines Aussichtspunkts, z. B. „Seeufer bei Tannbach“
func spot_name(key: Vector3i, spot: Dictionary) -> String:
	return "%s bei %s" % [KIND_NAMES[spot["kind"]], roads.highways.place_name(Vector2i(key.x, key.y))]


func found_count() -> int:
	return _found.size()


## [entdeckt, insgesamt] in der Gegend (6 × 6 Ortszellen) um diese Zelle
func region_counts(cell: Vector2i) -> Array:
	var region := Vector2i(floori(cell.x / float(REGION_CELLS)), floori(cell.y / float(REGION_CELLS)))
	var found := 0
	var total := 0
	for cz in range(region.y * REGION_CELLS, (region.y + 1) * REGION_CELLS):
		for cx in range(region.x * REGION_CELLS, (region.x + 1) * REGION_CELLS):
			for dir in 2:
				var key := Vector3i(cx, cz, dir)
				if not _exists(key):
					continue
				total += 1
				if _found.has(spot_id(key)):
					found += 1
	return [found, total]


## Gibt es den Aussichtspunkt (soweit bekannt)? Abschnitte, die schon berechnet sind und
## keinen Platz für eine Bucht hatten, zählen nicht.
func _exists(key: Vector3i) -> bool:
	if not has_spot(roads.world_gen, key) or roads.edge_status(key) == 2:
		return false
	var segment := roads.edge_segment(key)
	return segment == null or not segment.viewpoint.is_empty()


func _check_discovery() -> void:
	if car.linear_velocity.length() * 3.6 > discover_speed_kmh:
		return
	var p := car.global_position
	for pair: Array in roads.loaded_segments(Rect2(p.x - 60.0, p.z - 60.0, 120.0, 120.0)):
		var key: Vector3i = pair[0]
		var segment: RoadSegment = pair[1]
		if segment.viewpoint.is_empty() or _found.has(spot_id(key)):
			continue
		var center: Vector3 = segment.viewpoint["center"]
		if Vector2(center.x - p.x, center.z - p.z).length() < discover_radius:
			_discover(key, segment)


func _discover(key: Vector3i, segment: RoadSegment) -> void:
	var center: Vector3 = segment.viewpoint["center"]
	_found[spot_id(key)] = {"name": spot_name(key, segment.viewpoint), "kind": segment.viewpoint["kind"],
		"x": center.x, "z": center.z, "time": Time.get_unix_time_from_system(), "photo": ""}
	_save()
	var counts := region_counts(Vector2i(key.x, key.y))
	Toasts.post(get_tree(), "view", "Aussichtspunkt entdeckt", "%d von %d in dieser Gegend" % [counts[0], counts[1]],
		"P", "Foto")
	_update_map_spots()


## Aussichtspunkte rund ums Auto für die Karte. Noch nicht berechnete Straßen: ungefähr in der
## Mitte zwischen ihren Orten (ein „?“ darf ungenau sein).
func _update_map_spots() -> void:
	map_spots = []
	var p := car.global_position
	var cell_size := roads.cell_size
	var reach := ceili(map_radius / cell_size)
	var here := Vector2i(floori(p.x / cell_size), floori(p.z / cell_size))
	for cz in range(here.y - reach, here.y + reach + 1):
		for cx in range(here.x - reach, here.x + reach + 1):
			for dir in 2:
				var key := Vector3i(cx, cz, dir)
				if not _exists(key):
					continue
				var segment := roads.edge_segment(key)
				var position: Vector2
				if segment:
					var center: Vector3 = segment.viewpoint["center"]
					position = Vector2(center.x, center.z)
				else:
					var a: Vector3 = roads.node_at(Vector2i(cx, cz))
					var b: Vector3 = roads.node_at(roads.edge_end_cell(key))
					position = Vector2(a.x + b.x, a.z + b.z) * 0.5
				if position.distance_to(Vector2(p.x, p.z)) < map_radius:
					map_spots.append({"id": spot_id(key), "position": position, "found": _found.has(spot_id(key))})


## Ein Foto wurde gespeichert: dem nächsten entdeckten Aussichtspunkt (bis 150 m) zuordnen
func photo_saved(path: String, where: Vector3) -> void:
	var best := ""
	var best_distance := 150.0
	for id: String in _found:
		var spot: Dictionary = _found[id]
		var d := Vector2(spot["x"] - where.x, spot["z"] - where.z).length()
		if d < best_distance:
			best = id
			best_distance = d
	if best != "":
		_found[best]["photo"] = path
		_save()


## Liste für die Sammlung in der Garage: Foto, Name, Datum
func fill_collection(list: VBoxContainer) -> void:
	for child in list.get_children():
		child.queue_free()
	if _found.is_empty():
		list.add_child(UiStyle.label("Noch keine Aussichtspunkte entdeckt. Halte an einem an (Schild „Aussichtspunkt“).",
			15, "regular", UiStyle.TEXT_DIM))
		return
	var count_text := "1 Aussichtspunkt entdeckt" if _found.size() == 1 else "%d Aussichtspunkte entdeckt" % _found.size()
	list.add_child(UiStyle.label(count_text, 15, "medium", UiStyle.TEXT_DIM))
	var ids := _found.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return _found[a]["time"] > _found[b]["time"])
	for id: String in ids:
		var spot: Dictionary = _found[id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		var frame := Panel.new()
		frame.custom_minimum_size = Vector2(192.0, 108.0)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(1, 1, 1, 0.06)
		style.set_corner_radius_all(10)
		frame.add_theme_stylebox_override("panel", style)
		var texture := _thumbnail(spot["photo"])
		if texture:
			var picture := TextureRect.new()
			picture.texture = texture
			picture.set_anchors_preset(Control.PRESET_FULL_RECT)
			picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			frame.add_child(picture)
		else:
			var empty := UiStyle.label("Kein Foto", 13, "medium", UiStyle.TEXT_FAINT)
			empty.set_anchors_preset(Control.PRESET_FULL_RECT)
			empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			frame.add_child(empty)
		row.add_child(frame)
		var texts := VBoxContainer.new()
		texts.alignment = BoxContainer.ALIGNMENT_CENTER
		texts.add_child(UiStyle.label(spot["name"], 18, "semibold", UiStyle.TEXT))
		var date := Time.get_datetime_dict_from_unix_time(int(spot["time"]))
		var photo_text := "Foto gemacht" if texture else "Noch kein Foto (P drücken)"
		texts.add_child(UiStyle.label("Entdeckt am %d.%d.%d · %s" % [date.day, date.month, date.year, photo_text],
			14, "regular", UiStyle.TEXT_DIM))
		row.add_child(texts)
		list.add_child(row)


func _thumbnail(path: String) -> Texture2D:
	if path == "" or not FileAccess.file_exists(path):
		return null
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		return null
	image.resize(384, roundi(384.0 * image.get_height() / image.get_width()))
	return ImageTexture.create_from_image(image)


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK or not config.has_section("gefunden"):
		return
	for id in config.get_section_keys("gefunden"):
		_found[id] = config.get_value("gefunden", id)


func _save() -> void:
	# Testläufe (Startargumente nach „--“) verändern den Spielstand nicht
	if not OS.get_cmdline_user_args().is_empty():
		return
	var config := ConfigFile.new()
	for id: String in _found:
		config.set_value("gefunden", id, _found[id])
	config.save(SAVE_PATH)
