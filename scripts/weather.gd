class_name Weather
extends Node
## Wetter und Jahreszeiten.
## Sechs Wetterlagen (klar, bewölkt, Regen, Gewitter, Nebel, Schnee) wechseln alle paar
## Minuten fließend; welche wie oft kommt, hängt von der Jahreszeit ab. F5 schaltet das
## Wetter weiter (Automatisch → Klar → … → Schnee), J die Jahreszeit. Beides geht auch
## in der Garage und wird gespeichert.
## Was die Shader wissen müssen (Nässe, Schnee, Jahreszeit, Wind), steht in globalen
## Shader-Werten (Projekteinstellungen > Shader Globals). So muss nicht jedes Material
## einzeln Bescheid bekommen. Himmel und Licht passt DayNight an (liest die Werte hier).

enum Kind { CLEAR, CLOUDY, RAIN, STORM, FOG, SNOW }
enum Season { SPRING, SUMMER, AUTUMN, WINTER }

const KIND_NAMES: Array[String] = ["Klar", "Bewölkt", "Regen", "Gewitter", "Nebel", "Schnee"]
const KIND_IDS: Array[String] = ["clear", "cloudy", "rain", "storm", "fog", "snow"]
const SEASON_NAMES: Array[String] = ["Frühling", "Sommer", "Herbst", "Winter"]
const SEASON_IDS: Array[String] = ["spring", "summer", "autumn", "winter"]
const SETTINGS_PATH := "user://einstellungen.cfg"

## Werte jeder Wetterlage (Reihenfolge wie Kind):
## clouds = Wolkenbedeckung, overcast = wie grau und trüb alles ist, rain/snow = Niederschlag,
## fog = Faktor für den Fernnebel, valley_fog = Talnebel den ganzen Tag, morning_fog = wie
## stark sich morgens Talnebel bilden kann, lightning = Blitze, wind = Wind für Bäume und Gras
const STATES: Array[Dictionary] = [
	{"clouds": 0.3, "overcast": 0.0, "rain": 0.0, "snow": 0.0, "fog": 1.0, "valley_fog": 0.0,
		"morning_fog": 1.0, "lightning": 0.0, "wind": 1.0},
	{"clouds": 0.72, "overcast": 0.45, "rain": 0.0, "snow": 0.0, "fog": 1.8, "valley_fog": 0.0,
		"morning_fog": 0.7, "lightning": 0.0, "wind": 1.4},
	{"clouds": 0.96, "overcast": 0.85, "rain": 0.65, "snow": 0.0, "fog": 9.0, "valley_fog": 0.15,
		"morning_fog": 0.3, "lightning": 0.0, "wind": 1.8},
	{"clouds": 1.0, "overcast": 1.0, "rain": 1.0, "snow": 0.0, "fog": 13.0, "valley_fog": 0.0,
		"morning_fog": 0.0, "lightning": 1.0, "wind": 3.0},
	{"clouds": 0.85, "overcast": 0.7, "rain": 0.0, "snow": 0.0, "fog": 45.0, "valley_fog": 1.0,
		"morning_fog": 1.0, "lightning": 0.0, "wind": 0.4},
	{"clouds": 0.96, "overcast": 0.75, "rain": 0.0, "snow": 1.0, "fog": 16.0, "valley_fog": 0.15,
		"morning_fog": 0.3, "lightning": 0.0, "wind": 1.3},
]
## Wie oft jede Wetterlage pro Jahreszeit kommt (Gewichte, Reihenfolge wie Kind)
const CHANCES: Array = [
	[30, 30, 25, 5, 10, 0],   # Frühling
	[45, 25, 12, 13, 5, 0],   # Sommer
	[20, 30, 25, 3, 22, 0],   # Herbst: mehr Regen und Nebel
	[25, 30, 4, 0, 16, 25],   # Winter: Schnee statt Gewitter
]

