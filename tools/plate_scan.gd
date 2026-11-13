extends SceneTree
## Sucht in allen Automodellen (Garage: cars/*.tres, Verkehr: assets/models/verkehr/*) nach
## eigenen Kennzeichen: Flächen, deren Material-, Mesh-, Knoten- oder Texturname nach Kennzeichen
## klingt. Ausgabe je Fund: Name und Lage (Modell-Koordinaten). Für Teil 6 (Kennzeichen).
## Aufruf: Godot --headless --path . -s res://tools/plate_scan.gd [-- --all]  (--all: alle Materialnamen)

const WORDS: Array[String] = ["plate", "licen", "kennz", "nummer", "registr", "number", "kenteken",
	"matric", "targa", "placa", "badge_rear", "lp_", "_lp"]


func _initialize() -> void:
	var show_all := "--all" in OS.get_cmdline_user_args()
	var paths: Array[String] = []
	for file in DirAccess.get_files_at("res://cars"):
		if file.ends_with(".tres"):
			var profile := load("res://cars/" + file) as CarProfile
			if profile:
				var path := CarModel.model_path(profile)
				if path != "":
					paths.append(path)
	for folder in DirAccess.get_directories_at("res://assets/models/verkehr"):
		for file in DirAccess.get_files_at("res://assets/models/verkehr/" + folder):
			if file.get_extension() in ["glb", "gltf"]:
				paths.append("res://assets/models/verkehr/%s/%s" % [folder, file])
	for path in paths:
		var scene := load(path) as PackedScene
		if scene == null:
			print("%s: nicht ladbar" % path)
			continue
		var root := scene.instantiate()
		var names := {}
		print("== %s" % path)
		var stack: Array[Node] = [root]
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			stack.append_array(node.get_children())
			var mi := node as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			for s in mi.mesh.get_surface_count():
				var material := mi.get_active_material(s)
				var texture := ""
				if material is BaseMaterial3D and (material as BaseMaterial3D).albedo_texture:
					texture = (material as BaseMaterial3D).albedo_texture.resource_path.get_file()
				var label := "%s | %s | %s | %s" % [material.resource_name if material else "-", mi.mesh.resource_name, mi.name, texture]
				names[material.resource_name if material else "-"] = true
				# Form wie ein Kennzeichen: flach, mittig, 3- bis 6-mal so breit wie hoch (egal wie es heißt)
				if "--shape" in OS.get_cmdline_user_args():
					var box := _surface_aabb(mi, s, root)
					var depth := minf(box.size.z, box.size.x)
					var ratio := box.size.x / maxf(box.size.y, 0.0001)
					if absf(box.get_center().x) < 0.08 * maxf(box.size.x, 0.01) * 10.0 and ratio > 2.8 and ratio < 6.5 \
							and box.size.z < box.size.x * 0.35:
						print("   FORM: %s  Mitte %s Größe %s" % [label.substr(0, 150), box.get_center().snapped(Vector3.ONE * 0.01), box.size.snapped(Vector3.ONE * 0.01)])
				var low := label.to_lower()
				for word in WORDS:
					if low.contains(word):
						var aabb := _surface_aabb(mi, s, root)
						print("   FUND: %s  Mitte %s Größe %s" % [label, aabb.get_center().snapped(Vector3.ONE * 0.01), aabb.size.snapped(Vector3.ONE * 0.01)])
						break
		if show_all:
			print("   Materialien: ", ", ".join(PackedStringArray(names.keys())))
		root.free()
	quit()


## Lage einer Fläche im Modell (Koordinaten des Modell-Wurzelknotens)
func _surface_aabb(mi: MeshInstance3D, surface: int, root: Node) -> AABB:
	var xform := Transform3D()
	var node: Node = mi
	while node != null and node != root:
		if node is Node3D:
			xform = (node as Node3D).transform * xform
		node = node.get_parent()
	var verts: PackedVector3Array = mi.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
	var box := AABB(xform * verts[0], Vector3.ZERO)
	for v in verts:
		box = box.expand(xform * v)
	return box
