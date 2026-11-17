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

@export_group("Talsperren")
## Größe der Zellen, in denen höchstens eine Talsperre liegt, und Wahrscheinlichkeit dafür
@export var reservoir_cell_size: float = 10000.0
@export_range(0.0, 1.0) var reservoir_chance: float = 0.8
## Höhe der Mauerkrone über dem Fluss (Meter, je Talsperre zufällig dazwischen)
@export var dam_min_height: float = 22.0
@export var dam_max_height: float = 36.0
## Längste Mauer (Meter): sonst ist das Tal nicht eng genug
@export var dam_max_length: float = 700.0

@export_group("Wasserfälle")
## Chance auf einen Wasserfall pro Seen-Zelle (2,5 km), nur wo es steil genug ist
@export_range(0.0, 1.0) var waterfall_chance: float = 0.35
## Mindest- und Höchsthöhe eines Wasserfalls (Meter); nur wo der Fels steiler als 1,1 ist
@export var waterfall_min_drop: float = 16.0
@export var waterfall_max_drop: float = 55.0

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
## Ortszellen (wie RoadNetwork.cell_size): Talsperren liegen dort, wo die Luftlinie zwischen zwei
## Nachbarzellen einen Fluss kreuzt, damit eine Landstraße über die Mauer führen kann
const PLACE_CELL: float = 1200.0
## Stausee: Raster der Flutfüllung, größter Umkreis um die Mauer, Wasser so weit unter der Krone
const RESERVOIR_STEP: float = 40.0
const RESERVOIR_RADIUS: float = 4500.0
const RESERVOIR_FREEBOARD: float = 3.0

var _region: FastNoiseLite
var _zone: FastNoiseLite
var _mountain: FastNoiseLite
var _hill: FastNoiseLite
var _detail: FastNoiseLite
var _river: FastNoiseLite
var _river_mask: FastNoiseLite
var _forest: FastNoiseLite
var _variation: FastNoiseLite
## Baumgruppen und Lichtungen (Muster im Abstand von etwa 60 m)
var _groves: FastNoiseLite

var _lake_cache: Dictionary = {}
var _lake_mutex: Mutex = Mutex.new()
var _reservoir_cache: Dictionary = {}
var _waterfall_cache: Dictionary = {}
var _is_setup: bool = false


