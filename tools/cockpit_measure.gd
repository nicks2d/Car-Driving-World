extends SceneTree
## Messwerkzeug für die Cockpit-Werte im Profil (CarProfile, Gruppe „Cockpit“). Zeigt jedes Auto als
## Schnittbild mit Maßraster in Auto-Koordinaten (x nach links, y hoch, z nach vorne; Linien alle 10 cm,
## beschriftet alle 50 cm). Eingezeichnet sind die Werte aus dem Profil: Augen (rot), Lenkrad (türkis),
## Kombiinstrument (grün), Spiegel (gelb). Das Lenkrad ist um 90° nach links gedreht: So sieht man, welche
## Teile mitdrehen.
##
## Aufruf (im Projektordner, mit Fenster, nicht headless):
##   Godot --path . -s res://tools/cockpit_measure.gd -- [--cars=m2,f90] [--x=0.37] [--y=0.62] [--z=0.3]
##         [--parts] [--showall]
## Ohne --x/--y/--z wird bei den Werten aus dem Profil geschnitten (Augen, Lenkrad, 15 cm hinter dem Lenkrad).
## --parts listet die Teile rund ums Lenkrad und alle Spiegel-Teile (Name, Material, Mitte, Größe).
## --showall zeigt auch ausgeblendete Teile (hidden_parts, außer Motor).
## Bilder: screenshots/cockpit/ID_seite.png (Schnitt bei x, Blick von links), ID_oben.png (bei y, Blick von
## oben, vorne ist oben) und ID_hinten.png (bei z, Blick nach vorne wie der Fahrer).

const VIEWS: Array[String] = ["seite", "oben", "hinten"]

var _cars: PackedStringArray = PackedStringArray()
var _cut := {}
var _list_parts: bool = false
## --showall: ausgeblendete Teile (hidden_parts) außer dem Motor trotzdem zeigen
var _show_all: bool = false
var _model: CarModel
var _profile: CarProfile
var _camera: Camera3D
var _overlay: Control
var _view: String = ""
var _cut_value: float = 0.0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		var value := parts[1] if parts.size() > 1 else ""
		match parts[0]:
			"cars":
				_cars = value.split(",")
			"x", "y", "z":
				_cut[parts[0]] = float(value)
			"parts":
				_list_parts = true
			"showall":
				_show_all = true
	if _cars.is_empty():
		for file in DirAccess.get_files_at("res://cars"):
			if file.ends_with(".tres"):
				_cars.append(file.get_basename())
	DisplayServer.window_set_size(Vector2i(1400, 1000))
	# Gleichmäßiges Licht ohne Schatten, damit man auch unter dem Dach etwas sieht
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.16, 0.17, 0.19)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.7
	var world_env := WorldEnvironment.new()
	world_env.environment = environment
	root.add_child(world_env)
	for direction: Vector3 in [Vector3(-30, 40, 0), Vector3(20, -140, 0)]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = direction
		light.light_energy = 0.8
		root.add_child(light)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	# Sonst rechnet unproject_position mit der alten (interpolierten) Lage
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	root.add_child(_camera)
	_camera.current = true
	var layer := CanvasLayer.new()
	root.add_child(layer)
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	layer.add_child(_overlay)
	_run.call_deferred()


