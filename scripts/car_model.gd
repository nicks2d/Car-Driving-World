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
##  - Lenkrad an einen drehbaren Halter hängen (eigene Teile oder aus dem Innenraum geschnitten)
##  - Innenraum-Teile nur in der Cockpit-Sicht zeigen (set_cockpit_view)
##  - Leuchten (shaders/car_lamp.gdshader): Blinker leuchten im Scheinwerfer- und Rücklichtglas bzw. in
##    eigenen Blinkergläsern; nur wo das nicht geht, setzt CarSignals Kästchen (indicator_covered)
##  - Scheinwerfer mit Projektor-Bild: Abblendlicht mit scharfer Hell-Dunkel-Grenze, Fernlicht
##  - Begrüßungslicht in der Garage (play_welcome): Tagfahrlicht, Scheinwerfer, Rücklicht, Motorstart
##  - Wetter am Auto (Werte von CarWeather): Tropfen und Schnee als Zusatzdurchgang über dem Lack
##    (shaders/car_paint_fx.gdshader), Tropfen, Eis und Schnee im Glas; Kontaktschatten unter dem Auto
##  - Karosserie nickt und wankt mit der Beschleunigung (nur das Modell, die Physik bleibt gleich).
##    Kennzeichen, Scheinwerfer und Lenkrad hängen deshalb am Modell, die Räder an den Physik-Rädern.
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
@export var headlight_energy: float = 16.0
@export var headlight_range: float = 95.0
@export_range(5.0, 80.0) var headlight_angle: float = 32.0
## Leuchtstärke der Lampen selbst (Emission): Scheinwerfer, Rücklicht, Bremslicht
@export var headlight_glow: float = 6.0
@export var taillight_glow: float = 1.5
@export var brake_glow: float = 6.0
## Licht geht automatisch an, wenn die Sonne tiefer als so viele Grad steht
@export var lights_on_below_sun_degrees: float = 4.0
## Fernlicht (Lichthupe): so viel heller und weiter als das Abblendlicht
@export var high_beam_energy: float = 2.2
@export var high_beam_range: float = 1.8
## Begrüßungslicht: Sekunden bis Tagfahrlicht, Scheinwerfer, Rücklicht und Motorstart
@export var welcome_steps := Vector4(0.25, 0.9, 1.4, 1.9)
@export var welcome_volume_db: float = -6.0
## Diese Teile wechseln früher auf vereinfachte Versionen (LOD), Wert < 1 = früher
@export var low_detail_lod_bias: float = 0.35

@export_group("Karosserie in Bewegung")
## Wanken zur Kurvenaußenseite und Nicken (Bremsen: Nase runter) in Grad pro 1 g
@export var body_roll_per_g: float = 2.4
@export var body_pitch_per_g: float = 1.5
## Eigenfrequenz (Hz) und Dämpfung der Feder (1 = schwingt nicht nach)
@export var body_frequency: float = 1.5
@export var body_damping: float = 0.45
## Drehpunkt des Wankens und Nickens im Auto (Meter, etwa Höhe der Radnaben)
@export var body_pivot := Vector3(0.0, -0.1, 0.0)

## Platzhalter-Reifen und -Speiche an jedem Rad (car.tscn), solange kein Modell da ist
const PLACEHOLDER_WHEEL_PARTS: Array[String] = ["Tire", "Spoke"]
## Eigene Bild-Ebene (Ebene 11) für das Auto des Spielers: Die Kamera der Rückspiegel lässt sie aus
const OWN_CAR_LAYER: int = 1 << 10
## Scheiben: trocken und mit Regentropfen (gleiche Parameter)
const DRY_GLASS: Shader = preload("res://shaders/car_glass.gdshader")
const RAIN_GLASS: Shader = preload("res://shaders/car_glass_rain.gdshader")

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
var _head_glow: ShaderMaterial
var _tail_glow: ShaderMaterial
## Eigene Blinkergläser des Modells (leuchten ganz)
var _indicator_glass: ShaderMaterial
## Sind die Blinkerpunkte (vorne, hinten, Spiegel) durch Glas des Modells abgedeckt? Sonst Kästchen
## (CarSignals). Spiegel ohne eigenes Glas: kein Spiegelblinker.
var indicator_covered: Array[bool] = [false, false, false]
## Projektor-Bilder der Scheinwerfer (einmal berechnet)
static var _low_beam: ImageTexture
static var _high_beam: ImageTexture
## Wetter am Auto (CarWeather): nass, Schnee, Eis (0–1); Zusatzdurchgang über dem Lack; Kontaktschatten
var _fx := Vector3.ZERO
var _paint_fx: ShaderMaterial
var _contact_shadow: Decal
## Begrüßungslicht: Sekunden seit dem Start (negativ = aus), Spieler für den Motorstart
var _welcome_time: float = -1.0
var _welcome_sound: AudioStreamPlayer
var _spots: Array[SpotLight3D] = []
## Unsichtbares Material für die Original-Kennzeichen des Modells
var _hidden_material: StandardMaterial3D
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
var _plates: Array[MeshInstance3D] = []
## Lenkrad: Halter an der Lenksäule und Richtung der Säule (zeigt zum Fahrer)
var _steering: Node3D
var _steering_axis := Vector3.BACK
## Innenraum-Teile (nur in der Cockpit-Sicht sichtbar) und Teile mit niedriger Detailstufe
var _interior: Array[MeshInstance3D] = []
var _low_detail: Array[MeshInstance3D] = []
var _cockpit_view: bool = false
## Was beim Einbauen passiert ist (für tools/cockpit_measure.gd): Lenkrad-Teile, geschnittene Meshes, Zeit
var build_report: Dictionary = {}
## Karosserie: Wanken (x) und Nicken (y) in Grad, Tempo der Feder, gemessene Beschleunigung
var _body_angles := Vector2.ZERO
var _body_speed := Vector2.ZERO
var _body_accel := Vector3.ZERO
var _last_velocity := Vector3.ZERO