## Ein See: Mittelpunkt, Radius, Wasserhöhe und Tiefe. Ein Stausee (reservoir = true) hat statt
## des Kreises ein Raster (mask: 0 trocken, 1 Wasser, 2 Rand für die Wasserfläche), center und
## radius umschließen ihn nur grob, dazu die Staumauer.
class Lake:
	var center: Vector2
	var radius: float
	var level: float
	var depth: float
	var reservoir: bool = false
	## Becken unter einem Wasserfall (klein, mit Felsrand zur Talseite)
	var pool: bool = false
	var mask := PackedByteArray()
	var mask_origin := Vector2.ZERO
	var mask_size := Vector2i.ZERO
	## Staumauer: Enden der Krone, Höhe der Krone (Fahrbahn), Fließrichtung des Flusses (talab),
	## Mitte über dem Fluss, Landstraße darüber (Schlüssel wie im RoadNetwork), Namenszelle
	var dam_a := Vector2.ZERO
	var dam_b := Vector2.ZERO
	var crest: float = 0.0
	var flow := Vector2.ZERO
	var dam_center := Vector2.ZERO
	var river_level: float = 0.0
	var road_key := Vector3i.ZERO
	var name_cell := Vector2i.ZERO

	## Liegt p im See (mit margin Metern Rand)? Beim Stausee nie hinter der Mauer.
	func covers(p: Vector2, margin: float) -> bool:
		if not reservoir:
			return p.distance_to(center) < radius + margin
		if (p - dam_center).dot(flow) > -6.0 and dam_distance(p) < 60.0 + margin:
			return false
		var reach := ceili(margin / RESERVOIR_STEP)
		var c := Vector2i(floori((p.x - mask_origin.x) / RESERVOIR_STEP), floori((p.y - mask_origin.y) / RESERVOIR_STEP))
		for dz in range(-reach, reach + 1):
			for dx in range(-reach, reach + 1):
				var q := c + Vector2i(dx, dz)
				if q.x >= 0 and q.y >= 0 and q.x < mask_size.x and q.y < mask_size.y \
						and mask[q.y * mask_size.x + q.x] == 1:
					return true
		return false

	## Wasserfläche hier (Rand eingeschlossen, damit sie unter das Ufer reicht)? Nicht unter und
	## hinter der Mauer (ab 6 m vor der Kronenlinie).
	func surface_at(p: Vector2) -> bool:
		var c := Vector2i(floori((p.x - mask_origin.x) / RESERVOIR_STEP), floori((p.y - mask_origin.y) / RESERVOIR_STEP))
		if c.x < 0 or c.y < 0 or c.x >= mask_size.x or c.y >= mask_size.y or mask[c.y * mask_size.x + c.x] == 0:
			return false
		return (p - dam_center).dot(flow) < -6.0 or dam_distance(p) > 60.0

	## Abstand zur Kronenlinie der Mauer
	func dam_distance(p: Vector2) -> float:
		var along := dam_b - dam_a
		var t := clampf((p - dam_a).dot(along) / along.length_squared(), 0.0, 1.0)
		return p.distance_to(dam_a + along * t)


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
	_groves = _make_noise(21, 1.0 / 65.0, 2)
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
	# Stauseen füllen das Tal, wie es ist (das Gelände bleibt)
	if lake.reservoir:
		return h
	var d := Vector2(x, z).distance_to(lake.center)
	# Becken unter dem Wasserfall: rund ausgehöhlt, rundherum ein Rand knapp über dem Wasser, der
	# in 6 m ins Gelände übergeht (bergauf eine Kerbe, bergab ein Felsriegel)
	if lake.pool:
		if d < lake.radius:
			var t := d / lake.radius
			return lake.level - lake.depth * (1.0 - t * t)
		if d < lake.radius + 6.0:
			return lerpf(lake.level + 0.4, h, smoothstep(0.0, 1.0, (d - lake.radius) / 6.0))
		return h
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
		if lake.reservoir:
			if lake.surface_at(Vector2(x, z)):
				level = maxf(level, lake.level)
		elif Vector2(x, z).distance_to(lake.center) < lake.radius:
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


## Richtung des Flussbetts hier (entlang der Null-Linie des Fluss-Rauschens), talab.
## river_flow ist nur das großräumige Gefälle; der Fluss selbst schlängelt sich anders.
func river_direction(x: float, z: float) -> Vector2:
	var e := 3.0
	var gx := _river.get_noise_2d(x + e, z) - _river.get_noise_2d(x - e, z)
	var gz := _river.get_noise_2d(x, z + e) - _river.get_noise_2d(x, z - e)
	var along := Vector2(-gz, gx)
	if along.length() < 0.000001:
		return river_flow(x, z)
	along = along.normalized()
	return -along if along.dot(river_flow(x, z)) < 0.0 else along


## Alle Seen, die das Rechteck (plus Rand) berühren könnten, mit Stauseen
## (with_reservoirs = false: nur die runden, z. B. für Fernsicht ohne neue Berechnung)
func lakes_near(rect: Rect2, with_reservoirs: bool = true, with_pools: bool = true) -> Array:
	var result: Array = []
	if with_reservoirs:
		result.append_array(reservoirs_near(rect))
	if with_pools:
		for fall: Dictionary in waterfalls_near(rect.grow(10.0)):
			result.append(fall["pool"])
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
## Stauseen nur, wenn sie schon berechnet sind (für die Fernsicht: keine neue Flutfüllung).
func lake_at(x: float, z: float) -> Lake:
	var lake := _lake_in_cell(Vector2i(floori(x / lake_cell_size), floori(z / lake_cell_size)))
	if lake and Vector2(x, z).distance_to(lake.center) < lake.radius + LAKE_SHORE_WIDTH:
		return lake
	var cell := Vector2i(floori(x / reservoir_cell_size), floori(z / reservoir_cell_size))
	_lake_mutex.lock()
	var known: Lake = _reservoir_cache.get(cell)
	_lake_mutex.unlock()
	if known and known.surface_at(Vector2(x, z)):
		return known
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
# Talsperren: Staumauer über einem engen Flusstal, dahinter ein Stausee
# ---------------------------------------------------------------------------

