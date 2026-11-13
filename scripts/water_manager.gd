class_name WaterManager
extends Node3D
## Seen und alles, was das Auto im Wasser betrifft.
## - Für jeden See in der Nähe liegt eine flache, runde Wasserfläche auf Wasserhöhe; Stauseen
##   bekommen eine Fläche aus ihrem Raster (an der Mauer genau an der Wasserseite abgeschnitten)
##   und ihre Staumauer (Dam.build) mit Brüstung zum Anfahren, Überlauf und Laternen.
##   (Flüsse baut der TerrainManager pro Kachel, siehe terrain_chunk_job.gd.)
## - Fährt das Auto ins Wasser, wird es stark gebremst und nach ein paar Sekunden
##   auf die nächste Straße gesetzt. Die Fahrphysik des Autos selbst bleibt unverändert.

@export var water_material: Material
## Bis zu dieser Entfernung werden Seen angezeigt
@export var lake_distance: float = 3500.0
## Bremskraft im Wasser (Newton pro m/s Geschwindigkeit)
@export var water_drag: float = 2500.0
## Nach so vielen Sekunden im Wasser geht es zurück auf die Straße
@export var reset_after_seconds: float = 3.0
## Nachts: so viele echte Lichter an den nächsten Laternen der Staumauern, bis zu dieser Entfernung
@export var dam_light_count: int = 4
@export var dam_light_distance: float = 180.0

var world_gen: WorldGen
var car: VehicleBody3D
var roads: RoadNetwork
var _lakes: Dictionary = {}  # Mittelpunkt (Vector2) -> MeshInstance3D
var _disc_mesh: ArrayMesh
var _update_timer: float = 0.0
var _time_in_water: float = 0.0
var _dams: Dictionary = {}  # Mittelpunkt des Sees -> {"node", "lights"}
var _dam_concrete: ShaderMaterial
var _dam_dark: StandardMaterial3D
var _lamp_lights: Array[OmniLight3D] = []
var _day_night: DayNight


func start(gen: WorldGen, the_car: VehicleBody3D, road_network: RoadNetwork) -> void:
	world_gen = gen
	car = the_car
	roads = road_network
	_disc_mesh = _make_disc_mesh()


func _process(delta: float) -> void:
	if world_gen == null:
		return
	_update_timer -= delta
	if _update_timer > 0.0:
		return
	_update_timer = 0.5
	_update_dam_lights()
	var p := Vector2(car.global_position.x, car.global_position.z)
	var area := Rect2(p - Vector2.ONE * lake_distance, Vector2.ONE * lake_distance * 2.0)
	var wanted := {}
	# Stauseen nur, wenn schon berechnet (das machen die Gelände-Kacheln im Hintergrund)
	for lake: WorldGen.Lake in world_gen.lakes_near(area, false) + world_gen.cached_reservoirs_near(area):
		wanted[lake.center] = lake
	for center: Vector2 in _lakes.keys():
		if not wanted.has(center):
			_lakes[center].queue_free()
			_lakes.erase(center)
			if _dams.has(center):
				(_dams[center]["node"] as Node3D).queue_free()
				_dams.erase(center)
	for center: Vector2 in wanted:
		if _lakes.has(center):
			continue
		var lake: WorldGen.Lake = wanted[center]
		var surface := MeshInstance3D.new()
		surface.material_override = water_material
		surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		surface.position = Vector3(center.x, lake.level, center.y)
		if lake.reservoir:
			surface.mesh = _reservoir_mesh(lake)
			_dams[center] = _build_dam(lake)
		else:
			surface.mesh = _disc_mesh
			# Etwas kleiner als der See: am Rand liegt das Ufer genau auf Wasserhöhe
			var radius := lake.radius - 1.0
			surface.scale = Vector3(radius, 1.0, radius)
		add_child(surface)
		_lakes[center] = surface


