class_name GameSettings
extends Node
## Einstellungen: Grafik, Anzeige, Steuerung, Audio, Spiel. Alles wirkt sofort und wird in
## user://einstellungen.cfg gespeichert. Das Pausemenü (pause_menu.gd) ist nur die Oberfläche.
## Testläufe (Startargumente) nehmen die Standardwerte (Qualität „Hoch“, außer mit
## --quality=niedrig|mittel|hoch|ultra) und speichern nichts, damit Messungen vergleichbar sind.
## HUD-Farbe und Sportauspuff verwaltet weiter die Garage, das Wetter seinen Modus selbst.

signal changed

@export var world_environment: WorldEnvironment
@export var sun: DirectionalLight3D
@export var day_night: DayNight
@export var weather: Weather
@export var terrain: TerrainManager
@export var grass: GrassManager
@export var roads: RoadNetwork
@export var traffic: Traffic
@export var car: Car
@export var garage: Garage
@export var speedometer: Control
@export var fps_label: Label
@export var debug_tools: DebugTools
@export var cruise: CruiseControl
@export var exploration: Exploration
@export var chill_mode: ChillMode
## Schwere Einstellungen (Sichtweite, Vegetation, Gras) erst so lange nach dem letzten
## Ändern anwenden (beim Ziehen am Regler nicht bei jedem Schritt alles neu bauen)
@export var heavy_delay: float = 0.35

const PATH := "user://einstellungen.cfg"
## Qualitätsstufen: Werte der Grafik-Regler
const PRESETS := {
	"niedrig": {"render_scale": 0.55, "sichtweite": 1300.0, "schatten": 1, "vegetation": 0.6, "gras": 1,
		"ssao": false, "spiegelungen": false, "volumennebel": false, "wolkenschatten": false},
	"mittel": {"render_scale": 0.65, "sichtweite": 1700.0, "schatten": 2, "vegetation": 0.8, "gras": 2,
		"ssao": false, "spiegelungen": true, "volumennebel": false, "wolkenschatten": true},
	"hoch": {"render_scale": 0.75, "sichtweite": 2000.0, "schatten": 2, "vegetation": 1.0, "gras": 2,
		"ssao": true, "spiegelungen": true, "volumennebel": false, "wolkenschatten": true},
	"ultra": {"render_scale": 1.0, "sichtweite": 2600.0, "schatten": 3, "vegetation": 1.0, "gras": 3,
		"ssao": true, "spiegelungen": true, "volumennebel": true, "wolkenschatten": true},
}
const QUALITY_NAMES: Array[String] = ["niedrig", "mittel", "hoch", "ultra"]
const DEFAULTS := {
	"grafik": {"qualitaet": "hoch", "render_scale": 0.75, "sichtweite": 2000.0, "schatten": 2, "vegetation": 1.0,
		"gras": 2, "ssao": true, "spiegelungen": true, "volumennebel": false, "wolkenschatten": true, "verkehr": 1.0},
	"anzeige": {"vollbild": false, "aufloesung": "1280x720", "vsync": true, "fps_limit": 0, "fps_anzeige": false},
	"steuerung": {"grip": "sport", "lenkung": 1.0, "tempolimit": true},
	"audio": {"gesamt": 1.0, "motor": 1.0, "umgebung": 1.0, "musik": 0.8},
	"spiel": {"einheit": "kmh", "tageslaenge": 10.0, "entdecker": true, "chill_zeit": 1},
}
## Einstellungen, die etwas neu bauen (verzögert anwenden)
const HEAVY: Array[String] = ["sichtweite", "vegetation", "gras"]
## Schatten: Reichweite (m) und Größe der Schattenkarte je Stufe (0 = aus)
const SHADOW_DISTANCE: Array[float] = [0.0, 150.0, 300.0, 500.0]
const SHADOW_SIZE: Array[int] = [0, 2048, 4096, 4096]
## Gras: Umkreis (m) und Büschel pro m² je Stufe (Umkreis < 0 = kein Gras)
const GRASS_LEVELS: Array[Vector2] = [Vector2(-1.0, 3.0), Vector2(40.0, 2.0), Vector2(56.0, 3.0), Vector2(72.0, 4.0)]
const AUDIO_BUSES := {"gesamt": "Master", "motor": "Motor", "umgebung": "Umgebung", "musik": "Musik"}
## Belegbare Tasten: [Aktion, Name im Menü]
const ACTIONS: Array = [["accelerate", "Gas"], ["brake", "Bremse / rückwärts"], ["steer_left", "Links lenken"],
	["steer_right", "Rechts lenken"], ["handbrake", "Handbremse"], ["blink_left", "Blinker links"],
	["blink_right", "Blinker rechts"], ["hazard", "Warnblinker"], ["horn", "Hupe"], ["toggle_lights", "Licht"],
	["reset_car", "Auto aufrichten"], ["photo_mode", "Fotomodus"], ["toggle_map", "Große Karte"],
	["open_garage", "Garage"], ["cycle_weather", "Wetter wechseln"], ["cycle_season", "Jahreszeit wechseln"],
	["time_warp", "Zeitraffer (halten)"], ["cycle_paint", "Lackfarbe"], ["toggle_stickers", "Aufkleber"],
	["toggle_fps", "FPS-Anzeige"], ["cruise_toggle", "Tempomat an/aus"], ["cruise_faster", "Wunschtempo +"],
	["cruise_slower", "Wunschtempo −"], ["cruise_distance", "Abstandsstufe"], ["flash_lights", "Lichthupe"],
	["toggle_windows", "Fenster / Dach"]]

