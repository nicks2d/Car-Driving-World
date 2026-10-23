class_name Precipitation
extends Node3D
## Regen und Schnee rund um die Kamera (zwei Partikelsysteme). Die Tropfen und Flocken
## bleiben fest in der Welt und wandern in einem Kasten mit der Kamera mit
## (precipitation_motion.gdshader). Wie stark es regnet oder schneit, setzt das Wetter.

@export var camera: Camera3D
## Höchstzahl der Tropfen bzw. Flocken (bei voller Stärke alle sichtbar)
@export var rain_count: int = 9000
@export var snow_count: int = 7000
## Größe des Kastens um die Kamera (Meter)
@export var box_size: Vector3 = Vector3(36.0, 22.0, 36.0)
## Fallgeschwindigkeit (Meter pro Sekunde)
@export var rain_speed: float = 11.0
@export var snow_speed: float = 1.4
## Länge der Regenstriche = so viele Sekunden Weg (wie eine Belichtungszeit)
@export var streak_time: float = 0.045

## Stärke 0 bis 1, Wind und Helligkeit (setzt das Wetter)
var rain: float = 0.0
var snow: float = 0.0
var wind: Vector3 = Vector3.ZERO
var brightness: float = 1.0

var _rain: GPUParticles3D
var _snow: GPUParticles3D
var _rain_motion: ShaderMaterial
var _snow_motion: ShaderMaterial
var _rain_look: ShaderMaterial
var _snow_look: ShaderMaterial
var _last_camera_position: Vector3 = Vector3.ZERO
var _camera_velocity: Vector3 = Vector3.ZERO


func _ready() -> void:
	_rain_motion = _motion_material()
	_snow_motion = _motion_material()
	_snow_motion.set_shader_parameter("flutter", 0.6)
	_rain_look = _look_material(false, 0.012, 0.3, Color(0.75, 0.78, 0.82))
	_snow_look = _look_material(true, 0.09, 0.9, Color(0.95, 0.96, 1.0))
	_rain = _create_particles(rain_count, _rain_motion, _rain_look)
	_snow = _create_particles(snow_count, _snow_motion, _snow_look)


func _process(delta: float) -> void:
	if camera == null:
		return
	var p := camera.global_position
	# Tempo der Kamera (bei einem Sprung, z. B. Reset, nicht mitzählen)
	if delta > 0.0 and p.distance_to(_last_camera_position) < 50.0:
		_camera_velocity = _camera_velocity.lerp((p - _last_camera_position) / delta, clampf(delta * 8.0, 0.0, 1.0))
	_last_camera_position = p
	# Kasten etwas über der Kamera: oben sieht man mehr als unten
	global_position = p + Vector3(0.0, 3.0, 0.0)

	_rain.visible = rain > 0.001
	_snow.visible = snow > 0.001
	if _rain.visible:
		var fall := Vector3(wind.x, -rain_speed, wind.z)
		var relative := fall - _camera_velocity
		_rain_motion.set_shader_parameter("fall_velocity", fall)
		_rain_look.set_shader_parameter("intensity", rain)
		_rain_look.set_shader_parameter("streak_direction", relative.normalized())
		_rain_look.set_shader_parameter("streak_length", clampf(relative.length() * streak_time, 0.3, 2.5))
		_rain_look.set_shader_parameter("brightness", brightness)
	if _snow.visible:
		_snow_motion.set_shader_parameter("fall_velocity", Vector3(wind.x, -snow_speed, wind.z) * 0.6)
		_snow_look.set_shader_parameter("intensity", snow)
		_snow_look.set_shader_parameter("brightness", brightness)


func _motion_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/precipitation_motion.gdshader")
	material.set_shader_parameter("box_size", box_size)
	return material


func _look_material(is_snow: bool, size: float, opacity: float, color: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/precipitation.gdshader")
	material.set_shader_parameter("is_snow", is_snow)
	material.set_shader_parameter("size", size)
	material.set_shader_parameter("opacity", opacity)
	material.set_shader_parameter("color", color)
	material.set_shader_parameter("fade_radius", box_size.x * 0.5)
	return material


func _create_particles(count: int, motion: ShaderMaterial, look: ShaderMaterial) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = count
	# Sehr lange Lebensdauer, alle auf einmal: die Partikel werden nur im Kasten herumgeschoben
	particles.lifetime = 600.0
	particles.explosiveness = 1.0
	particles.local_coords = false
	# Jedes Bild rechnen und nicht zwischen Schritten überblenden (sonst Striche beim Umklappen)
	particles.fixed_fps = 0
	particles.interpolate = false
	particles.process_material = motion
	particles.visibility_aabb = AABB(-box_size * 0.5 - Vector3.ONE * 3.0, box_size + Vector3.ONE * 6.0)
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var quad := QuadMesh.new()
	quad.material = look
	particles.draw_pass_1 = quad
	particles.visible = false
	add_child(particles)
	return particles
