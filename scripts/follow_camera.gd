class_name FollowCamera
extends Camera3D
## Kamera des Spielers mit drei Ansichten (Taste Tab):
##  - Verfolger: folgt dem Auto weich von hinten (Feder: schwingt in Kurven leicht nach), schaut in die
##    Kurve hinein und weitet bei Tempo das Sichtfeld. Sie hängt bewusst nicht direkt am Auto, sonst
##    würde sie jede Bodenwelle und jedes Kippen der Karosserie mitmachen.
##  - Cockpit: vom Fahrersitz (Augen laut Profil), Armaturenbrett, Lenkrad und Spiegel sichtbar
##  - Ego: weiter vorne an der Scheibe, man sieht Motorhaube und den oberen Teil des Lenkrads
## Im Auto bewegt sich der Kopf mit: Fliehkraft, Bremsen und Gasgeben schieben ihn (Feder mit Dämpfer),
## dazu Zittern nach Drehzahl und Straße und ein kurzer Ruck beim Schalten. Bei Kollisionen
## (CollisionEffects) ruckt die Kamera kurz in allen Ansichten.

enum View { FOLLOW, COCKPIT, EGO }
const VIEW_NAMES: Array[String] = ["Verfolger", "Cockpit", "Ego-Sicht"]

## Das Auto, dem die Kamera folgt
@export var target: VehicleBody3D
## Aktuelle Ansicht
@export var view: View = View.FOLLOW

@export_group("Position")
## Abstand hinter dem Auto in Metern (im Stand)
@export var distance: float = 6.5
## Höhe über dem Auto in Metern
@export var height: float = 2.3
## Wie schnell die Kamera hinter das Auto schwenkt (Eigenfrequenz der Feder, höher = straffer)
@export var follow_speed: float = 3.2
## Dämpfung der Feder: 1 = schwingt nicht nach, kleiner = schwingt weich nach
@export var swing_damping: float = 0.72
## In die Kurve schauen: so viele Meter seitlich pro rad/s Drehrate (höchstens max_look_side)
@export var look_into_curve: float = 2.2
@export var max_look_side: float = 3.0
## Wie weit die Kamera in Fahrtrichtung vorausschaut (in Sekunden Fahrweg)
@export var look_ahead_time: float = 0.25
## Höchstens so viele Meter schaut sie voraus
@export var max_look_ahead: float = 8.0

@export_group("Tempo-Effekt")
## Bei diesem Tempo (km/h) ist der Zoom-Effekt voll da
@export var zoom_full_speed_kmh: float = 250.0
## So viele Meter weiter weg ist die Kamera bei vollem Tempo
@export var extra_distance: float = 2.5
## Sichtfeld im Stand in Grad
@export var base_fov: float = 65.0
## So viel breiter wird das Sichtfeld bei vollem Tempo (Grad)
@export var extra_fov: float = 10.0
## Wie schnell sich Abstand und Sichtfeld dem Tempo anpassen
@export var zoom_speed: float = 2.0

@export_group("Cockpit und Ego")
## Sichtfeld (senkrecht, Grad) und wie viel breiter es bei vollem Tempo wird
@export var cockpit_fov: float = 58.0
@export var ego_fov: float = 62.0
@export var inside_extra_fov: float = 4.0
## Ego-Sicht: so weit vor, über und neben den Augen (Meter, Auto-Koordinaten)
@export var ego_offset := Vector3(-0.08, 0.03, 0.3)
## Blick leicht nach unten (Grad), damit man die Instrumente sieht
@export var cockpit_pitch: float = -4.0
@export var ego_pitch: float = -3.0
## Nahe Grenze der Kamera im Auto (Meter): sonst schneidet sie das Lenkrad ab
@export var inside_near: float = 0.03
## Kopf: so viele Meter pro 1 g Beschleunigung, Eigenfrequenz der Feder (Hz) und Dämpfung (1 = schwingt
## nicht nach)
@export var head_shift_per_g: float = 0.05
@export var head_frequency: float = 1.7
@export var head_damping: float = 0.55
## So viele Grad neigt sich der Kopf bei 1 g (Kurve: zur Seite, Bremsen: nach vorne)
@export var head_tilt_per_g: float = 2.2
## Zittern in Metern: Motor bei Vollgas am Begrenzer, Straße bei 100 km/h (abseits der Straße mal Faktor)
@export var engine_shake: float = 0.0006
@export var road_shake: float = 0.0012
@export var offroad_shake_factor: float = 3.5
## Ruck beim Schalten: Tempo (m/s), das der Kopf nach vorne bekommt
@export var shift_kick: float = 0.1
## Blick in die Kurve: so viele Grad bei vollem Lenkeinschlag
@export var look_into_turn: float = 5.0