@export var day_night: DayNight
@export var car: Car
@export var camera: Camera3D
@export var world_environment: WorldEnvironment
@export var garage: Garage
@export var precipitation: Precipitation
@export var sound: WeatherSound
@export var terrain: TerrainManager

@export_group("Wechsel")
## Das Wetter wechselt (bei „Automatisch“) nach so vielen Minuten (zufällig dazwischen)
@export var change_min_minutes: float = 3.0
@export var change_max_minutes: float = 6.0
## So lange dauert der Übergang zur nächsten Wetterlage (Sekunden)
@export var transition_seconds: float = 45.0
## Übergang, wenn man das Wetter mit F5 selbst umschaltet
@export var manual_transition_seconds: float = 8.0
## Übergang beim Wechsel der Jahreszeit (Farben der Bäume, Schnee)
@export var season_transition_seconds: float = 6.0

@export_group("Nässe und Schnee")
## So viele Sekunden Regen, bis die Straße ganz nass ist
@export var wet_seconds: float = 40.0
## So viele Minuten dauert es danach, bis sie wieder trocken ist
@export var dry_minutes: float = 4.0
## So viele Sekunden Schneefall, bis alles weiß ist
@export var snow_seconds: float = 120.0
## So viele Minuten taut der Schnee (außer im Winter)
@export var melt_minutes: float = 6.0
## Schnee auf der Straße: so schnell liegt er, so schnell ist wieder geräumt
@export var road_snow_seconds: float = 60.0
@export var road_clear_minutes: float = 2.0
## Im Winter liegt auch ohne Schneefall so viel Schnee (0 bis 1)
@export_range(0.0, 1.0) var winter_snow_cover: float = 0.95
## Schneefallgrenze in Metern je Jahreszeit (Frühling, Sommer, Herbst, Winter)
@export var snow_lines: PackedFloat32Array = PackedFloat32Array([750.0, 950.0, 850.0, 250.0])

@export_group("Spiegelungen")
## Echte Spiegelungen (SSR) auf nasser Straße. Kostet ein paar FPS, nur bei Nässe an.
@export var wet_reflections: bool = true
## Schritte der Spiegelungs-Suche (weniger = schneller, aber Spiegelbilder enden früher)
@export var reflection_steps: int = 32

@export_group("Grip")
## Griffigkeit der Reifen auf nasser Straße und auf Schnee (1 = trocken)
@export var wet_grip: float = 0.7
@export var snow_grip: float = 0.5

@export_group("Talnebel")
## Dichte des Talnebels am Talboden (pro Meter; 0,012 ≈ 80 m Sicht)
@export var valley_fog_density: float = 0.012
## Dicke der Nebelschicht (Meter), bei der Wetterlage „Nebel“ dicker
@export var valley_fog_thickness: float = 30.0
@export var fog_weather_thickness: float = 80.0
## Wie stark sich morgens Talnebel bildet, je Jahreszeit (Herbst am meisten)
@export var morning_fog_by_season: PackedFloat32Array = PackedFloat32Array([0.7, 0.45, 1.0, 0.7])

@export_group("Gewitter")
## Abstand zwischen zwei Blitzen (Sekunden, zufällig dazwischen)
@export var lightning_min_seconds: float = 4.0
@export var lightning_max_seconds: float = 14.0

## -1 = automatisch wechseln, sonst feste Wetterlage (Kind)
var mode: int = -1
## Wetterlage, auf die gerade zugesteuert wird
var kind: int = Kind.CLEAR
var season: int = Season.SUMMER
## Aktuelle (übergeblendete) Werte, die andere lesen
var clouds: float = 0.3
var overcast: float = 0.0
var fog_factor: float = 1.0
var lightning_flash: float = 0.0
## Nässe der Straßen (0 bis 1), Schnee in der Landschaft und auf der Straße
var wetness: float = 0.0
var snow_ground: float = 0.0
var road_snow: float = 0.0
## 1 = Auto ist überdacht (Tunnel): kein Regen, trockene Reifen
var shelter: float = 0.0

