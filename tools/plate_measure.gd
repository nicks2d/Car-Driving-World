extends SceneTree
## Misst die Kennzeichen jedes Garage-Autos am geladenen Modell (genau wie im Spiel: CarModel
## skaliert und dreht es auf die Physik-Räder) und schreibt Lage, Größe und Neigung ins Profil
## (cars/*.tres: plate_front_*, plate_rear_*). Gemessen werden die Teile aus plate_hide (eigene
## Kennzeichen des Modells), ohne solche die Stoßstange (CarModel._measure_plates).
## Danach mit Fotos prüfen: Godot --path . -- --shot=NAME --car=ID --carview=0 --carzoom=4.2
##
## Aufruf (im Projektordner):
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s res://tools/plate_measure.gd
##   ... -- --cars=e30,e92     nur diese Autos
##   ... -- --dry              nur anzeigen, nichts speichern
##   ... -- --list             zusätzlich alle Teile in Kennzeichengröße mittig vorne/hinten nennen
##                             (Material, Teil, Mitte und Größe in Metern), um Kennzeichen ohne
##                             passenden Namen zu finden (dann in plate_hide eintragen)

var _queue: Array[String] = []
var _dry := false
var _car: Car
var _profile: CarProfile
var _path: String
var _timer := 0.0
var _list := false


func _initialize() -> void:
	var only: PackedStringArray = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--cars="):
			only = arg.trim_prefix("--cars=").split(",")
		elif arg == "--dry":
			_dry = true
		elif arg == "--list":
			_list = true
	for file in DirAccess.get_files_at("res://cars"):
		if file.ends_with(".tres") and (only.is_empty() or file.get_basename() in only):
			_queue.append("res://cars/" + file)
	_next()


func _next() -> void:
	if _car:
		_car.queue_free()
		_car = null
	if _queue.is_empty():
		quit()
		return
	_path = _queue.pop_front()
	_profile = load(_path) as CarProfile
	# Ohne gespeicherte Lage misst CarModel selbst
	var stored := [_profile.plate_front_position, _profile.plate_rear_position]
	_profile.plate_front_position = Vector3.ZERO
	_profile.plate_rear_position = Vector3.ZERO
	_profile.set_meta("stored", stored)
	_car = (load("res://scenes/car.tscn") as PackedScene).instantiate() as Car
	_car.profile = _profile
	root.add_child(_car)
	_car.freeze = true
	_timer = 0.0


func _process(delta: float) -> bool:
	if _car == null:
		return false
	_timer += delta
	var model := _car.get_node_or_null("Model") as CarModel
	var measured: Array = model.measured_plates if model else [null, null]
	if measured[0] == null and measured[1] == null:
		if _timer > 60.0:
			print("%s: Modell nicht geladen" % _profile.id)
			_next()
		return false
	if _list:
		_list_candidates(model)
	var line := "%s:" % _profile.id
	for side in 2:
		var spot: Variant = measured[side]
		var label := "vorne" if side == 0 else "hinten"
		if spot == null:
			line += "  %s –" % label
			continue
		line += "  %s Mitte %s Größe %s Neigung %.0f°" % [label, (spot["center"] as Vector3).snapped(Vector3.ONE * 0.001),
			(spot["size"] as Vector2).snapped(Vector2.ONE * 0.001), spot["tilt"]]
		if side == 0:
			_profile.plate_front_position = (spot["center"] as Vector3).snapped(Vector3.ONE * 0.001)
			_profile.plate_front_size = (spot["size"] as Vector2).snapped(Vector2.ONE * 0.001)
			_profile.plate_front_tilt = snappedf(spot["tilt"], 0.1)
		else:
			_profile.plate_rear_position = (spot["center"] as Vector3).snapped(Vector3.ONE * 0.001)
			_profile.plate_rear_size = (spot["size"] as Vector2).snapped(Vector2.ONE * 0.001)
			_profile.plate_rear_tilt = snappedf(spot["tilt"], 0.1)
	print(line)
	if not _dry:
		_write_plates()
	_next()
	return false


## Nur die Kennzeichen-Zeilen im Profil ersetzen (ResourceSaver würde die ganze Datei neu schreiben
## und alle Werte weglassen, die dem Standard entsprechen)
func _write_plates() -> void:
	var file := FileAccess.open(_path, FileAccess.READ)
	var lines := file.get_as_text().split("\n")
	file.close()
	var kept: PackedStringArray = []
	for line in lines:
		if line.begins_with("plate_front_") or line.begins_with("plate_rear_"):
			continue
		kept.append(line)
	while not kept.is_empty() and kept[kept.size() - 1].strip_edges() == "":
		kept.remove_at(kept.size() - 1)
	var p := _profile
	kept.append("plate_front_position = %s" % _vec3(p.plate_front_position))
	kept.append("plate_front_size = Vector2(%s, %s)" % [_num(p.plate_front_size.x), _num(p.plate_front_size.y)])
	kept.append("plate_front_tilt = %s" % _num(p.plate_front_tilt))
	kept.append("plate_rear_position = %s" % _vec3(p.plate_rear_position))
	kept.append("plate_rear_size = Vector2(%s, %s)" % [_num(p.plate_rear_size.x), _num(p.plate_rear_size.y)])
	kept.append("plate_rear_tilt = %s" % _num(p.plate_rear_tilt))
	file = FileAccess.open(_path, FileAccess.WRITE)
	file.store_string("\n".join(kept) + "\n")
	file.close()
	print("  gespeichert in %s" % _path)


func _vec3(v: Vector3) -> String:
	return "Vector3(%s, %s, %s)" % [_num(v.x), _num(v.y), _num(v.z)]


func _num(x: float) -> String:
	return String.num(snappedf(x, 0.001), 3)


## Teile in Kennzeichengröße (0,25–0,7 m breit, 5–30 cm hoch, mittig, ganz vorn oder hinten)
func _list_candidates(model: CarModel) -> void:
	var to_car := _car.global_transform.affine_inverse()
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.visible:
			continue
		var xform := to_car * mi.global_transform
		for s in mi.mesh.get_surface_count():
			var verts: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			if verts.is_empty():
				continue
			var box := AABB(xform * verts[0], Vector3.ZERO)
			for v in verts:
				box = box.expand(xform * v)
			var c := box.get_center()
			if box.size.x < 0.25 or box.size.x > 0.7 or box.size.y < 0.05 or box.size.y > 0.3 or absf(c.x) > 0.15:
				continue
			if absf(c.z) < _profile.wheelbase * 0.5 + 0.3:
				continue
			var material := mi.get_active_material(s)
			print("   Kandidat %s: %s | %s  Mitte %s Größe %s" % ["vorne" if c.z > 0.0 else "hinten",
				material.resource_name if material else "-", mi.name, c.snapped(Vector3.ONE * 0.01), box.size.snapped(Vector3.ONE * 0.01)])