## Pfad zum Modell eines Profils: scene.gltf (ältere Downloads) oder die .glb im Ordner
## (neuere Sketchfab-Downloads). Leer, wenn der Ordner fehlt.
static func model_path(profile: CarProfile) -> String:
	var folder := "res://assets/models/%s" % profile.model_folder
	if ResourceLoader.exists(folder + "/scene.gltf"):
		return folder + "/scene.gltf"
	# ResourceLoader.list_directory statt DirAccess: in der exportierten App liegen im Ordner nur
	# noch die umgewandelten Dateien, die Liste nennt trotzdem die ursprünglichen Namen
	for file in ResourceLoader.list_directory(folder):
		if file.get_extension().to_lower() == "glb":
			return folder.path_join(file)
	return ""


## Liegt das Modell dieses Autos im Projekt?
static func is_available(profile: CarProfile) -> bool:
	var path := model_path(profile)
	return path != "" and ResourceLoader.exists(path)


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
	# Lenkrad: dreht sich um die Lenksäule, Übersetzung aus dem Profil (links = gegen den Uhrzeigersinn)
	if _steering and _car:
		_steering.transform = Transform3D(Basis(_steering_axis, _car.steering * _profile.steering_ratio),
			_profile.steering_wheel_center)
	_update_body_motion(_delta)


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
	# Fenster: Lage der Scheiben im Auto und wie weit sie offen sind
	if _glass and _car:
		_glass.set_shader_parameter("car_inverse", Projection(_car.global_transform.affine_inverse()))
		_glass.set_shader_parameter("window_open", _car.windows_open)
		_glass.set_shader_parameter("car_speed", _car.linear_velocity.length())
		# Tropfen nur, solange das Auto nass ist (die Variante mit Tropfen greift das ganze Bild ab)
		var wanted := RAIN_GLASS if _fx.x > 0.01 else DRY_GLASS
		if _glass.shader != wanted:
			_glass.shader = wanted
		_glass.set_shader_parameter("wet", _fx.x)
		_glass.set_shader_parameter("snow", _fx.y)
		_glass.set_shader_parameter("frost", _fx.z)
	# Tropfen und Schnee auf dem Lack: Zusatzdurchgang nur, solange es etwas zu zeigen gibt (kostet sonst)
	if _paint and _paint_fx:
		var show_fx := _fx.x > 0.01 or _fx.y > 0.01
		_paint.next_pass = _paint_fx if show_fx else null
		if show_fx:
			_paint_fx.set_shader_parameter("car_inverse", Projection(_car.global_transform.affine_inverse()))
			_paint_fx.set_shader_parameter("car_basis", _car.global_basis)
			_paint_fx.set_shader_parameter("car_speed", _car.linear_velocity.length())
			_paint_fx.set_shader_parameter("wet", _fx.x)
			_paint_fx.set_shader_parameter("snow", _fx.y)
		if _glass_box.size != Vector3.ZERO:
			_glass.set_shader_parameter("top_y", _glass_box.end.y)
			_glass.set_shader_parameter("belt_y", _glass_box.position.y + _glass_box.size.y * 0.35)
	# Lichthupe: Fernlicht kurz an (heller, weiter, eigenes Projektor-Bild), auch tagsüber gut zu sehen
	var flash := _car.flash_time > 0.0
	var head := _lights_on
	var tail := _lights_on
	var drl := true
	if _welcome_time >= 0.0:
		# Begrüßungslicht: nacheinander Tagfahrlicht, Scheinwerfer, Rücklicht, dann der Motor
		var before := _welcome_time
		_welcome_time += _delta
		drl = _welcome_time >= welcome_steps.x
		head = _welcome_time >= welcome_steps.y
		tail = _welcome_time >= welcome_steps.z
		if before < welcome_steps.w and _welcome_time >= welcome_steps.w:
			_play_engine_start()
	for spot in _spots:
		spot.visible = head or flash
		spot.light_energy = headlight_energy * (high_beam_energy if flash else 1.0)
		spot.spot_range = headlight_range * (high_beam_range if flash else 1.0)
		spot.light_projector = _high_beam if flash else _low_beam
		# Fernlicht leuchtet waagerecht (Abblendlicht 2° nach unten, die Grenze steckt im Bild)
		spot.basis = Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, deg_to_rad(0.5 if flash else -2.0))
	var head_glow := headlight_glow * 3.0 if flash else (headlight_glow if head else (0.6 if drl else 0.05))
	_head_glow.set_shader_parameter("glow", head_glow)
	_tail_glow.set_shader_parameter("glow", brake_glow if _car.braking else (taillight_glow if tail else 0.1))
	# Blinker im Glas
	var to_car := Projection(global_transform.affine_inverse())
	var left := 1.0 if _car.signal_lit and (_car.hazard or _car.turn_signal == 1) else 0.0
	var right := 1.0 if _car.signal_lit and (_car.hazard or _car.turn_signal == -1) else 0.0
	for material in [_head_glow, _tail_glow, _indicator_glass]:
		material.set_shader_parameter("car_inverse", to_car)
		material.set_shader_parameter("left_lit", left)
		material.set_shader_parameter("right_lit", right)


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
			push_warning("Automodell konnte nicht geladen werden (Status %d): %s" % [status, path])
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


