class_name Cockpit
extends Node3D
## Alles, was man nur vom Fahrersitz aus sieht (Cockpit- und Ego-Sicht, Taste Tab):
##  - Rückspiegel: Eine Kamera hinter dem Fahrer rendert in niedriger Auflösung und 30 Bildern pro
##    Sekunde nach hinten (ohne das eigene Auto). Innen- und Außenspiegel zeigen je einen Ausschnitt.
##  - Kombiinstrument: eigenes Display mit Tacho und Drehzahl (die Modelle haben keine drehbaren
##    Zeiger), nachts leuchtend
##  - Innenlicht: nachts ein schwaches Licht der Armaturen
## Lage von Spiegeln und Display steht im Profil (CarProfile, Gruppe „Cockpit“). Lenkrad und Innenraum
## macht CarModel (set_cockpit_view). Aktiv ist das alles nur, solange die Kamera im Auto sitzt.

@export_group("Spiegel")
## Auflösung und Bildrate der Rückkamera (alle drei Spiegel zusammen)
@export var mirror_resolution := Vector2i(576, 192)
@export var mirror_fps: float = 30.0
## Sichtfeld der Rückkamera quer (Grad): links ein Drittel linker Spiegel, Mitte Innenspiegel,
## rechts ein Drittel rechter Spiegel
@export var mirror_fov: float = 110.0
## So weit sieht man in den Spiegeln (Meter)
@export var mirror_far: float = 400.0
## So weit vor der Stelle aus dem Profil hängt das Spiegelbild (Meter, zum Fahrer hin)
@export var mirror_offset: float = 0.04
## Wie oft die Umgebung (Himmel, Nebel) für die Rückkamera übernommen wird (Sekunden)
@export var environment_refresh: float = 0.25

@export_group("Display")
@export var display_resolution := Vector2i(512, 192)
@export var display_fps: float = 30.0
## Leuchtkraft des Displays am Tag und in der Nacht
@export var display_glow_day: float = 1.6
@export var display_glow_night: float = 0.7

@export_group("Innenlicht")
## Helligkeit und Reichweite des Armaturen-Lichts in der Nacht
@export var cabin_light_energy: float = 0.025
@export var cabin_light_range: float = 0.8

## Sitzt die Kamera gerade im Auto?
var active: bool = false

var _car: Car
var _model: CarModel
var _mirror_viewport: SubViewport
var _mirror_camera: Camera3D
var _display_viewport: SubViewport
var _display_canvas: Control
var _display_material: StandardMaterial3D
var _cabin_light: OmniLight3D
var _parts: Array[Node3D] = []
var _built: bool = false
var _mirror_timer: float = 0.0
var _display_timer: float = 0.0
var _environment_timer: float = 0.0
var _day_night: DayNight


func _ready() -> void:
	_car = get_parent() as Car
	_model = _car.get_node("Model") as CarModel
	_model.model_ready.connect(_on_model_ready)
	# Rückkamera: eigenes Bild, rendert nur auf Anfrage (siehe _process)
	_mirror_viewport = SubViewport.new()
	_mirror_viewport.size = mirror_resolution
	_mirror_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	# HDR ohne Tonemapping: Das Hauptbild macht das Tonemapping für die Spiegel mit
	_mirror_viewport.use_hdr_2d = true
	_mirror_viewport.positional_shadow_atlas_size = 0
	add_child(_mirror_viewport)
	_mirror_camera = Camera3D.new()
	_mirror_camera.keep_aspect = Camera3D.KEEP_WIDTH
	_mirror_camera.fov = mirror_fov
	_mirror_camera.near = 0.3
	_mirror_camera.far = mirror_far
	_mirror_camera.cull_mask = 0xFFFFF & ~CarModel.OWN_CAR_LAYER
	_mirror_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_mirror_viewport.add_child(_mirror_camera)
	# Display: nur 2D, wird im Takt neu gezeichnet
	_display_viewport = SubViewport.new()
	_display_viewport.size = display_resolution
	_display_viewport.disable_3d = true
	_display_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_display_viewport)
	_display_canvas = Control.new()
	_display_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_display_canvas.draw.connect(_draw_display)
	_display_viewport.add_child(_display_canvas)
	_cabin_light = OmniLight3D.new()
	_cabin_light.light_color = Color(1.0, 0.92, 0.82)
	_cabin_light.light_energy = cabin_light_energy
	_cabin_light.omni_range = cabin_light_range
	_cabin_light.shadow_enabled = false
	_cabin_light.visible = false
	add_child(_cabin_light)