var _values: Dictionary = {}
var _keys: Dictionary = {}  # Aktion -> physischer Tastencode (nur geänderte)
var _testing: bool = false
var _pending: Dictionary = {}  # schwere Einstellung -> Sekunden bis zum Anwenden


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_testing = debug_tools != null and debug_tools.is_active()
	_values = DEFAULTS.duplicate(true)
	if not _testing:
		_load()
	else:
		if debug_tools.quality != "" and PRESETS.has(debug_tools.quality):
			_values["grafik"]["qualitaet"] = debug_tools.quality
			_values["grafik"].merge(PRESETS[debug_tools.quality], true)
		if debug_tools.traffic_density >= 0.0:
			_values["grafik"]["verkehr"] = debug_tools.traffic_density
	_apply_all()


func _process(delta: float) -> void:
	for key: String in _pending.keys():
		_pending[key] -= delta
		if _pending[key] <= 0.0:
			_pending.erase(key)
			_apply("grafik", key)


func get_value(section: String, key: String) -> Variant:
	return _values[section][key]


## Wert setzen, sofort anwenden (schwere etwas verzögert) und speichern
func set_value(section: String, key: String, value: Variant) -> void:
	_values[section][key] = value
	if section == "grafik" and PRESETS["hoch"].has(key):
		_values["grafik"]["qualitaet"] = _matching_quality()
	if key in HEAVY:
		_pending[key] = heavy_delay
	else:
		_apply(section, key)
	_save()
	changed.emit()


## Qualitätsstufe: alle Grafik-Regler auf die Werte der Stufe
func set_quality(quality: String) -> void:
	_values["grafik"]["qualitaet"] = quality
	_values["grafik"].merge(PRESETS[quality], true)
	for key: String in PRESETS[quality]:
		_apply("grafik", key)
	_save()
	changed.emit()


## Einen Reiter auf die Standardwerte zurücksetzen
func reset_section(section: String) -> void:
	_values[section] = DEFAULTS[section].duplicate(true)
	match section:
		"steuerung":
			InputMap.load_from_project_settings()
			_keys.clear()
		"spiel":
			if garage:
				garage.set_accent(0)
				garage.set_sport_exhaust(true)
			if weather:
				weather.set_mode(-1, false)
	for key: String in _values[section]:
		_apply(section, key)
	_save()
	changed.emit()


## Passt die Grafik genau zu einer Stufe? Sonst „eigene“.
func _matching_quality() -> String:
	for quality in QUALITY_NAMES:
		var preset: Dictionary = PRESETS[quality]
		var same := true
		for key: String in preset:
			if not is_equal_approx(float(preset[key]), float(_values["grafik"][key])):
				same = false
				break
		if same:
			return quality
	return "eigene"


func _apply_all() -> void:
	for section: String in _values:
		for key: String in _values[section]:
			_apply(section, key)
	for action: String in _keys:
		_bind(action, _keys[action])


func _apply(section: String, key: String) -> void:
	var value: Variant = _values[section][key]
	match key:
		"tempolimit":
			if cruise:
				cruise.adopt_limits = value
		"render_scale":
			get_tree().root.scaling_3d_scale = value
		"sichtweite", "vegetation":
			var sight: float = _values["grafik"]["sichtweite"]
			var max_lod := 1 if sight < 1500.0 else (3 if sight > 2300.0 else 2)
			if terrain:
				terrain.set_detail(sight, _values["grafik"]["vegetation"], max_lod)
			if roads:
				roads.mesh_distance = sight + 300.0
		"schatten":
			var level: int = value
			if day_night:
				day_night.shadows_allowed = level > 0
			if sun and level > 0:
				sun.directional_shadow_max_distance = SHADOW_DISTANCE[level]
				RenderingServer.directional_shadow_atlas_set_size(SHADOW_SIZE[level], true)
				RenderingServer.directional_soft_shadow_filter_set_quality(
					RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM if level == 3 else
					(RenderingServer.SHADOW_QUALITY_SOFT_LOW if level == 2 else RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW))
		"gras":
			var grass_level: Vector2 = GRASS_LEVELS[value]
			if grass:
				grass.set_level(grass_level.x, grass_level.y)
		"ssao":
			if world_environment:
				world_environment.environment.ssao_enabled = value
		"spiegelungen":
			if weather:
				weather.wet_reflections = value
		"volumennebel":
			if day_night:
				day_night.set_volumetric_fog(value)
		"wolkenschatten":
			if weather:
				weather.cloud_shadows = value
		"verkehr":
			if traffic:
				traffic.set_density(value)
		"vollbild", "aufloesung":
			_apply_window()
		"vsync":
			if not _testing:
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if value else DisplayServer.VSYNC_DISABLED)
		"fps_limit":
			Engine.max_fps = value
		"fps_anzeige":
			if fps_label:
				fps_label.visible = value
		"grip":
			if car:
				car.set_grip_level(value)
		"lenkung":
			if car:
				car.steer_sensitivity = value
		"gesamt", "motor", "umgebung", "musik":
			var bus := AudioServer.get_bus_index(AUDIO_BUSES[key])
			if bus != -1:
				var volume: float = value
				AudioServer.set_bus_mute(bus, volume < 0.01)
				AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(volume, 0.0001)))
		"einheit":
			if speedometer:
				speedometer.set("use_mph", value == "mph")
		"chill_zeit":
			if chill_mode:
				chill_mode.time_factor = float(value)
		"entdecker":
			if exploration:
				exploration.enabled = value
		"tageslaenge":
			if day_night:
				day_night.day_length_minutes = value


