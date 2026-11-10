class_name Exploration
extends Node
## Entdecker-Karte und Orte-Sammlung.
## - Was man gesehen hat, steht in Kacheln (TILE_METERS, je TILE_PIXELS² Pixel, 8 m pro Pixel):
##   300 m um jede Fahrt (weich auslaufend) und von Aussichtspunkten aus das, was man von dort
##   wirklich sieht (Strahlen übers Gelände im Blickfächer, bis 2,5 km). Große Karte und Minimap
##   legen über den Rest einen weichen Nebel (fog_texture), Straßen dort sind versteckt; Route
##   und Navi bleiben sichtbar. Gespeichert als PNG in user://karte/.
##   Gerechnet wird im WorkerThreadPool (ein Auftrag nach dem anderen), damit nichts ruckelt.
## - Orte: Fährt man durch einen Ort (näher als VISIT_RADIUS an der Mitte), kommt er in die
##   Sammlung (Name, Datum, Foto aus dem Fotomodus, falls dort eines gemacht wurde), beim ersten
##   Mal mit Meldung. Gespeichert in user://orte.cfg.
## Testläufe (Argumente) speichern nichts und laden nichts.

signal changed

@export var car: Node3D
@export var roads: RoadNetwork
@export var debug_tools: DebugTools
## Sichtweite um das Auto und von Aussichtspunkten (Meter), halber Öffnungswinkel dort (Grad)
@export var reveal_radius: float = 300.0
@export var viewpoint_radius: float = 2500.0
@export var viewpoint_half_angle: float = 55.0
## Entdecker-Karte an (Einstellungen > Spiel); aus = alles sichtbar wie früher
@export var enabled: bool = true
## Nebelfarbe (hellste Stelle der Wolken) und Deckkraft (so dicht, dass Straßen verschwinden)
@export var fog_color: Color = Color(0.17, 0.19, 0.235)
@export_range(0.0, 1.0) var fog_alpha: float = 0.985
## Wolkenmuster im Nebel: dunkelste Stelle (Anteil der Nebelfarbe)
@export_range(0.0, 1.0) var fog_cloud_dark: float = 0.62

const TILE_PIXELS: int = 256
const METERS_PER_PIXEL: float = 8.0
const TILE_METERS: float = TILE_PIXELS * METERS_PER_PIXEL
const MAP_DIR := "user://karte/"
const PLACES_PATH := "user://orte.cfg"
## So nah an der Ortsmitte (Meter) gilt ein Ort als besucht
const VISIT_RADIUS: float = 170.0
## Sichtstrahlen von Aussichtspunkten: Abstand der Strahlen (Grad) und der Prüfpunkte (Meter)
const RAY_STEP_DEGREES: float = 1.0
const RAY_STEP_METERS: float = 20.0
const EYE_HEIGHT: float = 2.0

## Kachel-Daten: LA8 (je Pixel Helligkeit = Wolkenmuster und Deckkraft = Nebel, 255 = unbekannt)
var _data: Dictionary = {}  # Vector2i -> PackedByteArray
## Neue Kachel: Wolkenmuster (nahtlos, für alle Kacheln gleich) und ganz Nebel
var _template := PackedByteArray()
var _full_fog: ImageTexture
var _on_disk: Dictionary = {}  # Vector2i -> true (gespeicherte Kacheln, noch nicht geladen)
var _textures: Dictionary = {}  # Vector2i -> ImageTexture
var _dirty: Dictionary = {}  # geändert seit der letzten Textur
var _unsaved: Dictionary = {}  # geändert seit dem letzten Speichern
var _mutex := Mutex.new()
var _queue: Array[Dictionary] = []
var _task: int = -1
var _places: Dictionary = {}  # "x,z" -> {"name", "time", "x", "z", "photo"}
var _timer: float = 0.0
var _save_timer: float = 20.0
var _last_reveal := Vector2.INF


func _ready() -> void:
	# Weiterrechnen, auch wenn Karte oder Garage das Spiel anhalten (das Auto steht dann)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_make_template()
	if _testing():
		return
	var files := DirAccess.get_files_at(MAP_DIR) if DirAccess.dir_exists_absolute(MAP_DIR) else PackedStringArray()
	for file in files:
		var parts := file.get_basename().split("_")
		if file.get_extension() == "png" and parts.size() == 2:
			_on_disk[Vector2i(parts[0].to_int(), parts[1].to_int())] = true
	_load_places()


func _testing() -> bool:
	return debug_tools != null and debug_tools.is_active()


