class_name DayNight
extends Node
## Tag-Nacht-Wechsel: bewegt Sonne und Mond und färbt Himmel, Licht und Nebel passend
## zur Uhrzeit. Ein ganzer Tag dauert day_length_minutes Minuten. Taste T = Zeitraffer.
## Nachts wird das Sonnenlicht zum Mondlicht. So reicht ein einziges Licht mit Schatten.
## Das Wetter (weather.gd) macht den Himmel grauer, die Sonne schwächer, den Nebel dichter
## und lässt bei Gewitter alles kurz aufblitzen.

@export var sun: DirectionalLight3D
@export var world_environment: WorldEnvironment
@export var weather: Weather

@export_group("Zeit")
## Aktuelle Uhrzeit in Stunden (0 bis 24)
@export_range(0.0, 24.0, 0.01) var time_of_day: float = 10.0
## So viele echte Minuten dauert ein ganzer Tag
@export var day_length_minutes: float = 10.0
## So viel schneller läuft die Zeit, solange T gedrückt ist
@export var time_warp_factor: float = 60.0
@export var sunrise_hour: float = 6.0
@export var sunset_hour: float = 20.0
## Zeit anhalten (z. B. für Screenshots)
@export var paused: bool = false

@export_group("Licht")
## Höchster Sonnenstand mittags in Grad
@export var sun_max_elevation: float = 55.0
@export var sun_energy: float = 1.6
@export var moon_energy: float = 0.35
## Helligkeit des Umgebungslichts tagsüber / nachts
@export var day_ambient: float = 1.0
@export var night_ambient: float = 1.6
## Belichtung tagsüber / nachts (nachts etwas heller, damit man noch etwas sieht)
@export var day_exposure: float = 1.0
@export var night_exposure: float = 2.2
## Farbe des Grundlichts nachts (der Himmel allein ist zu dunkel dafür)
@export var night_ambient_color: Color = Color(0.20, 0.26, 0.42)
## Farbsättigung tagsüber / nachts
@export var day_saturation: float = 1.1
@export var night_saturation: float = 0.55

@export_group("Grafik")
## Volumetrischer Nebel (Lichtstrahlen, schöner, aber teurer)
@export var volumetric_fog: bool = false
## Wie dicht der Fernnebel ist
@export var fog_density: float = 0.00006
@export_range(0.0, 1.0) var cloud_coverage: float = 0.45

@export_group("Farbverläufe (links Nacht, Mitte Sonnenuntergang, rechts Mittag)")
@export var zenith_colors: Gradient = _gradient([
	[0.0, Color(0.02, 0.035, 0.08)], [0.22, Color(0.06, 0.08, 0.19)], [0.31, Color(0.18, 0.24, 0.46)],
	[0.4, Color(0.24, 0.40, 0.70)], [0.6, Color(0.22, 0.45, 0.82)], [1.0, Color(0.17, 0.42, 0.86)]])
@export var horizon_colors: Gradient = _gradient([
	[0.0, Color(0.06, 0.08, 0.15)], [0.22, Color(0.24, 0.18, 0.32)], [0.31, Color(0.98, 0.46, 0.22)],
	[0.4, Color(1.0, 0.70, 0.44)], [0.6, Color(0.74, 0.82, 0.92)], [1.0, Color(0.66, 0.80, 0.95)]])
@export var sun_colors: Gradient = _gradient([
	[0.0, Color(1.0, 0.3, 0.1)], [0.3, Color(1.0, 0.38, 0.14)], [0.4, Color(1.0, 0.66, 0.38)],
	[0.6, Color(1.0, 0.89, 0.74)], [1.0, Color(1.0, 0.97, 0.93)]])
@export var glow_colors: Gradient = _gradient([
	[0.0, Color(0.3, 0.2, 0.3)], [0.3, Color(1.0, 0.42, 0.16)], [0.42, Color(1.0, 0.65, 0.35)],
	[0.7, Color(1.0, 0.92, 0.78)], [1.0, Color(1.0, 0.96, 0.9)]])
