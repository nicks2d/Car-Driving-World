extends Node3D
## Das sichtbare Auto. Lädt das BMW-Modell (falls es in assets/models/bmw_m2/ liegt) und
## baut es ins Auto ein: passend skaliert, Räder drehen und lenken mit, eigene Materialien
## (Lack, Glas, Felgen, Lichter), Scheinwerfer. Ohne Modell bleibt die Platzhalter-Box.
##
## Tasten: C = Lackfarbe wechseln, K = Aufkleber an/aus, L = Licht an/aus.

## Pfad zum Modell (siehe assets/models/README.md)
@export var model_path: String = "res://assets/models/bmw_m2/scene.gltf"

@export_group("Lack")
## Farben, durch die Taste C schaltet (die erste ist die Startfarbe)
@export var paint_colors: Array[Color] = [
	Color(0.02, 0.24, 0.66),  # Long Beach Blue
	Color(0.88, 0.89, 0.88),  # Alpine White
	Color(0.015, 0.015, 0.02),  # Black Sapphire
	Color(0.62, 0.64, 0.65),  # Hockenheim Silver
	Color(0.85, 0.3, 0.04),  # Sunset Orange
	Color(0.48, 0.02, 0.04),  # Melbourne Red
]
## Metallic-Anteil und Rauheit der Lackschicht unter dem Klarlack
@export_range(0.0, 1.0) var paint_metallic: float = 0.6
@export_range(0.0, 1.0) var paint_roughness: float = 0.38
## Klarlack: Stärke und Rauheit (klein = spiegelt klar)
@export_range(0.0, 1.0) var clearcoat: float = 1.0
@export_range(0.0, 1.0) var clearcoat_roughness: float = 0.06
## Aufkleber (Greddy, Bosch, ...) beim Start sichtbar?
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

## Welche Teile des Modells wie behandelt werden (Namen aus der glTF-Datei)
const WHEEL_PREFIX := "wms13p"
const CALIPER_PREFIX := "polySurface"
const HIDDEN_PREFIXES: Array[String] = ["b_Engine_Geo"]
const STICKER_NAMES: Array[String] = ["bmw-m-power-logo", "Bosch-logo_svg", "greddy", "show"]
const STICKER_PREFIX := "stickers_white"
## Diese Teile werfen Schatten (die großen Karosserieteile und Reifen). Alles andere nicht:
## Innenraum, Felgen, Lichter usw. spart so viel Rechenzeit.
const SHADOW_MATERIALS: Array[String] = ["coloured", "painted_carbon", "carbon1", "tire__spec"]
## Diese Teile sieht man nur klein oder durch die Scheiben: Sie wechseln früher auf ihre
## vereinfachten Versionen (LOD). Wert < 1 = früher vereinfachen.
const LOD_BIAS := {"bBMW_M2Competition_2018InteriorA_Material1": 0.25, "coloured_exhaust": 0.25,
	"tire__spec": 0.5, "Matte__FF114182__sec_env_8_spec": 0.5, "Matte__FFBFBFBF__env_9_spec": 0.5,
	"Matte__FFBFBF00__env_7_spec": 0.5}

var _car: VehicleBody3D
var _model: Node3D
var _paint: StandardMaterial3D
var _paint_index: int = 0
var _stickers: Array[Node3D] = []
var _head_glow: StandardMaterial3D
var _tail_glow: StandardMaterial3D
var _spots: Array[SpotLight3D] = []
var _lights_on: bool = false
var _was_night: bool = false
var _day_night: DayNight
## Bremssättel: lenken mit, drehen sich aber nicht mit dem Rad. [Halter, Rad]
var _calipers: Array = []


func _ready() -> void:
	_car = get_parent() as VehicleBody3D
	# Erst im nächsten Moment einbauen: Während _ready() richtet das Auto noch seine
	# Kind-Nodes ein und nimmt keine neuen an
	_build.call_deferred()


func _build() -> void:
	_day_night = get_tree().get_first_node_in_group("day_night") as DayNight
	if not ResourceLoader.exists(model_path):
		print("BMW-Modell nicht gefunden, fahre mit Platzhalter (siehe assets/models/README.md)")
		return
	var scene := load(model_path) as PackedScene
	if scene == null:
		return
	_model = scene.instantiate() as Node3D
	add_child(_model)
	_fit_to_wheels()
	_setup_parts(_model)
	_setup_headlights()
	_set_stickers(stickers_visible)
	# Platzhalter ausblenden
	for path in ["BodyMesh", "CabinMesh", "HeadlightLeft", "HeadlightRight"]:
		(_car.get_node(path) as Node3D).visible = false
	for wheel in _wheels():
		for child in ["Tire", "Spoke"]:
			(wheel.get_node(child) as Node3D).visible = false


func _physics_process(_delta: float) -> void:
	# Bremssättel folgen Federung und Lenkung, drehen sich aber nicht mit
	for pair: Array in _calipers:
		var holder: Node3D = pair[0]
		var wheel: VehicleWheel3D = pair[1]
		holder.transform = Transform3D(Basis(Vector3.UP, wheel.steering), wheel.transform.origin)