func _process(delta: float) -> void:
	# Fertigen Auftrag abholen, nächsten starten
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		changed.emit()
	if _task < 0 and not _queue.is_empty():
		_task = WorkerThreadPool.add_task(_run.bind(_queue.pop_front()), false, "Entdecker-Karte")
	if car == null:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = 0.5
		var p := Vector2(car.global_position.x, car.global_position.z)
		if p.distance_to(_last_reveal) > 20.0:
			_last_reveal = p
			reveal_circle(p, reveal_radius)
		_check_places(p)
	_save_timer -= delta
	if _save_timer <= 0.0:
		_save_timer = 20.0
		save_tiles()


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	save_tiles()


# ---------------------------------------------------------------------------
# Aufdecken
# ---------------------------------------------------------------------------

## Kreis aufdecken (am Rand weich), z. B. rund um das Auto. Ein noch wartender Kreis wird ersetzt.
func reveal_circle(center: Vector2, radius: float) -> void:
	for i in _queue.size():
		if not _queue[i]["view"]:
			_queue[i] = {"center": center, "radius": radius, "view": false}
			return
	_queue.append({"center": center, "radius": radius, "view": false})


## Blick von einem Aussichtspunkt: Fächer in Richtung look, nur was das Gelände nicht verdeckt
func reveal_view(center: Vector3, look: Vector2) -> void:
	_queue.append({"center": Vector2(center.x, center.z), "height": center.y + EYE_HEIGHT,
		"look": look.normalized(), "radius": viewpoint_radius, "view": true})
	reveal_circle(Vector2(center.x, center.z), reveal_radius * 1.5)


## Wolkenmuster: nahtloses Rauschen (FastNoiseLite, fester Seed) als Helligkeit, Deckkraft 255
func _make_template() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 4711
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	var image := noise.get_seamless_image(TILE_PIXELS, TILE_PIXELS)
	image.convert(Image.FORMAT_L8)
	# Helligkeit (0 … 1, normalisiert) auf fog_cloud_dark … 1 stauchen
	var data := image.get_data()
	var dark := fog_cloud_dark * 255.0
	for i in data.size():
		data[i] = roundi(dark + data[i] / 255.0 * (255.0 - dark))
	image = Image.create_from_data(TILE_PIXELS, TILE_PIXELS, false, Image.FORMAT_L8, data)
	image.convert(Image.FORMAT_LA8)
	_template = image.get_data()
	_full_fog = ImageTexture.create_from_image(image)


## Kachel-Daten holen (vorher _mutex sperren): geladen, von der Festplatte oder ganz Nebel
func _tile_data(cell: Vector2i) -> PackedByteArray:
	if _data.has(cell):
		return _data[cell]
	var data := PackedByteArray()
	if _on_disk.has(cell):
		var image := Image.load_from_file(ProjectSettings.globalize_path(MAP_DIR + "%d_%d.png" % [cell.x, cell.y]))
		if image:
			if image.get_format() != Image.FORMAT_LA8:
				image.convert(Image.FORMAT_LA8)
			if image.get_width() != TILE_PIXELS or image.get_height() != TILE_PIXELS:
				image.resize(TILE_PIXELS, TILE_PIXELS)
			data = image.get_data()
	if data.size() != TILE_PIXELS * TILE_PIXELS * 2:
		data = _template.duplicate()
	_data[cell] = data
	return data