## Staumauer bauen: Beton (beidseitig, Fugen im Shader), Handlauf und Masten aus Metall,
## leuchtende Lampen, dunkle Öffnungen und fallendes Wasser am Überlauf, unten Gischt und Rauschen
func _build_dam(lake: WorldGen.Lake) -> Dictionary:
	var parts := Dam.build(lake, world_gen)
	if _dam_concrete == null:
		_dam_concrete = ShaderMaterial.new()
		_dam_concrete.shader = load("res://shaders/dam.gdshader")
		_dam_dark = StandardMaterial3D.new()
		_dam_dark.albedo_color = Color(0.04, 0.045, 0.05)
		_dam_dark.cull_mode = BaseMaterial3D.CULL_DISABLED
	var node := Node3D.new()
	add_child(node)
	node.position = Dam.anchor(lake)
	var materials := {"concrete": _dam_concrete, "metal": roads.rail_material, "lamps": roads.lamp_material,
		"gates": _dam_dark, "water": Waterfalls.fall_material(false)}
	for part: String in materials:
		var arrays: Array = parts[part]
		if arrays.is_empty():
			continue
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.material_override = materials[part]
		if part != "concrete":
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(instance)
	# Die Brüstung hält das Auto auf der Krone
	var faces: PackedVector3Array = parts["collision"]
	if not faces.is_empty():
		var local := PackedVector3Array()
		for f in faces:
			local.append(f - node.position)
		var body := StaticBody3D.new()
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(local)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		node.add_child(body)
	var top: Vector3 = parts["spill_top"]
	var bottom: Vector3 = parts["spill_bottom"]
	if bottom != Vector3.ZERO:
		var effects := Waterfalls.make_effects(Dam.SPILL_WIDTH, top.y - bottom.y)
		node.add_child(effects)
		effects.global_position = bottom
	return {"node": node, "lights": parts["lights"]}


## Nachts echte Lichter an den nächsten Laternen der Staumauern (wenige, ohne Schatten)
func _update_dam_lights() -> void:
	if _day_night == null:
		_day_night = get_tree().get_first_node_in_group("day_night") as DayNight
	var night := _day_night != null and _day_night.sun_direction().y < sin(deg_to_rad(4.0))
	if _lamp_lights.is_empty():
		for k in dam_light_count:
			var light := OmniLight3D.new()
			light.light_color = Color(1.0, 0.86, 0.65)
			light.omni_range = 18.0
			light.light_energy = 2.0
			light.visible = false
			add_child(light)
			_lamp_lights.append(light)
	var near: Array = []
	if night:
		var p := car.global_position
		for dam: Dictionary in _dams.values():
			for head: Vector3 in dam["lights"]:
				var d := head.distance_to(p)
				if d < dam_light_distance:
					near.append([d, head])
		near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for k in _lamp_lights.size():
		_lamp_lights[k].visible = k < near.size()
		if _lamp_lights[k].visible:
			_lamp_lights[k].global_position = near[k][1]


func _physics_process(delta: float) -> void:
	if world_gen == null or car.freeze:
		return
	var p := car.global_position
	var lakes: Array = world_gen.lakes_near(Rect2(p.x - 1.0, p.z - 1.0, 2.0, 2.0))
	var level := world_gen.water_level_at(p.x, p.z, lakes)
	if level > WorldGen.NO_WATER and p.y < level + 0.2:
		# Im Wasser: kräftig abbremsen
		car.apply_central_force(-car.linear_velocity * water_drag)
		_time_in_water += delta
		if _time_in_water > reset_after_seconds:
			_time_in_water = 0.0
			# Zurück vor die Stelle, an der das Auto die Straße verlassen hat (wie Taste R)
			var reset := get_node_or_null("../CarReset") as CarReset
			if reset:
				reset.back_to_road()
				Toasts.post(get_tree(), "pin", "Zurück auf die Straße", "Aus dem Wasser geholt")
			else:
				var result := roads.nearest_road_transform(p, car.global_basis.z)
				if result["found"]:
					car.teleport(result["transform"])
	else:
		_time_in_water = 0.0