## Alle Stauseen, die das Rechteck berühren könnten (rechnet fehlende aus)
func reservoirs_near(rect: Rect2) -> Array:
	var result: Array = []
	var grown := rect.grow(RESERVOIR_RADIUS + 100.0)
	var c0 := Vector2i(floori(grown.position.x / reservoir_cell_size), floori(grown.position.y / reservoir_cell_size))
	var c1 := Vector2i(floori(grown.end.x / reservoir_cell_size), floori(grown.end.y / reservoir_cell_size))
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var lake := reservoir_in_cell(Vector2i(cx, cz))
			if lake and rect.grow(lake.radius).has_point(lake.center):
				result.append(lake)
	return result


## Die Talsperre einer Zelle (oder null), einmal berechnet und gemerkt
func reservoir_in_cell(cell: Vector2i) -> Lake:
	_lake_mutex.lock()
	var known: bool = _reservoir_cache.has(cell)
	var cached: Lake = _reservoir_cache.get(cell)
	_lake_mutex.unlock()
	if known:
		return cached
	var lake := _make_reservoir(cell)
	_lake_mutex.lock()
	_reservoir_cache[cell] = lake
	_lake_mutex.unlock()
	return lake


## Schon berechnete Stauseen in einem Bereich (rechnet nichts Neues, z. B. für die große Karte)
func cached_reservoirs_near(rect: Rect2) -> Array:
	var result: Array = []
	_lake_mutex.lock()
	for lake: Lake in _reservoir_cache.values():
		if lake and rect.grow(lake.radius).has_point(lake.center):
			result.append(lake)
	_lake_mutex.unlock()
	return result


## Führt über diese Landstraße (RoadNetwork-Schlüssel) eine Staumauer? Dann die Talsperre.
func dam_for_road(key: Vector3i) -> Lake:
	var middle := (Vector2(key.x, key.y) + Vector2(0.5, 0.5) + (Vector2(0.5, 0.0) if key.z == 0 else Vector2(0.0, 0.5))) * PLACE_CELL
	var lake := reservoir_in_cell(Vector2i(floori(middle.x / reservoir_cell_size), floori(middle.y / reservoir_cell_size)))
	return lake if lake and lake.road_key == key else null


## Talsperre suchen: Wo kreuzt die Luftlinie zwischen zwei Ortszellen einen vollen Fluss, und
## ist das Tal dort eng (beide Hänge erreichen die Kronenhöhe bald)? Die engsten Stellen werden
## nacheinander geflutet, bis ein Stausee dicht ist (nichts läuft um die Mauer oder aus dem
## Umkreis heraus). Nur aus dem Gelände, damit es unabhängig von der Reihenfolge ist.
func _make_reservoir(cell: Vector2i) -> Lake:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash_cell(cell.x, cell.y, 505)
	if rng.randf() > reservoir_chance:
		return null
	var height := rng.randf_range(dam_min_height, dam_max_height)
	var origin := Vector2(cell) * reservoir_cell_size
	var inner := Rect2(origin, Vector2.ONE * reservoir_cell_size)
	var candidates: Array = []
	var p0 := Vector2i(ceili(inner.position.x / PLACE_CELL), ceili(inner.position.y / PLACE_CELL))
	var p1 := Vector2i(floori(inner.end.x / PLACE_CELL), floori(inner.end.y / PLACE_CELL))
	for pz in range(p0.y, p1.y):
		for px in range(p0.x, p1.x):
			for dir in 2:
				var a := (Vector2(px, pz) + Vector2(0.5, 0.5)) * PLACE_CELL
				var b := a + (Vector2(PLACE_CELL, 0.0) if dir == 0 else Vector2(0.0, PLACE_CELL))
				var site := _dam_site(a, b, height)
				if not site.is_empty():
					site["key"] = Vector3i(px, pz, dir)
					candidates.append(site)
	candidates.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x["length"] < y["length"])
	for k in mini(candidates.size(), 3):
		var lake := _flood(candidates[k])
		if lake:
			lake.name_cell = Vector2i(lake.road_key.x, lake.road_key.y)
			return lake
	return null


