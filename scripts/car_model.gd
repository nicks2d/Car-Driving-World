class_name CarModel
extends Node3D
## Das sichtbare Auto. Lädt das Modell aus dem Profil des Autos (CarProfile) und baut es ein:
##  - Teile nach den Mustern im Profil einordnen (Räder, Bremssättel, Aufkleber, ausblenden)
##  - Rad-Meshes, die alle vier Räder enthalten, nach Ecken aufteilen
##  - eingeschlagene Vorderräder gerade stellen (wenn das Profil es sagt)
##  - Modell so skalieren und verschieben, dass seine Räder auf den Physik-Rädern sitzen
##  - Räder an die Physik-Räder hängen (drehen, lenken, federn), Bremssättel nur lenken lassen
##  - unbewegliche Teile pro Material zusammenfassen (weniger Draw Calls, wenn gewünscht)
##  - eigene Materialien (Lack, Glas, Felgen, Reifen, Lichter), Schatten nur für große Teile
## Ohne Modell bleibt die Platzhalter-Box. Als Kind eines Car fährt es mit; sonst (Vorschau
## in der Garage) stellt es die Räder einfach an ihre Plätze.
##
## Tasten (nur am Car): C = Lackfarbe wechseln, K = Aufkleber an/aus, L = Licht an/aus.

## Wird gesendet, wenn das Modell fertig eingebaut ist (oder keins da ist)
signal model_ready

@export_group("Lack")
## Klarlack: Stärke und Rauheit (klein = spiegelt klar)
@export_range(0.0, 1.0) var clearcoat: float = 1.0
@export_range(0.0, 1.0) var clearcoat_roughness: float = 0.06
## Aufkleber beim Start sichtbar?
@export var stickers_visible: bool = true

@export_group("Licht")
## Helligkeit der Scheinwerfer (SpotLight3D) und wie weit sie reichen
@export var headlight_energy: float = 10.0
@export var headlight_range: float = 80.0
@export_range(5.0, 80.0) var headlight_angle: float = 32.0
## Leuchtstärke der Lampen selbst (Emission): Scheinwerfer, Rücklicht, Bremslicht
@export var headlight_glow: float = 6.0
@export var taillight_glow: float = 1.5
@export var brake_glow: float = 6.0
## Licht geht automatisch an, wenn die Sonne tiefer als so viele Grad steht
@export var lights_on_below_sun_degrees: float = 4.0
## Diese Teile wechseln früher auf vereinfachte Versionen (LOD), Wert < 1 = früher
@export var low_detail_lod_bias: float = 0.35

## Aktuelle Lackfarbe (Index in profile.paint_colors)
var paint_index: int = 0
## Gemessen am Modell (in Metern, nach dem Einpassen): Radstand, Spurweiten, Radradius.
## Hilft beim Einstellen der Profile, damit Physik und Modell zusammenpassen.
var measured: Dictionary = {}

var _root: Node3D
var _car: Car
var _profile: CarProfile
var _loading_path: String = ""
var _pivot: Node3D
var _model: Node3D
var _paint: StandardMaterial3D
var _stickers: Array[Node3D] = []
var _head_glow: StandardMaterial3D
var _tail_glow: StandardMaterial3D
var _spots: Array[SpotLight3D] = []
var _lights_on: bool = false
var _was_night: bool = false
var _day_night: DayNight
## Radplätze in der Reihenfolge der Ecken (vorne links, vorne rechts, hinten links,
## hinten rechts): bei einem Car die VehicleWheel3D, in der Vorschau einfache Knoten
var _anchors: Array[Node3D] = []
## Bremssättel: lenken mit, drehen sich aber nicht mit dem Rad. [Halter, Rad]
var _calipers: Array = []
## Alles, was beim Wechsel wieder weg muss (Halter, Scheinwerfer, Vorschau-Räder)
var _extra_nodes: Array[Node] = []


## Pfad zum Modell eines Profils
static func model_path(profile: CarProfile) -> String:
	return "res://assets/models/%s/scene.gltf" % profile.model_folder