var world_gen: WorldGen
var _current: Dictionary = STATES[Kind.CLEAR].duplicate()
var _from: Dictionary = STATES[Kind.CLEAR].duplicate()
var _blend: float = 1.0
var _blend_time: float = 1.0
var _change_timer: float = 0.0
## Anteil jeder Jahreszeit (für weiche Übergänge), Reihenfolge wie Season
var _season_weights: PackedFloat32Array = PackedFloat32Array([0.0, 1.0, 0.0, 0.0])
var _lightning_timer: float = 3.0
var _flash_time: float = 10.0
var _flash_strength: float = 0.0
var _thunder_delay: float = -1.0
var _thunder_distance: float = 0.0
var _fog_floor: float = 0.0
var _fog_mesh: MeshInstance3D
var _fog_material: ShaderMaterial
var _toast: Label
var _toast_time: float = 0.0
var _weather_option: OptionButton
var _season_option: OptionButton
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_change_timer = _rng.randf_range(change_min_minutes, change_max_minutes) * 60.0
	_create_valley_fog()
	_create_toast()
	_load_settings()
	_add_garage_rows.call_deferred()


## Wetter festlegen: -1 = automatisch, sonst eine Wetterlage. instant = sofort fertig
## (z. B. aus der Garage), sonst fließender Übergang.
func set_mode(new_mode: int, instant: bool, save: bool = true) -> void:
	mode = clampi(new_mode, -1, Kind.size() - 1)
	if mode >= 0:
		_set_kind(mode, 0.0 if instant else manual_transition_seconds)
	elif CHANCES[season][kind] == 0:
		_set_kind(_pick_kind(), 0.0 if instant else manual_transition_seconds)
	if instant:
		_settle()
	_sync_options()
	if save:
		_save_settings()


func set_season(new_season: int, instant: bool, save: bool = true) -> void:
	season = posmod(new_season, Season.size())
	# Passt das Wetter nicht zur Jahreszeit (z. B. Schnee im Sommer), wechselt es
	if mode < 0 and CHANCES[season][kind] == 0:
		_set_kind(_pick_kind(), 0.0 if instant else manual_transition_seconds)
	if instant:
		for i in _season_weights.size():
			_season_weights[i] = 1.0 if i == season else 0.0
		_settle()
	_sync_options()
	if save:
		_save_settings()


## Für Tests (--weather=rain, --season=winter): sofort und ohne zu speichern
func set_debug(weather_id: String, season_id: String) -> void:
	var s := SEASON_IDS.find(season_id)
	set_season(s if s >= 0 else Season.SUMMER, true, false)
	var k := KIND_IDS.find(weather_id)
	set_mode(k if k >= 0 else Kind.CLEAR, true, false)


func weather_name() -> String:
	return KIND_NAMES[kind]


func _set_kind(new_kind: int, seconds: float) -> void:
	kind = new_kind
	_from = _current.duplicate()
	_blend = 0.0
	_blend_time = maxf(seconds, 0.001)
	if seconds <= 0.0:
		_blend = 1.0
		_current = STATES[kind].duplicate()


## Nässe und Schnee sofort so setzen, wie sie nach längerer Zeit wären
func _settle() -> void:
	var state: Dictionary = STATES[kind]
	_current = state.duplicate()
	_blend = 1.0
	wetness = 1.0 if state["rain"] > 0.0 else 0.0
	road_snow = 1.0 if state["snow"] > 0.0 else 0.0
	var base := _season_weights[Season.WINTER] * winter_snow_cover
	snow_ground = 1.0 if state["snow"] > 0.0 else base
	_apply(0.0)