## Wasserfläche eines Stausees (relativ zu lake.center): je Rasterzeile lange Streifen aus den
## Wasserzellen; nah an der Mauer Zelle für Zelle, abgeschnitten 6 m vor der Kronenlinie
func _reservoir_mesh(lake: WorldGen.Lake) -> ArrayMesh:
	var verts := PackedVector3Array()
	var step := WorldGen.RESERVOIR_STEP
	var size := lake.mask_size
	var add_polygon := func(polygon: PackedVector2Array) -> void:
		for k in range(1, polygon.size() - 1):
			for q: Vector2 in [polygon[0], polygon[k], polygon[k + 1]]:
				verts.append(Vector3(q.x - lake.center.x, 0.0, q.y - lake.center.y))
	for cz in size.y:
		var run_start := -1
		for cx in size.x + 1:
			var wet := cx < size.x and lake.mask[cz * size.x + cx] > 0
			var corner := lake.mask_origin + Vector2(cx, cz) * step
			# Nah an der Mauer: einzeln, mit Schnitt an der Wasserseite
			if wet and lake.dam_distance(corner + Vector2.ONE * step * 0.5) < 80.0:
				if run_start >= 0:
					add_polygon.call(_cell_run(lake, run_start, cx, cz))
					run_start = -1
				var clipped := _clip_behind_dam(lake, _cell_run(lake, cx, cx + 1, cz))
				if clipped.size() >= 3:
					add_polygon.call(clipped)
				continue
			if wet and run_start < 0:
				run_start = cx
			elif not wet and run_start >= 0:
				add_polygon.call(_cell_run(lake, run_start, cx, cz))
				run_start = -1
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	var uvs := PackedVector2Array()
	uvs.resize(verts.size())
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	if not verts.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Rechteck über die Zellen von cx0 bis cx1 (ausschließlich) in Zeile cz (Weltkoordinaten x/z)
func _cell_run(lake: WorldGen.Lake, cx0: int, cx1: int, cz: int) -> PackedVector2Array:
	var step := WorldGen.RESERVOIR_STEP
	var a := lake.mask_origin + Vector2(cx0, cz) * step
	var b := lake.mask_origin + Vector2(cx1, cz + 1) * step
	return PackedVector2Array([a, Vector2(b.x, a.y), b, Vector2(a.x, b.y)])


## Vieleck an der Linie 6 m vor der Mauerkrone abschneiden (nur die Wasserseite bleibt)
func _clip_behind_dam(lake: WorldGen.Lake, polygon: PackedVector2Array) -> PackedVector2Array:
	var keep := func(q: Vector2) -> float:
		return -6.0 - (q - lake.dam_center).dot(lake.flow)
	var result := PackedVector2Array()
	for k in polygon.size():
		var a := polygon[k]
		var b := polygon[(k + 1) % polygon.size()]
		var ka: float = keep.call(a)
		var kb: float = keep.call(b)
		if ka >= 0.0:
			result.append(a)
		if (ka >= 0.0) != (kb >= 0.0):
			result.append(a.lerp(b, ka / (ka - kb)))
	return result


## Kreisscheibe mit Radius 1 (wird pro See skaliert)
func _make_disc_mesh() -> ArrayMesh:
	var verts := PackedVector3Array([Vector3.ZERO])
	var normals := PackedVector3Array([Vector3.UP])
	var uvs := PackedVector2Array([Vector2.ZERO])
	var indices := PackedInt32Array()
	var steps := 96
	for i in steps:
		var angle := TAU * i / steps
		verts.append(Vector3(cos(angle), 0.0, sin(angle)))
		normals.append(Vector3.UP)
		uvs.append(Vector2.ZERO)
	for i in steps:
		indices.append_array([0, i + 1, (i + 1) % steps + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