@export var cloud_light_colors: Gradient = _gradient([
	[0.0, Color(0.07, 0.08, 0.12)], [0.24, Color(0.30, 0.26, 0.36)], [0.31, Color(1.0, 0.56, 0.36)],
	[0.42, Color(1.0, 0.84, 0.66)], [1.0, Color(1.0, 1.0, 1.0)]])
@export var cloud_shadow_colors: Gradient = _gradient([
	[0.0, Color(0.02, 0.025, 0.04)], [0.3, Color(0.36, 0.26, 0.36)], [0.45, Color(0.5, 0.48, 0.55)],
	[1.0, Color(0.58, 0.63, 0.72)]])

## 0 = Nacht, 1 = Tag (für andere, z. B. Helligkeit von Regen und Talnebel)
var daylight: float = 1.0
## Wie tief die Kamera in einem Tunnel ist (setzt TunnelEffects): 0 = draußen, 1 = drin
var tunnel_cover: float = 0.0

@export_group("Tunnel")
## So viel heller belichtet das Auge nach einer Weile im Tunnel
@export var tunnel_exposure: float = 2.4
## So schnell passt sich das Auge an (höher = schneller; Hell → Dunkel dauert länger)
@export var adapt_to_dark: float = 0.8
@export var adapt_to_light: float = 2.0

var _adaptation: float = 0.0

var _sky_material: ShaderMaterial


func _ready() -> void:
	# Damit andere (z. B. das Auto für die Scheinwerfer) den Tag-Nacht-Wechsel finden
	add_to_group("day_night")
	var env := world_environment.environment
	_sky_material = env.sky.sky_material as ShaderMaterial
	env.fog_density = fog_density
	env.adjustment_enabled = true
	set_volumetric_fog(volumetric_fog)
	_update_lighting()


func _process(delta: float) -> void:
	var hours_per_second := 24.0 / (day_length_minutes * 60.0)
	if Input.is_action_pressed("time_warp"):
		time_of_day += delta * hours_per_second * time_warp_factor
	elif not paused:
		time_of_day += delta * hours_per_second
	time_of_day = fposmod(time_of_day, 24.0)
	# Augen-Anpassung: im Tunnel langsam heller, draußen schneller wieder normal
	var speed := adapt_to_dark if tunnel_cover > _adaptation else adapt_to_light
	_adaptation = move_toward(_adaptation, tunnel_cover, delta * speed)
	_update_lighting()


## Uhrzeit setzen und das Licht sofort anpassen (auch wenn das Spiel pausiert, z. B. Garage)
func set_time(hours: float) -> void:
	time_of_day = fposmod(hours, 24.0)
	_update_lighting()


## Licht neu berechnen (z. B. nachdem sich das Wetter in der Garage geändert hat)
func refresh() -> void:
	_update_lighting()


## Volumetrischen Nebel an- oder ausschalten (Qualitätsstufe hoch)
func set_volumetric_fog(enabled: bool) -> void:
	volumetric_fog = enabled
	world_environment.environment.volumetric_fog_enabled = enabled


## Richtung zur Sonne. Sie geht im Osten (+X) auf, steht mittags im Süden und geht im Westen unter.
func sun_direction() -> Vector3:
	var angle: float
	if time_of_day >= sunrise_hour and time_of_day <= sunset_hour:
		angle = (time_of_day - sunrise_hour) / (sunset_hour - sunrise_hour) * PI
	else:
		var night_length := 24.0 - (sunset_hour - sunrise_hour)
		angle = PI + fposmod(time_of_day - sunset_hour, 24.0) / night_length * PI
	var tilt := deg_to_rad(90.0 - sun_max_elevation)
	return Vector3(cos(angle), sin(angle) * cos(tilt), sin(angle) * sin(tilt)).normalized()


