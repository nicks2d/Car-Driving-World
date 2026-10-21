extends Camera3D
## Kamera, die dem Auto weich von hinten folgt.
## Sie hängt bewusst nicht direkt am Auto, sonst würde sie jede Bodenwelle
## und jedes Kippen der Karosserie mitmachen.

## Das Auto, dem die Kamera folgt
@export var target: VehicleBody3D

@export_group("Position")
## Abstand hinter dem Auto in Metern (im Stand)
@export var distance: float = 6.5
## Höhe über dem Auto in Metern
@export var height: float = 2.3
## Wie schnell die Kamera hinter das Auto schwenkt (höher = straffer)
@export var follow_speed: float = 4.0
## Wie weit die Kamera in Fahrtrichtung vorausschaut (in Sekunden Fahrweg)
@export var look_ahead_time: float = 0.25
## Höchstens so viele Meter schaut sie voraus
@export var max_look_ahead: float = 8.0

@export_group("Tempo-Effekt")
## Bei diesem Tempo (km/h) ist der Zoom-Effekt voll da
@export var zoom_full_speed_kmh: float = 200.0
## So viele Meter weiter weg ist die Kamera bei vollem Tempo
@export var extra_distance: float = 2.5
## Sichtfeld im Stand in Grad
@export var base_fov: float = 70.0
## So viel breiter wird das Sichtfeld bei vollem Tempo (Grad)
@export var extra_fov: float = 12.0
## Wie schnell sich Abstand und Sichtfeld dem Tempo anpassen
@export var zoom_speed: float = 2.0

# Geglättete Fahrtrichtung, hinter der die Kamera steht
var _heading: Vector3 = Vector3.BACK
# 0 = Auto steht, 1 = volles Tempo
var _zoom: float = 0.0


func _ready() -> void:
	# Beim Start sofort an die richtige Stelle springen statt hinzugleiten
	_update_camera(0.0, true)
	reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	# Im Physik-Takt bewegen, genau wie das Auto. Die Physik-Interpolation
	# sorgt dann dafür, dass beides auch bei 120 Hz-Bildschirmen flüssig aussieht.
	_update_camera(delta, false)


func _update_camera(delta: float, snap: bool) -> void:
	if not target:
		return

	# Richtung langsam der Fahrtrichtung des Autos nachführen.
	# 1 - exp(-k * delta) macht das Glätten unabhängig von der Bildrate.
	var smooth: float = 1.0 if snap else 1.0 - exp(-follow_speed * delta)
	_heading = _heading.slerp(_flat_forward(), smooth).normalized()

	# Bei Tempo etwas zurückfahren und das Sichtfeld weiten
	var speed_kmh: float = target.linear_velocity.length() * 3.6
	var zoom_target: float = clampf(speed_kmh / zoom_full_speed_kmh, 0.0, 1.0)
	_zoom = lerpf(_zoom, zoom_target, 1.0 if snap else 1.0 - exp(-zoom_speed * delta))
	fov = base_fov + extra_fov * _zoom

	var car_pos: Vector3 = target.global_position
	global_position = car_pos - _heading * (distance + extra_distance * _zoom) + Vector3.UP * height

	# Blickpunkt: etwas über dem Auto, plus ein Stück in Fahrtrichtung voraus
	var ahead: Vector3 = target.linear_velocity * look_ahead_time
	ahead.y = 0.0
	ahead = ahead.limit_length(max_look_ahead)
	look_at(car_pos + Vector3.UP + ahead, Vector3.UP)


## Blickrichtung des Autos flach auf dem Boden (ohne Neigung nach oben/unten)
func _flat_forward() -> Vector3:
	# Beim VehicleBody3D zeigt die Nase in Richtung +Z
	var forward: Vector3 = target.global_basis.z
	forward.y = 0.0
	if forward.length() < 0.1:
		# Auto steht fast senkrecht: lieber die alte Richtung behalten
		return _heading
	return forward.normalized()
