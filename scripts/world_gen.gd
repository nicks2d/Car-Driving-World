class_name WorldGen
extends Resource
## Die „Welt-Formel“: berechnet für jeden Punkt (x, z) Geländehöhe, Wasser,
## Wald usw. Gleicher Seed = gleiche Welt, egal in welcher Reihenfolge man fragt.
## Viele Hintergrund-Threads benutzen diese Formel gleichzeitig. Deshalb wird nach
## setup() nichts mehr verändert, außer dem See-Speicher (der hat ein Mutex-Schloss).

## Startwert für den Zufall: anderer Seed = andere Welt
@export var world_seed: int = 1337

@export_group("Gelände")
## Höhe der tiefsten Regionen in Metern
@export var base_height: float = 60.0
## So viel höher können ganze Regionen liegen (sehr großräumig)
@export var region_height: float = 120.0
## Höhe der sanften Hügel
@export var hill_height: float = 110.0
## Höhe der Bergketten
@export var mountain_height: float = 1800.0
## Ungefährer Abstand zwischen zwei Gebirgszonen in Metern
@export var mountain_zone_size: float = 9000.0
## Breite eines einzelnen Bergrückens in Metern
@export var mountain_size: float = 3200.0
## Kleine Unebenheiten im Boden
@export var detail_height: float = 2.0

@export_group("Flüsse")
## Ungefährer Abstand zwischen Flüssen in Metern
@export var river_spacing: float = 14000.0
## Breite des Flusses (Wasseroberfläche)
@export var river_width: float = 26.0
## Tiefe des Flussbetts unter der Wasseroberfläche
@export var river_depth: float = 3.0
## Breite des flachen Tals links und rechts vom Fluss
@export var river_valley_width: float = 450.0

@export_group("Seen")
## Größe der Zellen, in denen höchstens ein See liegt
@export var lake_cell_size: float = 2500.0
## Wahrscheinlichkeit für einen See pro Zelle (0 bis 1)
@export_range(0.0, 1.0) var lake_chance: float = 0.65
@export var lake_min_radius: float = 110.0
@export var lake_max_radius: float = 300.0

@export_group("Schnee und Wald")
## Ab dieser Höhe liegt Schnee (mit etwas Zufall)
@export var snow_height: float = 950.0
## Über dieser Höhe wachsen keine Bäume
@export var tree_line: float = 800.0

## Breite des Ufers zwischen Wasserrand und Talboden
const RIVER_BANK: float = 8.0
## So weit unter dem Talboden liegt der Wasserspiegel eines Flusses
const RIVER_WATER_DROP: float = 1.2
## Wert für „hier ist kein Wasser“
const NO_WATER: float = -1.0e9
## So weit reicht die Senke rund um einen See (Meter hinter dem Wasserrand)
const LAKE_SHORE_WIDTH: float = 300.0

var _region: FastNoiseLite
var _zone: FastNoiseLite
var _mountain: FastNoiseLite
var _hill: FastNoiseLite
var _detail: FastNoiseLite
var _river: FastNoiseLite
var _river_mask: FastNoiseLite
var _forest: FastNoiseLite
var _variation: FastNoiseLite

var _lake_cache: Dictionary = {}
var _lake_mutex: Mutex = Mutex.new()
var _is_setup: bool = false


## Ein See: Mittelpunkt, Radius, Wasserhöhe und Tiefe
class Lake:
	var center: Vector2
	var radius: float
	var level: float
	var depth: float