## Neues Auto: Spiegel und Display weg, beim nächsten Blick aus dem Cockpit neu anlegen
func _on_model_ready() -> void:
	for part in _parts:
		part.queue_free()
	_parts.clear()
	_built = false


## Spiegel und Display für das aktuelle Auto anlegen (erst beim ersten Blick aus dem Cockpit)
func _build_parts() -> void:
	_built = true
	var profile := _car.profile
	if profile == null:
		return
	var eye := profile.eye_position
	var third := 1.0 / 3.0
	if profile.mirror_inner_position != Vector3.ZERO:
		# Innenspiegel: mittlerer Teil des Bilds (etwas breiter als ein Drittel)
		_add_mirror(profile.mirror_inner_position, profile.mirror_inner_size, 0.3, 0.7, eye)
	if profile.mirror_side_position != Vector3.ZERO:
		var side := profile.mirror_side_position
		# Links im Auto (+x) = rechts im Kamerabild
		_add_mirror(side, profile.mirror_side_size, 1.0 - third, 1.0, eye)
		_add_mirror(Vector3(-side.x, side.y, side.z), profile.mirror_side_size, 0.0, third, eye)
	if profile.cluster_position != Vector3.ZERO:
		var quad := QuadMesh.new()
		quad.size = profile.cluster_size
		_display_material = StandardMaterial3D.new()
		_display_material.albedo_color = Color(0.05, 0.05, 0.05)
		_display_material.albedo_texture = _display_viewport.get_texture()
		_display_material.emission_enabled = true
		_display_material.emission_texture = _display_viewport.get_texture()
		_display_material.roughness = 0.25
		var display := MeshInstance3D.new()
		display.name = "ClusterDisplay"
		display.mesh = quad
		display.material_override = _display_material
		# Schaut zum Fahrer (Quad zeigt nach +z, also umdrehen) und um cluster_tilt nach oben
		display.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(profile.cluster_tilt)) * Basis(Vector3.UP, PI),
			profile.cluster_position)
		_add_part(display)
		_cabin_light.position = profile.cluster_position + Vector3(-profile.cluster_position.x * 0.5, 0.05, -0.25)
	_set_parts_visible(active)