@export_group("Kollision")
## Ruck bei einem vollen Aufprall: Verfolger (Meter), im Auto (Kopf-Tempo m/s)
@export var hit_shake: float = 0.35
@export var hit_head_kick: float = 0.6
# Richtung (Winkel um die Hochachse), hinter der die Kamera steht, und wie schnell sie schwenkt
var _yaw: float = 0.0
var _yaw_velocity: float = 0.0
# Seitlicher Blick in die Kurve (Meter) und Ruck nach Kollisionen (0–1, klingt ab)
var _look_side: float = 0.0
var _jolt: float = 0.0
# 0 = Auto steht, 1 = volles Tempo
var _zoom: float = 0.0
# Kopf im Auto: Auslenkung und Tempo der Feder (Auto-Koordinaten), gemessene Beschleunigung, Zittern
var _head := Vector3.ZERO
var _head_velocity := Vector3.ZERO
var _last_velocity := Vector3.ZERO
var _accel := Vector3.ZERO
var _shake := Vector3.ZERO
var _look_yaw: float = 0.0
var _on_road: bool = true
var _road_check_timer: float = 0.0
var _connected_car: VehicleBody3D


func _ready() -> void:
	# Beim Start sofort an die richtige Stelle springen statt hinzugleiten
	_update_camera(0.0, true)
	reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	# Im Physik-Takt bewegen, genau wie das Auto. Die Physik-Interpolation
	# sorgt dann dafür, dass beides auch bei 120 Hz-Bildschirmen flüssig aussieht.
	_update_camera(delta, false)


func _unhandled_input(event: InputEvent) -> void:
	# Nur, wenn die Kamera gerade selbst fährt (nicht im Fotomodus, Chill-Modus, Test-Fotos)
	if event.is_action_pressed("cycle_camera") and current and is_physics_processing():
		set_view(((view + 1) % View.size()) as View)
		Toasts.post(get_tree(), "camera", VIEW_NAMES[view], "Tab wechselt die Ansicht")


## Ansicht wechseln (springt sofort an die neue Stelle)
func set_view(new_view: View) -> void:
	view = new_view
	_head = Vector3.ZERO
	_head_velocity = Vector3.ZERO
	_update_camera(0.0, true)
	reset_physics_interpolation()


## Sitzt die Kamera gerade im Auto (Cockpit oder Ego) und fährt sie selbst?
func is_inside_car() -> bool:
	return view != View.FOLLOW and current and is_physics_processing()


func _update_camera(delta: float, snap: bool) -> void:
	if not target:
		return
	if target != _connected_car and target is Car:
		_connected_car = target
		(target as Car).gear_changed.connect(_on_gear_changed)
		var collisions := target.get_node_or_null("CollisionEffects") as CollisionEffects
		if collisions:
			collisions.hit.connect(_on_hit)
	_jolt = move_toward(_jolt, 0.0, delta * 3.0)
	if view == View.FOLLOW or not (target is Car) or (target as Car).profile == null:
		near = 0.1
		_update_follow(delta, snap)
	else:
		near = inside_near
		_update_inside(delta, snap)


func _update_follow(delta: float, snap: bool) -> void:
	# Hinter das Auto schwenken wie an einer Feder: bei großer Dämpfung weich, darunter schwingt die
	# Kamera nach einer Kurve leicht nach
	var forward := _flat_forward()
	var target_yaw := atan2(forward.x, forward.z)
	if snap:
		_yaw = target_yaw
		_yaw_velocity = 0.0
	else:
		var omega := follow_speed
		var spring := wrapf(target_yaw - _yaw, -PI, PI) * omega * omega - _yaw_velocity * 2.0 * swing_damping * omega
		_yaw_velocity += spring * delta
		_yaw = wrapf(_yaw + _yaw_velocity * delta, -PI, PI)
	var heading := Vector3(sin(_yaw), 0.0, cos(_yaw))

	# Bei Tempo etwas zurückfahren und das Sichtfeld weiten
	var speed_kmh: float = target.linear_velocity.length() * 3.6
	var zoom_target: float = clampf(speed_kmh / zoom_full_speed_kmh, 0.0, 1.0)
	_zoom = lerpf(_zoom, zoom_target, 1.0 if snap else 1.0 - exp(-zoom_speed * delta))
	fov = base_fov + extra_fov * _zoom

	var car_pos: Vector3 = target.global_position
	var shake := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * hit_shake * _jolt * _jolt
	global_position = car_pos - heading * (distance + extra_distance * _zoom) + Vector3.UP * height + shake

	# Blickpunkt: etwas über dem Auto, ein Stück in Fahrtrichtung voraus und seitlich in die Kurve
	var ahead: Vector3 = target.linear_velocity * look_ahead_time
	ahead.y = 0.0
	ahead = ahead.limit_length(max_look_ahead)
	var side_target := clampf(target.angular_velocity.y * look_into_curve, -max_look_side, max_look_side)
	_look_side = side_target if snap else lerpf(_look_side, side_target, 1.0 - exp(-2.5 * delta))
	var left := Vector3(heading.z, 0.0, -heading.x)
	look_at(car_pos + Vector3.UP + ahead + left * _look_side, Vector3.UP)


