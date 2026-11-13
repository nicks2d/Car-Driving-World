extends SceneTree
## Bereitet die Verkehrsmodelle (assets/models/verkehr/*) einmal für das Spiel vor und speichert
## sie als leichte PreparedModel-Ressource (prepared/model.res im Modell-Ordner). Das Spiel lädt
## nie die riesigen GLB-Dateien.
##
## Ablauf je Modell:
## 1. GLB laden, auf echte Länge skalieren, mittig auf den Boden (Nase zeigt schon nach +Z).
## 2. Teile nach Material einordnen: Lack, Glas, Scheinwerfer, Rücklicht, Reifen, Felge,
##    Innenraum/Technik (weg) oder übrige Karosserie.
## 3. Sichtbarkeitstest: Strahlen aus 48 Richtungen auf das Modell. Teile der Karosserie, die
##    kein Strahl trifft (Innenraum hinter den Scheiben, Motor, Achsen), fliegen raus.
## 4. Je Rolle eine Fläche (Karosserie mit Punktfarben aus den Materialfarben), mit Godots
##    Mesh-Vereinfachung auf das Budget: nah ≤ 60.000, mittel ≈ 10.000 Dreiecke. Räder je Ecke
##    als eigenes Mesh (drehen sich nah).
## 5. Vorschaubilder (Lack orange) nach prepared/ und Bericht im Terminal.
##
## Die Tankstelle (assets/models/raststaette/small_red_gas_station) ebenso: ohne eigene
## Asphaltfläche, die Ladenregale (Cube.006/.038, ~390.000 Dreiecke, Fotos echter Marken) werden
## schlichte Kästen, Bilder mit Marken (Regale, Werbetafel „MILES+“) werden neutral ersetzt,
## Materialien und Texturen bleiben, vereinfacht auf ca. 60.000 Dreiecke. Dazu einfache
## Kollisionsformen (Laden, Dachstützen, Zapfsäulen-Inseln).
##
## Aufruf (mit Fenster, wegen der Vorschaubilder), im Projektordner:
##   /Applications/Godot.app/Contents/MacOS/Godot --path . -s res://tools/setup_traffic_models.gd
##   ... -- --only=2014_audi_s3_limousine      (nur ein Modell)
##   ... -- --only=tankstelle                  (nur die Tankstelle)

const NEAR_BUDGET: int = 60000
const MID_BUDGET: int = 10000
## Je Rad (nah); in der mittleren Stufe sind die Räder einfache Zylinder
const WHEEL_NEAR_BUDGET: int = 2000
## Gewichte beim Verteilen des Budgets (der Lack trägt die Form, Kleinteile sieht man kaum)
const ROLE_WEIGHTS := {"paint": 2.2, "body": 0.8, "glass": 0.6, "cover": 0.5, "head": 0.5, "tail": 0.6}
## Eine vereinfachte Stufe muss so viel der Oberfläche behalten (sonst schrumpfen dünne Teile
## wie Türbleche weg und es entstehen Löcher)
const MIN_AREA_KEPT: float = 0.85
## Reifen/Felge zählt nur in Radnähe als Rad: unter dieser Höhe (m) und außen (Anteil der
## halben Breite), sonst Karosserie (z. B. Dichtungen aus demselben Gummi-Material)
const WHEEL_MAX_HEIGHT: float = 0.8
const WHEEL_MIN_SIDE: float = 0.45
## Glas vor dieser Länge (Anteil ab der Mitte) und unter dieser Höhe = Abdeckung der Leuchten
const COVER_FRONT: float = 0.38
const COVER_REAR: float = 0.40
const COVER_HEIGHT: float = 0.95
const RAY_DIRECTIONS: int = 48
const RAY_GRID: int = 140
## So oft muss ein Teil getroffen werden, um als sichtbar zu gelten
const MIN_HITS: int = 3
## Namensteile, die fast immer Innenraum oder Technik bedeuten
const INTERIOR_WORDS: Array[String] = ["interior", "seat", "cuero", "leather", "lether", "tela", "carpet",
	"tapete", "belt", "costura", "stitch", "dashboard", "steering", "engine", "rollcage", "speaker", "botoes",
	"button", "ponteiro", "cluster", "ecran", "screen", "chass"]
const PREVIEW_SIZE := Vector2i(900, 560)
const GAS_FOLDER := "res://assets/models/raststaette/small_red_gas_station"
const GAS_NEAR_BUDGET: int = 60000
const GAS_MID_BUDGET: int = 8000
## Bilder der Tankstelle mit Fotos echter Marken (Nummer = Bild in der GLB): Regale und Werbung
const GAS_SHELF_IMAGES: Array[String] = ["_11.", "_12.", "_13.", "_14."]
const GAS_AD_IMAGE: String = "_15."

## Je Modell: echte Länge (m) und Namensteile (Material oder Knoten, klein geschrieben verglichen)
## für die Rollen. Was nirgends passt, ist Karosserie (und muss den Sichtbarkeitstest bestehen).
const MODELS := {
	"2014_audi_s3_limousine": {"length": 4.47,
		"remove": ["intplastic", "intcrom", "plasticwheel", "plasticshine", "plasticint2", "windows_int",
			"teto", "mirror_symbol", "wheel"],
		"paint": ["carpaint"], "glass": ["vidros", "blackglass", "redclear"], "head": ["flights"], "tail": ["red2"],
		"tire": ["tyre"], "rim": ["material_23", "rimlogo"], "plate": ["ext_plate"]},
	"2021_honda_accord": {"length": 4.88,
		"remove": ["chrome_int", "seat_b", "wood", "panels", "red_plas", "indi", "phong15", "costura_tim",
			"int_glass", "phong19", "rubber"],
		"paint": ["paint"], "glass": ["glass"], "head": [], "tail": ["rear_light", "red_glass"],
		"tire": ["tyre_1", "tyre_2"], "rim": ["rim"], "plate": ["plate_phong9"]},
	# Weggelassen: Rennversion mit Überrollkäfig ohne Seitenscheiben, nach dem Vereinfachen fehlen
	# Teile der hinteren Tür (Stand 5.11.). Nick sucht ein anderes Modell.
	"kia_stinger": {"length": 4.83, "skip": true,
		"remove": ["edge_color", "rollcage"],
		"paint": ["material_7", "material_5", "body"], "glass": ["window"], "head": ["lamp0", "lamp1"],
		"tail": ["lamp_r0", "lamp_r1"],
		"tire": ["wheel1", "tyre_side", "profiel"], "rim": []},
	"2005_pontiac_aztek": {"length": 4.63,
		"remove": ["interior_", "gray_011", "white_057", "blue_053"],
		"paint": ["carpaint"], "glass": ["windowglass"], "head": ["clearglass"], "tail": ["redglass", "red_057"],
		"tire": ["tire"], "rim": ["rim", "brakedisk"], "plate": ["licplate"]},
	"2023_volkswagen_id_buzz_gtx": {"length": 4.71,
		"remove": [],
		"paint": ["material__2125713589"], "glass": ["glasss"], "head": ["front_light"],
		"tail": ["red_light", "glassred1"], "tire": ["rubber_rough"], "rim": ["steel2"],
		# Kein eigenes Kennzeichen, vorne aber eine Mulde in der Karosserie (Foto): Höhe und Breite
		"plate_front_height": 0.51, "plate_front_width": 0.45,
		# Reifen-Material steckt auch in Dichtungen: nur Teile in Radgröße sind Räder
		"wheel_part_max": 0.9},
	"2017_lexus_lc_500": {"length": 4.77,
		"remove": ["tela", "interiora", "interiortilling", "seatbelt", "carbon1"],
		"paint": ["painttnr"], "glass": ["window_material"], "head": ["lighta"], "tail": ["red_glass"],
		"tire": ["phong7", "phong6"], "rim": ["phong9", "phong8"], "plate": ["manufacturerplate"]},
}