## Nächste Wetterlage zufällig, gewichtet nach Jahreszeit (normalerweise nicht dieselbe wie jetzt)
func _pick_kind(allow_current: bool = false) -> int:
	var chances: Array = CHANCES[season]
	var total := 0.0
	for i in chances.size():
		if i != kind or allow_current:
			total += chances[i]
	var r := _rng.randf() * total
	for i in chances.size():
		if i == kind and not allow_current:
			continue
		r -= chances[i]
		if r <= 0.0 and chances[i] > 0:
			return i
	return Kind.CLEAR


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cycle_weather"):
		var next := mode + 1 if mode < Kind.size() - 1 else -1
		set_mode(next, false)
		_show_toast("Wetter: " + ("Automatisch (gerade %s)" % KIND_NAMES[kind] if mode < 0 else KIND_NAMES[mode]))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("cycle_season"):
		set_season(season + 1, false)
		_show_toast("Jahreszeit: " + SEASON_NAMES[season])
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	# Automatischer Wechsel
	if mode < 0:
		_change_timer -= delta
		if _change_timer <= 0.0:
			_change_timer = _rng.randf_range(change_min_minutes, change_max_minutes) * 60.0
			_set_kind(_pick_kind(), transition_seconds)
	# Übergang zwischen zwei Wetterlagen
	if _blend < 1.0:
		_blend = minf(_blend + delta / _blend_time, 1.0)
		var t := smoothstep(0.0, 1.0, _blend)
		var target: Dictionary = STATES[kind]
		for key: String in target:
			_current[key] = lerpf(_from[key], target[key], t)
	# Jahreszeiten weich überblenden
	for i in _season_weights.size():
		_season_weights[i] = move_toward(_season_weights[i], 1.0 if i == season else 0.0,
			delta / season_transition_seconds)
	_update_surfaces(delta)
	_update_lightning(delta)
	_apply(delta)
	if _toast_time > 0.0:
		_toast_time -= delta
		_toast.modulate.a = clampf(_toast_time / 0.5, 0.0, 1.0)


## Nässe und Schnee steigen bei Niederschlag und gehen danach langsam zurück
func _update_surfaces(delta: float) -> void:
	var rain: float = _current["rain"]
	var snow: float = _current["snow"]
	if rain > 0.05:
		wetness = move_toward(wetness, 1.0, delta * rain / wet_seconds * 1.5)
	else:
		wetness = move_toward(wetness, 0.0, delta / (dry_minutes * 60.0))
	if snow > 0.05:
		road_snow = move_toward(road_snow, 1.0, delta * snow / road_snow_seconds)
		snow_ground = move_toward(snow_ground, 1.0, delta * snow / snow_seconds)
	else:
		road_snow = move_toward(road_snow, 0.0, delta / (road_clear_minutes * 60.0))
	# Im Winter liegt immer Schnee; kommt der Winter, wird es in ein paar Sekunden weiß
	var base := _season_weights[Season.WINTER] * winter_snow_cover
	if snow_ground < base:
		snow_ground = move_toward(snow_ground, base, delta / season_transition_seconds)
	elif snow <= 0.05:
		snow_ground = move_toward(snow_ground, base, delta / (melt_minutes * 60.0))


## Blitze bei Gewitter: kurzes Flackern, der Donner kommt je nach Entfernung später
func _update_lightning(delta: float) -> void:
	if _current["lightning"] > 0.5:
		_lightning_timer -= delta
		if _lightning_timer <= 0.0:
			_lightning_timer = _rng.randf_range(lightning_min_seconds, lightning_max_seconds)
			_flash_time = 0.0
			_thunder_distance = _rng.randf_range(400.0, 5000.0)
			# Nahe Blitze sind heller
			_flash_strength = lerpf(1.0, 0.35, _thunder_distance / 5000.0)
			_thunder_delay = _thunder_distance / 343.0
	_flash_time += delta
	# Zwei, drei schnelle Lichtblitze hintereinander, dann ausklingen
	var t := _flash_time
	var flicker := 0.0
	if t < 0.07:
		flicker = 1.0
	elif t < 0.13:
		flicker = 0.15
	elif t < 0.2:
		flicker = 0.75
	elif t < 0.26:
		flicker = 0.1
	elif t < 0.3:
		flicker = 0.45
	else:
		flicker = 0.45 * exp(-(t - 0.3) * 12.0)
	lightning_flash = flicker * _flash_strength * (1.0 - shelter)
	if _thunder_delay >= 0.0:
		_thunder_delay -= delta
		if _thunder_delay < 0.0 and sound:
			sound.play_thunder(_thunder_distance)