## Die vier Radknoten (in der Vorschau: zum Drehen auf dem Prüfstand)
func wheel_anchors() -> Array[Node3D]:
	return _anchors


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
	_interior.clear()
	_low_detail.clear()
	_steering = null


func _set_placeholder(on: bool) -> void:
	if _car == null:
		return
	for path in ["BodyMesh", "CabinMesh", "HeadlightLeft", "HeadlightRight"]:
		(_car.get_node(path) as Node3D).visible = on
	for wheel in _wheels():
		for child in PLACEHOLDER_WHEEL_PARTS:
			(wheel.get_node(child) as Node3D).visible = on


# ---------------------------------------------------------------------------
# Einbauen
# ---------------------------------------------------------------------------

func _build(scene: PackedScene) -> void:
	build_report = {}
	# Messen und Einpassen im ruhenden Auto
	transform = Transform3D.IDENTITY
	_body_angles = Vector2.ZERO
	_body_speed = Vector2.ZERO
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
	var started := Time.get_ticks_usec()
	var steering_parts := _build_steering_wheel(body)
	build_report["steering_ms"] = (Time.get_ticks_usec() - started) / 1000.0
	build_report["steering_parts"] = steering_parts.size()
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
	for mi in body + wheels + calipers + steering_parts:
		_setup_mesh(mi)
	_setup_headlights()
	_measure_indicators()
	_set_stickers(stickers_visible)
	_set_placeholder(false)
	_place_plates(body)
	_add_contact_shadow()
	set_cockpit_view(_cockpit_view)


## Kennzeichen vorne und hinten: Text aus der Garage (pro Auto gespeichert). Lage, Größe und Neigung
## stehen im Profil (gemessen mit tools/plate_measure.gd, per Foto geprüft). Fehlt die Lage dort,
## wird sie hier gemessen: an den eigenen Kennzeichen-Teilen des Modells (Profil plate_hide), sonst
## an der Stoßstange (vorderster bzw. hinterster Punkt in der Mitte auf 0,40 m bzw. 0,55 m Höhe).
## Die Original-Kennzeichen sind immer unsichtbar (nie doppelt). „Kein Kennzeichen“ (Garage)
## blendet auch unser Schild aus.
func _place_plates(body: Array) -> void:
	if _car == null:
		return
	measured_plates = _measure_plates(body)
	var text := plate_text(_profile.id)
	_plates.clear()
	for side in 2:
		var spot: Variant = measured_plates[side]
		var stored := _profile.plate_front_position if side == 0 else _profile.plate_rear_position
		if stored != Vector3.ZERO:
			spot = {"center": stored, "size": _profile.plate_front_size if side == 0 else _profile.plate_rear_size,
				"tilt": _profile.plate_front_tilt if side == 0 else _profile.plate_rear_tilt}
		if spot == null:
			continue
		var plate := LicensePlate.make_mesh(text, spot["size"])
		add_child(plate)
		# 1,2 cm vor die Fläche (entlang ihrer Normale), damit nichts flimmert
		var tilt := deg_to_rad(spot["tilt"])
		var normal := Vector3(0.0, sin(tilt), cos(tilt) * (1.0 if side == 0 else -1.0))
		LicensePlate.place(plate, (spot["center"] as Vector3) + normal * 0.012, side == 0, spot["tilt"])
		plate.visible = plates_enabled(_profile.id)
		plate.layers = OWN_CAR_LAYER
		_extra_nodes.append(plate)
		_plates.append(plate)


## Gemessene Kennzeichen-Stellen [vorne, hinten]: {"center", "size", "tilt"} oder null (für das
## Messwerkzeug, das die Werte ins Profil schreibt)
var measured_plates: Array = [null, null]