func _update_lighting() -> void:
	var sun_dir := sun_direction()
	# Der Mond steht ungefähr gegenüber der Sonne, etwas versetzt
	var moon_dir := Vector3(-sun_dir.x * 0.8, -sun_dir.y, -sun_dir.z + 0.35).normalized()
	var elevation := rad_to_deg(asin(sun_dir.y))
	# Position im Farbverlauf: 0 = tiefe Nacht (-18°), 1 = hoher Sonnenstand (+40°)
	var t := clampf((elevation + 18.0) / 58.0, 0.0, 1.0)
	var day := smoothstep(-4.0, 6.0, elevation)
	var night := 1.0 - smoothstep(-14.0, -3.0, elevation)
	daylight = day
	# Wetter: 0 = klar, 1 = ganz grau (Regen, Gewitter); Blitz = kurzes Aufleuchten
	var overcast := weather.overcast if weather else 0.0
	var flash := weather.lightning_flash if weather else 0.0

	# --- Licht: tagsüber Sonne, nachts Mond ---
	if elevation > -4.0:
		_point_light_from(sun_dir)
		sun.light_color = sun_colors.sample(t)
		sun.light_energy = sun_energy * day * (1.0 - overcast * 0.8)
	else:
		_point_light_from(moon_dir)
		sun.light_color = Color(0.62, 0.72, 1.0)
		sun.light_energy = moon_energy * smoothstep(-4.0, -10.0, elevation) * clampf(moon_dir.y * 4.0, 0.0, 1.0) \
			* (1.0 - overcast * 0.9)

	# Bei bedecktem Himmel gibt es keine harten Schatten. Ganz ausschalten spart viel
	# Rechenzeit, die dafür in Regen-Spiegelungen und Partikel geht.
	var shadow_opacity := 1.0 - smoothstep(0.45, 0.75, overcast)
	sun.shadow_enabled = shadow_opacity > 0.01
	sun.shadow_opacity = shadow_opacity
	# Ohne Schatten würde die Sonne durch die Tunnelwände scheinen
	if not sun.shadow_enabled:
		sun.light_energy *= 1.0 - tunnel_cover

	# --- Himmel (bei trübem Wetter grauer und dunkler) ---
	var zenith := _overcast_color(zenith_colors.sample(t), overcast)
	var horizon := _overcast_color(horizon_colors.sample(t), overcast)
	_sky_material.set_shader_parameter("sun_direction", sun_dir)
	_sky_material.set_shader_parameter("moon_direction", moon_dir)
	_sky_material.set_shader_parameter("zenith_color", zenith)
	_sky_material.set_shader_parameter("horizon_color", horizon)
	_sky_material.set_shader_parameter("ground_color", horizon.darkened(0.6))
	_sky_material.set_shader_parameter("sun_glow_color", glow_colors.sample(t))
	# Das Glühen ist bei tiefer Sonne viel stärker als mittags
	_sky_material.set_shader_parameter("sun_glow_strength", lerpf(1.6, 0.35, smoothstep(0.0, 30.0, elevation))
		* smoothstep(-10.0, -1.0, elevation) * (1.0 - overcast * 0.85))
	_sky_material.set_shader_parameter("sun_disk_color", sun_colors.sample(t))
	_sky_material.set_shader_parameter("sun_disk_energy", 40.0 * (1.0 - overcast * 0.97))
	_sky_material.set_shader_parameter("night_amount", night * (1.0 - overcast))
	var cloud_light := cloud_light_colors.sample(t)
	cloud_light = cloud_light.lerp(Color(cloud_light.get_luminance(), cloud_light.get_luminance(), cloud_light.get_luminance()), overcast * 0.6)
	_sky_material.set_shader_parameter("cloud_light_color", cloud_light * (1.0 - overcast * 0.45))
	_sky_material.set_shader_parameter("cloud_shadow_color", cloud_shadow_colors.sample(t) * (1.0 - overcast * 0.55))
	_sky_material.set_shader_parameter("cloud_coverage", weather.clouds if weather else cloud_coverage)
	_sky_material.set_shader_parameter("sky_energy", 1.0 + flash * 2.5)
	# Regenbogen nur bei tiefer Sonne (sonst liegt er unter dem Horizont) und wenn sie scheint
	var rainbow := weather.rainbow if weather else 0.0
	rainbow *= smoothstep(1.0, 6.0, elevation) * (1.0 - smoothstep(32.0, 41.0, elevation)) \
		* (1.0 - smoothstep(0.35, 0.7, overcast))
	_sky_material.set_shader_parameter("rainbow", rainbow)
	_sky_material.set_shader_parameter("aurora", (weather.aurora if weather else 0.0) * night * (1.0 - overcast))

	# --- Umgebung: Nebel, Umgebungslicht, Belichtung ---
	var env := world_environment.environment
	env.fog_light_color = horizon.lerp(zenith, 0.3)
	env.fog_sun_scatter = lerpf(0.5, 0.1, smoothstep(0.0, 25.0, elevation)) * day * (1.0 - overcast)
	# Regen und Nebel: Fernnebel viel dichter, auch der Himmel verschwindet darin
	var fog_factor := weather.fog_factor if weather else 1.0
	env.fog_density = fog_density * fog_factor
	env.fog_sky_affect = lerpf(0.3, 0.95, clampf((fog_factor - 1.0) / 20.0, 0.0, 1.0))
	env.ambient_light_energy = lerpf(night_ambient, day_ambient, day) + flash * 3.0
	# Nachts kommt ein Teil des Grundlichts von einer festen Nachtfarbe statt vom Himmel
	env.ambient_light_color = night_ambient_color
	env.ambient_light_sky_contribution = lerpf(0.25, 1.0, day)
	# Nachts sieht das Auge kaum Farben, tagsüber darf es etwas kräftiger sein
	env.adjustment_saturation = lerpf(night_saturation, day_saturation, smoothstep(-8.0, 4.0, elevation))
	# Bei trübem Wetter etwas heller belichten (wie das Auge, das sich anpasst)
	env.tonemap_exposure = lerpf(night_exposure, day_exposure, smoothstep(-10.0, 2.0, elevation)) * (1.0 + overcast * 0.25)
	# Im Tunnel: kein Licht vom Himmel (auch keine Himmels-Spiegelung), das Auge passt sich an.
	# Nachts ist es draußen ohnehin dunkel, dann braucht es keine Anpassung.
	env.ambient_light_energy *= 1.0 - tunnel_cover * 0.92
	env.ambient_light_sky_contribution *= 1.0 - tunnel_cover
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED if tunnel_cover > 0.5 \
		else Environment.REFLECTION_SOURCE_SKY
	env.tonemap_exposure *= lerpf(1.0, tunnel_exposure, _adaptation * day)


## Himmelsfarbe bei trübem Wetter: Richtung Grau (gleiche Helligkeit) und etwas dunkler
func _overcast_color(color: Color, overcast: float) -> Color:
	var l := color.get_luminance()
	var grey := Color(l * 0.95, l * 0.98, l * 1.05) * (1.0 - overcast * 0.4)
	return color.lerp(grey, overcast)


## Dreht das Licht so, dass es aus dieser Richtung scheint
func _point_light_from(direction_to_light: Vector3) -> void:
	var up := Vector3.UP if absf(direction_to_light.y) < 0.99 else Vector3.RIGHT
	sun.global_basis = Basis.looking_at(-direction_to_light, up)


static func _gradient(stops: Array) -> Gradient:
	var gradient := Gradient.new()
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for stop: Array in stops:
		offsets.append(stop[0])
		colors.append(stop[1])
	gradient.offsets = offsets
	gradient.colors = colors
	return gradient