## Alle Werte an Shader, Auto, Partikel, Geräusche und Umgebung weitergeben
func _apply(delta: float) -> void:
	clouds = _current["clouds"]
	overcast = _current["overcast"]
	fog_factor = _current["fog"]
	var w := _season_weights
	var snow_line := 0.0
	for i in w.size():
		snow_line += w[i] * snow_lines[i]
	RenderingServer.global_shader_parameter_set("wetness", wetness * (1.0 - snow_ground * 0.5))
	RenderingServer.global_shader_parameter_set("road_snow", road_snow)
	RenderingServer.global_shader_parameter_set("snow_cover", snow_ground)
	RenderingServer.global_shader_parameter_set("snow_line", snow_line)
	RenderingServer.global_shader_parameter_set("season_spring", w[Season.SPRING])
	RenderingServer.global_shader_parameter_set("season_autumn", w[Season.AUTUMN])
	RenderingServer.global_shader_parameter_set("season_winter", w[Season.WINTER])
	RenderingServer.global_shader_parameter_set("rain_amount", _current["rain"])
	RenderingServer.global_shader_parameter_set("weather_wind", _current["wind"])
	if terrain:
		terrain.set_bare_trees(w[Season.WINTER] > 0.5)

	# Auto: nasse Straße ~70 % Grip, Schnee ~50 %; im Tunnel trocken
	if car:
		var dry := shelter
		var grip := lerpf(1.0, wet_grip, wetness * (1.0 - dry))
		grip = minf(grip, lerpf(1.0, snow_grip, road_snow * (1.0 - dry)))
		car.grip_factor = grip
		car.wetness = maxf(wetness, road_snow) * (1.0 - dry)

	# Echte Spiegelungen auf nasser Straße (Screen Space Reflections)
	if world_environment:
		var env := world_environment.environment
		env.ssr_enabled = wet_reflections and wetness > 0.04
		env.ssr_max_steps = reflection_steps

	var daylight := day_night.daylight if day_night else 1.0
	if precipitation:
		precipitation.rain = _current["rain"] * (1.0 - shelter)
		precipitation.snow = _current["snow"] * (1.0 - shelter)
		var wind: float = _current["wind"]
		precipitation.wind = Vector3(1.6, 0.0, 0.9) * (wind - 0.6)
		precipitation.brightness = lerpf(0.06, 1.0, daylight) * (1.0 - overcast * 0.35) + lightning_flash * 2.0
	if sound:
		sound.rain = _current["rain"] * (1.0 - shelter * 0.8)
		sound.wind = clampf((_current["wind"] - 1.2) / 1.8, 0.0, 1.0) * (1.0 - shelter * 0.8)
	_update_valley_fog(delta, daylight)