## Kennzeichen am Modell messen (Auto-Koordinaten) und die Original-Teile ausblenden
func _measure_plates(body: Array) -> Array:
	var to_car := _car.global_transform.affine_inverse()
	var words: PackedStringArray = _profile.plate_hide
	# Zwei einzelne Listen: Packed-Arrays sind Werte, append() auf ein Element eines Arrays
	# verändert nur eine Kopie
	var front_points := PackedVector3Array()
	var rear_points := PackedVector3Array()
	var normals: Array = [Vector3.ZERO, Vector3.ZERO]
	for mi: MeshInstance3D in body:
		if not is_instance_valid(mi) or mi.mesh == null:
			continue
		var xform := to_car * mi.global_transform
		for s in mi.mesh.get_surface_count():
			var material := mi.mesh.surface_get_material(s)
			var names := ((material.resource_name if material else "") + " " + String(mi.name)).to_lower()
			var is_plate := false
			for word in words:
				if word.begins_with("="):
					# Genau dieser Teilname (Teile mit allgemeinem Material, z. B. „plaste“)
					if String(mi.name).to_lower() == word.substr(1).to_lower():
						is_plate = true
				elif word != "" and names.contains(word.to_lower()):
					is_plate = true
			if not is_plate:
				continue
			var arrays := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var vertex_normals: Variant = arrays[Mesh.ARRAY_NORMAL]
			for k in verts.size():
				var p := xform * verts[k]
				var side := 0 if p.z > 0.0 else 1
				if side == 0:
					front_points.append(p)
				else:
					rear_points.append(p)
				if vertex_normals != null:
					var n: Vector3 = (xform.basis * (vertex_normals as PackedVector3Array)[k]).normalized()
					# Nur Normalen, die nach außen zeigen (Vorderseite des Schilds)
					if n.z * (1.0 if side == 0 else -1.0) > 0.3:
						normals[side] += n
			if _hidden_material == null:
				_hidden_material = StandardMaterial3D.new()
				_hidden_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				_hidden_material.albedo_color = Color(0, 0, 0, 0)
			mi.set_surface_override_material(s, _hidden_material)
	var result: Array = [null, null]
	for side in 2:
		var list := front_points if side == 0 else rear_points
		if list.size() < 3:
			continue
		var box := AABB(list[0], Vector3.ZERO)
		for p in list:
			box = box.expand(p)
		var n: Vector3 = normals[side]
		var tilt := 0.0
		if n.length() > 0.01:
			n = n.normalized()
			tilt = rad_to_deg(atan2(n.y, absf(n.z)))
		var height := box.size.y / maxf(cos(deg_to_rad(tilt)), 0.5)
		# Auf die Außenfläche des Originals (nicht in seine Mitte, sonst verdecken die Ränder einer
		# Mulde das Schild)
		var center := box.get_center()
		center.z = box.end.z if side == 0 else box.position.z
		result[side] = {"center": center, "size": LicensePlate.fit_size(Vector2(box.size.x, height)), "tilt": tilt}
	# Ohne eigenes Kennzeichen: an der Stoßstange messen
	if result[0] == null or result[1] == null:
		var floor_y := Car.resting_wheel_center(_profile, 0).y - _profile.wheel_radius
		var front := -INF
		var rear := INF
		for mi: MeshInstance3D in body:
			if not is_instance_valid(mi) or mi.mesh == null:
				continue
			var xform := to_car * mi.global_transform
			for s in mi.mesh.get_surface_count():
				var verts: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
				for k in range(0, verts.size(), 3):
					var p := xform * verts[k]
					if absf(p.x) > 0.3:
						continue
					var height := p.y - floor_y
					if absf(height - 0.40) < 0.07:
						front = maxf(front, p.z)
					if absf(height - 0.55) < 0.07:
						rear = minf(rear, p.z)
		if result[0] == null and not is_inf(front):
			result[0] = {"center": Vector3(0.0, floor_y + 0.40, front), "size": LicensePlate.SIZE, "tilt": 0.0}
		if result[1] == null and not is_inf(rear):
			result[1] = {"center": Vector3(0.0, floor_y + 0.55, rear), "size": LicensePlate.SIZE, "tilt": 0.0}
	return result


## Neues Kennzeichen oder „Kein Kennzeichen“ (Garage) an beide Schilder
func refresh_plates() -> void:
	var shown := plates_enabled(_profile.id)
	for plate in _plates:
		if is_instance_valid(plate):
			var quad := plate.mesh as QuadMesh
			(quad.material as StandardMaterial3D).albedo_texture = LicensePlate.make_texture(plate_text(_profile.id),
				LicensePlate.pixels_for(quad.size))
			plate.visible = shown


## Gespeichertes Kennzeichen eines Autos (Garage), sonst „M-EW 2026“
static func plate_text(car_id: String) -> String:
	var config := ConfigFile.new()
	config.load("user://einstellungen.cfg")
	return config.get_value("kennzeichen", car_id, "M-EW 2026")


## Testlauf --noplate: alle Autos ohne Kennzeichen (nur im Speicher)
static var test_no_plates: bool = false


