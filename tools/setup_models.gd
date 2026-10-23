extends SceneTree
## Einmal ausführen, nachdem neue Automodelle in assets/models/ gelegt wurden
## (siehe assets/models/README.md). Im Terminal, im Projektordner:
##   Godot --headless --path . --import
##   Godot --headless --path . -s res://tools/setup_models.gd
##   Godot --headless --path . --import
## Stellt alle Modell-Texturen auf höchstens 2048 px, Mipmaps (weniger Flimmern in der
## Ferne) und Grafikkarten-Kompression (weniger Speicher). Normal-Maps werden als solche
## markiert. Godot importiert die Texturen beim nächsten --import neu.

const MAX_SIZE: int = 2048


func _initialize() -> void:
	var changed := 0
	for folder in DirAccess.get_directories_at("res://assets/models"):
		var texture_dir := "res://assets/models/%s/textures" % folder
		if not DirAccess.dir_exists_absolute(texture_dir):
			continue
		for file in DirAccess.get_files_at(texture_dir):
			if file.ends_with(".import") and _patch(texture_dir.path_join(file)):
				changed += 1
	print("Textur-Einstellungen angepasst: %d Dateien. Jetzt einmal --import ausführen." % changed)
	quit()


func _patch(path: String) -> bool:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return false
	config.set_value("params", "compress/mode", 2)
	config.set_value("params", "mipmaps/generate", true)
	config.set_value("params", "process/size_limit", MAX_SIZE)
	if "normal" in path.get_file().to_lower():
		config.set_value("params", "compress/normal_map", 1)
	config.save(path)
	return true