## Liegt das Modell dieses Autos im Projekt?
static func is_available(profile: CarProfile) -> bool:
	return ResourceLoader.exists(model_path(profile))


func _ready() -> void:
	_root = get_parent() as Node3D
	_car = _root as Car
	if _car:
		# Erst im nächsten Moment: Während _ready() richtet das Auto noch seine Kind-Nodes
		# ein und nimmt keine neuen an. Dann das Auto zeigen, das in dem Moment gewählt ist.
		_car.profile_changed.connect(func(_p: CarProfile) -> void: _show_current.call_deferred())
		_show_current.call_deferred()


func _show_current() -> void:
	if _car.profile and (_profile != _car.profile or (_model == null and _loading_path == "")):
		show_profile(_car.profile)


## Modell eines Autos laden und einbauen (das alte wird freigegeben)
func show_profile(profile: CarProfile) -> void:
	if _root == null:
		_root = get_parent() as Node3D
	_clear()
	_profile = profile
	paint_index = clampi(paint_index, 0, maxi(profile.paint_colors.size() - 1, 0))
	if _car == null:
		_make_preview_anchors()
	else:
		_anchors.assign(_car.corner_wheels())
	if not is_available(profile):
		print("Modell für %s nicht gefunden (siehe assets/models/README.md)" % profile.display_name)
		_set_placeholder(true)
		model_ready.emit()
		return
	# Im Hintergrund laden, damit das Spiel nicht hängt
	_loading_path = model_path(profile)
	ResourceLoader.load_threaded_request(_loading_path)


## Wird das Modell gerade geladen?
func is_loading() -> bool:
	return _loading_path != ""


func set_paint(index: int) -> void:
	paint_index = index
	if _paint and _profile and index < _profile.paint_colors.size():
		_paint.albedo_color = _profile.paint_colors[index]


func _physics_process(_delta: float) -> void:
	# Bremssättel folgen Federung und Lenkung, drehen sich aber nicht mit
	for pair: Array in _calipers:
		var holder: Node3D = pair[0]
		var wheel := pair[1] as VehicleWheel3D
		if wheel:
			holder.transform = Transform3D(Basis(Vector3.UP, wheel.steering), wheel.transform.origin)


func _process(_delta: float) -> void:
	if _loading_path != "":
		_check_loading()
		return
	if _model == null or _car == null:
		return
	if Input.is_action_just_pressed("cycle_paint"):
		set_paint((paint_index + 1) % _profile.paint_colors.size())
	if Input.is_action_just_pressed("toggle_stickers") and not _stickers.is_empty():
		_set_stickers(not _stickers[0].visible)
	# Licht: schaltet sich bei Dämmerung an und morgens aus, L schaltet von Hand
	var night := _is_night() or _car.in_tunnel
	if night != _was_night:
		_was_night = night
		_lights_on = night
	if Input.is_action_just_pressed("toggle_lights"):
		_lights_on = not _lights_on
	for spot in _spots:
		spot.visible = _lights_on
	_head_glow.emission_energy_multiplier = headlight_glow if _lights_on else 0.15
	_tail_glow.emission_energy_multiplier = brake_glow if _car.braking else (taillight_glow if _lights_on else 0.1)