## Hat dieses Auto ein Kennzeichen? (Garage: „Kein Kennzeichen“ schaltet es pro Auto ab)
static func plates_enabled(car_id: String) -> bool:
	if test_no_plates:
		return false
	var config := ConfigFile.new()
	config.load("user://einstellungen.cfg")
	return not bool(config.get_value("kennzeichen_aus", car_id, false))


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
		piece.set_meta("part", corner)
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
		# Aufkleber (Taste K) und Innenraum (nur im Cockpit sichtbar) bleiben einzeln
		if _matches(mi, _profile.sticker_parts) or _matches(mi, _profile.interior_parts):
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
		# Die Platzhalter-Räder des Autos hängen auch hier, die gehören nicht dazu
		if mi == null or mi.mesh == null or mi.is_queued_for_deletion() or mi.name in PLACEHOLDER_WHEEL_PARTS:
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
	# Pro Auto neu (Glas-Deckkraft und Glanzgrenze stehen im Profil)
	_glass = null
	_glass_box = AABB()
	_rim = null
	_tire = null
	_exhaust = null
	_smoothed.clear()
	_paint = StandardMaterial3D.new()
	_paint.albedo_color = _profile.paint_colors[paint_index] if not _profile.paint_colors.is_empty() else Color.GRAY
	_paint.metallic = _profile.paint_metallic
	_paint.roughness = _profile.paint_roughness
	_paint.clearcoat_enabled = true
	_paint.clearcoat = clearcoat
	_paint.clearcoat_roughness = clearcoat_roughness
	_paint_fx = ShaderMaterial.new()
	_paint_fx.shader = preload("res://shaders/car_paint_fx.gdshader")
	var points := _profile.indicator_points
	_head_glow = _lamp_material(Color(0.9, 0.92, 0.95), Color(1.0, 0.96, 0.88), points[0] if points.size() > 0 else Vector3.DOWN * 100.0)
	_tail_glow = _lamp_material(Color(0.5, 0.02, 0.02), Color(1.0, 0.05, 0.03), points[1] if points.size() > 1 else Vector3.DOWN * 100.0)
	_indicator_glass = _lamp_material(Color(0.55, 0.3, 0.08), Color.BLACK, Vector3.ZERO)
	_indicator_glass.set_shader_parameter("whole_part", 1.0)
	_indicator_glass.set_shader_parameter("glow", 0.0)


var _glass: ShaderMaterial
## Scheiben im Auto (Auto-Koordinaten): für Brüstung und Oberkante der Seitenfenster
var _glass_box := AABB()
var _rim: StandardMaterial3D
var _tire: StandardMaterial3D
var _exhaust: StandardMaterial3D
## Kopien zu glatter Originalmaterialien (Original → Kopie), siehe CarProfile.min_roughness
var _smoothed: Dictionary = {}


## front: liegt das Teil in der vorderen Hälfte des Autos? (Scheinwerfer leuchten nur vorne,
## Rücklichter nur hinten)
func _replacement_for(material: Material, front: bool) -> Material:
	if material == null:
		return null
	var material_name := material.resource_name
	if _any_match(material_name, _profile.paint_materials):
		return _paint
	if _any_match(material_name, _profile.indicator_materials):
		return _indicator_glass
	if _any_match(material_name, _profile.headlight_materials):
		return _head_glow if front else null
	if _any_match(material_name, _profile.taillight_materials):
		return _tail_glow if not front else null
	if _any_match(material_name, _profile.glass_materials):
		if _glass == null:
			# Eigener Shader: Seitenscheiben lassen sich herunterfahren (Car.windows_open)
			_glass = ShaderMaterial.new()
			_glass.shader = DRY_GLASS
			_glass.set_shader_parameter("glass_color", Color(0.03, 0.04, 0.05, _profile.glass_opacity))
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
	var base := material as BaseMaterial3D
	if base and base.roughness < _profile.min_roughness:
		if not _smoothed.has(base):
			var copy := base.duplicate() as BaseMaterial3D
			copy.roughness = _profile.min_roughness
			_smoothed[base] = copy
		return _smoothed[base]
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
			if replacement == _glass and _car:
				var in_car := _car.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()
				_glass_box = in_car if _glass_box.size == Vector3.ZERO else _glass_box.merge(in_car)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _matches(mi, _profile.shadow_parts) \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _matches(mi, _profile.low_detail_parts):
		mi.lod_bias = low_detail_lod_bias
		_low_detail.append(mi)
	if _matches(mi, _profile.sticker_parts):
		_stickers.append(mi)
	if _matches(mi, _profile.interior_parts):
		_interior.append(mi)
	if _car:
		mi.layers = OWN_CAR_LAYER


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
	if _low_beam == null:
		_low_beam = _beam_texture(true)
		_high_beam = _beam_texture(false)
	var box := _box_of(lamps) if not lamps.is_empty() else AABB(Vector3(-0.7, 0.6, 2.1), Vector3(1.4, 0.1, 0.1))
	var spacing := box.size.x * 0.5 * 0.75
	for side: float in [1.0, -1.0]:
		var spot := SpotLight3D.new()
		spot.light_color = Color(1.0, 0.95, 0.86)
		spot.light_energy = headlight_energy
		spot.spot_range = headlight_range
		spot.spot_angle = headlight_angle
		spot.spot_attenuation = 0.35
		spot.light_projector = _low_beam
		spot.shadow_enabled = side > 0.0
		# SpotLight3D leuchtet entlang -Z: umdrehen, damit es nach vorne (+Z) zeigt, etwas
		# nach unten neigen und vor das Auto setzen (nicht ins eigene Gehäuse)
		spot.transform = Transform3D(Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, deg_to_rad(-3.0)),
			Vector3(side * spacing, box.get_center().y, box.end.z + 0.25))
		spot.visible = false
		add_child(spot)
		_spots.append(spot)
		_extra_nodes.append(spot)