## Ein Spiegel: Quad an dieser Stelle, zum Auge gedreht, zeigt den Ausschnitt u_from–u_to der Rückkamera
func _add_mirror(center: Vector3, mirror_size: Vector2, u_from: float, u_to: float, eye: Vector3) -> void:
	var quad := QuadMesh.new()
	quad.size = mirror_size
	# Ausschnitt mit dem Seitenverhältnis des Spiegels (Bildmitte in der Höhe)
	var pixel_width := (u_to - u_from) * mirror_resolution.x
	var height := clampf(pixel_width / (mirror_size.x / mirror_size.y) / mirror_resolution.y, 0.1, 1.0)
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/car_mirror.gdshader")
	material.set_shader_parameter("view", _mirror_viewport.get_texture())
	material.set_shader_parameter("region", Vector4(u_from, 0.5 - height * 0.5, u_to, 0.5 + height * 0.5))
	var mirror := MeshInstance3D.new()
	mirror.name = "Mirror"
	mirror.mesh = quad
	mirror.material_override = material
	mirror.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Vorderseite (+z) zum Auge, etwas vor das Glas des Modells (das Glas steht meist schräger, sonst
	# taucht das Bild zur Hälfte dahinter ab)
	var toward_eye := (eye - center).normalized()
	mirror.transform = Transform3D(Basis.looking_at(-toward_eye, Vector3.UP), center + toward_eye * mirror_offset)
	_add_part(mirror)


func _add_part(part: MeshInstance3D) -> void:
	part.layers = CarModel.OWN_CAR_LAYER
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_car.add_child(part)
	_parts.append(part)


func _set_parts_visible(on: bool) -> void:
	for part in _parts:
		part.visible = on


func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d() as FollowCamera
	var now := camera != null and camera.is_inside_car() and _car.profile != null
	if now and not _built and not _model.is_loading():
		_build_parts()
	if now != active:
		active = now
		_set_parts_visible(active)
		_model.set_cockpit_view(active)
		_environment_timer = 0.0
		if not active:
			_cabin_light.visible = false
	if not active:
		return
	var night := _is_night() or _car.in_tunnel
	_cabin_light.visible = night
	if _display_material:
		_display_material.emission_energy_multiplier = display_glow_night if night else display_glow_day
	# Rückkamera: hinter dem Fahrer auf Augenhöhe in der Mitte, Blick nach hinten
	var eye := _car.profile.eye_position
	var car_transform := _car.get_global_transform_interpolated()
	_mirror_camera.global_transform = car_transform * Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, eye.y, eye.z))
	_environment_timer -= delta
	if _environment_timer <= 0.0:
		_environment_timer = environment_refresh
		_copy_environment()
	_mirror_timer -= delta
	if mirror_fps > 0.0 and _mirror_timer <= 0.0:
		_mirror_timer += 1.0 / mirror_fps
		_mirror_timer = maxf(_mirror_timer, 0.0)
		_mirror_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_display_timer -= delta
	if _display_timer <= 0.0:
		_display_timer = maxf(_display_timer + 1.0 / display_fps, 0.0)
		_display_canvas.queue_redraw()
		_display_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## Umgebung der Welt (Himmel, Nebel, Licht ändern sich mit Tageszeit und Wetter) als Kopie für die
## Rückkamera: ohne Tonemapping (macht das Hauptbild) und ohne teure Bildeffekte
func _copy_environment() -> void:
	var world := get_viewport().find_world_3d()
	if world == null or world.environment == null:
		return
	var copy := world.environment.duplicate() as Environment
	copy.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	copy.tonemap_exposure = 1.0
	copy.tonemap_white = 1.0
	copy.glow_enabled = false
	copy.ssao_enabled = false
	copy.ssil_enabled = false
	copy.ssr_enabled = false
	copy.sdfgi_enabled = false
	copy.volumetric_fog_enabled = false
	copy.adjustment_enabled = false
	_mirror_camera.environment = copy


func _is_night() -> bool:
	if _day_night == null:
		_day_night = get_tree().get_first_node_in_group("day_night") as DayNight
	return _day_night != null and _day_night.sun_direction().y < sin(deg_to_rad(_model.lights_on_below_sun_degrees))


# ---------------------------------------------------------------------------
# Display: Tacho links, Drehzahl rechts, Gang und Tempo in der Mitte
# ---------------------------------------------------------------------------

const START_ANGLE: float = PI * 0.75
const SWEEP: float = PI * 1.5