func _run() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var folder := ProjectSettings.globalize_path("res://screenshots/cockpit")
	DirAccess.make_dir_recursive_absolute(folder)
	for id in _cars:
		_profile = load("res://cars/%s.tres" % id) as CarProfile
		if _show_all:
			_profile = _profile.duplicate() as CarProfile
			var keep := PackedStringArray()
			for pattern in _profile.hidden_parts:
				if pattern.to_lower().contains("engine"):
					keep.append(pattern)
			_profile.hidden_parts = keep
		_model = CarModel.new()
		holder.add_child(_model)
		_model.show_profile(_profile)
		if _model.is_loading():
			await _model.model_ready
		print("== %s  Modell-Box %s" % [id, _box_text()])
		print("   Lenkrad: %s" % _model.build_report)
		# Lenkrad um 90° nach links drehen: zeigt, was alles zum Lenkrad gehört
		var steering := _model.get("_steering") as Node3D
		if steering:
			steering.transform = Transform3D(Basis(CarModel.steering_axis(_profile), PI * 0.5), steering.position)
		if _list_parts:
			_print_parts()
		for view in VIEWS:
			_place_camera(view)
			_overlay.queue_redraw()
			for i in 6:
				await process_frame
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			image.save_png(folder.path_join("%s_%s.png" % [id, view]))
		_model.clear()
		_model.queue_free()
		await process_frame
	print("Fertig: %s" % folder)
	quit()