# ---------------------------------------------------------------------------
# Lenkrad und Cockpit
# ---------------------------------------------------------------------------

## Richtung der Lenksäule (zeigt vom Lenkrad zum Fahrer, nach hinten und oben)
static func steering_axis(profile: CarProfile) -> Vector3:
	var angle := deg_to_rad(profile.steering_column_angle)
	return Vector3(0.0, sin(angle), -cos(angle))


## Lenkrad an einen drehbaren Halter hängen. Teile aus dem Profil (steering_wheel_parts) kommen ganz
## daran. Außerdem wird alles, was im Zylinder um die Lenksäule liegt (Mitte, Halbmesser, Tiefe aus dem
## Profil), aus den übrigen Meshes herausgeschnitten. body enthält danach statt der geschnittenen
## Meshes ihre Reste. Gibt die Teile am Halter zurück.
func _build_steering_wheel(body: Array[MeshInstance3D]) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	var center := _profile.steering_wheel_center
	if center == Vector3.ZERO:
		return result
	_steering_axis = steering_axis(_profile)
	_steering = Node3D.new()
	_steering.name = "SteeringWheel"
	add_child(_steering)
	_steering.position = center
	_extra_nodes.append(_steering)
	var depth := _profile.steering_wheel_depth
	var reach := Vector3.ONE * Vector2(_profile.steering_wheel_radius, depth).length()
	var cut_box := AABB(center - reach, reach * 2.0)
	var cut_meshes := 0
	for mi in body.duplicate():
		if not is_instance_valid(mi) or mi.is_queued_for_deletion():
			continue
		var parts: Array[MeshInstance3D] = []
		if _matches(mi, _profile.steering_wheel_parts):
			parts.append(mi)
			body.erase(mi)
		elif depth > 0.0 and (_to_root(mi) * mi.get_aabb()).intersects(cut_box) and _touches_steering_wheel(mi):
			body.erase(mi)
			cut_meshes += 1
			for piece in _split_mesh(mi, func(p: Vector3) -> int: return 0 if _in_steering_wheel(p) else 1):
				if piece.get_meta("part") == 0:
					parts.append(piece)
				else:
					body.append(piece)
		for part in parts:
			_attach(part, _steering, center)
			result.append(part)
	build_report["cut_meshes"] = cut_meshes
	return result


## Liegt dieser Punkt (im Auto) im Zylinder des Lenkrads?
func _in_steering_wheel(p: Vector3) -> bool:
	var d := p - _profile.steering_wheel_center
	var along := d.dot(_steering_axis)
	if absf(along) > _profile.steering_wheel_depth:
		return false
	return (d - _steering_axis * along).length() < _profile.steering_wheel_radius


## Liegt mindestens ein Punkt dieses Meshes im Zylinder des Lenkrads? (Sonst nicht schneiden: das Teilen
## kostet Zeit und die Detailstufen des Meshes)
func _touches_steering_wheel(mi: MeshInstance3D) -> bool:
	var to_root := _to_root(mi)
	for s in mi.mesh.get_surface_count():
		var verts: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		for v in verts:
			if _in_steering_wheel(to_root * v):
				return true
	return false


## Cockpit-Sicht an oder aus: Innenraum zeigen (von außen ausgeblendet), volle Detailstufe für die
## Teile, die sonst früher vereinfacht werden, und klare Scheiben von innen
func set_cockpit_view(on: bool) -> void:
	_cockpit_view = on
	for mi in _interior:
		if is_instance_valid(mi):
			mi.visible = on
	for mi in _low_detail:
		if is_instance_valid(mi):
			mi.lod_bias = 2.0 if on else low_detail_lod_bias
	if _glass:
		_glass.set_shader_parameter("inside", 1.0 if on else 0.0)