var _only: String = ""
var _ray_params: PhysicsRayQueryParameters3D


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.trim_prefix("--only=")
	_run.call_deferred()


func _run() -> void:
	# Zwei Bilder warten, bis Fenster und Physik bereit sind
	await process_frame
	await process_frame
	for model_name: String in MODELS:
		if _only != "" and model_name != _only:
			continue
		if MODELS[model_name].get("skip", false):
			print("%s: weggelassen (siehe Kommentar in MODELS)" % model_name)
			continue
		var folder := "res://assets/models/verkehr/" + model_name
		var glb := _glb_in(folder)
		if glb == "":
			print("%s: keine .glb gefunden, übersprungen" % model_name)
			continue
		await _prepare_vehicle(model_name, folder, glb, MODELS[model_name])
	if _only == "" or _only == "tankstelle":
		var glb := _glb_in(GAS_FOLDER)
		if glb != "":
			await _prepare_gas_station(glb)
		else:
			print("Tankstelle: keine .glb gefunden, übersprungen")
	print("Fertig.")
	quit()


func _glb_in(folder: String) -> String:
	if not DirAccess.dir_exists_absolute(folder):
		return ""
	for file in DirAccess.get_files_at(folder):
		if file.get_extension().to_lower() == "glb":
			return folder.path_join(file)
	return ""


# ---------------------------------------------------------------------------
# Ein Auto
# ---------------------------------------------------------------------------

func _prepare_vehicle(model_name: String, folder: String, glb: String, config: Dictionary) -> void:
	var started := Time.get_ticks_msec()
	var scene := load(glb) as PackedScene
	var model := scene.instantiate() as Node3D
	root.add_child(model)
	await process_frame
	# Auf echte Länge skalieren, Mitte auf (0, 0), Boden auf 0
	var raw := _bounds(model)
	var factor: float = config["length"] / raw.size.z
	model.scale = Vector3.ONE * factor
	model.position = -Vector3(raw.get_center().x, raw.position.y, raw.get_center().z) * factor
	await process_frame
	# Teile einsammeln und einordnen
	var parts: Array = []
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null:
			continue
		for s in instance.mesh.get_surface_count():
			# Linien (Kanten aus SketchUp-Exporten) gehören nicht zur Oberfläche
			if instance.mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var material := instance.get_active_material(s)
			var material_name := material.resource_name if material else ""
			var part := {"instance": instance, "surface": s, "material": material, "name": material_name,
				"node": String(instance.name), "xform": instance.global_transform,
				"role": _role(material_name, String(instance.name), material, config), "hits": 0,
				"tris": _triangle_count(instance.mesh, s)}
			parts.append(part)
	var report := {}
	for part: Dictionary in parts:
		var line: Array = report.get(part["name"], [0, part["role"], 0])
		line[0] += part["tris"]
		report[part["name"]] = line
	# Sichtbarkeitstest
	await _ray_visibility(parts)
	# Nur Teile in Radgröße sind Räder (wenn das Modell Gummi auch für Dichtungen benutzt)
	if config.has("wheel_part_max"):
		for part: Dictionary in parts:
			if part["role"] in ["tire", "rim"]:
				var box: AABB = part["xform"] * (part["instance"] as MeshInstance3D).mesh.get_aabb()
				if maxf(box.size.y, box.size.z) > config["wheel_part_max"] or box.size.x > 0.5:
					part["role"] = "body"
	# Räder bleiben immer (oft verdecken Radkappen oder Kotflügel sie für fast alle Strahlen)
	for part: Dictionary in parts:
		if part["role"] == "body" and part["hits"] < MIN_HITS:
			part["role"] = "hidden"
		var line: Array = report[part["name"]]
		line[2] += part["hits"]
		if part["role"] == "hidden" and line[1] != "remove":
			line[1] = "unsichtbar"
	# Flächen bauen; Glas vorne und hinten unten ist die Abdeckung der Leuchten (fast klar)
	var groups := {}
	for role: String in ["body", "paint", "glass", "head", "tail", "tire", "rim"]:
		groups[role] = _merge(parts, [role])
	var glass_split := _split_covers(groups["glass"], config["length"])
	groups["glass"] = glass_split[0]
	groups["cover"] = glass_split[1]
	# Ohne eigenes Scheinwerfer-Material (Accord): was direkt hinter der vorderen Abdeckung
	# liegt (Reflektoren im Gehäuse), leuchtet als Scheinwerfer
	if _tris(groups["head"]) == 0 and _tris(groups["cover"]) > 0:
		var head_split := _heads_behind_cover(groups["body"], groups["cover"])
		groups["body"] = head_split[0]
		groups["head"] = head_split[1]
	# Reifen und Felgen: nur Dreiecke in Radnähe, der Rest gehört zur Karosserie
	var width := _arrays_bounds(_merge(parts, ["body", "paint"])).size.x
	var wheel_split := _split_wheel_zone(_merge(parts, ["tire", "rim"]), width)
	groups["body"] = _join(groups["body"], wheel_split[1])
	var wheel_data: Array = wheel_split[0]
	var prepared := PreparedModel.new()
	var all := _merge(parts, ["body", "paint", "glass", "head", "tail", "tire", "rim"])
	prepared.size = _arrays_bounds(all).size
	prepared.front_corner = _corner(groups["head"], true, prepared.size)
	prepared.rear_corner = _corner(groups["tail"], false, prepared.size)
	prepared.plate_spots = _plate_spots(_merge(parts, ["plate"]))
	# Mulde ohne eigenes Teil (Höhe aus MODELS): vorderste Stelle der Karosserie in dieser Höhe
	if config.has("plate_front_height") and (prepared.plate_spots[0] as Dictionary).is_empty():
		var height: float = config["plate_front_height"]
		var shell: Array = _merge(parts, ["body", "paint"])
		var front := -INF
		for v: Vector3 in shell[0] as PackedVector3Array:
			if absf(v.x) < 0.2 and absf(v.y - height) < 0.04:
				front = maxf(front, v.z)
		if not is_inf(front):
			prepared.plate_spots[0] = {"center": Vector3(0.0, height, front),
				"size": LicensePlate.fit_size(Vector2(config.get("plate_front_width", 0.52), 0.11)), "tilt": 0.0}
			print("   Kennzeichen vorne (Mulde): Mitte %s" % Vector3(0.0, height, front).snapped(Vector3.ONE * 0.01))
	# Räder je Ecke
	var corners := _split_corners(wheel_data)
	var near_wheel_tris := 0
	for c in 4:
		var corner: Array = corners[c]
		if _tris(corner) == 0:
			continue
		var center := _arrays_bounds(corner).get_center()
		var local := _offset(corner, -center)
		var simple := _simplify(local, WHEEL_NEAR_BUDGET)
		near_wheel_tris += _tris(simple)
		prepared.wheel_meshes.append(_mesh_from({"wheel": simple}))
		prepared.wheel_centers.append(center)
	# Nahe und mittlere Stufe: Budget nach Dreiecken und Gewicht der Rolle verteilen
	var roles: Array[String] = ["body", "paint", "glass", "cover", "head", "tail"]
	var near_parts := {}
	var mid_parts := {}
	var weighted_total := 0.0
	for role in roles:
		weighted_total += _tris(groups[role]) * float(ROLE_WEIGHTS[role])
	var wheels_mid := _wheel_cylinders(prepared.wheel_centers, corners)
	for role in roles:
		var tris := _tris(groups[role])
		if tris == 0:
			continue
		var share := tris * float(ROLE_WEIGHTS[role]) / maxf(weighted_total, 1.0)
		var near_budget := maxi(int((NEAR_BUDGET - near_wheel_tris) * share), mini(tris, 400))
		var mid_budget := maxi(int((MID_BUDGET - _tris(wheels_mid)) * share), mini(tris, 120))
		var keep_area := role == "paint" or role == "glass"
		near_parts[role] = _simplify(groups[role], near_budget, keep_area)
		mid_parts[role] = _simplify(groups[role], mid_budget, keep_area)
	if _tris(wheels_mid) > 0:
		mid_parts["wheels"] = wheels_mid
	prepared.near_mesh = _mesh_from(near_parts)
	prepared.mid_mesh = _mesh_from(mid_parts)
	prepared.info = {"source_triangles": _tris(all), "seconds": (Time.get_ticks_msec() - started) / 1000.0}
	model.queue_free()
	# Speichern und Vorschau
	DirAccess.make_dir_recursive_absolute(folder + "/prepared")
	var error := ResourceSaver.save(prepared, folder + "/prepared/model.res", ResourceSaver.FLAG_COMPRESS)
	await _previews(prepared, folder + "/prepared")
	var near_count := _mesh_tris(prepared.near_mesh) + near_wheel_tris
	print("== %s: %s, Größe %s, nah %d, mittel %d Dreiecke, Räder %d, %.0f s (Speichern: %s)" % [model_name,
		_thousands(_tris(all)) + " sichtbare von " + _thousands(_sum_tris(parts)), prepared.size.snapped(Vector3.ONE * 0.01),
		near_count, _mesh_tris(prepared.mid_mesh), prepared.wheel_meshes.size(),
		(Time.get_ticks_msec() - started) / 1000.0, error_string(error)])
	var names := report.keys()
	names.sort_custom(func(a: String, b: String) -> bool: return report[a][0] > report[b][0])
	for material_name: String in names.slice(0, 40):
		var line: Array = report[material_name]
		print("   %-36s %8d Dr.  %-10s  Treffer %d" % [material_name.substr(0, 36), line[0], line[1], line[2]])