func setup() -> void:
	if _is_setup:
		return
	_region = _make_noise(1, 1.0 / 14000.0, 2)
	_zone = _make_noise(2, 1.0 / mountain_zone_size, 3)
	_mountain = _make_noise(3, 1.0 / mountain_size, 6)
	_mountain.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_mountain.fractal_lacunarity = 2.1
	_mountain.domain_warp_enabled = true
	_mountain.domain_warp_amplitude = 350.0
	_mountain.domain_warp_frequency = 1.0 / 2500.0
	# Wichtig: Standardmäßig verzerrt Godot in 5 immer feineren Stufen (bis ~2 m),
	# das macht das Gelände aus der Nähe stachelig. 2 grobe Stufen reichen.
	_mountain.domain_warp_fractal_octaves = 2
	_mountain.domain_warp_fractal_lacunarity = 2.0
	_hill = _make_noise(4, 1.0 / 1100.0, 4)
	_detail = _make_noise(5, 1.0 / 90.0, 3)
	_river = _make_noise(6, 1.0 / river_spacing, 1)
	_river.domain_warp_enabled = true
	_river.domain_warp_amplitude = 700.0
	_river.domain_warp_frequency = 1.0 / 3000.0
	_river.domain_warp_fractal_octaves = 2
	_river.domain_warp_fractal_lacunarity = 2.0
	_river_mask = _make_noise(7, 1.0 / 16000.0, 2)
	_forest = _make_noise(8, 1.0 / 1400.0, 3)
	_variation = _make_noise(9, 1.0 / 700.0, 2)
	_is_setup = true