## Talnebel: liegt in einer dünnen Schicht über dem Talboden. Er bildet sich vor allem
## morgens (je nach Jahreszeit und Wetter) und bei der Wetterlage „Nebel“ den ganzen Tag.
func _update_valley_fog(delta: float, daylight: float) -> void:
	if _fog_mesh == null or camera == null or world_gen == null:
		return
	var hour := day_night.time_of_day if day_night else 12.0
	var morning := smoothstep(1.5, 5.0, hour) * (1.0 - smoothstep(8.5, 11.0, hour))
	var season_fog := 0.0
	for i in _season_weights.size():
		season_fog += _season_weights[i] * morning_fog_by_season[i]
	var amount := maxf(_current["valley_fog"], morning * season_fog * _current["morning_fog"])
	_fog_mesh.visible = amount > 0.01
	if not _fog_mesh.visible:
		return
	# Talboden unter der Kamera (ändert sich nur großräumig), weich nachgeführt
	var cam := camera.global_position
	var floor_height := world_gen.ground_level(cam.x, cam.z)
	_fog_floor = floor_height if delta == 0.0 or absf(_fog_floor - floor_height) > 200.0 \
		else lerpf(_fog_floor, floor_height, clampf(delta * 0.5, 0.0, 1.0))
	var env := world_environment.environment
	# Farbe: wie der Fernnebel, aber heller (Nebel streut das Licht)
	var light := lerpf(0.04, 1.0, daylight) * (1.0 - overcast * 0.3) + lightning_flash
	var color := env.fog_light_color.lerp(Color(0.86, 0.88, 0.9) * light, 0.5)
	_fog_material.set_shader_parameter("floor_height", _fog_floor)
	_fog_material.set_shader_parameter("density", valley_fog_density * amount)
	_fog_material.set_shader_parameter("thickness",
		lerpf(valley_fog_thickness, fog_weather_thickness, _current["valley_fog"]))
	_fog_material.set_shader_parameter("fog_color", color)
	if day_night:
		_fog_material.set_shader_parameter("sun_direction", day_night.sun_direction())
		_fog_material.set_shader_parameter("sun_color", day_night.sun.light_color * day_night.sun.light_energy * 0.3)


func _create_valley_fog() -> void:
	if camera == null:
		return
	_fog_material = ShaderMaterial.new()
	_fog_material.shader = load("res://shaders/valley_fog.gdshader")
	# Nach dem Wasser zeichnen (das hat Priorität 1), sonst schaut es aus dem Nebel heraus
	_fog_material.render_priority = 2
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	_fog_mesh = MeshInstance3D.new()
	_fog_mesh.mesh = quad
	_fog_mesh.material_override = _fog_material
	_fog_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Der Shader legt das Viereck über den ganzen Bildschirm: nie wegsortieren
	_fog_mesh.extra_cull_margin = 16384.0
	_fog_mesh.position = Vector3(0.0, 0.0, -1.0)
	_fog_mesh.visible = false
	camera.add_child.call_deferred(_fog_mesh)


# ---------------------------------------------------------------------------
# Anzeige, Garage, Speichern
# ---------------------------------------------------------------------------

func _create_toast() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_toast = Label.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.position = Vector2(-300, 112)
	_toast.size = Vector2(600, 40)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 24)
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.modulate.a = 0.0
	layer.add_child(_toast)


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast_time = 2.5


func _add_garage_rows() -> void:
	if garage == null:
		return
	_weather_option = OptionButton.new()
	_weather_option.add_item("Wetter: Automatisch")
	for kind_name in KIND_NAMES:
		_weather_option.add_item("Wetter: " + kind_name)
	_weather_option.item_selected.connect(func(index: int) -> void: set_mode(index - 1, true))
	_weather_option.focus_mode = Control.FOCUS_NONE
	garage.add_setting_row(_weather_option)
	_season_option = OptionButton.new()
	for season_name in SEASON_NAMES:
		_season_option.add_item("Jahreszeit: " + season_name)
	_season_option.item_selected.connect(func(index: int) -> void: set_season(index, true))
	_season_option.focus_mode = Control.FOCUS_NONE
	garage.add_setting_row(_season_option)
	_sync_options()


func _sync_options() -> void:
	if _weather_option:
		_weather_option.select(mode + 1)
	if _season_option:
		_season_option.select(season)


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		set_season(Season.SUMMER, true, false)
		kind = _pick_kind(true)
		set_mode(-1, true, false)
		return
	set_season(config.get_value("welt", "jahreszeit", Season.SUMMER), true, false)
	var saved: int = config.get_value("welt", "wetter", -1)
	# Automatisch: mit einem zufälligen (zur Jahreszeit passenden) Wetter anfangen
	if saved < 0:
		kind = _pick_kind(true)
	set_mode(saved, true, false)


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("welt", "wetter", mode)
	config.set_value("welt", "jahreszeit", season)
	config.save(SETTINGS_PATH)