## Lage der Original-Kennzeichen [vorne, hinten]: Mitte, Größe (Breite, Höhe) und Neigung in Grad
## aus den Punkten und Normalen der Kennzeichen-Teile, leeres Dictionary = keins
func _plate_spots(data: Array) -> Array:
	var verts: PackedVector3Array = data[0]
	var normals: PackedVector3Array = data[1]
	var result: Array = [{}, {}]
	for side in 2:
		var facing := 1.0 if side == 0 else -1.0
		var box := AABB()
		var count := 0
		var normal := Vector3.ZERO
		for k in verts.size():
			if verts[k].z * facing <= 0.0:
				continue
			box = AABB(verts[k], Vector3.ZERO) if count == 0 else box.expand(verts[k])
			count += 1
			if normals[k].z * facing > 0.3:
				normal += normals[k]
		if count < 3:
			continue
		var tilt := 0.0
		if normal.length() > 0.01:
			normal = normal.normalized()
			tilt = rad_to_deg(atan2(normal.y, absf(normal.z)))
		var height := box.size.y / maxf(cos(deg_to_rad(tilt)), 0.5)
		# Auf die Außenfläche des Originals (Ränder einer Mulde verdecken es sonst)
		var center := box.get_center()
		center.z = box.end.z if side == 0 else box.position.z
		result[side] = {"center": center, "size": LicensePlate.fit_size(Vector2(box.size.x, height)), "tilt": tilt}
		print("   Kennzeichen %s: Mitte %s, Größe %s, Neigung %.0f°" % ["vorne" if side == 0 else "hinten",
			box.get_center().snapped(Vector3.ONE * 0.01), Vector2(box.size.x, height).snapped(Vector2.ONE * 0.01), tilt])
	return result


## Rolle eines Teils nach Material- und Knotennamen
func _role(material_name: String, node_name: String, material: Material, config: Dictionary) -> String:
	var names := (material_name + " " + node_name).to_lower()
	var standard := material as BaseMaterial3D
	# Unsichtbare Hilfsflächen (z. B. Kantenlinien aus SketchUp)
	if standard and standard.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and standard.albedo_color.a < 0.05 \
			and not config.get("keep_transparent", false):
		return "remove"
	# Kennzeichen zuerst: Sie werden vermessen und dann weggelassen (das Spiel setzt sein eigenes)
	for role: String in ["plate", "remove", "paint", "glass", "head", "tail", "tire", "rim"]:
		for word: String in config.get(role, []):
			if word in names:
				return role
	for word in INTERIOR_WORDS:
		if word in names:
			return "remove"
	return "body"