## Mögliche Mauer auf der Luftlinie a–b: {"center", "flow", "axis", "left", "right", "crest",
## "river", "length"} oder leer
func _dam_site(a: Vector2, b: Vector2, height: float) -> Dictionary:
	var length := a.distance_to(b)
	var step := 4.0
	for k in range(roundi(length * 0.1 / step), roundi(length * 0.9 / step)):
		var p := a.lerp(b, k * step / length)
		var strength := _river_strength(p.x, p.y)
		if strength < 0.85 or river_distance(p.x, p.y) > 5.0:
			continue
		var flow := river_direction(p.x, p.y)
		if flow == Vector2.ZERO:
			return {}
		# Die Straße soll längs über die Krone führen: Luftlinie fast quer zum Fluss (über 60°)
		if absf((b - a).normalized().dot(flow)) > 0.5:
			return {}
		var axis := Vector2(-flow.y, flow.x)
		var river := ground_level(p.x, p.y) - RIVER_WATER_DROP
		var crest := river + height
		var sides: Array[float] = []
		for sgn: float in [-1.0, 1.0]:
			var found := -1.0
			var d := 16.0
			while d < dam_max_length * 0.75:
				var q := p + axis * sgn * d
				if natural_height(q.x, q.y) >= crest + 0.5:
					found = d
					break
				d += 8.0
			sides.append(found)
		if sides[0] < 0.0 or sides[1] < 0.0 or sides[0] + sides[1] > dam_max_length:
			return {}
		return {"center": p, "flow": flow, "axis": axis, "left": sides[0], "right": sides[1],
			"crest": crest, "river": river, "length": sides[0] + sides[1]}
	return {}


## Stausee hinter der Mauer fluten (Raster RESERVOIR_STEP). null, wenn er nicht dicht ist,
## zu klein, zu groß oder einen runden See berührt.
func _flood(site: Dictionary) -> Lake:
	var center: Vector2 = site["center"]
	var flow: Vector2 = site["flow"]
	var axis: Vector2 = site["axis"]
	var level: float = site["crest"] - RESERVOIR_FREEBOARD
	var dam_a: Vector2 = center - axis * float(site["left"])
	var dam_b: Vector2 = center + axis * float(site["right"])
	var n := int(RESERVOIR_RADIUS * 2.0 / RESERVOIR_STEP)
	var grid_origin := center - Vector2.ONE * RESERVOIR_RADIUS
	var mask := PackedByteArray()
	mask.resize(n * n)
	var visited := PackedByteArray()
	visited.resize(n * n)
	var cell_of := func(p: Vector2) -> Vector2i:
		return Vector2i(floori((p.x - grid_origin.x) / RESERVOIR_STEP), floori((p.y - grid_origin.y) / RESERVOIR_STEP))
	# Die Mauer sperrt (Streifen von 20 m um die Kronenlinie)
	var barrier := func(p: Vector2) -> bool:
		var t := clampf((p - dam_a).dot(dam_b - dam_a) / dam_a.distance_squared_to(dam_b), 0.0, 1.0)
		return p.distance_to(dam_a.lerp(dam_b, t)) < 20.0
	var start: Vector2i = cell_of.call(center - flow * 48.0)
	var stack: Array[Vector2i] = [start]
	visited[start.y * n + start.x] = 1
	var count := 0
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		var p := grid_origin + (Vector2(c) + Vector2(0.5, 0.5)) * RESERVOIR_STEP
		if barrier.call(p) or natural_height(p.x, p.y) >= level:
			continue
		if c.x == 0 or c.y == 0 or c.x == n - 1 or c.y == n - 1:
			return null
		mask[c.y * n + c.x] = 1
		count += 1
		if count * RESERVOIR_STEP * RESERVOIR_STEP > 12.0e6:
			return null
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q := c + d
			if visited[q.y * n + q.x] == 0:
				visited[q.y * n + q.x] = 1
				stack.append(q)
	if count * RESERVOIR_STEP * RESERVOIR_STEP < 1.5e5:
		return null
	# Läuft das Wasser um die Mauer herum ins Tal darunter?
	var below: Vector2i = cell_of.call(center + flow * 64.0)
	if mask[below.y * n + below.x] == 1:
		return null
	# Rand für die Wasserfläche (eine Zelle breiter, nicht durch die Mauer)
	var bounds := Rect2()
	var first := true
	for cz in range(1, n - 1):
		for cx in range(1, n - 1):
			if mask[cz * n + cx] != 0:
				continue
			var near := mask[cz * n + cx - 1] == 1 or mask[cz * n + cx + 1] == 1 or mask[(cz - 1) * n + cx] == 1 \
				or mask[(cz + 1) * n + cx] == 1
			var p := grid_origin + (Vector2(cx, cz) + Vector2(0.5, 0.5)) * RESERVOIR_STEP
			if near and not ((p - center).dot(flow) > -6.0 and barrier.call(p)):
				mask[cz * n + cx] = 3
	for i in mask.size():
		if mask[i] == 3:
			mask[i] = 2
		if mask[i] != 0:
			var p := grid_origin + (Vector2(i % n, floori(float(i) / n)) + Vector2(0.5, 0.5)) * RESERVOIR_STEP
			bounds = Rect2(p, Vector2.ZERO) if first else bounds.expand(p)
			first = false
	# Keine runden Seen im Stausee
	for lake: Lake in lakes_near(bounds, false):
		for i in mask.size():
			if mask[i] == 1:
				var p := grid_origin + (Vector2(i % n, floori(float(i) / n)) + Vector2(0.5, 0.5)) * RESERVOIR_STEP
				if p.distance_to(lake.center) < lake.radius + 60.0:
					return null
	var lake := Lake.new()
	lake.reservoir = true
	lake.level = level
	lake.depth = level - float(site["river"])
	lake.mask = mask
	lake.mask_origin = grid_origin
	lake.mask_size = Vector2i(n, n)
	lake.center = bounds.get_center()
	lake.radius = bounds.size.length() * 0.5 + RESERVOIR_STEP
	lake.dam_a = dam_a
	lake.dam_b = dam_b
	lake.crest = site["crest"]
	lake.flow = flow
	lake.dam_center = center
	lake.river_level = site["river"]
	lake.road_key = site["key"]
	return lake