## Fenster oder Vollbild, Fenstergröße (in Testläufen nicht: die bestimmen das selbst)
func _apply_window() -> void:
	if _testing:
		return
	var full: bool = _values["anzeige"]["vollbild"]
	if full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var parts := (_values["anzeige"]["aufloesung"] as String).split("x")
	var wanted := Vector2i(int(parts[0]), int(parts[1]))
	var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	wanted = wanted.min(screen.size)
	DisplayServer.window_set_size(wanted)
	DisplayServer.window_set_position(screen.position + Vector2i((Vector2(screen.size - wanted) * 0.5).round()))


# ---------------------------------------------------------------------------
# Tasten
# ---------------------------------------------------------------------------

## Physischer Tastencode der ersten Taste einer Aktion (0 = keine)
func key_of(action: String) -> int:
	for event in InputMap.action_get_events(action):
		var key := event as InputEventKey
		if key:
			return key.physical_keycode if key.physical_keycode != 0 else key.keycode
	return 0


## Name einer Taste so, wie sie auf der Tastatur steht (deutsches Layout: Z/Y richtig)
static func key_name(code: int) -> String:
	if code == 0:
		return "—"
	var names := {KEY_SPACE: "Leertaste", KEY_SHIFT: "Umschalt", KEY_CTRL: "Strg", KEY_ALT: "Alt",
		KEY_ENTER: "Eingabe", KEY_TAB: "Tab", KEY_BACKSPACE: "Rücktaste", KEY_UP: "↑", KEY_DOWN: "↓",
		KEY_LEFT: "←", KEY_RIGHT: "→", KEY_META: "Cmd", KEY_CAPSLOCK: "Feststell"}
	if names.has(code):
		return names[code]
	var label := DisplayServer.keyboard_get_label_from_physical(code as Key)
	return OS.get_keycode_string(label if label != KEY_NONE else code as Key)


## Taste neu belegen (Esc bleibt für das Menü)
func rebind(action: String, code: int) -> void:
	_bind(action, code)
	_keys[action] = code
	_save()
	changed.emit()


func _bind(action: String, code: int) -> void:
	if not InputMap.has_action(action):
		return
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			InputMap.action_erase_event(action, event)
	var key := InputEventKey.new()
	key.physical_keycode = code as Key
	InputMap.action_add_event(action, key)


## Andere Aktionen mit derselben Taste (für die Warnung im Menü)
func duplicates_of(action: String) -> Array[String]:
	var result: Array[String] = []
	var code := key_of(action)
	if code == 0:
		return result
	for entry: Array in ACTIONS:
		if entry[0] != action and key_of(entry[0]) == code:
			result.append(entry[1])
	return result


# ---------------------------------------------------------------------------
# Speichern
# ---------------------------------------------------------------------------

func _load() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return
	for section: String in _values:
		for key: String in _values[section]:
			if config.has_section_key(section, key):
				var stored: Variant = config.get_value(section, key)
				var wanted := typeof(_values[section][key])
				# Nur Werte der richtigen Art übernehmen (alte oder kaputte Datei), Zahlen angleichen
				if wanted == TYPE_INT and typeof(stored) in [TYPE_INT, TYPE_FLOAT]:
					_values[section][key] = int(stored)
				elif wanted == TYPE_FLOAT and typeof(stored) in [TYPE_INT, TYPE_FLOAT]:
					_values[section][key] = float(stored)
				elif typeof(stored) == wanted:
					_values[section][key] = stored
	if config.has_section("tasten"):
		for action: String in config.get_section_keys("tasten"):
			_keys[action] = int(config.get_value("tasten", action))


func _save() -> void:
	if _testing:
		return
	var config := ConfigFile.new()
	config.load(PATH)
	for section: String in _values:
		for key: String in _values[section]:
			config.set_value(section, key, _values[section][key])
	if config.has_section("tasten"):
		config.erase_section("tasten")
	for action: String in _keys:
		config.set_value("tasten", action, _keys[action])
	config.save(PATH)