func _process(_delta: float) -> void:
	if _model == null:
		return
	if Input.is_action_just_pressed("cycle_paint"):
		_paint_index = (_paint_index + 1) % paint_colors.size()
		_paint.albedo_color = paint_colors[_paint_index]
	if Input.is_action_just_pressed("toggle_stickers"):
		_set_stickers(not _stickers[0].visible)
	# Licht: schaltet sich bei Dämmerung an und morgens aus, L schaltet von Hand
	var night := _is_night()
	if night != _was_night:
		_was_night = night
		_lights_on = night
	if Input.is_action_just_pressed("toggle_lights"):
		_lights_on = not _lights_on
	for spot in _spots:
		spot.visible = _lights_on
	_head_glow.emission_energy_multiplier = headlight_glow if _lights_on else 0.15
	var braking: bool = _car.get("braking")
	_tail_glow.emission_energy_multiplier = brake_glow if braking else (taillight_glow if _lights_on else 0.1)


func _is_night() -> bool:
	if _day_night == null:
		return false
	return _day_night.sun_direction().y < sin(deg_to_rad(lights_on_below_sun_degrees))


func _wheels() -> Array[VehicleWheel3D]:
	var result: Array[VehicleWheel3D] = []
	for child in _car.get_children():
		if child is VehicleWheel3D:
			result.append(child)
	return result


## Wo die Radmitte steht, wenn das Auto ruhig auf der Straße steht (relativ zum Auto).
## Die Federung ist dann etwas eingedrückt: um Gewicht / Federhärte (Godot rechnet die
## Federkraft mal Masse, deshalb hängt das nicht vom Gewicht ab).
func _resting_center(wheel: VehicleWheel3D) -> Vector3:
	var sag := 9.81 / (4.0 * wheel.suspension_stiffness)
	return wheel.position - Vector3(0.0, wheel.wheel_rest_length - sag, 0.0)


## Mittelpunkt aller Meshes unter node, relativ zum Auto
func _center_in_car(node: Node) -> Vector3:
	var box := AABB()
	var first := true
	var to_car := _car.global_transform.affine_inverse()
	for mi in _meshes_under(node):
		var part := (to_car * mi.global_transform) * mi.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box.get_center()


