class_name TunnelEffects
extends Node
## Was im Tunnel passiert:
##  - ein paar echte Lichter an den Deckenlampen rund ums Auto (die übrigen Lampen leuchten
##    nur selbst, das kostet nichts)
##  - Hall auf dem Motorgeräusch (eigener Audio-Bus „Tunnel“ mit Reverb)
##  - Augen-Anpassung, kein Himmelslicht, kein Regen, trockene Reifen (über DayNight und Wetter)
##  - Abblendlicht an

@export var roads: RoadNetwork
@export var car: Car
@export var camera: Camera3D
@export var day_night: DayNight
@export var weather: Weather

@export_group("Lichter")
## So viele echte Lichter gibt es höchstens gleichzeitig (der Rest der Lampen leuchtet nur selbst)
@export var light_count: int = 8
@export var light_range: float = 20.0
@export var light_energy: float = 1.6
@export var light_color: Color = Color(1.0, 0.86, 0.68)
## Lichter werden so oft (Sekunden) neu verteilt
@export var light_update_interval: float = 0.2

@export_group("Hall")
## Anteil des Halls im Tunnel (0 bis 1)
@export var reverb_wet: float = 0.45
@export var reverb_room_size: float = 0.75

## 0 = draußen, 1 = tief im Tunnel (Kamera bzw. Auto)
var camera_cover: float = 0.0
var car_cover: float = 0.0

const BUS_NAME := "Tunnel"

var _lights: Array[OmniLight3D] = []
var _light_timer: float = 0.0
var _reverb: AudioEffectReverb


func _ready() -> void:
	for i in light_count:
		var light := OmniLight3D.new()
		light.omni_range = light_range
		light.light_energy = light_energy
		light.light_color = light_color
		light.omni_attenuation = 0.9
		light.shadow_enabled = false
		light.visible = false
		add_child(light)
		_lights.append(light)
	_create_bus()


## Eigener Audio-Bus mit Hall. Alle Geräusche des Autos laufen darüber.
func _create_bus() -> void:
	var index := AudioServer.get_bus_index(BUS_NAME)
	if index == -1:
		AudioServer.add_bus()
		index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, BUS_NAME)
		AudioServer.set_bus_send(index, "Master")
		_reverb = AudioEffectReverb.new()
		_reverb.room_size = reverb_room_size
		_reverb.damping = 0.35
		_reverb.spread = 0.8
		_reverb.wet = 0.0
		_reverb.dry = 1.0
		AudioServer.add_bus_effect(index, _reverb)
	else:
		_reverb = AudioServer.get_bus_effect(index, 0) as AudioEffectReverb
	if car:
		for player in car.find_children("*", "AudioStreamPlayer", true, false):
			(player as AudioStreamPlayer).bus = BUS_NAME


func _process(delta: float) -> void:
	if roads == null or car == null or camera == null:
		return
	camera_cover = roads.tunnel_cover(camera.global_position)
	car_cover = roads.tunnel_cover(car.global_position)
	if day_night:
		day_night.tunnel_cover = camera_cover
	if weather:
		weather.shelter = camera_cover
		weather.car_shelter = car_cover
	car.in_tunnel = car_cover > 0.3
	if _reverb:
		_reverb.wet = reverb_wet * car_cover
	_light_timer -= delta
	if _light_timer <= 0.0:
		_light_timer = light_update_interval
		_place_lights()


## Die echten Lichter an die Lampen setzen, die dem Auto am nächsten sind
func _place_lights() -> void:
	var spots := roads.tunnel_lights_near(car.global_position, 90.0)
	for i in _lights.size():
		var light := _lights[i]
		light.visible = i < spots.size()
		if light.visible:
			light.global_position = spots[i]