func _triangle_count(mesh: Mesh, surface: int) -> int:
	var arrays := mesh.surface_get_arrays(surface)
	if arrays[Mesh.ARRAY_INDEX] != null:
		return (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3


func _sum_tris(parts: Array) -> int:
	var total := 0
	for part: Dictionary in parts:
		total += part["tris"]
	return total


func _bounds(model: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null:
			continue
		var box := instance.global_transform * instance.mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


# ---------------------------------------------------------------------------
# Sichtbarkeit per Strahlen
# ---------------------------------------------------------------------------

func _ray_visibility(parts: Array) -> void:
	var bodies := {}  # Instanz-ID des Körpers -> Teil
	var holder := Node3D.new()
	root.add_child(holder)
	var bounds := AABB()
	var first := true
	for part: Dictionary in parts:
		if part["role"] == "remove":
			continue
		var source: Mesh = (part["instance"] as MeshInstance3D).mesh
		var single := ArrayMesh.new()
		single.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, source.surface_get_arrays(part["surface"]))
		var shape := single.create_trimesh_shape()
		if shape == null:
			continue
		var body := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		body.transform = part["xform"]
		holder.add_child(body)
		bodies[body.get_instance_id()] = part
		var box: AABB = part["xform"] * single.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	await physics_frame
	await physics_frame
	var space := root.get_world_3d().direct_space_state
	_ray_params = PhysicsRayQueryParameters3D.new()
	_ray_params.hit_back_faces = true
	var center := bounds.get_center()
	var radius := bounds.size.length() * 0.75
	for k in RAY_DIRECTIONS:
		# Richtungen gleichmäßig auf der Kugel, kaum von unten (dort schaut niemand hin)
		var y := 1.0 - 1.6 * (k + 0.5) / RAY_DIRECTIONS
		var ring := sqrt(maxf(1.0 - y * y, 0.0))
		var angle := k * 2.39996
		var direction := Vector3(cos(angle) * ring, y, sin(angle) * ring).normalized()
		var u := direction.cross(Vector3.UP if absf(direction.y) < 0.9 else Vector3.RIGHT).normalized()
		var v := direction.cross(u).normalized()
		for i in RAY_GRID:
			for j in RAY_GRID:
				var offset := u * ((i + 0.5) / RAY_GRID - 0.5) * radius * 2.0 + v * ((j + 0.5) / RAY_GRID - 0.5) * radius * 2.0
				_ray_params.from = center + direction * radius * 2.0 + offset
				_ray_params.to = center - direction * radius * 2.0 + offset
				var hit := space.intersect_ray(_ray_params)
				if not hit.is_empty():
					var part: Variant = bodies.get(hit["collider_id"])
					if part != null:
						(part as Dictionary)["hits"] += 1
		if k % 8 == 7:
			await process_frame
	holder.queue_free()


# ---------------------------------------------------------------------------
# Flächen zusammenfassen und vereinfachen
# ---------------------------------------------------------------------------

## Alle Teile mit diesen Rollen zu einer Fläche: [Punkte, Normalen, Farben, Indizes]
func _merge(parts: Array, roles: Array) -> Array:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for part: Dictionary in parts:
		if not part["role"] in roles:
			continue
		var arrays := (part["instance"] as MeshInstance3D).mesh.surface_get_arrays(part["surface"])
		var xform: Transform3D = part["xform"]
		var part_verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var base := verts.size()
		verts.append_array(xform * part_verts)
		var part_normals: Variant = arrays[Mesh.ARRAY_NORMAL]
		var basis := xform.basis
		if part_normals != null:
			for n: Vector3 in part_normals:
				normals.append((basis * n).normalized())
		else:
			for i in part_verts.size():
				normals.append(Vector3.UP)
		var color := _material_color(part["material"])
		var first_color := colors.size()
		colors.resize(first_color + part_verts.size())
		for i in part_verts.size():
			colors[first_color + i] = color
		var part_indices: Variant = arrays[Mesh.ARRAY_INDEX]
		if part_indices != null:
			for index: int in part_indices:
				indices.append(base + index)
		else:
			for i in part_verts.size():
				indices.append(base + i)
	return [verts, normals, colors, indices]


## Farbe eines Materials (Grundfarbe mal mittlere Texturfarbe)
func _material_color(material: Material) -> Color:
	var standard := material as BaseMaterial3D
	if standard == null:
		return Color(0.5, 0.5, 0.5)
	var color := standard.albedo_color
	if standard.albedo_texture:
		var image := standard.albedo_texture.get_image()
		if image:
			if image.is_compressed():
				image.decompress()
			image.resize(1, 1, Image.INTERPOLATE_BILINEAR)
			color *= image.get_pixel(0, 0)
	color.a = 1.0
	return color


func _tris(data: Array) -> int:
	return (data[3] as PackedInt32Array).size() / 3


func _arrays_bounds(data: Array) -> AABB:
	var verts: PackedVector3Array = data[0]
	if verts.is_empty():
		return AABB()
	var result := AABB(verts[0], Vector3.ZERO)
	for p in verts:
		result = result.expand(p)
	return result


func _offset(data: Array, shift: Vector3) -> Array:
	var verts: PackedVector3Array = data[0]
	var moved := PackedVector3Array()
	moved.resize(verts.size())
	for i in verts.size():
		moved[i] = verts[i] + shift
	return [moved, data[1], data[2], data[3]]


## Glas in Scheiben und Leuchten-Abdeckungen (vorne/hinten, unterhalb der Scheiben) teilen
func _split_covers(data: Array, length: float) -> Array:
	var verts: PackedVector3Array = data[0]
	var indices: PackedInt32Array = data[3]
	var window_indices := PackedInt32Array()
	var cover_indices := PackedInt32Array()
	for t in indices.size() / 3:
		var a := indices[t * 3]
		var b := indices[t * 3 + 1]
		var c := indices[t * 3 + 2]
		var middle := (verts[a] + verts[b] + verts[c]) / 3.0
		var cover := middle.y < COVER_HEIGHT and (middle.z > length * COVER_FRONT or middle.z < -length * COVER_REAR)
		if cover:
			cover_indices.append_array([a, b, c])
		else:
			window_indices.append_array([a, b, c])
	return [_compact([verts, data[1], data[2], window_indices]), _compact([verts, data[1], data[2], cover_indices])]


## Karosserie in [Rest, Scheinwerfer] teilen: Scheinwerfer = Dreiecke im Raum der vorderen
## Leuchten-Abdeckung (je Seite, bis 15 cm dahinter)
func _heads_behind_cover(body: Array, cover: Array) -> Array:
	var boxes: Array[AABB] = []
	for side: float in [1.0, -1.0]:
		var box := AABB()
		var found := false
		for p in (cover[0] as PackedVector3Array):
			if p.z > 0.0 and p.x * side > 0.0:
				box = box.expand(p) if found else AABB(p, Vector3.ZERO)
				found = true
		if found:
			box = box.grow(0.03)
			box.position.z -= 0.15
			box.size.z += 0.15
			boxes.append(box)
	var verts: PackedVector3Array = body[0]
	var indices: PackedInt32Array = body[3]
	var rest_indices := PackedInt32Array()
	var head_indices := PackedInt32Array()
	for t in indices.size() / 3:
		var a := indices[t * 3]
		var b := indices[t * 3 + 1]
		var c := indices[t * 3 + 2]
		var middle := (verts[a] + verts[b] + verts[c]) / 3.0
		var inside := false
		for box in boxes:
			inside = inside or box.has_point(middle)
		if inside:
			head_indices.append_array([a, b, c])
		else:
			rest_indices.append_array([a, b, c])
	return [_compact([verts, body[1], body[2], rest_indices]), _compact([verts, body[1], body[2], head_indices])]


## Reifen/Felge in Rad-Dreiecke (unten, außen) und den Rest teilen
func _split_wheel_zone(data: Array, width: float) -> Array:
	var verts: PackedVector3Array = data[0]
	var indices: PackedInt32Array = data[3]
	var wheel_indices := PackedInt32Array()
	var other_indices := PackedInt32Array()
	for t in indices.size() / 3:
		var a := indices[t * 3]
		var b := indices[t * 3 + 1]
		var c := indices[t * 3 + 2]
		var middle := (verts[a] + verts[b] + verts[c]) / 3.0
		if middle.y < WHEEL_MAX_HEIGHT and absf(middle.x) > width * 0.5 * WHEEL_MIN_SIDE:
			wheel_indices.append_array([a, b, c])
		else:
			other_indices.append_array([a, b, c])
	return [_compact([verts, data[1], data[2], wheel_indices]), _compact([verts, data[1], data[2], other_indices])]


## Zwei Flächen-Daten aneinanderhängen
func _join(first: Array, second: Array) -> Array:
	var verts: PackedVector3Array = (first[0] as PackedVector3Array).duplicate()
	var normals: PackedVector3Array = (first[1] as PackedVector3Array).duplicate()
	var colors: PackedColorArray = (first[2] as PackedColorArray).duplicate()
	var indices: PackedInt32Array = (first[3] as PackedInt32Array).duplicate()
	var base := verts.size()
	verts.append_array(second[0])
	normals.append_array(second[1])
	colors.append_array(second[2])
	for index: int in second[3]:
		indices.append(base + index)
	return [verts, normals, colors, indices]


## Fläche der Dreiecke (zum Prüfen, ob eine vereinfachte Stufe Teile verliert)
func _area(verts: PackedVector3Array, indices: PackedInt32Array) -> float:
	var total := 0.0
	for t in indices.size() / 3:
		var a := verts[indices[t * 3]]
		total += (verts[indices[t * 3 + 1]] - a).cross(verts[indices[t * 3 + 2]] - a).length()
	return total * 0.5


## Einfache Rad-Zylinder (12 Seiten) für die mittlere Stufe, Größe aus den echten Rädern
func _wheel_cylinders(centers: PackedVector3Array, corners: Array) -> Array:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var dark := Color(0.06, 0.06, 0.07)
	var k := 0
	for c in 4:
		if _tris(corners[c]) == 0:
			continue
		var box := _arrays_bounds(corners[c])
		var center := centers[k]
		k += 1
		# Radius aus der Höhe (die Länge kann durch Nachbarteile größer wirken)
		var radius := box.size.y * 0.5
		var half := box.size.x * 0.5
		var sides := 12
		for side in sides:
			var a0 := TAU * side / sides
			var a1 := TAU * (side + 1) / sides
			var p0 := Vector3(0.0, cos(a0), sin(a0)) * radius
			var p1 := Vector3(0.0, cos(a1), sin(a1)) * radius
			var n := Vector3(0.0, cos((a0 + a1) * 0.5), sin((a0 + a1) * 0.5))
			# Lauffläche
			var base := verts.size()
			for p: Vector3 in [p0 + Vector3(-half, 0, 0), p0 + Vector3(half, 0, 0), p1 + Vector3(half, 0, 0), p1 + Vector3(-half, 0, 0)]:
				verts.append(center + p)
				normals.append(n)
				colors.append(dark)
			# Godot zeichnet Dreiecke im Uhrzeigersinn (von außen gesehen) als Vorderseite
			indices.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
			# Seitenflächen: dunkler Reifen, außen etwas davor eine kleinere helle Felge
			for s: float in [1.0, -1.0]:
				var outside := s * center.x > 0.0
				for layer in (2 if outside else 1):
					var scale := 1.0 if layer == 0 else 0.62
					var x := s * (half + 0.004 * layer)
					base = verts.size()
					for p: Vector3 in [Vector3(x, 0, 0), p0 * scale + Vector3(x, 0, 0), p1 * scale + Vector3(x, 0, 0)]:
						verts.append(center + p)
						normals.append(Vector3(s, 0, 0))
						colors.append(dark if layer == 0 else Color(0.5, 0.51, 0.53))
					indices.append_array([base, base + 2, base + 1] if s > 0.0 else [base, base + 1, base + 2])
	return [verts, normals, colors, indices]


## Räder auf die vier Ecken aufteilen (nach der Lage jedes Dreiecks)
func _split_corners(data: Array) -> Array:
	var verts: PackedVector3Array = data[0]
	var indices: PackedInt32Array = data[3]
	var corner_indices: Array = [PackedInt32Array(), PackedInt32Array(), PackedInt32Array(), PackedInt32Array()]
	for t in indices.size() / 3:
		var a := indices[t * 3]
		var b := indices[t * 3 + 1]
		var c := indices[t * 3 + 2]
		var middle := (verts[a] + verts[b] + verts[c]) / 3.0
		# 0 vorne links, 1 vorne rechts, 2 hinten links, 3 hinten rechts (links = +X)
		var corner := (0 if middle.z > 0.0 else 2) + (0 if middle.x > 0.0 else 1)
		var list: PackedInt32Array = corner_indices[corner]
		list.append_array([a, b, c])
		corner_indices[corner] = list
	var result: Array = []
	for c in 4:
		result.append(_compact([verts, data[1], data[2], corner_indices[c]]))
	return result


## Nur die benutzten Punkte behalten
func _compact(data: Array) -> Array:
	var verts: PackedVector3Array = data[0]
	var normals: PackedVector3Array = data[1]
	var colors: PackedColorArray = data[2]
	var indices: PackedInt32Array = data[3]
	var remap := PackedInt32Array()
	remap.resize(verts.size())
	remap.fill(-1)
	var new_verts := PackedVector3Array()
	var new_normals := PackedVector3Array()
	var new_colors := PackedColorArray()
	var new_indices := PackedInt32Array()
	new_indices.resize(indices.size())
	for i in indices.size():
		var old := indices[i]
		if remap[old] == -1:
			remap[old] = new_verts.size()
			new_verts.append(verts[old])
			new_normals.append(normals[old])
			new_colors.append(colors[old])
		new_indices[i] = remap[old]
	return [new_verts, new_normals, new_colors, new_indices]


## Auf höchstens budget Dreiecke vereinfachen (Godots Mesh-Vereinfachung, meshoptimizer).
## keep_area: die Oberfläche muss weitgehend erhalten bleiben (Lack, Glas)
func _simplify(data: Array, budget: int, keep_area: bool = false) -> Array:
	if _tris(data) <= budget or _tris(data) == 0:
		return _compact(data)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = data[0]
	arrays[Mesh.ARRAY_NORMAL] = data[1]
	arrays[Mesh.ARRAY_COLOR] = data[2]
	arrays[Mesh.ARRAY_INDEX] = data[3]
	# Erst gleiche Punkte verschweißen (sonst kann die Vereinfachung kaum etwas zusammenlegen)
	var tool := SurfaceTool.new()
	tool.create_from_arrays(arrays)
	tool.index()
	var welded := tool.commit_to_arrays()
	# Die gröbste Stufe der Kette bleibt dicht; Normalen ganz zu verschmelzen ging weiter, riss
	# aber Löcher in Stoßstangen und Türen. Lieber etwas über dem Budget.
	return _compact(_lod_for_budget(welded, budget, 25.0, keep_area))


## Godots LOD-Kette (meshoptimizer) erzeugen und die erste Stufe nehmen, die ins Budget passt
## (sonst die gröbste). Gibt [Punkte, Normalen, Farben, Indizes] der Importer-Daten zurück.
func _lod_for_budget(welded: Array, budget: int, merge_angle: float, keep_area: bool) -> Array:
	var importer := ImporterMesh.new()
	importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, welded)
	importer.generate_lods(merge_angle, merge_angle, [])
	var arrays := importer.get_surface_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var best: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var full_area := _area(verts, best) if keep_area else 0.0
	var sizes := []
	for lod in importer.get_surface_lod_count(0):
		var candidate := importer.get_surface_lod_indices(0, lod)
		# Lieber über dem Budget bleiben als Teile verlieren (Löcher)
		if keep_area and _area(verts, candidate) < full_area * MIN_AREA_KEPT:
			break
		best = candidate
		sizes.append(best.size() / 3)
		if best.size() / 3 <= budget * 1.3:
			break
	if OS.get_environment("LOD_DEBUG") != "":
		print("  vereinfachen %d -> Ziel %d (Winkel %.0f): Stufen %s" % [(arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3,
			budget, merge_angle, sizes])
	return [arrays[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_NORMAL], arrays[Mesh.ARRAY_COLOR], best]


func _mesh_from(surfaces: Dictionary) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for role: String in surfaces:
		var data: Array = surfaces[role]
		if _tris(data) == 0:
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = data[0]
		arrays[Mesh.ARRAY_NORMAL] = data[1]
		arrays[Mesh.ARRAY_COLOR] = data[2]
		arrays[Mesh.ARRAY_INDEX] = data[3]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_name(mesh.get_surface_count() - 1, role)
	return mesh


func _mesh_tris(mesh: ArrayMesh) -> int:
	var total := 0
	for i in mesh.get_surface_count():
		total += (mesh.surface_get_arrays(i)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return total


## Äußerste linke Ecke der Leuchten (vorne: größtes z, hinten: kleinstes z)
func _corner(data: Array, front: bool, size: Vector3) -> Vector3:
	if _tris(data) == 0:
		return Vector3(size.x * 0.5 - 0.15, 0.7, size.z * (0.5 if front else -0.5))
	var box := _arrays_bounds(data)
	return Vector3(box.end.x - 0.08, box.get_center().y, box.end.z if front else box.position.z)


func _thousands(value: int) -> String:
	var text := str(value)
	var result := ""
	while text.length() > 3:
		result = "." + text.substr(text.length() - 3) + result
		text = text.substr(0, text.length() - 3)
	return text + result


# ---------------------------------------------------------------------------
# Tankstelle
# ---------------------------------------------------------------------------

func _prepare_gas_station(glb: String) -> void:
	var started := Time.get_ticks_msec()
	var model := (load(glb) as PackedScene).instantiate() as Node3D
	root.add_child(model)
	await process_frame
	var shelf_texture := _neutral_shelf_texture()
	var ad_texture := _neutral_ad_texture()
	# Teile einsammeln: ohne Asphalt, Regale merken (werden Kästen)
	var parts: Array = []
	var shelves := {}  # Knoten -> AABB
	var replaced_images := 0
	var materials := {}  # Original-Material -> Kopie für das Spiel
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		var node_name := String(instance.name).to_lower()
		for s in instance.mesh.get_surface_count():
			if instance.mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var material := instance.get_active_material(s)
			var material_name := material.resource_name.to_lower() if material else ""
			var box: AABB = instance.global_transform * instance.mesh.get_aabb()
			if material_name == "asphalt":
				continue
			if node_name.begins_with("cube_006") or node_name.begins_with("cube_038"):
				var key := node_name.substr(0, 8)
				shelves[key] = (shelves[key] as AABB).merge(box) if shelves.has(key) else box
				continue
			if material and not materials.has(material):
				var copy := material.duplicate() as BaseMaterial3D
				if copy and copy.albedo_texture:
					var file := copy.albedo_texture.resource_path.get_file()
					for marker_text in GAS_SHELF_IMAGES:
						if marker_text in file:
							copy.albedo_texture = shelf_texture
							replaced_images += 1
					if GAS_AD_IMAGE in file:
						copy.albedo_texture = ad_texture
						replaced_images += 1
				materials[material] = copy
			parts.append({"instance": instance, "surface": s, "material": material, "box": box,
				"node": node_name, "tris": _triangle_count(instance.mesh, s)})
	# Je Material eine Fläche (mit UVs und Texturen)
	var by_material := {}
	for part: Dictionary in parts:
		var list: Array = by_material.get(part["material"], [])
		list.append(part)
		by_material[part["material"]] = list
	# Je Material zweimal: alles (nah) und nur größere Teile (mittel, Kleinkram sieht man nicht)
	var merged: Array = []  # [Arrays nah, Arrays mittel (oder leer), Material, Dreiecke]
	var total := 0
	for material: Variant in by_material:
		var all_parts := SurfaceTool.new()
		var large_parts := SurfaceTool.new()
		var has_large := false
		for part: Dictionary in by_material[material]:
			var mesh: Mesh = (part["instance"] as MeshInstance3D).mesh
			var xform: Transform3D = (part["instance"] as Node3D).global_transform
			all_parts.append_from(mesh, part["surface"], xform)
			if (part["box"] as AABB).size.length() > 1.5:
				large_parts.append_from(mesh, part["surface"], xform)
				has_large = true
		# Indizes erzeugen (append_from liefert oft nur Punkte) und gleiche Punkte verschweißen
		all_parts.index()
		var arrays := all_parts.commit_to_arrays()
		var mid_arrays: Array = []
		if has_large:
			large_parts.index()
			mid_arrays = large_parts.commit_to_arrays()
		var tris := (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		total += tris
		merged.append([arrays, mid_arrays, materials.get(material), tris])
	# Regale als schlichte Kästen mit neutralem Regalbild
	var shelf_material := StandardMaterial3D.new()
	shelf_material.albedo_texture = shelf_texture
	shelf_material.roughness = 0.8
	for key: String in shelves:
		var box_arrays := _box_arrays(shelves[key])
		merged.append([box_arrays, box_arrays, shelf_material, 12])
	# Vereinfachen: nah ~60.000, mittel ~8.000 Dreiecke (nur große Flächen)
	var near := ArrayMesh.new()
	var mid := ArrayMesh.new()
	for entry: Array in merged:
		var tris: int = entry[3]
		var share := float(tris) / maxf(total, 1.0)
		for stage in 2:
			var arrays: Array = entry[stage]
			if arrays.is_empty():
				continue
			var stage_tris := (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			var budget := maxi(int((GAS_NEAR_BUDGET if stage == 0 else GAS_MID_BUDGET) * share), 24)
			var reduced := arrays if stage_tris <= budget else _simplify_full(arrays, budget)
			var mesh := near if stage == 0 else mid
			if (reduced[Mesh.ARRAY_INDEX] as PackedInt32Array).size() < 3:
				continue
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, reduced)
			var material: Material = entry[2]
			mesh.surface_set_material(mesh.get_surface_count() - 1, material)
			if material:
				mesh.surface_set_name(mesh.get_surface_count() - 1, material.resource_name)
	var prepared := PreparedModel.new()
	prepared.near_mesh = near
	prepared.mid_mesh = mid
	prepared.size = _bounds_of_parts(parts).size
	prepared.collision_boxes = _gas_collision(parts)
	# Lichte Höhe: Unterkante der tiefsten Teile über den Zapfsäulen-Inseln (Dach, Leuchtkästen;
	# das Dach liegt auf der Seite x > 0, der Laden auf x < 0)
	var clearance := INF
	for part: Dictionary in parts:
		var box: AABB = part["box"]
		if box.position.y > 3.0 and box.size.x > 2.0 and box.get_center().x > 0.0:
			clearance = minf(clearance, box.position.y)
	prepared.info = {"clearance": clearance, "replaced_images": replaced_images, "source_triangles": total,
		"emissive": ["glowin", "glowin.001", "Material.026", "Material.027", "Material.029"]}
	model.queue_free()
	DirAccess.make_dir_recursive_absolute(GAS_FOLDER + "/prepared")
	var error := ResourceSaver.save(prepared, GAS_FOLDER + "/prepared/model.res", ResourceSaver.FLAG_COMPRESS)
	await _gas_previews(prepared, GAS_FOLDER + "/prepared")
	print("== Tankstelle: %s Dreiecke (ohne Asphalt und Regale), nah %d, mittel %d, Größe %s, lichte Höhe %.2f m, %d Kollisionsformen, %d Bilder ersetzt, %d Regale als Kasten, %.0f s (Speichern: %s)" % [
		_thousands(total), _mesh_tris(near), _mesh_tris(mid), prepared.size.snapped(Vector3.ONE * 0.1), clearance,
		prepared.collision_boxes.size(), replaced_images, shelves.size(), (Time.get_ticks_msec() - started) / 1000.0,
		error_string(error)])


## Vereinfachen mit allen Werten (UVs, Tangenten): Godots LOD-Kette, erste Stufe im Budget
func _simplify_full(arrays: Array, budget: int) -> Array:
	var importer := ImporterMesh.new()
	importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
	importer.generate_lods(25.0, 60.0, [])
	var result := importer.get_surface_arrays(0)
	var best: PackedInt32Array = result[Mesh.ARRAY_INDEX]
	for lod in importer.get_surface_lod_count(0):
		best = importer.get_surface_lod_indices(0, lod)
		if best.size() / 3 <= budget * 1.3:
			break
	var compacted := result.duplicate()
	compacted[Mesh.ARRAY_INDEX] = best
	# Nicht mehr benutzte Punkte bleiben drin; die Tankstelle gibt es nur einmal im Speicher
	return compacted


func _bounds_of_parts(parts: Array) -> AABB:
	var result := AABB()
	for i in parts.size():
		var box: AABB = parts[i]["box"]
		result = box if i == 0 else result.merge(box)
	return result


## Kollision: Laden (Wände), Dachstützen (schmale hohe Teile), Zapfsäulen-Inseln und Säulen
func _gas_collision(parts: Array) -> Array[AABB]:
	var boxes: Array[AABB] = []
	var shop := AABB()
	var has_shop := false
	for part: Dictionary in parts:
		var box: AABB = part["box"]
		var node: String = part["node"]
		if node.begins_with("plane_001"):
			shop = shop.merge(box) if has_shop else box
			has_shop = true
		elif node.begins_with("plane_003") or node.begins_with("plane_004"):
			boxes.append(box)
		elif box.size.y > 1.5 and box.size.y < 3.0 and box.size.x < 3.0 and box.size.z < 3.0 and box.position.y < 0.5:
			# Zapfsäulen (ca. 2,2 m hoch)
			boxes.append(box)
		elif node.begins_with("cube_002"):
			# Die Dachstützen stecken in einem Teil: nach Lage auf 4 Säulen aufteilen
			boxes.append_array(_pillars(part))
	if has_shop:
		boxes.append(shop)
	return boxes


func _pillars(part: Dictionary) -> Array[AABB]:
	var arrays := (part["instance"] as MeshInstance3D).mesh.surface_get_arrays(part["surface"])
	var xform: Transform3D = (part["instance"] as Node3D).global_transform
	var clusters := {}  # Raster 3 m -> AABB
	for p: Vector3 in xform * (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array):
		var key := Vector2i(floori(p.x / 3.0), floori(p.z / 3.0))
		clusters[key] = (clusters[key] as AABB).expand(p) if clusters.has(key) else AABB(p, Vector3.ZERO)
	var result: Array[AABB] = []
	for key: Vector2i in clusters:
		var box: AABB = clusters[key]
		if box.size.y > 2.0:
			result.append(box)
	return result


## Kasten (mit UVs) für ein ersetztes Regal
func _box_arrays(box: AABB) -> Array:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := box.get_center()
	var h := box.size * 0.5
	for axis in 3:
		for s: float in [1.0, -1.0]:
			var n := Vector3.ZERO
			n[axis] = s
			var u := Vector3.ZERO
			u[(axis + 1) % 3] = 1.0
			var v := Vector3.ZERO
			v[(axis + 2) % 3] = 1.0
			var corners: Array[Vector3] = []
			var uvs: Array[Vector2] = [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
			for q: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				corners.append(c + n * h + u * h * q.x + v * h * q.y)
			var order: Array = [0, 2, 1, 0, 3, 2] if s > 0.0 else [0, 1, 2, 0, 2, 3]
			for k: int in order:
				tool.set_normal(n)
				tool.set_uv(uvs[k])
				tool.add_vertex(corners[k])
	tool.generate_tangents()
	tool.index()
	return tool.commit_to_arrays()


## Neutrales Regalbild: Reihen bunter Packungen ohne Schrift
func _neutral_shelf_texture() -> ImageTexture:
	var image := Image.create(512, 256, false, Image.FORMAT_RGB8)
	image.fill(Color(0.85, 0.86, 0.88))
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var palette: Array[Color] = [Color("#C0392B"), Color("#E67E22"), Color("#F1C40F"), Color("#27AE60"),
		Color("#2980B9"), Color("#8E44AD"), Color("#ECF0F1"), Color("#7F8C8D"), Color("#D35400"), Color("#16A085")]
	for row in 4:
		var y := row * 64
		image.fill_rect(Rect2i(0, y + 56, 512, 8), Color(0.6, 0.62, 0.65))
		var x := 2
		while x < 510:
			var width := rng.randi_range(14, 34)
			var height := rng.randi_range(30, 52)
			image.fill_rect(Rect2i(x, y + 56 - height, mini(width, 510 - x), height), palette[rng.randi() % palette.size()])
			x += width + 2
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


## Neutrale Werbetafel: Farbverlauf mit einer Kaffeetasse (statt der Werbung „MILES+“)
func _neutral_ad_texture() -> ImageTexture:
	var image := Image.create(256, 256, false, Image.FORMAT_RGB8)
	for y in 256:
		for x in 256:
			var t := (x + y) / 510.0
			image.set_pixel(x, y, Color("#B3261E").lerp(Color("#E8892B"), t))
	var white := Color(0.97, 0.95, 0.9)
	# Tasse: Kelch, Henkel, Untertasse, Dampf
	for y in range(110, 175):
		var half := int(lerpf(42.0, 30.0, (y - 110) / 65.0))
		image.fill_rect(Rect2i(128 - half, y, half * 2, 1), white)
	for a in 64:
		var angle := TAU * a / 64.0
		for r in range(14, 20):
			image.set_pixel(int(170 + cos(angle) * r), int(135 + sin(angle) * r), white)
	image.fill_rect(Rect2i(78, 178, 100, 7), white)
	for k in 3:
		for y in range(70, 102):
			image.set_pixel(int(108 + k * 20 + sin(y * 0.25 + k) * 4), y, white)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


func _gas_previews(prepared: PreparedModel, folder: String) -> void:
	var viewport := SubViewport.new()
	viewport.size = PREVIEW_SIZE
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.55, 0.62, 0.72)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.75, 0.78, 0.85)
	environment.environment.ambient_light_energy = 0.7
	viewport.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, 30.0, 0.0)
	viewport.add_child(sun)
	var camera := Camera3D.new()
	camera.fov = 45.0
	viewport.add_child(camera)
	var instance := MeshInstance3D.new()
	viewport.add_child(instance)
	for view: Array in [["nah", 0, Vector3(30.0, 14.0, 34.0)], ["nah_laden", 0, Vector3(-30.0, 8.0, 22.0)],
			["mittel", 1, Vector3(30.0, 14.0, 34.0)]]:
		instance.mesh = prepared.near_mesh if view[1] == 0 else prepared.mid_mesh
		camera.position = view[2]
		camera.look_at(Vector3(2.0, 2.0, 0.0))
		for i in 3:
			await process_frame
		viewport.get_texture().get_image().save_png(ProjectSettings.globalize_path(folder) + "/preview_%s.png" % view[0])
	viewport.queue_free()


# ---------------------------------------------------------------------------
# Vorschaubilder
# ---------------------------------------------------------------------------

func _previews(prepared: PreparedModel, folder: String) -> void:
	var viewport := SubViewport.new()
	viewport.size = PREVIEW_SIZE
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.62, 0.66, 0.72)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.75, 0.78, 0.85)
	environment.environment.ambient_light_energy = 0.6
	viewport.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	viewport.add_child(sun)
	var camera := Camera3D.new()
	camera.fov = 35.0
	viewport.add_child(camera)
	var holder := Node3D.new()
	viewport.add_child(holder)
	for stage in 2:
		for child in holder.get_children():
			child.queue_free()
		var instance := MeshInstance3D.new()
		instance.mesh = prepared.near_mesh if stage == 0 else prepared.mid_mesh
		_preview_materials(instance)
		holder.add_child(instance)
		if stage == 0:
			for w in prepared.wheel_meshes.size():
				var wheel := MeshInstance3D.new()
				wheel.mesh = prepared.wheel_meshes[w]
				wheel.position = prepared.wheel_centers[w]
				wheel.material_override = _vertex_color_material()
				holder.add_child(wheel)
		for view: Array in [["vorne", Vector3(4.2, 1.7, 6.0)], ["hinten", Vector3(-4.6, 1.9, -5.6)], ["seite", Vector3(-8.5, 1.0, 0.0)]]:
			if stage == 1 and view[0] != "vorne":
				continue
			camera.position = view[1]
			camera.look_at(Vector3(0.0, 0.7, 0.0))
			await process_frame
			await process_frame
			await process_frame
			var image := viewport.get_texture().get_image()
			image.save_png(ProjectSettings.globalize_path(folder) + "/preview_%s_%s.png" % ["nah" if stage == 0 else "mittel", view[0]])
	viewport.queue_free()