# ---------------------------------------------------------------------------
# Wasserfälle: ein Bach fällt über eine steile Felskante
# ---------------------------------------------------------------------------

## Wasserfälle, die das Rechteck berühren: {"path" (Punkte von oben nach unten, knapp über dem
## Fels), "top", "bottom", "width", "drop", "cell"}
func waterfalls_near(rect: Rect2) -> Array:
	var result: Array = []
	var grown := rect.grow(80.0)
	var c0 := Vector2i(floori(grown.position.x / lake_cell_size), floori(grown.position.y / lake_cell_size))
	var c1 := Vector2i(floori(grown.end.x / lake_cell_size), floori(grown.end.y / lake_cell_size))
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var cell := Vector2i(cx, cz)
			_lake_mutex.lock()
			var known: bool = _waterfall_cache.has(cell)
			var fall: Dictionary = _waterfall_cache.get(cell, {})
			_lake_mutex.unlock()
			if not known:
				fall = _make_waterfall(cell)
				_lake_mutex.lock()
				_waterfall_cache[cell] = fall
				_lake_mutex.unlock()
			if not fall.is_empty():
				var top: Vector3 = fall["top"]
				var bottom: Vector3 = fall["bottom"]
				if grown.has_point(Vector2(top.x, top.z)) or grown.has_point(Vector2(bottom.x, bottom.z)):
					result.append(fall)
	return result


