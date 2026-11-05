extends SceneTree
## Einmal ausführen, nachdem neue Modelle in assets/models/ gelegt wurden
## (siehe assets/models/README.md). Im Terminal, im Projektordner:
##   Godot --headless --path . --import
##   Godot --headless --path . -s res://tools/setup_models.gd
##   Godot --headless --path . --import
## Stellt alle Modell-Texturen auf höchstens 2048 px (Verkehr: 1024 px), Mipmaps (weniger
## Flimmern in der Ferne) und Grafikkarten-Kompression (weniger Speicher). Normal-Maps werden
## als solche markiert. Godot importiert die Texturen beim nächsten --import neu.
## Gefunden werden Texturen in textures/-Ordnern (glTF-Downloads) und die Bilder, die Godot
## beim Import aus einer .glb neben die Datei legt (Name_0.png usw.).

const MAX_SIZE: int = 2048
const TRAFFIC_MAX_SIZE: int = 1024
const IMAGE_TYPES: Array[String] = ["png", "jpg", "jpeg", "webp"]


func _initialize() -> void:
	var changed := _scan("res://assets/models")
	print("Textur-Einstellungen angepasst: %d Dateien. Jetzt einmal --import ausführen." % changed)
	quit()


## Alle Unterordner durchgehen (Garage-Autos, verkehr/*, raststaette/*)
func _scan(folder: String) -> int:
	var changed := 0
	for file in DirAccess.get_files_at(folder):
		if file.ends_with(".import") and file.get_basename().get_extension().to_lower() in IMAGE_TYPES:
			var limit := TRAFFIC_MAX_SIZE if "/verkehr/" in folder + "/" else MAX_SIZE
			if _patch(folder.path_join(file), limit):
				changed += 1
	for sub in DirAccess.get_directories_at(folder):
		# Vorbereitete Spiel-Versionen haben keine eigenen Bilddateien
		if sub != "prepared":
			changed += _scan(folder.path_join(sub))
	return changed


func _patch(path: String, limit: int) -> bool:
	var config := ConfigFile.new()
	if config.load(path) != OK or config.get_value("remap", "importer", "") != "texture":
		return false
	config.set_value("params", "compress/mode", 2)
	config.set_value("params", "mipmaps/generate", true)
	config.set_value("params", "process/size_limit", limit)
	if "normal" in path.get_file().to_lower():
		config.set_value("params", "compress/normal_map", 1)
	config.save(path)
	return true