func _check_loading() -> void:
	var status := ResourceLoader.load_threaded_get_status(_loading_path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	var path := _loading_path
	_loading_path = ""
	var scene := ResourceLoader.load_threaded_get(path) as PackedScene
	# Inzwischen wurde vielleicht schon ein anderes Auto gewählt
	if scene == null or path != model_path(_profile):
		if scene == null:
			_set_placeholder(true)
			model_ready.emit()
		return
	_build(scene)
	model_ready.emit()


func _is_night() -> bool:
	if _day_night == null:
		_day_night = get_tree().get_first_node_in_group("day_night") as DayNight
	if _day_night == null:
		return false
	return _day_night.sun_direction().y < sin(deg_to_rad(lights_on_below_sun_degrees))


func _wheels() -> Array[VehicleWheel3D]:
	var result: Array[VehicleWheel3D] = []
	for child in _root.get_children():
		if child is VehicleWheel3D:
			result.append(child)
	return result


## Vorschau ohne Physik: vier Knoten dort, wo die Radmitten stehen würden
func _make_preview_anchors() -> void:
	_anchors.clear()
	for corner in 4:
		var anchor := Node3D.new()
		anchor.position = Car.resting_wheel_center(_profile, corner)
		_root.add_child(anchor)
		_anchors.append(anchor)
		_extra_nodes.append(anchor)


## Modell freigeben (z. B. die Vorschau in der Garage beim Schließen)
func clear() -> void:
	_clear()
	_profile = null
	_loading_path = ""


func _clear() -> void:
	if _pivot:
		_pivot.queue_free()
	for node in _extra_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_extra_nodes.clear()
	_pivot = null
	_model = null
	_stickers.clear()
	_spots.clear()
	_calipers.clear()
	_anchors.clear()


func _set_placeholder(on: bool) -> void:
	if _car == null:
		return
	for path in ["BodyMesh", "CabinMesh", "HeadlightLeft", "HeadlightRight"]:
		(_car.get_node(path) as Node3D).visible = on
	for wheel in _wheels():
		for child in ["Tire", "Spoke"]:
			(wheel.get_node(child) as Node3D).visible = on


# ---------------------------------------------------------------------------
# Einbauen
# ---------------------------------------------------------------------------

func _build(scene: PackedScene) -> void:
	_pivot = Node3D.new()
	_pivot.name = "ModelPivot"
	_pivot.rotation.y = deg_to_rad(_profile.model_rotation_deg)
	add_child(_pivot)
	_model = scene.instantiate() as Node3D
	_pivot.add_child(_model)
	var wheels: Array[MeshInstance3D] = []
	var calipers: Array[MeshInstance3D] = []
	var body: Array[MeshInstance3D] = []
	for mi in _meshes_under(_model):
		if _matches(mi, _profile.hidden_parts):
			mi.queue_free()
		elif _matches(mi, _profile.wheel_parts):
			wheels.append(mi)
		elif _matches(mi, _profile.caliper_parts):
			calipers.append(mi)
		else:
			body.append(mi)
	# Mitte zwischen den Rädern (noch in Modellgröße): daran werden Ecken unterschieden
	var wheel_box := _box_of(wheels)
	var middle := wheel_box.get_center()
	wheels = _split_all(wheels, middle, wheel_box.size)
	calipers = _split_all(calipers, middle, wheel_box.size)
	# Vier Ecken: 0 = vorne links (+x, +z), 1 = vorne rechts, 2 = hinten links, 3 = hinten rechts
	var corner_parts: Array = [[], [], [], []]
	for mi in wheels:
		corner_parts[_corner_of(_center_in_root(mi), middle)].append(mi)
	var corner_centers: Array[Vector3] = []
	for corner in 4:
		var parts: Array[MeshInstance3D] = []
		parts.assign(corner_parts[corner])
		corner_centers.append(_box_of(parts).get_center())
	var caliper_corners: Array = [[], [], [], []]
	for mi in calipers:
		caliper_corners[_corner_of(_center_in_root(mi), middle)].append(mi)
	if _profile.straighten_front_wheels:
		for corner in 2:
			_straighten(corner_parts[corner], corner_parts[corner] + caliper_corners[corner], corner_centers[corner])
	_fit(corner_centers)
	_measure(corner_centers, corner_parts)
	# Räder an die Physik-Räder (bzw. Vorschau-Halter) hängen, Sättel an eigene Halter
	for corner in 4:
		var anchor := _anchors[corner]
		var center := Car.resting_wheel_center(_profile, corner)
		for mi: MeshInstance3D in corner_parts[corner]:
			_attach(mi, anchor, center)
		if caliper_corners[corner].is_empty():
			continue
		var holder := Node3D.new()
		holder.name = "Caliper" + anchor.name
		_root.add_child(holder)
		holder.position = center
		_extra_nodes.append(holder)
		for mi: MeshInstance3D in caliper_corners[corner]:
			_attach(mi, holder, center)
		_calipers.append([holder, anchor])
	_make_materials()
	if _profile.merge_static_parts:
		body = _merge_static(body)
		# Auch die vielen kleinen Radteile pro Ecke zusammenfassen
		wheels = []
		calipers = []
		for corner in 4:
			wheels.append_array(_merge_attached(_anchors[corner]))
		for pair: Array in _calipers:
			calipers.append_array(_merge_attached(pair[0]))
	for mi in body + wheels + calipers:
		_setup_mesh(mi)
	_setup_headlights()
	_set_stickers(stickers_visible)
	_set_placeholder(false)


func _meshes_under(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is MeshInstance3D and (current as MeshInstance3D).mesh:
			result.append(current)
		stack.append_array(current.get_children())
	return result


## Passt eins der Muster auf den Knoten, einen seiner Eltern oder eins seiner Materialien?
func _matches(mi: MeshInstance3D, patterns: PackedStringArray) -> bool:
	if patterns.is_empty():
		return false
	var names: Array[String] = []
	var node: Node = mi
	while node and node != _pivot:
		names.append(String(node.name))
		node = node.get_parent()
	for s in mi.mesh.get_surface_count():
		var material := mi.mesh.surface_get_material(s)
		if material:
			names.append(material.resource_name)
	for text in names:
		for pattern in patterns:
			if text.matchn(pattern):
				return true
	return false


## Lage eines Mesh relativ zum Auto
func _to_root(node: Node3D) -> Transform3D:
	return _root.global_transform.affine_inverse() * node.global_transform


func _center_in_root(mi: MeshInstance3D) -> Vector3:
	return (_to_root(mi) * mi.get_aabb()).get_center()


func _box_of(meshes: Array[MeshInstance3D]) -> AABB:
	var box := AABB()
	for i in meshes.size():
		var part := _to_root(meshes[i]) * meshes[i].get_aabb()
		box = part if i == 0 else box.merge(part)
	return box


## 0 = vorne links (+x, +z), 1 = vorne rechts, 2 = hinten links, 3 = hinten rechts
func _corner_of(p: Vector3, middle: Vector3) -> int:
	return (0 if p.x > middle.x else 1) + (0 if p.z > middle.z else 2)


## Meshes, die über mehrere Ecken reichen (z. B. alle vier Reifen in einem Mesh), aufteilen
func _split_all(meshes: Array[MeshInstance3D], middle: Vector3, size: Vector3) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for mi in meshes:
		var box := _to_root(mi) * mi.get_aabb()
		var spans_x := box.position.x < middle.x - size.x * 0.1 and box.end.x > middle.x + size.x * 0.1
		var spans_z := box.position.z < middle.z - size.z * 0.1 and box.end.z > middle.z + size.z * 0.1
		if spans_x or spans_z:
			result.append_array(_split_by_corner(mi, middle))
		else:
			result.append(mi)
	return result


func _split_by_corner(mi: MeshInstance3D, middle: Vector3) -> Array[MeshInstance3D]:
	return _split_mesh(mi, func(p: Vector3) -> int: return _corner_of(p, middle))


## Ein Mesh in bis zu vier Meshes aufteilen: classify(Mitte eines Dreiecks, relativ zum Auto)
## sagt, in welches Teil (0 bis 3) das Dreieck kommt. Die neuen Meshes stehen an derselben
## Stelle wie das alte.
func _split_mesh(mi: MeshInstance3D, classify: Callable) -> Array[MeshInstance3D]:
	var to_root := _to_root(mi)
	var pieces: Array[ArrayMesh] = [ArrayMesh.new(), ArrayMesh.new(), ArrayMesh.new(), ArrayMesh.new()]
	for s in mi.mesh.get_surface_count():
		var arrays := mi.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			indices.resize(verts.size())
			for i in verts.size():
				indices[i] = i
		# Packed-Arrays sind Werte: vier einzelne Listen statt einer Liste von Listen
		var c0 := PackedInt32Array()
		var c1 := PackedInt32Array()
		var c2 := PackedInt32Array()
		var c3 := PackedInt32Array()
		for t in range(0, indices.size() - 2, 3):
			var a := indices[t]
			var b := indices[t + 1]
			var c := indices[t + 2]
			var center := to_root * ((verts[a] + verts[b] + verts[c]) / 3.0)
			match classify.call(center):
				0: c0.append_array([a, b, c])
				1: c1.append_array([a, b, c])
				2: c2.append_array([a, b, c])
				3: c3.append_array([a, b, c])
		var per_corner: Array[PackedInt32Array] = [c0, c1, c2, c3]
		for corner in 4:
			if per_corner[corner].is_empty():
				continue
			var part := _compact(arrays, per_corner[corner])
			pieces[corner].add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, part)
			pieces[corner].surface_set_material(pieces[corner].get_surface_count() - 1, mi.mesh.surface_get_material(s))
	var result: Array[MeshInstance3D] = []
	for corner in 4:
		if pieces[corner].get_surface_count() == 0:
			continue
		var piece := MeshInstance3D.new()
		piece.name = "%s_Teil%d" % [mi.name, corner]
		piece.mesh = pieces[corner]
		mi.get_parent().add_child(piece)
		piece.transform = mi.transform
		result.append(piece)
	mi.queue_free()
	return result


## Nur die Punkte behalten, die die Dreiecke in indices wirklich benutzen (sonst wäre jedes
## Teilstück so groß wie das ganze Mesh)
func _compact(arrays: Array, indices: PackedInt32Array) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var new_index := PackedInt32Array()
	new_index.resize(verts.size())
	new_index.fill(-1)
	var used := PackedInt32Array()
	var remapped := PackedInt32Array()
	remapped.resize(indices.size())
	for i in indices.size():
		var old := indices[i]
		if new_index[old] == -1:
			new_index[old] = used.size()
			used.append(old)
		remapped[i] = new_index[old]
	var result := []
	result.resize(Mesh.ARRAY_MAX)
	result[Mesh.ARRAY_INDEX] = remapped
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var uv2s: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2] if arrays[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
	var new_verts := PackedVector3Array()
	var new_normals := PackedVector3Array()
	var new_tangents := PackedFloat32Array()
	var new_colors := PackedColorArray()
	var new_uvs := PackedVector2Array()
	var new_uv2s := PackedVector2Array()
	for old in used:
		new_verts.append(verts[old])
		if not normals.is_empty():
			new_normals.append(normals[old])
		if not tangents.is_empty():
			new_tangents.append_array([tangents[old * 4], tangents[old * 4 + 1], tangents[old * 4 + 2], tangents[old * 4 + 3]])
		if not colors.is_empty():
			new_colors.append(colors[old])
		if not uvs.is_empty():
			new_uvs.append(uvs[old])
		if not uv2s.is_empty():
			new_uv2s.append(uv2s[old])
	result[Mesh.ARRAY_VERTEX] = new_verts
	if not new_normals.is_empty():
		result[Mesh.ARRAY_NORMAL] = new_normals
	if not new_tangents.is_empty():
		result[Mesh.ARRAY_TANGENT] = new_tangents
	if not new_colors.is_empty():
		result[Mesh.ARRAY_COLOR] = new_colors
	if not new_uvs.is_empty():
		result[Mesh.ARRAY_TEX_UV] = new_uvs
	if not new_uv2s.is_empty():
		result[Mesh.ARRAY_TEX_UV2] = new_uv2s
	return result


## Eingeschlagene Räder gerade stellen: Die Achse eines Rads ist die Richtung, in der es am
## dünnsten ist. Ihren Winkel misst man an den Punkten des Meshes und dreht ihn zurück.
func _straighten(wheel_parts: Array, parts: Array, center: Vector3) -> void:
	# Kovarianz der Punkte in der x-z-Ebene: die Richtung mit der kleinsten Streuung ist die Achse
	var sxx := 0.0
	var szz := 0.0
	var sxz := 0.0
	var count := 0
	for mi: MeshInstance3D in wheel_parts:
		var to_root := _to_root(mi)
		for s in mi.mesh.get_surface_count():
			var verts: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for i in range(0, verts.size(), 5):
				var p := to_root * verts[i] - center
				sxx += p.x * p.x
				szz += p.z * p.z
				sxz += p.x * p.z
				count += 1
	if count == 0:
		return
	# Hauptachsen-Winkel der Punktwolke (Winkel der größten Streuung = Rollrichtung)
	var roll_angle := 0.5 * atan2(2.0 * sxz, sxx - szz)
	# Die Rollrichtung sollte entlang z liegen (Winkel 90°); die Abweichung ist der Lenkwinkel
	var steer := wrapf(roll_angle - PI * 0.5, -PI * 0.5, PI * 0.5)
	if absf(steer) < deg_to_rad(1.5):
		return
	var turn := Transform3D(Basis.IDENTITY, center) * Transform3D(Basis(Vector3.UP, steer), Vector3.ZERO) \
		* Transform3D(Basis.IDENTITY, -center)
	for mi: MeshInstance3D in parts:
		mi.global_transform = _root.global_transform * turn * _to_root(mi)


## Maße des eingepassten Modells merken (siehe measured)
func _measure(corner_centers: Array[Vector3], corner_parts: Array) -> void:
	var s := _pivot.transform.basis.get_scale().x
	var radius := 0.0
	for mi: MeshInstance3D in corner_parts[2]:
		radius = maxf(radius, (_to_root(mi) * mi.get_aabb()).size.y * 0.5)
	measured = {"scale": s,
		"wheelbase": ((corner_centers[0].z + corner_centers[1].z) - (corner_centers[2].z + corner_centers[3].z)) * 0.5 * s,
		"track_front": (corner_centers[0].x - corner_centers[1].x) * s,
		"track_rear": (corner_centers[2].x - corner_centers[3].x) * s,
		"wheel_radius": radius,
		"length": (_box_of(_meshes_under(_model)).size.z)}


## Modell so skalieren und verschieben, dass seine Radmitten auf den Physik-Rädern sitzen
func _fit(corner_centers: Array[Vector3]) -> void:
	var front := (corner_centers[0] + corner_centers[1]) * 0.5
	var rear := (corner_centers[2] + corner_centers[3]) * 0.5
	var physics_front := (Car.resting_wheel_center(_profile, 0) + Car.resting_wheel_center(_profile, 1)) * 0.5
	var physics_rear := (Car.resting_wheel_center(_profile, 2) + Car.resting_wheel_center(_profile, 3)) * 0.5
	var scale_factor := (physics_front.z - physics_rear.z) / (front.z - rear.z)
	var model_middle := (front + rear) * 0.5
	var physics_middle := (physics_front + physics_rear) * 0.5
	_pivot.transform = Transform3D(_pivot.transform.basis.scaled(Vector3.ONE * scale_factor),
		physics_middle - model_middle * scale_factor)


## part an new_parent hängen, ohne dass es sich bewegt (new_parent steht später bei center)
func _attach(part: Node3D, new_parent: Node3D, center: Vector3) -> void:
	var in_root := _to_root(part)
	part.get_parent().remove_child(part)
	new_parent.add_child(part)
	part.transform = Transform3D(Basis.IDENTITY, center).affine_inverse() * in_root
	# Hängt jetzt außerhalb des Modells: beim Autowechsel extra freigeben
	_extra_nodes.append(part)


## Unbewegliche Teile pro Material zu einem Mesh zusammenfassen
func _merge_static(meshes: Array[MeshInstance3D]) -> Array[MeshInstance3D]:
	var by_material := {}  # Material -> SurfaceTool
	var keep: Array[MeshInstance3D] = []
	var to_model := _model.global_transform.affine_inverse()
	for mi in meshes:
		# Aufkleber bleiben einzeln (Taste K)
		if _matches(mi, _profile.sticker_parts):
			keep.append(mi)
			continue
		var relative := to_model * mi.global_transform
		for s in mi.mesh.get_surface_count():
			var material := mi.mesh.surface_get_material(s)
			if not by_material.has(material):
				var tool := SurfaceTool.new()
				tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				by_material[material] = tool
			(by_material[material] as SurfaceTool).append_from(mi.mesh, s, relative)
		mi.queue_free()
	for material: Material in by_material:
		var tool: SurfaceTool = by_material[material]
		var mesh := tool.commit()
		mesh.surface_set_material(0, material)
		var merged := MeshInstance3D.new()
		merged.name = "Merged_" + (material.resource_name if material else "ohne")
		merged.mesh = mesh
		_model.add_child(merged)
		keep.append(merged)
	return keep


## Alle Meshes, die an einem Rad (oder Bremssattel-Halter) hängen, pro Material zu einem
## Mesh zusammenfassen
func _merge_attached(holder: Node3D) -> Array[MeshInstance3D]:
	var by_material := {}
	for child in holder.get_children():
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null or mi.is_queued_for_deletion():
			continue
		for s in mi.mesh.get_surface_count():
			var material := mi.mesh.surface_get_material(s)
			if not by_material.has(material):
				var tool := SurfaceTool.new()
				tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				by_material[material] = tool
			(by_material[material] as SurfaceTool).append_from(mi.mesh, s, mi.transform)
		mi.queue_free()
	var result: Array[MeshInstance3D] = []
	for material: Material in by_material:
		var mesh := (by_material[material] as SurfaceTool).commit()
		mesh.surface_set_material(0, material)
		var merged := MeshInstance3D.new()
		merged.mesh = mesh
		holder.add_child(merged)
		_extra_nodes.append(merged)
		result.append(merged)
	return result


## Eigene Materialien für Lack, Glas, Felgen, Reifen und Lichter
func _make_materials() -> void:
	_paint = StandardMaterial3D.new()
	_paint.albedo_color = _profile.paint_colors[paint_index] if not _profile.paint_colors.is_empty() else Color.GRAY
	_paint.metallic = _profile.paint_metallic
	_paint.roughness = _profile.paint_roughness
	_paint.clearcoat_enabled = true
	_paint.clearcoat = clearcoat
	_paint.clearcoat_roughness = clearcoat_roughness
	_head_glow = StandardMaterial3D.new()
	_head_glow.albedo_color = Color(0.9, 0.92, 0.95)
	_head_glow.emission_enabled = true
	_head_glow.emission = Color(1.0, 0.96, 0.88)
	_tail_glow = StandardMaterial3D.new()
	_tail_glow.albedo_color = Color(0.5, 0.02, 0.02)
	_tail_glow.emission_enabled = true
	_tail_glow.emission = Color(1.0, 0.05, 0.03)


var _glass: StandardMaterial3D
var _rim: StandardMaterial3D
var _tire: StandardMaterial3D
var _exhaust: StandardMaterial3D


## front: liegt das Teil in der vorderen Hälfte des Autos? (Scheinwerfer leuchten nur vorne,
## Rücklichter nur hinten)
func _replacement_for(material: Material, front: bool) -> Material:
	if material == null:
		return null
	var material_name := material.resource_name
	if _any_match(material_name, _profile.paint_materials):
		return _paint
	if _any_match(material_name, _profile.headlight_materials):
		return _head_glow if front else null
	if _any_match(material_name, _profile.taillight_materials):
		return _tail_glow if not front else null
	if _any_match(material_name, _profile.glass_materials):
		if _glass == null:
			_glass = StandardMaterial3D.new()
			_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_glass.albedo_color = Color(0.03, 0.04, 0.05, _profile.glass_opacity)
			_glass.metallic = 0.2
			_glass.roughness = 0.03
		return _glass
	if _any_match(material_name, _profile.rim_materials):
		if _rim == null:
			_rim = StandardMaterial3D.new()
			_rim.albedo_color = Color(0.06, 0.06, 0.065)
			_rim.metallic = 0.85
			_rim.roughness = 0.3
		return _rim
	if _any_match(material_name, _profile.tire_materials):
		if _tire == null:
			_tire = StandardMaterial3D.new()
			_tire.albedo_color = Color(0.03, 0.03, 0.03)
			_tire.roughness = 0.95
		return _tire
	if _any_match(material_name, _profile.exhaust_materials):
		if _exhaust == null:
			_exhaust = StandardMaterial3D.new()
			_exhaust.albedo_color = Color(0.32, 0.3, 0.28)
			_exhaust.metallic = 1.0
			_exhaust.roughness = 0.25
		return _exhaust
	return null


func _any_match(text: String, patterns: PackedStringArray) -> bool:
	for pattern in patterns:
		if text.matchn(pattern):
			return true
	return false


## Materialien ersetzen, Schatten und Detailstufe einstellen, Aufkleber merken
func _setup_mesh(mi: MeshInstance3D) -> void:
	if not is_instance_valid(mi) or mi.is_queued_for_deletion():
		return
	var box := _to_root(mi) * mi.get_aabb()
	# Lichter-Meshes, die vorne und hinten zugleich liegen, in zwei Hälften teilen
	if box.position.z < -0.5 and box.end.z > 0.5 and _has_light(mi):
		for piece in _split_mesh(mi, func(p: Vector3) -> int: return 0 if p.z > 0.0 else 1):
			_setup_mesh(piece)
		return
	var front := box.get_center().z > 0.0
	for s in mi.mesh.get_surface_count():
		var replacement := _replacement_for(mi.mesh.surface_get_material(s), front)
		if replacement:
			mi.set_surface_override_material(s, replacement)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _matches(mi, _profile.shadow_parts) \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _matches(mi, _profile.low_detail_parts):
		mi.lod_bias = low_detail_lod_bias
	if _matches(mi, _profile.sticker_parts):
		_stickers.append(mi)


func _has_light(mi: MeshInstance3D) -> bool:
	for s in mi.mesh.get_surface_count():
		var material := mi.mesh.surface_get_material(s)
		if material and (_any_match(material.resource_name, _profile.headlight_materials)
				or _any_match(material.resource_name, _profile.taillight_materials)):
			return true
	return false


func _set_stickers(on: bool) -> void:
	for sticker in _stickers:
		sticker.visible = on


## Zwei Scheinwerfer vorne am Auto. Nur einer wirft Schatten (spart Rechenzeit).
func _setup_headlights() -> void:
	var lamps: Array[MeshInstance3D] = []
	for mi in _meshes_under(_pivot):
		for s in mi.mesh.get_surface_count():
			if mi.get_surface_override_material(s) == _head_glow:
				lamps.append(mi)
	var box := _box_of(lamps) if not lamps.is_empty() else AABB(Vector3(-0.7, 0.6, 2.1), Vector3(1.4, 0.1, 0.1))
	var spacing := box.size.x * 0.5 * 0.75
	for side: float in [1.0, -1.0]:
		var spot := SpotLight3D.new()
		spot.light_color = Color(1.0, 0.95, 0.86)
		spot.light_energy = headlight_energy
		spot.spot_range = headlight_range
		spot.spot_angle = headlight_angle
		spot.spot_attenuation = 0.6
		spot.shadow_enabled = side > 0.0
		# SpotLight3D leuchtet entlang -Z: umdrehen, damit es nach vorne (+Z) zeigt, etwas
		# nach unten neigen und vor das Auto setzen (nicht ins eigene Gehäuse)
		spot.transform = Transform3D(Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, deg_to_rad(-3.0)),
			Vector3(side * spacing, box.get_center().y, box.end.z + 0.25))
		spot.visible = false
		_root.add_child(spot)
		_spots.append(spot)
		_extra_nodes.append(spot)