## Steilste Stelle unter einigen Zufallspunkten der Zelle; von dort bergab, solange es steil ist.
## Leer, wenn es nirgends steil und hoch genug ist oder unten Wasser steht.
func _make_waterfall(cell: Vector2i) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash_cell(cell.x, cell.y, 606)
	if rng.randf() > waterfall_chance:
		return {}
	var origin := Vector2(cell) * lake_cell_size
	var top := Vector2.ZERO
	var best_slope := 0.0
	for k in 64:
		var p0 := origin + Vector2(rng.randf_range(200.0, lake_cell_size - 200.0), rng.randf_range(200.0, lake_cell_size - 200.0))
		var g0 := _gradient(p0, 6.0)
		if g0.length() < 1.1 or g0.length() < best_slope or natural_height(p0.x, p0.y) > snow_height - 160.0:
			continue
		var edge := _waterfall_edge(p0)
		if edge != Vector2.INF:
			best_slope = g0.length()
			top = edge
	if best_slope == 0.0:
		return {}
	var path := PackedVector3Array()
	var p := top
	for k in 30:
		var h := natural_height(p.x, p.y)
		path.append(Vector3(p.x, h, p.y))
		var g := _gradient(p, 3.0)
		# Unten wird es flacher (dort ist das Becken), höher als waterfall_max_drop wird es nicht
		if k > 2 and (g.length() < 0.6 or path[0].y - h > waterfall_max_drop):
			break
		if g.length() < 0.001:
			break
		p -= g.normalized() * 3.0
	var drop := path[0].y - path[path.size() - 1].y
	if drop < waterfall_min_drop or path.size() < 5:
		return {}
	# Nicht im Schnee (weißer Schaum auf weißem Fels) und unten mit Wald und Wiese
	if path[0].y > snow_height - 120.0 or path[path.size() - 1].y > tree_line:
		return {}
	var bottom := path[path.size() - 1]
	if water_level_at(bottom.x, bottom.z, lakes_near(Rect2(Vector2(bottom.x, bottom.z), Vector2.ONE), false, false)) > NO_WATER:
		return {}
	var width := rng.randf_range(3.5, 8.0)
	var pool := Lake.new()
	pool.pool = true
	pool.center = Vector2(bottom.x, bottom.z)
	pool.radius = width * 0.8 + 2.5
	pool.level = bottom.y - 0.4
	pool.depth = 1.8
	return {"path": path, "top": path[0], "bottom": bottom, "width": width, "drop": drop, "cell": cell, "pool": pool}


## Kante eines Wasserfalls über dem steilen Punkt p: bergauf bis dahin, wo es flacher wird.
## Vector2.INF, wenn dort nichts herabfließen kann: Über der Kante muss der Hang weitergehen
## (das Wasser kommt von oben), und sie liegt in einer Rinne (links und rechts höher), nicht auf
## einem Grat.
func _waterfall_edge(p: Vector2) -> Vector2:
	var top := p
	for k in 12:
		var g := _gradient(top, 4.0)
		if g.length() < 0.6:
			break
		top += g.normalized() * 3.0
	var up_dir := _gradient(top, 4.0).normalized()
	var side := Vector2(-up_dir.y, up_dir.x)
	var h_top := natural_height(top.x, top.y)
	var behind := top + up_dir * 120.0
	if natural_height(behind.x, behind.y) - h_top < 25.0:
		return Vector2.INF
	var l := top + side * 22.0
	var r := top - side * 22.0
	if natural_height(l.x, l.y) - h_top < 1.5 or natural_height(r.x, r.y) - h_top < 1.5:
		return Vector2.INF
	return top


## Steigung des natürlichen Geländes (zeigt bergauf)
func _gradient(p: Vector2, e: float) -> Vector2:
	return Vector2(natural_height(p.x + e, p.y) - natural_height(p.x - e, p.y),
		natural_height(p.x, p.y + e) - natural_height(p.x, p.y - e)) / (2.0 * e)


# ---------------------------------------------------------------------------
# Wald, Schnee, Zufall
# ---------------------------------------------------------------------------

## Wie dicht hier Wald steht (0 bis 1). slope = 1 - Normale.y (0 = flach)
func forest_density(x: float, z: float, height: float, slope: float) -> float:
	var base := smoothstep(-0.15, 0.35, _forest.get_noise_2d(x, z))
	var below_line := 1.0 - smoothstep(tree_line - 120.0, tree_line, height)
	var not_steep := 1.0 - smoothstep(0.25, 0.4, slope)
	return base * below_line * not_steep


## Baumgruppen (-1 bis 1, Muster im Abstand von etwa 60 m): hoch = dichte Gruppe, tief = Lücke bzw. Lichtung
func groves(x: float, z: float) -> float:
	return _groves.get_noise_2d(x, z)


## Großflächige Zufalls-Variation (-1 bis 1), z. B. für Farbe oder Dichte
func variation(x: float, z: float) -> float:
	return _variation.get_noise_2d(x, z)


## Ganzzahliger Zufallswert für eine Zelle, immer gleich für denselben Seed
func hash_cell(cx: int, cz: int, salt: int) -> int:
	var h: int = cx * 374761393 + cz * 668265263 + salt * 2246822519 + world_seed * 3266489917
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return h & 0x7FFFFFFF
