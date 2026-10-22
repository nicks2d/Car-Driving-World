extends Node3D
## Startet die Welt: richtet die Welt-Formel ein, sucht einen Startplatz für das Auto
## und lässt es erst losfahren, wenn das Gelände drumherum geladen ist.

## Die Welt-Formel mit allen Einstellungen (Seed, Bergeshöhe, ...)
@export var world_gen: WorldGen
@export var terrain: TerrainManager
@export var horizon: HorizonRing
@export var car: VehicleBody3D
@export var loading_screen: Control
@export var debug_tools: DebugTools
@export var day_night: DayNight
@export var roads: RoadNetwork
@export var water: WaterManager
@export var grass: GrassManager

var world_is_ready: bool = false
var _car_on_road: bool = false
var _start_point: Vector2 = Vector2.ZERO
var _start_heading: float = 0.0
var _place_timer: float = 0.0


func _ready() -> void:
	world_gen.setup()
	var start_point := Vector2.ZERO
	var heading := 0.0
	if debug_tools.has_start_position:
		start_point = debug_tools.start_position
		heading = debug_tools.start_heading
	if debug_tools.time_of_day >= 0.0:
		day_night.time_of_day = debug_tools.time_of_day
		day_night.paused = true
	if debug_tools.volumetric_fog:
		day_night.set_volumetric_fog(true)
	_start_point = start_point
	_start_heading = heading
	car.freeze = true
	# Vorläufiger Platz, bis die Straßen in der Nähe berechnet sind
	car.teleport(find_start(start_point, heading), true)
	roads.start(world_gen, car)
	terrain.start(world_gen, car, roads)
	horizon.start(world_gen, car)
	water.start(world_gen, car, roads)
	grass.start(world_gen, car, terrain, roads)
	loading_screen.visible = true


func _process(delta: float) -> void:
	if world_is_ready:
		return
	if not _car_on_road:
		_place_car_on_road(delta)
		return
	if terrain.is_area_ready(car.global_position) and horizon.is_ready():
		world_is_ready = true
		loading_screen.visible = false
		car.freeze = false
		debug_tools.on_world_ready(self)


## Setzt das Auto auf die nächste Straße, sobald die Straßen in der Nähe berechnet sind
func _place_car_on_road(delta: float) -> void:
	_place_timer += delta
	if not roads.is_area_ready(_start_point, 1200.0):
		return
	var forward := Vector3(sin(deg_to_rad(_start_heading)), 0.0, cos(deg_to_rad(_start_heading)))
	var result := roads.nearest_road_transform(Vector3(_start_point.x, 0.0, _start_point.y), forward)
	if result["found"]:
		car.teleport(result["transform"], true)
		_car_on_road = true
	elif _place_timer > 15.0:
		# Notfall: weit und breit keine Straße, dann eben im Gelände starten
		push_warning("Keine Straße in der Nähe gefunden, Auto startet im Gelände.")
		_car_on_road = true


## Geländehöhe an einer Stelle (ohne Straßen)
func ground_height(x: float, z: float) -> float:
	var lakes: Array = world_gen.lakes_near(Rect2(x - 1.0, z - 1.0, 2.0, 2.0))
	return world_gen.terrain_height(x, z, lakes)


## Sucht in der Nähe eine flache, trockene Stelle für das Auto
func find_start(near: Vector2, heading_degrees: float) -> Transform3D:
	var best := near
	var best_score := INF
	for iz in range(-8, 9):
		for ix in range(-8, 9):
			var p := near + Vector2(ix, iz) * 40.0
			var lakes: Array = world_gen.lakes_near(Rect2(p.x - 1.0, p.y - 1.0, 2.0, 2.0))
			if world_gen.water_level_at(p.x, p.y, lakes) > WorldGen.NO_WATER:
				continue
			var h := world_gen.terrain_height(p.x, p.y, lakes)
			var bumpiness := absf(world_gen.terrain_height(p.x + 4.0, p.y, lakes) - h) \
				+ absf(world_gen.terrain_height(p.x, p.y + 4.0, lakes) - h)
			var score := bumpiness * 10.0 + p.distance_to(near) * 0.01
			if score < best_score:
				best_score = score
				best = p
	var start_position := Vector3(best.x, ground_height(best.x, best.y) + 1.2, best.y)
	return Transform3D(Basis(Vector3.UP, deg_to_rad(heading_degrees)), start_position)