func _box_text() -> String:
	var box := AABB()
	var first := true
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		var part := (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		box = part if first else box.merge(part)
		first = false
	return "von %s bis %s" % [box.position.snapped(Vector3.ONE * 0.01), box.end.snapped(Vector3.ONE * 0.01)]


## Teile in der Nähe des Lenkrads (bzw. vor den Augen) auflisten
func _print_parts() -> void:
	var around := _profile.steering_wheel_center if _profile.steering_wheel_center != Vector3.ZERO \
		else _profile.eye_position + Vector3(0.0, -0.15, 0.45)
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var box := mi.global_transform * mi.get_aabb()
		var material := mi.mesh.surface_get_material(0)
		var is_mirror := (String(mi.name) + (material.resource_name if material else "")).to_lower().contains("mirror")
		if not is_mirror and (box.get_center().distance_to(around) > 0.45 or box.size.length() > 1.2):
			continue
		var base := material as BaseMaterial3D
		var look := "Farbe %s%s" % [base.albedo_color.to_html(false), " + Textur" if base.albedo_texture else ""] if base else ""
		print("   %s | %s | Mitte %s Größe %s | %d Punkte | %s" % [mi.name, material.resource_name if material else "",
			box.get_center().snapped(Vector3.ONE * 0.01), box.size.snapped(Vector3.ONE * 0.01),
			mi.mesh.surface_get_array_len(0), look])


## Kamera so, dass alles vor der Schnittebene weggeschnitten ist
func _place_camera(view: String) -> void:
	_view = view
	var eye := _profile.eye_position
	var wheel := _profile.steering_wheel_center if _profile.steering_wheel_center != Vector3.ZERO \
		else eye + Vector3(0.0, -0.12, 0.5)
	match view:
		"seite":
			_cut_value = _cut.get("x", eye.x)
			_camera.size = 2.0
			_camera.global_transform = Transform3D(Basis.looking_at(Vector3(-1, 0, 0), Vector3.UP),
				Vector3(_cut_value + 10.0, 0.6, -0.1))
		"oben":
			_cut_value = _cut.get("y", wheel.y)
			_camera.size = 2.0
			_camera.global_transform = Transform3D(Basis.looking_at(Vector3(0, -1, 0), Vector3(0, 0, 1)),
				Vector3(0.0, _cut_value + 10.0, 0.0))
		"hinten":
			# Etwas hinter dem Lenkrad schneiden, damit es ganz zu sehen ist
			_cut_value = _cut.get("z", wheel.z - 0.15)
			_camera.size = 1.6
			_camera.global_transform = Transform3D(Basis.looking_at(Vector3(0, 0, 1), Vector3.UP),
				Vector3(0.0, 0.6, _cut_value - 10.0))
	_camera.near = 10.0
	_camera.far = 13.0


## Punkt in Auto-Koordinaten auf den Bildschirm
func _screen(p: Vector3) -> Vector2:
	return _camera.unproject_position(p)


## Punkt in der Schnittebene aus zwei Koordinaten
func _plane_point(a: float, b: float) -> Vector3:
	match _view:
		"seite":
			return Vector3(_cut_value, b, a)  # a = z, b = y
		"oben":
			return Vector3(a, _cut_value, b)  # a = x, b = z
	return Vector3(a, b, _cut_value)  # a = x, b = y


func _draw_overlay() -> void:
	if _profile == null or _view == "":
		return
	var font := ThemeDB.fallback_font
	# Raster alle 10 cm im Bereich ±2,5 m
	for k in range(-25, 26):
		var v := k * 0.1
		var strong := k % 5 == 0
		var color := Color(1, 1, 1, 0.45 if strong else 0.13)
		# Breite -1: immer genau ein Bildpunkt (dünne Linien gehen beim Skalieren sonst verloren)
		_overlay.draw_line(_screen(_plane_point(v, -2.5)), _screen(_plane_point(v, 2.5)), color, -1.0)
		_overlay.draw_line(_screen(_plane_point(-2.5, v)), _screen(_plane_point(2.5, v)), color, -1.0)
		if strong:
			var axis_a := {"seite": "z", "oben": "x", "hinten": "x"}[_view] as String
			var axis_b := {"seite": "y", "oben": "z", "hinten": "y"}[_view] as String
			_overlay.draw_string(font, _screen(_plane_point(v, 0.0)) + Vector2(3, -3), "%s %.1f" % [axis_a, v],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 0.6))
			_overlay.draw_string(font, _screen(_plane_point(0.0, v)) + Vector2(3, -3), "%s %.1f" % [axis_b, v],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 0.6))
	_overlay.draw_string(font, Vector2(16, 30), "%s  %s-Schnitt bei %.2f" % [_profile.id, _view, _cut_value],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
	# Augen
	_overlay.draw_circle(_screen(_profile.eye_position), 7.0, Color(1, 0.2, 0.2))
	# Lenkrad: Kreis senkrecht zur Lenksäule
	var c := _profile.steering_wheel_center
	if c != Vector3.ZERO:
		var a := deg_to_rad(_profile.steering_column_angle)
		var axis := Vector3(0.0, sin(a), -cos(a))
		var u := Vector3.RIGHT
		var w := axis.cross(u).normalized()
		var points := PackedVector2Array()
		for i in 49:
			var t := TAU * i / 48.0
			points.append(_screen(c + (u * cos(t) + w * sin(t)) * _profile.steering_wheel_radius))
		_overlay.draw_polyline(points, Color(0.2, 1, 1), 2.0)
		_overlay.draw_line(_screen(c - axis * _profile.steering_wheel_depth), _screen(c + axis * _profile.steering_wheel_depth),
			Color(0.2, 1, 1), 2.0)
	_draw_rect(_profile.cluster_position, _profile.cluster_size, _profile.cluster_tilt, Color(0.3, 1, 0.3))
	_draw_rect(_profile.mirror_inner_position, _profile.mirror_inner_size, -1.0, Color(1, 0.9, 0.2))
	_draw_rect(_profile.mirror_side_position, _profile.mirror_side_size, -1.0, Color(1, 0.9, 0.2))
	if _profile.mirror_side_position != Vector3.ZERO:
		var right := _profile.mirror_side_position * Vector3(-1, 1, 1)
		_draw_rect(right, _profile.mirror_side_size, -1.0, Color(1, 0.9, 0.2))


## Rechteck (Breite × Höhe) um center: geneigt um tilt Grad (oben nach hinten), tilt < 0 = zum Auge gedreht
func _draw_rect(center: Vector3, size: Vector2, tilt: float, color: Color) -> void:
	if center == Vector3.ZERO:
		return
	var basis := Basis(Vector3.RIGHT, deg_to_rad(tilt)) if tilt >= 0.0 \
		else Basis.looking_at(center - _profile.eye_position, Vector3.UP)
	var corners := PackedVector2Array()
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1)]:
		corners.append(_screen(center + basis * Vector3(corner.x * size.x * 0.5, corner.y * size.y * 0.5, 0.0)))
	_overlay.draw_polyline(corners, color, 2.0)