func _draw_display() -> void:
	var canvas := _display_canvas
	var area := Vector2(display_resolution)
	canvas.draw_rect(Rect2(Vector2.ZERO, area), Color(0.012, 0.015, 0.02))
	var profile := _car.profile
	if profile == null:
		return
	var speed := _car.linear_velocity.length() * 3.6
	var max_speed := ceilf((profile.top_speed_kmh + 30.0) / 40.0) * 40.0
	var max_rpm := ceilf((profile.redline_rpm + 300.0) / 1000.0) * 1000.0
	var red_rpm := floorf((profile.redline_rpm - 400.0) / 500.0) * 500.0
	var radius := area.y * 0.42
	var left := Vector2(area.x * 0.2, area.y * 0.54)
	var right := Vector2(area.x * 0.8, area.y * 0.54)
	_draw_dial(left, radius, speed / max_speed, 0.0, max_speed, 20.0, 2, UiStyle.accent)
	_draw_dial(right, radius, _car.engine_rpm / max_rpm, red_rpm / max_rpm, max_rpm / 1000.0, 0.5, 2,
		UiStyle.RED if _car.engine_rpm >= red_rpm else UiStyle.accent)
	# Mitte: Gang groß, darunter das Tempo
	var middle := area.x * 0.5
	var gear_text := "R" if _car.gear < 0 else str(_car.gear)
	UiStyle.draw_text(canvas, gear_text, Vector2(middle, area.y * 0.5), 64, "extrabold", UiStyle.TEXT, 0.5)
	UiStyle.draw_text(canvas, str(roundi(speed)), Vector2(middle, area.y * 0.78), 30, "semibold", UiStyle.TEXT_DIM, 0.5)
	UiStyle.draw_text(canvas, "km/h", Vector2(middle, area.y * 0.92), 15, "medium", UiStyle.TEXT_FAINT, 0.5)
	# Blinker oben in der Mitte
	if _car.signal_lit:
		var green := Color("#3FD47A")
		if _car.hazard or _car.turn_signal == 1:
			_draw_arrow(Vector2(middle - 46.0, area.y * 0.14), -1.0, green)
		if _car.hazard or _car.turn_signal == -1:
			_draw_arrow(Vector2(middle + 46.0, area.y * 0.14), 1.0, green)


## Rundinstrument: Skala von 0 bis top (Striche alle minor, Zahl an jedem major_every-ten Strich), roter
## Bereich ab red_from (Anteil 0–1, 0 = keiner), Zeiger auf value (Anteil 0–1)
func _draw_dial(center: Vector2, radius: float, value: float, red_from: float, top: float, minor: float,
		major_every: int, needle_color: Color) -> void:
	var canvas := _display_canvas
	canvas.draw_arc(center, radius, START_ANGLE, START_ANGLE + SWEEP, 64, Color(1, 1, 1, 0.14), 3.0, true)
	if red_from > 0.0:
		canvas.draw_arc(center, radius - 2.0, START_ANGLE + SWEEP * red_from, START_ANGLE + SWEEP, 24,
			Color(UiStyle.RED, 0.9), 6.0, true)
	var steps := roundi(top / minor)
	for k in steps + 1:
		var amount := k * minor
		var direction := Vector2.from_angle(START_ANGLE + SWEEP * amount / top)
		var is_major := k % major_every == 0
		var inner := radius - (12.0 if is_major else 7.0)
		canvas.draw_line(center + direction * inner, center + direction * (radius - 1.0),
			Color(1, 1, 1, 0.8 if is_major else 0.35), 2.0 if is_major else 1.0, true)
		if is_major:
			UiStyle.draw_text(canvas, str(roundi(amount)), center + direction * (radius - 26.0) + Vector2(0, 5), 13,
				"medium", UiStyle.TEXT_DIM, 0.5)
	# Zeiger mit Nabe
	var angle := START_ANGLE + SWEEP * clampf(value, 0.0, 1.02)
	var tip := center + Vector2.from_angle(angle) * (radius - 4.0)
	canvas.draw_line(center - Vector2.from_angle(angle) * 10.0, tip, needle_color, 3.5, true)
	canvas.draw_circle(center, 7.0, Color(0.1, 0.11, 0.13))
	canvas.draw_arc(center, 7.0, 0.0, TAU, 20, needle_color, 2.0, true)


func _draw_arrow(center: Vector2, direction: float, color: Color) -> void:
	var points := PackedVector2Array([Vector2(-13, 0), Vector2(-1, -11), Vector2(-1, -4.5), Vector2(12, -4.5),
		Vector2(12, 4.5), Vector2(-1, 4.5), Vector2(-1, 11)])
	for i in points.size():
		points[i] = center + Vector2(points[i].x * -direction, points[i].y)
	_display_canvas.draw_colored_polygon(points, color)
