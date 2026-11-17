class_name CarWeather
extends Node
## Wetter am Auto: wie nass, verschneit und vereist das Auto gerade ist (je 0–1). CarModel zeichnet es
## (Tropfen auf Lack und Scheiben, Schnee auf flachen Flächen, Eis auf den Scheiben).
##  - Nass: bei Regen in ein paar Sekunden, danach trocknet es langsam (im Stand ~2 min, beim Fahren
##    schneller). Im Tunnel kommt kein Regen dazu.
##  - Schnee: wächst, solange es schneit und das Auto (fast) steht, weht beim Fahren weg, taut über 1 °C
##  - Eis: Unter 0 °C sind die Scheiben zwischen 5 und 10 Uhr vereist (auch schon beim Start), beim
##    Fahren tauen sie langsam ab (Gebläse, von unten her), im Stand frieren sie langsam wieder zu.

@export_group("Nässe")
## Sekunden, bis das Auto bei Regen ganz nass ist, und bis es im Stand wieder trocken ist
@export var wet_seconds: float = 4.0
@export var dry_seconds: float = 120.0
## So viel schneller trocknet es bei 100 km/h
@export var dry_speed_factor: float = 4.0

@export_group("Schnee")
## Sekunden bis zur vollen Schneedecke im Stand (bei starkem Schnee), Tempo (km/h) bis zu dem noch Schnee
## liegen bleibt, und ab dem er wegweht; Sekunden zum Wegwehen bei 100 km/h
@export var snow_seconds: float = 90.0
@export var snow_settle_kmh: float = 8.0
@export var snow_blow_kmh: float = 25.0
@export var snow_blow_seconds: float = 4.0
@export var snow_melt_seconds: float = 150.0

@export_group("Eis")
## Kalter Morgen: zwischen diesen Uhrzeiten unter 0 °C vereist
@export var frost_hours := Vector2(5.0, 10.0)
## Sekunden zum Abtauen beim Fahren (ab 50 km/h, darunter langsamer), zum Wiedervereisen im Stand
@export var thaw_seconds: float = 40.0
@export var refreeze_seconds: float = 180.0

## Aktueller Zustand (0–1)
var wet: float = 0.0
var snow: float = 0.0
var frost: float = 0.0
## Für Test-Fotos (DebugTools): feste Werte, negativ = berechnen
var forced := Vector3(-1.0, -1.0, -1.0)

var _car: Car
var _model: CarModel
var _weather: Weather
var _day_night: DayNight
var _started: bool = false


func _ready() -> void:
	_car = get_parent() as Car
	_model = _car.get_node("Model") as CarModel


func _process(delta: float) -> void:
	if _weather == null:
		_weather = get_tree().get_first_node_in_group("weather") as Weather
		_day_night = get_tree().get_first_node_in_group("day_night") as DayNight
	if _weather == null or _car.freeze:
		return
	var kmh := _car.linear_velocity.length() * 3.6
	var temperature := _weather.temperature(_car.global_position.y)
	var hour := _day_night.time_of_day if _day_night else 12.0
	var cold_morning := temperature < 0.0 and hour >= frost_hours.x and hour <= frost_hours.y
	# Beim Start an einem kalten Morgen: Scheiben schon vereist
	if not _started:
		_started = true
		if cold_morning:
			frost = 1.0
	# Nässe
	var rain := 0.0 if _car.in_tunnel else Weather.rain_now
	if rain > 0.01:
		wet = move_toward(wet, maxf(rain, wet), delta / wet_seconds)
	else:
		wet = move_toward(wet, 0.0, delta / dry_seconds * (1.0 + dry_speed_factor * kmh / 100.0))
	# Schnee
	if Weather.snow_now > 0.1 and kmh < snow_settle_kmh and not _car.in_tunnel:
		snow = move_toward(snow, 1.0, delta / snow_seconds * Weather.snow_now)
	if kmh > snow_blow_kmh:
		snow = move_toward(snow, 0.0, delta / snow_blow_seconds * (kmh - snow_blow_kmh) / (100.0 - snow_blow_kmh))
	if temperature > 1.0:
		snow = move_toward(snow, 0.0, delta / snow_melt_seconds)
	# Eis
	if kmh > 5.0:
		frost = move_toward(frost, 0.0, delta / thaw_seconds * clampf(kmh / 50.0, 0.3, 1.0))
	elif cold_morning:
		frost = move_toward(frost, 1.0, delta / refreeze_seconds)
	if temperature > 0.0:
		frost = move_toward(frost, 0.0, delta / thaw_seconds * 0.5)
	_model.set_weather_fx(wet if forced.x < 0.0 else forced.x, snow if forced.y < 0.0 else forced.y,
		frost if forced.z < 0.0 else forced.z)
