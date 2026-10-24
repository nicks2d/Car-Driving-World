class_name MapTiles
extends Node
## Das Kartenbild (Gelände, Wald, Wasser) in Kacheln. Jede Kachel wird einmal im Hintergrund
## berechnet und dann gemerkt. Es gibt mehrere Zoomstufen: grob für die große Karte,
## fein für die Minimap. Straßen, Route und Auto zeichnet die Karte selbst darüber
## (MapView), sie stecken nicht in den Kacheln.

## Pixel pro Kachel-Seite
@export var tile_pixels: int = 128
## Kantenlänge einer Kachel je Zoomstufe in Metern (bei 128 px: 4, 16 und 64 m pro Pixel)
@export var level_sizes: Array[float] = [512.0, 2048.0, 8192.0]
@export var max_parallel_jobs: int = 2
## So viele fertige Kacheln werden höchstens gemerkt (die am längsten unbenutzten fallen raus)
@export var max_cached_tiles: int = 400

var world_gen: WorldGen

var _tiles: Dictionary = {}  # Vector3i(Stufe, x, z) -> ImageTexture
var _jobs: Dictionary = {}  # Vector3i -> TileJob
var _last_used: Dictionary = {}  # Vector3i -> Bildnummer
var _running: int = 0


## Farben im dunklen Kartenstil (Entwurf „Glas“)
const GROUND := Color("#111721")
const FOREST := Color("#122023")
const MOUNTAIN := Color("#1A2130")
const SNOW := Color("#2A3242")
const WATER := Color("#1E3A5C")


## Hintergrund-Auftrag: eine Kachel berechnen
class TileJob:
	var world_gen: WorldGen
	var origin: Vector2
	var size: float
	var pixels: int
	var image: Image
	var task_id: int = -1

	func run() -> void:
		var n := pixels
		var step := size / n
		var lakes: Array = world_gen.lakes_near(Rect2(origin, Vector2(size, size)).grow(step))
		# Höhen mit einem Pixel Rand rechts und unten (für die Schattierung)
		var heights := PackedFloat32Array()
		heights.resize((n + 1) * (n + 1))
		for y in n + 1:
			for x in n + 1:
				heights[y * (n + 1) + x] = world_gen.terrain_height(origin.x + (x + 0.5) * step,
					origin.y + (y + 0.5) * step, lakes)
		image = Image.create(n, n, false, Image.FORMAT_RGB8)
		var snow := world_gen.snow_height
		for y in n:
			for x in n:
				var h := heights[y * (n + 1) + x]
				var gx := (heights[y * (n + 1) + x + 1] - h) / step
				var gz := (heights[(y + 1) * (n + 1) + x] - h) / step
				var wx := origin.x + (x + 0.5) * step
				var wz := origin.y + (y + 0.5) * step
				var level := world_gen.water_level_at(wx, wz, lakes)
				if level > WorldGen.NO_WATER and h < level:
					image.set_pixel(x, y, WATER)
					continue
				# Dunkler Stil: fast einfarbig, Wald etwas grünlicher, hohe Berge und Schnee heller
				var color := GROUND.lerp(MOUNTAIN, smoothstep(500.0, 1200.0, h))
				color = color.lerp(SNOW, smoothstep(snow - 50.0, snow + 150.0, h) * 0.8)
				var slope := 1.0 - 1.0 / sqrt(1.0 + gx * gx + gz * gz)
				color = color.lerp(FOREST, world_gen.forest_density(wx, wz, h, slope) * 0.7)
				# Schattierung (Licht von Nordwesten) nur ganz leicht
				color *= clampf(1.0 + (gx + gz) * 0.35, 0.8, 1.2)
				# Höhenlinien alle 100 m
				if floori(h / 100.0) != floori((h + maxf(absf(gx), absf(gz)) * step) / 100.0):
					color = color.lerp(Color(1, 1, 1), 0.05)
				image.set_pixel(x, y, color)


## Zoomstufe, deren Pixel ungefähr so groß sind wie die gewünschte Kartengröße
func level_for(meters_per_pixel: float) -> int:
	for level in level_sizes.size():
		if level_sizes[level] / tile_pixels >= meters_per_pixel:
			return level
	return level_sizes.size() - 1


## Fertige Kachel (oder null, dann wird sie bestellt)
func get_tile(level: int, tx: int, tz: int) -> Texture2D:
	var key := Vector3i(level, tx, tz)
	_last_used[key] = Engine.get_process_frames()
	if _tiles.has(key):
		return _tiles[key]
	if not _jobs.has(key) and _running < max_parallel_jobs and world_gen:
		var job := TileJob.new()
		job.world_gen = world_gen
		job.size = level_sizes[level]
		job.origin = Vector2(tx, tz) * job.size
		job.pixels = tile_pixels
		job.task_id = WorkerThreadPool.add_task(job.run, false, "Kartenkachel")
		_jobs[key] = job
		_running += 1
	return null


func _process(_delta: float) -> void:
	for key: Vector3i in _jobs.keys():
		var job: TileJob = _jobs[key]
		if not WorkerThreadPool.is_task_completed(job.task_id):
			continue
		WorkerThreadPool.wait_for_task_completion(job.task_id)
		_jobs.erase(key)
		_running -= 1
		_tiles[key] = ImageTexture.create_from_image(job.image)
	# Zu viele Kacheln gemerkt: die am längsten unbenutzten vergessen
	if _tiles.size() > max_cached_tiles:
		var keys: Array = _tiles.keys()
		keys.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return _last_used.get(a, 0) < _last_used.get(b, 0))
		for i in _tiles.size() - max_cached_tiles:
			_tiles.erase(keys[i])
			_last_used.erase(keys[i])


func _exit_tree() -> void:
	for job: TileJob in _jobs.values():
		WorkerThreadPool.wait_for_task_completion(job.task_id)