func _make_noise(offset: int, frequency: float, octaves: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = world_seed * 31 + offset
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM if octaves > 1 else FastNoiseLite.FRACTAL_NONE
	noise.fractal_octaves = octaves
	return noise


# ---------------------------------------------------------------------------
# Gelände
# ---------------------------------------------------------------------------

## Höhe des Talbodens: ändert sich nur sehr großräumig. Flüsse liegen genau hier.
func ground_level(x: float, z: float) -> float:
	return base_height + region_height * (_region.get_noise_2d(x, z) * 0.5 + 0.5)


## Wie stark hier Gebirge ist (0 = flaches Land, 1 = mitten in der Bergkette)
func mountain_factor(x: float, z: float) -> float:
	return smoothstep(0.02, 0.42, _zone.get_noise_2d(x, z))


## Alles, was über dem Talboden liegt: Hügel, Berge, kleine Unebenheiten.
## Ist nie negativ, damit Flüsse und Seen nicht über dem Gelände schweben.
func _relief(x: float, z: float) -> float:
	var zone := mountain_factor(x, z)
	var hills := pow(_hill.get_noise_2d(x, z) * 0.5 + 0.5, 1.4) * hill_height * (1.0 + zone)
	var mountains := 0.0
	if zone > 0.0:
		var ridge := _mountain.get_noise_2d(x, z) * 0.5 + 0.5
		mountains = pow(ridge, 2.3) * mountain_height * zone
	var detail := (_detail.get_noise_2d(x, z) * 0.5 + 0.5) * detail_height
	return hills + mountains + detail


## Stärke des Flusses an dieser Stelle (0 = kein Fluss, 1 = voller Fluss).
## So beginnen und enden Flüsse irgendwo, statt die ganze Welt zu zerschneiden.
func _river_strength(x: float, z: float) -> float:
	return smoothstep(0.0, 0.25, _river_mask.get_noise_2d(x, z))


## Ungefähre Entfernung zur Flussmitte in Metern (sehr groß = weit weg).
## Der Fluss liegt dort, wo das Fluss-Rauschen genau 0 ist.
func river_distance(x: float, z: float) -> float:
	var n := _river.get_noise_2d(x, z)
	# Grob vorsortieren: Weit weg vom Nullpunkt brauchen wir es nicht genau
	if absf(n) > 0.6:
		return 1.0e6
	# Steigung des Rauschens: Wert / Steigung = Entfernung zur Null-Linie
	var e := 3.0
	var gx := (_river.get_noise_2d(x + e, z) - n) / e
	var gz := (_river.get_noise_2d(x, z + e) - n) / e
	var g := sqrt(gx * gx + gz * gz)
	# Wo das Rauschen sehr flach ist, wäre der Fluss sonst riesig breit: Steigung nach unten begrenzen
	return absf(n) / maxf(g, 2.0 / river_spacing)


## Gelände ohne Seen und Straßen: Talboden + Relief, entlang der Flüsse zum Tal abgesenkt
func natural_height(x: float, z: float) -> float:
	var floor_h := ground_level(x, z)
	var relief := _relief(x, z)
	var strength := _river_strength(x, z)
	if strength <= 0.0:
		return floor_h + relief
	var d := river_distance(x, z)
	# Erst entsteht ein Tal, und erst wenn das Tal ganz abgesenkt ist, fließt Wasser darin.
	# So gibt es nie einen tiefen, schmalen Graben im unberührten Gelände.
	var valley_amount := smoothstep(0.0, 0.4, strength)
	var channel := _river_channel(strength)
	var half := river_width * 0.5 * channel
	var bank := RIVER_BANK * channel
	# Je näher am Fluss, desto mehr wird das Relief zum flachen Talboden.
	# Bei hohen Bergen wird das Tal breiter, sonst entstünden senkrechte Schluchtwände.
	var valley := smoothstep(half + bank, half + bank + river_valley_width + relief * 0.5, d)
	var h := floor_h + relief * lerpf(1.0, valley, valley_amount)
	# Flussbett: unter dem Wasserspiegel eine runde Rinne, am Ufer sanft ansteigend
	if channel > 0.0 and d < half + bank:
		var water := floor_h - RIVER_WATER_DROP
		var bed: float
		if d < half:
			var t := d / maxf(half, 0.001)
			bed = water - river_depth * channel * (1.0 - t * t)
		else:
			bed = lerpf(water - 0.3, floor_h, smoothstep(half, half + bank, d))
		h = minf(h, bed)
	return h


## Wie viel Wasser der Fluss führt (0 = trockenes Tal, 1 = voller Fluss)
func _river_channel(strength: float) -> float:
	return smoothstep(0.4, 0.7, strength)


## Gelände inklusive Seen (aber ohne Straßen). lakes kommt von lakes_near().
func terrain_height(x: float, z: float, lakes: Array) -> float:
	var h := natural_height(x, z)
	for lake: Lake in lakes:
		h = _apply_lake(lake, x, z, h)
	return h


func _apply_lake(lake: Lake, x: float, z: float, h: float) -> float:
	var d := Vector2(x, z).distance_to(lake.center)
	if d > lake.radius + LAKE_SHORE_WIDTH:
		return h
	var surface: float
	if d < lake.radius:
		# Seeboden: in der Mitte am tiefsten, am Rand genau auf Wasserhöhe
		var t := d / lake.radius
		surface = lake.level - lake.depth * (1.0 - t * t)
	else:
		# Ufer: steigt vom Wasser aus erst flach, dann immer steiler an.
		# So wird höheres Gelände zu einer sanften Senke statt zu einer Klippe.
		var s := d - lake.radius
		surface = lake.level + s * 0.12 + s * s * 0.001
	return minf(h, surface)


# ---------------------------------------------------------------------------
# Wasser
# ---------------------------------------------------------------------------

## Höhe der Wasseroberfläche hier, oder NO_WATER, wenn hier kein Wasser ist
func water_level_at(x: float, z: float, lakes: Array) -> float:
	var level := NO_WATER
	var strength := _river_strength(x, z)
	if strength > 0.0:
		var half := river_width * 0.5 * _river_channel(strength)
		if half > 1.0 and river_distance(x, z) < half:
			level = ground_level(x, z) - RIVER_WATER_DROP
	for lake: Lake in lakes:
		if Vector2(x, z).distance_to(lake.center) < lake.radius:
			level = maxf(level, lake.level)
	return level


## Höhe des Flusswassers, wenn hier ein Fluss fließt. margin erweitert den Bereich etwas
## über das Ufer hinaus, damit die Wasserfläche unter dem Ufer endet statt am Rand zu enden.
func river_surface_near(x: float, z: float, margin: float) -> float:
	var strength := _river_strength(x, z)
	if strength <= 0.0:
		return NO_WATER
	var half := river_width * 0.5 * _river_channel(strength)
	if half < 1.0 or river_distance(x, z) > half + margin:
		return NO_WATER
	return ground_level(x, z) - RIVER_WATER_DROP


## Richtung, in die ein Fluss hier fließt (bergab entlang des Talbodens)
func river_flow(x: float, z: float) -> Vector2:
	var e := 25.0
	var slope := Vector2(ground_level(x + e, z) - ground_level(x - e, z), ground_level(x, z + e) - ground_level(x, z - e))
	return -slope.normalized() if slope.length() > 0.00001 else Vector2.ZERO


## Alle Seen, die das Rechteck (plus Rand) berühren könnten
func lakes_near(rect: Rect2) -> Array:
	var result: Array = []
	var grown := rect.grow(lake_max_radius + LAKE_SHORE_WIDTH)
	var c0 := Vector2i(floori(grown.position.x / lake_cell_size), floori(grown.position.y / lake_cell_size))
	var c1 := Vector2i(floori(grown.end.x / lake_cell_size), floori(grown.end.y / lake_cell_size))
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var lake: Lake = _lake_in_cell(Vector2i(cx, cz))
			if lake and grown.has_point(lake.center):
				result.append(lake)
	return result


## Der See, in dem dieser Punkt liegt (oder null). Ein See passt immer ganz in seine Zelle.
func lake_at(x: float, z: float) -> Lake:
	var lake := _lake_in_cell(Vector2i(floori(x / lake_cell_size), floori(z / lake_cell_size)))
	if lake and Vector2(x, z).distance_to(lake.center) < lake.radius + LAKE_SHORE_WIDTH:
		return lake
	return null


## Der See einer Zelle (oder null). Wird einmal berechnet und dann gemerkt.
func _lake_in_cell(cell: Vector2i) -> Lake:
	_lake_mutex.lock()
	var known: bool = _lake_cache.has(cell)
	var cached: Lake = _lake_cache.get(cell)
	_lake_mutex.unlock()
	if known:
		return cached
	var lake := _make_lake(cell)
	_lake_mutex.lock()
	_lake_cache[cell] = lake
	_lake_mutex.unlock()
	return lake


func _make_lake(cell: Vector2i) -> Lake:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash_cell(cell.x, cell.y, 101)
	if rng.randf() > lake_chance:
		return null
	var radius := rng.randf_range(lake_min_radius, lake_max_radius)
	var margin := lake_max_radius + LAKE_SHORE_WIDTH + 20.0
	var center := Vector2(
		(cell.x + 0.0) * lake_cell_size + rng.randf_range(margin, lake_cell_size - margin),
		(cell.y + 0.0) * lake_cell_size + rng.randf_range(margin, lake_cell_size - margin))
	# Nicht in Gebirgen und nicht direkt an einem Fluss
	if mountain_factor(center.x, center.y) > 0.3:
		return null
	if _river_strength(center.x, center.y) > 0.0 and river_distance(center.x, center.y) < radius + 80.0:
		return null
	# Wasserhöhe = etwas unter dem niedrigsten Punkt am Rand, damit das Becken dicht ist
	var lowest := INF
	var highest := -INF
	for i in 32:
		var angle := TAU * i / 32.0
		var p := center + Vector2(cos(angle), sin(angle)) * radius
		var h := natural_height(p.x, p.y)
		lowest = minf(lowest, h)
		highest = maxf(highest, h)
	var middle := natural_height(center.x, center.y)
	# Zu hügelig: lieber kein See als ein komisches Loch im Berg
	if highest - lowest > 45.0 or middle - lowest > 35.0:
		return null
	var lake := Lake.new()
	lake.center = center
	lake.radius = radius
	lake.level = lowest - 1.5
	lake.depth = rng.randf_range(5.0, 12.0)
	return lake


# ---------------------------------------------------------------------------
# Wald, Schnee, Zufall
# ---------------------------------------------------------------------------

## Wie dicht hier Wald steht (0 bis 1). slope = 1 - Normale.y (0 = flach)
func forest_density(x: float, z: float, height: float, slope: float) -> float:
	var base := smoothstep(-0.15, 0.35, _forest.get_noise_2d(x, z))
	var below_line := 1.0 - smoothstep(tree_line - 120.0, tree_line, height)
	var not_steep := 1.0 - smoothstep(0.25, 0.4, slope)
	return base * below_line * not_steep


## Großflächige Zufalls-Variation (-1 bis 1), z. B. für Farbe oder Dichte
func variation(x: float, z: float) -> float:
	return _variation.get_noise_2d(x, z)


## Ganzzahliger Zufallswert für eine Zelle, immer gleich für denselben Seed
func hash_cell(cx: int, cz: int, salt: int) -> int:
	var h: int = cx * 374761393 + cz * 668265263 + salt * 2246822519 + world_seed * 3266489917
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return h & 0x7FFFFFFF