func _preview_materials(instance: MeshInstance3D) -> void:
	var mesh := instance.mesh as ArrayMesh
	for i in mesh.get_surface_count():
		var role := mesh.surface_get_name(i)
		var material := _vertex_color_material()
		match role:
			"paint":
				material = StandardMaterial3D.new()
				material.albedo_color = Color(1.0, 0.45, 0.05)
				material.metallic = 0.4
				material.roughness = 0.35
			"glass":
				material = StandardMaterial3D.new()
				material.albedo_color = Color(0.08, 0.1, 0.13)
				material.roughness = 0.1
			"cover":
				material = StandardMaterial3D.new()
				material.albedo_color = Color(0.9, 0.95, 1.0, 0.2)
				material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				material.roughness = 0.05
			"head":
				material = StandardMaterial3D.new()
				material.albedo_color = Color(0.2, 0.9, 1.0)
				material.emission_enabled = true
				material.emission = Color(0.2, 0.9, 1.0)
			"tail":
				material = StandardMaterial3D.new()
				material.albedo_color = Color(1.0, 0.05, 0.05)
				material.emission_enabled = true
				material.emission = Color(1.0, 0.05, 0.05)
		# Viele Teile sind nur von einer Seite gebaut (im Original doppelseitig)
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		instance.set_surface_override_material(i, material)


func _vertex_color_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.6
	return material