## Läuft im WorkerThreadPool: rechnet den neuen Nebel auf Kopien und schreibt sie dann zurück
## (immer nur ein Auftrag gleichzeitig, der Hauptthread liest nur)
func _run(request: Dictionary) -> void:
	var center: Vector2 = request["center"]
	var radius: float = request["radius"]
	var view: bool = request["view"]
	var look := Vector2.ZERO
	var min_cos := -1.0
	var visible := PackedByteArray()
	var rays := 0
	var steps := 0
	if view:
		look = request["look"]
		min_cos = cos(deg_to_rad(viewpoint_half_angle))
		rays = roundi(viewpoint_half_angle * 2.0 / RAY_STEP_DEGREES) + 1
		steps = ceili(radius / RAY_STEP_METERS) + 1
		visible = _sight_lines(center, request["height"], look, rays, steps)
	var soft := minf(radius * 0.35, 400.0)
	var c0 := Vector2i(floori((center.x - radius) / TILE_METERS), floori((center.y - radius) / TILE_METERS))
	var c1 := Vector2i(floori((center.x + radius) / TILE_METERS), floori((center.y + radius) / TILE_METERS))
	var results: Dictionary = {}
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var cell := Vector2i(cx, cz)
			_mutex.lock()
			var data := _tile_data(cell).duplicate()
			_mutex.unlock()
			var origin := Vector2(cell) * TILE_METERS
			var p0 := Vector2i(clampi(floori((center.x - radius - origin.x) / METERS_PER_PIXEL), 0, TILE_PIXELS - 1),
				clampi(floori((center.y - radius - origin.y) / METERS_PER_PIXEL), 0, TILE_PIXELS - 1))
			var p1 := Vector2i(clampi(ceili((center.x + radius - origin.x) / METERS_PER_PIXEL), 0, TILE_PIXELS - 1),
				clampi(ceili((center.y + radius - origin.y) / METERS_PER_PIXEL), 0, TILE_PIXELS - 1))
			var changed_tile := false
			for pz in range(p0.y, p1.y + 1):
				var wz := origin.y + (pz + 0.5) * METERS_PER_PIXEL - center.y
				for px in range(p0.x, p1.x + 1):
					var offset := Vector2(origin.x + (px + 0.5) * METERS_PER_PIXEL - center.x, wz)
					var d := offset.length()
					if d > radius:
						continue
					var value := 1.0 - smoothstep(radius - soft, radius, d)
					if view and d > 1.0:
						# Fächer: zur Seite hin weich auslaufend, dahinter nur, was man sieht
						var c := offset.dot(look) / d
						value *= smoothstep(min_cos - 0.08, min_cos + 0.04, c)
						if value <= 0.0:
							continue
						# Zwischen den vier nächsten Strahl-Punkten weich überblenden
						var ray := clampf(rad_to_deg(look.angle_to(offset)) / RAY_STEP_DEGREES + (rays >> 1), 0.0, rays - 1.001)
						var step := clampf(d / RAY_STEP_METERS, 0.0, steps - 1.001)
						var r0 := floori(ray)
						var s0 := floori(step)
						var fr := ray - r0
						var fs := step - s0
						var near := lerpf(visible[r0 * steps + s0], visible[r0 * steps + s0 + 1], fs)
						var far := lerpf(visible[(r0 + 1) * steps + s0], visible[(r0 + 1) * steps + s0 + 1], fs)
						value *= lerpf(near, far, fr) / 255.0
					var fog := roundi((1.0 - value) * 255.0)
					var index := (pz * TILE_PIXELS + px) * 2 + 1
					if fog < data[index] - 2:
						data[index] = fog
						changed_tile = true
			if changed_tile:
				results[cell] = data
	if results.is_empty():
		return
	_mutex.lock()
	for cell: Vector2i in results:
		_data[cell] = results[cell]
		_dirty[cell] = true
		_unsaved[cell] = true
	_mutex.unlock()


## Sichtlinien vom Aussichtspunkt: je Strahl und Schritt 255 = sichtbar, 0 = vom Gelände verdeckt
## (weich: knapp unter der Sichtlinie zählt halb). Ein Strahl merkt sich den steilsten Winkel.
func _sight_lines(center: Vector2, eye: float, look: Vector2, rays: int, steps: int) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(rays * steps)
	var world_gen := roads.world_gen
	for r in rays:
		var direction := look.rotated(deg_to_rad((r - (rays >> 1)) * RAY_STEP_DEGREES))
		var highest := -INF
		result[r * steps] = 255
		for s in range(1, steps):
			var d := s * RAY_STEP_METERS
			var p := center + direction * d
			var slope := (world_gen.terrain_height(p.x, p.y, []) - eye) / d
			# Gesehen wird der Boden, wenn er nicht unter der bisher steilsten Sichtlinie liegt;
			# knapp darunter (bis 4 m je 100 m) halb, damit der Rand weich ausläuft
			result[r * steps + s] = roundi(255.0 * clampf(1.0 - (highest - slope) / 0.04, 0.0, 1.0))
			highest = maxf(highest, slope)
	return result


## Wie gut ist diese Stelle bekannt (0 = Nebel, 1 = gesehen)?
func known_at(p: Vector2) -> float:
	var cell := Vector2i(floori(p.x / TILE_METERS), floori(p.y / TILE_METERS))
	if not _data.has(cell) and not _on_disk.has(cell):
		return 0.0
	var px := clampi(floori((p.x - cell.x * TILE_METERS) / METERS_PER_PIXEL), 0, TILE_PIXELS - 1)
	var pz := clampi(floori((p.y - cell.y * TILE_METERS) / METERS_PER_PIXEL), 0, TILE_PIXELS - 1)
	_mutex.lock()
	var fog := _tile_data(cell)[(pz * TILE_PIXELS + px) * 2 + 1]
	_mutex.unlock()
	return 1.0 - fog / 255.0