## Cockpit und Ego: Augen laut Profil, Kopf bewegt sich mit Beschleunigung, Zittern und Schaltruck
func _update_inside(delta: float, snap: bool) -> void:
	var car := target as Car
	var car_basis := car.global_basis
	var speed := car.linear_velocity.length()
	if snap or delta <= 0.0:
		_last_velocity = car.linear_velocity
		_accel = Vector3.ZERO
	else:
		# Beschleunigung im Auto (geglättet, sonst zuckt der Kopf bei jedem Kontakt der Räder)
		var accel_world := (car.linear_velocity - _last_velocity) / delta
		_last_velocity = car.linear_velocity
		# Über 60 g ist kein Unfall mehr, sondern ein Sprung (Reset, Teleport): nicht mitwackeln
		if accel_world.length() > 600.0:
			accel_world = Vector3.ZERO
			_head_velocity = Vector3.ZERO
		_accel = _accel.lerp(car_basis.inverse() * accel_world, 1.0 - exp(-12.0 * delta))
		# Der Kopf wird gegen die Beschleunigung gedrückt: Feder mit Dämpfer zieht ihn zurück
		var push := -_accel / 9.81 * head_shift_per_g
		push.y *= 0.5
		push = push.limit_length(head_shift_per_g * 1.6)
		var omega := TAU * head_frequency
		var spring := (push - _head) * omega * omega - _head_velocity * 2.0 * head_damping * omega
		_head_velocity += spring * delta
		_head += _head_velocity * delta
		_shake = _shake.lerp(_shake_target(car, speed, delta), 0.5)
	var inside_view := view == View.COCKPIT
	var eye := car.profile.eye_position + (Vector3.ZERO if inside_view else ego_offset)
	# Blick leicht in die Kurve
	var look_target := car.steer_amount() * deg_to_rad(look_into_turn)
	_look_yaw = look_target if snap else lerpf(_look_yaw, look_target, 1.0 - exp(-4.0 * delta))
	# Kopf neigt sich zur Seite, zu der er gedrückt wird (Kurve links: nach rechts)
	var roll := _head.x / head_shift_per_g * deg_to_rad(head_tilt_per_g)
	var pitch := deg_to_rad(cockpit_pitch if inside_view else ego_pitch) - _head.z / head_shift_per_g * deg_to_rad(head_tilt_per_g) * 0.5
	var head_basis := Basis(Vector3.UP, PI + _look_yaw) * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.BACK, roll)
	global_transform = car.global_transform * Transform3D(head_basis, eye + _head + _shake)
	var zoom := clampf(speed * 3.6 / zoom_full_speed_kmh, 0.0, 1.0)
	fov = (cockpit_fov if inside_view else ego_fov) + inside_extra_fov * zoom


## Zittern: Motor nach Drehzahl und Gas, Straße nach Tempo (abseits der Straße stärker)
func _shake_target(car: Car, speed: float, delta: float) -> Vector3:
	_road_check_timer -= delta
	if _road_check_timer <= 0.0:
		_road_check_timer = 0.2
		var body := car.corner_wheels()[0].get_contact_body()
		_on_road = body != null and (body.has_meta("road_segment") or body.has_meta("junction"))
	var rpm := clampf(car.engine_rpm / car.profile.redline_rpm, 0.0, 1.0)
	var engine := engine_shake * rpm * rpm * (0.3 + 0.7 * car.throttle_input)
	var road := road_shake * clampf(speed / 27.8, 0.0, 1.5) * (1.0 if _on_road else offroad_shake_factor)
	return Vector3(randf_range(-1.0, 1.0) * (engine + road * 0.4), randf_range(-1.0, 1.0) * (engine + road),
		randf_range(-1.0, 1.0) * engine * 0.5)


## Schaltruck: Beim Hochschalten unter Last nickt der Kopf kurz nach vorne (Zugkraft bricht ab)
func _on_gear_changed(new_gear: int) -> void:
	if view == View.FOLLOW or not (target is Car):
		return
	var car := target as Car
	var load_factor := clampf(car.throttle_input, 0.2, 1.0)
	_head_velocity.z += shift_kick * load_factor * (1.0 if new_gear > 1 else 0.5)


## Kollision (CollisionEffects): Kamera ruckt; im Auto wird der Kopf weggestoßen
func _on_hit(strength: float, direction: Vector3) -> void:
	_jolt = maxf(_jolt, strength)
	if view != View.FOLLOW:
		_head_velocity += -direction.normalized() * hit_head_kick * strength


## Blickrichtung des Autos flach auf dem Boden (ohne Neigung nach oben/unten)
func _flat_forward() -> Vector3:
	# Beim VehicleBody3D zeigt die Nase in Richtung +Z
	var forward: Vector3 = target.global_basis.z
	forward.y = 0.0
	if forward.length() < 0.1:
		# Auto steht fast senkrecht: lieber die alte Richtung behalten
		return Vector3(sin(_yaw), 0.0, cos(_yaw))
	return forward.normalized()