## Karosserie nickt und wankt: Feder mit Dämpfer gegen die Beschleunigung im Auto (Kurve: nach außen,
## Bremsen: Nase runter, Gas: Heck runter). Nur am Modell; in der Cockpit-Sicht nicht (dort bewegt
## sich der Kopf, und Spiegel und Display hängen fest am Auto).
func _update_body_motion(delta: float) -> void:
	if _car == null or _model == null or delta <= 0.0:
		return
	var accel := (_car.linear_velocity - _last_velocity) / delta
	_last_velocity = _car.linear_velocity
	# Sprünge (Reset, Teleport) nicht mitmachen
	if accel.length() > 600.0:
		accel = Vector3.ZERO
	_body_accel = _body_accel.lerp(_car.global_basis.inverse() * accel, 1.0 - exp(-10.0 * delta))
	var wanted := Vector2.ZERO
	if not _cockpit_view:
		# Rollwinkel positiv = rechte Seite (−x) runter; Kurve links (Beschleunigung +x) drückt nach rechts
		wanted = Vector2(_body_accel.x / 9.81 * body_roll_per_g, -_body_accel.z / 9.81 * body_pitch_per_g)
		wanted = wanted.limit_length(maxf(body_roll_per_g, body_pitch_per_g) * 1.8)
	var omega := TAU * body_frequency
	_body_speed += ((wanted - _body_angles) * omega * omega - _body_speed * 2.0 * body_damping * omega) * delta
	_body_angles += _body_speed * delta
	# Um die Fahrtrichtung (z) wanken, um die Querachse (x) nicken (positiv = Nase runter)
	var rotation_basis := Basis(Vector3.BACK, deg_to_rad(_body_angles.x)) * Basis(Vector3.RIGHT, deg_to_rad(_body_angles.y))
	transform = Transform3D(rotation_basis, body_pivot - rotation_basis * body_pivot)


# ---------------------------------------------------------------------------
# Leuchten, Blinker, Scheinwerfer-Bild, Begrüßungslicht
# ---------------------------------------------------------------------------

func _lamp_material(albedo: Color, glow_color: Color, indicator_point: Vector3) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/car_lamp.gdshader")
	material.set_shader_parameter("albedo_color", albedo)
	material.set_shader_parameter("glow_color", glow_color)
	material.set_shader_parameter("indicator_point", indicator_point)
	material.set_shader_parameter("indicator_radius", _profile.indicator_radius)
	return material


## Welche Blinkerpunkte (vorne, hinten, Spiegel) liegen auf Glas des Modells? Vorne und hinten: ein Punkt
## des Scheinwerfer- bzw. Rücklichtglases oder eines eigenen Blinkerglases im Radius. Liegt der gemessene
## Punkt knapp daneben (bis 25 cm), rückt der leuchtende Bereich auf die nächste Stelle des Glases.
## Spiegel: ein eigenes Blinkerglas in 25 cm Umkreis.
func _measure_indicators() -> void:
	indicator_covered = [false, false, false]
	var points := _profile.indicator_points
	if _car == null or points.size() < 3:
		return
	var radius := _profile.indicator_radius
	# Nächster Punkt des Scheinwerfer- bzw. Rücklichtglases zum Blinkerpunkt vorne und hinten
	var nearest: Array[float] = [INF, INF]
	var nearest_point: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	for mi in _meshes_under(self):
		for s in mi.mesh.get_surface_count():
			var material := mi.get_surface_override_material(s)
			if material != _head_glow and material != _tail_glow and material != _indicator_glass:
				continue
			var to_root := _to_root(mi)
			for v: Vector3 in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				var p := to_root * v
				p.x = absf(p.x)
				for k in 2:
					if material == (_tail_glow if k == 0 else _head_glow):
						continue
					var distance := p.distance_to(points[k])
					if distance < radius:
						indicator_covered[k] = true
					if material != _indicator_glass and distance < nearest[k]:
						nearest[k] = distance
						nearest_point[k] = p
				if material == _indicator_glass and p.distance_to(points[2]) < 0.25:
					indicator_covered[2] = true
	for k in 2:
		if not indicator_covered[k] and nearest[k] < 0.25:
			# Etwas zur Mitte des Autos hin, damit der Bereich nicht nur die Kante trifft
			var moved := nearest_point[k] + Vector3(-radius * 0.4, 0.0, 0.0)
			(_head_glow if k == 0 else _tail_glow).set_shader_parameter("indicator_point", moved)
			indicator_covered[k] = true
			build_report["indicator_moved_%d" % k] = snappedf(nearest[k], 0.01)
	build_report["indicators"] = indicator_covered