func _meshes_under(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is MeshInstance3D:
			result.append(current)
		stack.append_array(current.get_children())
	return result


## Modell so skalieren und verschieben, dass seine Räder genau auf den Physik-Rädern sitzen
func _fit_to_wheels() -> void:
	var groups: Array[Node3D] = []
	for child in _model.find_children(WHEEL_PREFIX + "*", "Node3D", true, false):
		groups.append(child)
	var model_centers: Array[Vector3] = []
	for group in groups:
		model_centers.append(_center_in_car(group))
	# Radstand im Modell und in der Physik: daraus die Skalierung
	var front := _average_where(model_centers, true)
	var rear := _average_where(model_centers, false)
	var wheels := _wheels()
	var physics_centers: Array[Vector3] = []
	for wheel in wheels:
		physics_centers.append(_resting_center(wheel))
	var physics_front := _average_where(physics_centers, true)
	var physics_rear := _average_where(physics_centers, false)
	var scale_factor := (physics_front.z - physics_rear.z) / (front.z - rear.z)
	var model_middle := (front + rear) * 0.5
	var physics_middle := (physics_front + physics_rear) * 0.5
	_model.transform = Transform3D(Basis.from_scale(Vector3.ONE * scale_factor),
		physics_middle - model_middle * scale_factor)
	# Jede Radgruppe an das passende Physik-Rad hängen (gleiche Seite, gleiche Achse).
	# Das Physik-Rad dreht und lenkt sich um seine Mitte, die Gruppe dreht sich mit.
	for group in groups:
		var center := _center_in_car(group)
		var wheel := _nearest_wheel(center)
		_attach(group, wheel, _resting_center(wheel))
	# Bremssättel: eigener Halter pro Rad, der nur lenkt und federt
	for caliper in _model.find_children(CALIPER_PREFIX + "*", "Node3D", true, false):
		var wheel := _nearest_wheel(_center_in_car(caliper))
		var holder := Node3D.new()
		holder.name = "Caliper" + wheel.name
		_car.add_child(holder)
		holder.position = _resting_center(wheel)
		_attach(caliper, holder, _resting_center(wheel))
		_calipers.append([holder, wheel])


## part an new_parent hängen, ohne dass es sich bewegt (new_parent steht später bei center)
func _attach(part: Node3D, new_parent: Node3D, center: Vector3) -> void:
	var in_car := _car.global_transform.affine_inverse() * part.global_transform
	part.get_parent().remove_child(part)
	new_parent.add_child(part)
	part.transform = Transform3D(Basis.IDENTITY, center).affine_inverse() * in_car


func _nearest_wheel(point: Vector3) -> VehicleWheel3D:
	var best: VehicleWheel3D = null
	for wheel in _wheels():
		if best == null or _resting_center(wheel).distance_to(point) < _resting_center(best).distance_to(point):
			best = wheel
	return best


## Mittelwert der Punkte vorne (z > 0) oder hinten
func _average_where(points: Array[Vector3], front: bool) -> Vector3:
	var total := Vector3.ZERO
	var count := 0
	for p in points:
		if (p.z > 0.0) == front:
			total += p
			count += 1
	return total / maxi(count, 1)


## Materialien ersetzen, Schatten einstellen, Unsichtbares ausblenden, Aufkleber merken
func _setup_parts(root: Node) -> void:
	_paint = StandardMaterial3D.new()
	_paint.albedo_color = paint_colors[0]
	_paint.metallic = paint_metallic
	_paint.roughness = paint_roughness
	_paint.clearcoat_enabled = true
	_paint.clearcoat = clearcoat
	_paint.clearcoat_roughness = clearcoat_roughness
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.03, 0.04, 0.05, 0.55)
	glass.metallic = 0.2
	glass.roughness = 0.03
	var rim := StandardMaterial3D.new()
	rim.albedo_color = Color(0.06, 0.06, 0.065)
	rim.metallic = 0.85
	rim.roughness = 0.3
	var tire := StandardMaterial3D.new()
	tire.albedo_color = Color(0.03, 0.03, 0.03)
	tire.roughness = 0.95
	var exhaust := StandardMaterial3D.new()
	exhaust.albedo_color = Color(0.32, 0.3, 0.28)
	exhaust.metallic = 1.0
	exhaust.roughness = 0.25
	_head_glow = StandardMaterial3D.new()
	_head_glow.albedo_color = Color(0.9, 0.92, 0.95)
	_head_glow.emission_enabled = true
	_head_glow.emission = Color(1.0, 0.96, 0.88)
	_tail_glow = StandardMaterial3D.new()
	_tail_glow.albedo_color = Color(0.5, 0.02, 0.02)
	_tail_glow.emission_enabled = true
	_tail_glow.emission = Color(1.0, 0.05, 0.03)
	var replacements := {
		# Die Karosserie des Widebody-Modells ist aus Carbon („painted_carbon“), nur ein paar
		# Leisten sind farbig („coloured“). Beides bekommt den Lack, Anbauteile bleiben Carbon.
		"coloured": _paint, "window_coloured": _paint, "painted_carbon": _paint,
		"windscreen": glass, "coloured_exhaust": exhaust, "tire__spec": tire,
		"Matte__FF114182__sec_env_8_spec": rim, "Matte__FFBFBFBF__env_9_spec": rim,
		"Matte__FFBFBF00__env_7_spec": rim,
		"whitelights": _head_glow, "redlights": _tail_glow,
	}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if _starts_with_any(node.name, HIDDEN_PREFIXES):
			(node as Node3D).visible = false
			continue
		if String(node.name) in STICKER_NAMES or String(node.name).begins_with(STICKER_PREFIX):
			_stickers.append(node as Node3D)
		if not node is MeshInstance3D:
			continue
		var mi := node as MeshInstance3D
		var casts := false
		for s in mi.mesh.get_surface_count():
			var original := mi.mesh.surface_get_material(s)
			var material_name := original.resource_name if original else ""
			if replacements.has(material_name):
				mi.set_surface_override_material(s, replacements[material_name])
			if material_name in SHADOW_MATERIALS:
				casts = true
			if LOD_BIAS.has(material_name):
				mi.lod_bias = LOD_BIAS[material_name]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _starts_with_any(text: String, prefixes: Array[String]) -> bool:
	for prefix in prefixes:
		if text.begins_with(prefix):
			return true
	return false


func _set_stickers(on: bool) -> void:
	for sticker in _stickers:
		sticker.visible = on


## Zwei Scheinwerfer vorne am Auto. Nur einer wirft Schatten (spart Rechenzeit).
func _setup_headlights() -> void:
	var lamps := _model.find_children("*", "MeshInstance3D", true, false)
	var front := 2.0
	var height := 0.6
	for lamp: MeshInstance3D in lamps:
		if lamp.mesh.get_surface_count() > 0 and lamp.get_surface_override_material(0) == _head_glow:
			var center := _center_in_car(lamp)
			front = center.z
			height = center.y
	for side: float in [1.0, -1.0]:
		var spot := SpotLight3D.new()
		spot.light_color = Color(1.0, 0.95, 0.86)
		spot.light_energy = headlight_energy
		spot.spot_range = headlight_range
		spot.spot_angle = headlight_angle
		spot.spot_attenuation = 0.6
		spot.shadow_enabled = side > 0.0
		# SpotLight3D leuchtet entlang -Z: umdrehen, damit es nach vorne (+Z) zeigt,
		# und etwas nach unten neigen. Etwas vor das Auto setzen, damit der Scheinwerfer
		# nicht im eigenen Gehäuse steckt.
		spot.transform = Transform3D(Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, deg_to_rad(-3.0)),
			Vector3(side * 0.6, height, front + 0.25))
		spot.visible = false
		_car.add_child(spot)
		_spots.append(spot)