## Nebel-Textur einer Kachel (Helligkeit = Wolken, Deckkraft = Nebel; beim Zeichnen mit
## fog_color/fog_alpha einfärben). Wo noch gar nichts gesehen ist: eine gemeinsame Textur.
func fog_texture(cell: Vector2i) -> Texture2D:
	if not _data.has(cell) and not _on_disk.has(cell):
		return _full_fog
	if _textures.has(cell) and not _dirty.has(cell):
		return _textures[cell]
	_mutex.lock()
	var data := _tile_data(cell)
	_dirty.erase(cell)
	_mutex.unlock()
	var image := Image.create_from_data(TILE_PIXELS, TILE_PIXELS, false, Image.FORMAT_LA8, data)
	if _textures.has(cell):
		(_textures[cell] as ImageTexture).update(image)
	else:
		_textures[cell] = ImageTexture.create_from_image(image)
	return _textures[cell]


func save_tiles() -> void:
	if _testing() or _unsaved.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MAP_DIR))
	_mutex.lock()
	var cells := _unsaved.keys()
	_unsaved.clear()
	var copies: Array[PackedByteArray] = []
	for cell: Vector2i in cells:
		copies.append(_data[cell])
	_mutex.unlock()
	for i in cells.size():
		var cell: Vector2i = cells[i]
		var image := Image.create_from_data(TILE_PIXELS, TILE_PIXELS, false, Image.FORMAT_LA8, copies[i])
		image.save_png(ProjectSettings.globalize_path(MAP_DIR + "%d_%d.png" % [cell.x, cell.y]))
		_on_disk[cell] = true


# ---------------------------------------------------------------------------
# Orte
# ---------------------------------------------------------------------------

func _check_places(p: Vector2) -> void:
	if roads == null:
		return
	var cell := Vector2i(floori(p.x / roads.cell_size), floori(p.y / roads.cell_size))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var c := cell + Vector2i(dx, dz)
			var node: Variant = roads.node_at(c)
			if node == null:
				continue
			var center := Vector2((node as Vector3).x, (node as Vector3).z)
			var id := "%d,%d" % [c.x, c.y]
			if center.distance_to(p) < VISIT_RADIUS and not _places.has(id):
				_visit(id, c, center)


func _visit(id: String, cell: Vector2i, center: Vector2) -> void:
	var place := roads.highways.place_name(cell)
	_places[id] = {"name": place, "time": Time.get_unix_time_from_system(), "x": center.x, "z": center.y, "photo": ""}
	_save_places()
	var count := _places.size()
	Toasts.post(get_tree(), "pin", "Neuer Ort: %s" % place, ("1 Ort besucht" if count == 1 else "%d Orte besucht" % count),
		"G", "Sammlung")
	changed.emit()


func place_count() -> int:
	return _places.size()


## Foto aus dem Fotomodus: bekommt der nächste besuchte Ort (bis 300 m)
func photo_saved(path: String, where: Vector3) -> void:
	var best := ""
	var best_distance := 300.0
	for id: String in _places:
		var entry: Dictionary = _places[id]
		var d := Vector2(entry["x"], entry["z"]).distance_to(Vector2(where.x, where.z))
		if d < best_distance:
			best_distance = d
			best = id
	if best != "":
		_places[best]["photo"] = path
		_save_places()


## Sammlung in der Garage: Zähler, dann alle Orte (neueste zuerst) mit Datum und Foto
func fill_places(list: VBoxContainer) -> void:
	for child in list.get_children():
		child.queue_free()
	if _places.is_empty():
		list.add_child(UiStyle.label("Noch keine Orte besucht. Fahr durch ein Dorf (gelbes Ortsschild).",
			15, "regular", UiStyle.TEXT_DIM))
		return
	var count := _places.size()
	list.add_child(UiStyle.label("1 Ort besucht" if count == 1 else "%d Orte besucht" % count, 15, "medium", UiStyle.TEXT_DIM))
	for entry: Dictionary in places():
		var date := Time.get_datetime_dict_from_unix_time(int(entry["time"]))
		var texture := Viewpoints.thumbnail(entry["photo"])
		var photo_text := "Foto gemacht" if texture else "Noch kein Foto (P drücken)"
		list.add_child(Viewpoints.collection_row(entry["name"], "Besucht am %d.%d.%d · %s" % [date.day, date.month,
			date.year, photo_text], texture))


## Liste für die Garage: neueste zuerst
func places() -> Array:
	var list: Array = _places.values()
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["time"] > b["time"])
	return list


func _load_places() -> void:
	var config := ConfigFile.new()
	if config.load(PLACES_PATH) != OK:
		return
	for id: String in config.get_sections():
		_places[id] = {"name": config.get_value(id, "name", ""), "time": config.get_value(id, "time", 0),
			"x": config.get_value(id, "x", 0.0), "z": config.get_value(id, "z", 0.0), "photo": config.get_value(id, "photo", "")}


func _save_places() -> void:
	if _testing():
		return
	var config := ConfigFile.new()
	for id: String in _places:
		for key: String in _places[id]:
			config.set_value(id, key, _places[id][key])
	config.save(PLACES_PATH)