## Projektor-Bild eines Scheinwerfers (Mitte = Achse des Lichts, oben = oben). Abblendlicht: hell unter
## einer scharfen Hell-Dunkel-Grenze, die rechts (Fahrbahnrand) ansteigt, breit zur Seite, helle Mitte
## knapp unter der Grenze. Fernlicht: ohne Grenze, heller Kern.
static func _beam_texture(low: bool) -> ImageTexture:
	var size := 128
	var image := Image.create(size, size, false, Image.FORMAT_RGB8)
	for py in size:
		for px in size:
			var x := (px + 0.5) / size * 2.0 - 1.0
			var y := 1.0 - (py + 0.5) / size * 2.0
			var value := 0.0
			if low:
				# Grenze waagerecht knapp über der Achse, rechts mit 15° ansteigend
				var cutoff := 0.04 + maxf(x - 0.08, 0.0) * tan(deg_to_rad(15.0))
				var below := clampf((cutoff - y) / 0.025, 0.0, 1.0)
				# Hellster Bereich knapp unter der Grenze (reicht weit), breite Streuung darunter (Rand, nah)
				var core := exp(-pow(x / 0.36, 2.0) - pow((y + 0.03) / 0.08, 2.0))
				var spread := exp(-pow(x / 0.95, 2.0) - pow((y + 0.15) / 0.35, 2.0))
				value = below * (0.55 * spread + 0.9 * core + 0.15) + (1.0 - below) * 0.03
			else:
				var core := exp(-pow(x / 0.3, 2.0) - pow(y / 0.18, 2.0))
				var spread := exp(-pow(x / 0.85, 2.0) - pow(y / 0.5, 2.0))
				value = 0.9 * core + 0.4 * spread + 0.06
			# Zum Rand des Kegels weich ausblenden
			value *= clampf((1.0 - Vector2(x, y).length()) / 0.12, 0.0, 1.0)
			var c := clampf(value, 0.0, 1.0)
			image.set_pixel(px, py, Color(c, c, c))
	return ImageTexture.create_from_image(image)


## Begrüßungslicht in der Garage starten (beim Auswählen eines Autos): nacheinander Tagfahrlicht,
## Scheinwerfer, Rücklicht, dann der Motorstart. Läuft, bis end_welcome() kommt.
func play_welcome() -> void:
	_welcome_time = 0.0


func end_welcome() -> void:
	_welcome_time = -1.0


## Motorstart: Anlasser (surrendes Brummen), dann zünden die Zylinder, die Drehzahl schießt hoch und
## fällt auf Leerlauf. Im Code berechnet, Zündfolge nach Zylinderzahl des Profils.
func _play_engine_start() -> void:
	if _profile == null:
		return
	if _welcome_sound == null:
		_welcome_sound = AudioStreamPlayer.new()
		_welcome_sound.bus = &"Motor"
		add_child(_welcome_sound)
	var rate := 22050
	var length := int(rate * 2.2)
	var samples := PackedFloat32Array()
	samples.resize(length)
	var phase := 0.0
	var crank := 0.0
	var low := 0.0
	var idle := _profile.idle_rpm
	for i in length:
		var t := float(i) / rate
		# Drehzahl: Anlasser 250/min, ab 0,55 s zünden, Spitze bei 0,8 s, dann Leerlauf
		var rpm := 250.0
		if t > 0.55:
			rpm = lerpf(idle * 2.1, idle, clampf((t - 0.8) / 0.9, 0.0, 1.0)) if t > 0.8 else lerpf(250.0, idle * 2.1, (t - 0.55) / 0.25)
		var firing := rpm / 120.0 * maxf(_profile.cylinders, 1)
		phase = fmod(phase + firing / rate, 1.0)
		crank = fmod(crank + 11.0 * rpm / 250.0 / rate, 1.0)
		var value := 0.0
		if t < 0.6:
			# Anlasser: gepulstes Surren
			value += (sin(TAU * 180.0 * t) * 0.3 + randf_range(-0.2, 0.2)) * (0.6 + 0.4 * sin(TAU * crank))
		if t > 0.5:
			# Zündungen als kurze Druckstöße, tiefpassgefiltert
			var pulse := exp(-phase * 9.0) * (1.0 + _profile.sound_rumble)
			low = lerpf(low, pulse + randf_range(-0.08, 0.08), 0.25)
			value += low * clampf((t - 0.5) / 0.08, 0.0, 1.0) * 1.6
		value *= clampf((2.2 - t) / 0.3, 0.0, 1.0)
		samples[i] = value
	var peak := 0.001
	for v in samples:
		peak = maxf(peak, absf(v))
	var data := PackedByteArray()
	data.resize(length * 2)
	for i in length:
		data.encode_s16(i * 2, int(clampf(samples[i] / peak, -1.0, 1.0) * 28000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = data
	_welcome_sound.stream = wav
	_welcome_sound.volume_db = welcome_volume_db
	_welcome_sound.play()


## Wetter am Auto setzen (CarWeather, jedes Bild): nass, Schnee, Eis (0–1)
func set_weather_fx(wet: float, snow: float, frost: float) -> void:
	_fx = Vector3(wet, snow, frost)


## Weicher Kontaktschatten auf dem Boden unter dem Auto (nicht auf dem eigenen Auto: Ebene 11 aus)
func _add_contact_shadow() -> void:
	if _car == null:
		return
	_contact_shadow = ContactShadow.make(Vector2(_profile.body_size.x, _profile.body_size.z))
	_contact_shadow.cull_mask = 0xFFFFF & ~OWN_CAR_LAYER
	var ground := Car.resting_wheel_center(_profile, 0).y - _profile.wheel_radius
	_contact_shadow.position = Vector3(0.0, ground + 0.15, _profile.body_center.z)
	_car.add_child(_contact_shadow)
	_extra_nodes.append(_contact_shadow)

