extends Node3D
## Kleine Flammen an den Endrohren, wenn es beim Gaswegnehmen im Auspuff knallt (nur mit
## Sportauspuff): pro Endrohr ein paar leuchtende Partikel, dazu ein kurzer orangefarbener
## Lichtblitz (ohne Schatten). Wo die Endrohre sitzen, steht im Profil (exhaust_tips).

## Wie lange eine Flamme sichtbar ist (Sekunden) und wie weit sie herausschießt (m/s)
@export var flame_lifetime: float = 0.09
@export var flame_speed: float = 5.0
@export var flame_size: float = 0.13
## Lichtblitz: Helligkeit bei einem starken Knall und Reichweite (Meter)
@export var light_energy: float = 2.0
@export var light_range: float = 3.5
## Erst ab dieser Knallstärke (0..1) gibt es eine Flamme
@export var min_strength: float = 0.3

var _car: Car
var _flames: Array[GPUParticles3D] = []
var _light: OmniLight3D
var _flash: float = 0.0
var _draw_material: StandardMaterial3D
var _process_material: ParticleProcessMaterial


func _ready() -> void:
	_car = get_parent() as Car
	_make_materials()
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.55, 0.2)
	_light.omni_range = light_range
	_light.shadow_enabled = false
	_light.visible = false
	add_child(_light)
	_car.profile_changed.connect(_build)
	if _car.profile:
		_build(_car.profile)
	(_car.get_node("EngineSound") as Node).connect("popped", _on_popped)


func _make_materials() -> void:
	# Weicher, runder Fleck, additiv (hell auf dunkel, nachts gut zu sehen)
	var blob := GradientTexture2D.new()
	blob.fill = GradientTexture2D.FILL_RADIAL
	blob.fill_from = Vector2(0.5, 0.5)
	blob.fill_to = Vector2(1.0, 0.5)
	var falloff := Gradient.new()
	falloff.set_color(0, Color(1, 1, 1, 1))
	falloff.set_color(1, Color(1, 1, 1, 0))
	blob.gradient = falloff
	_draw_material = StandardMaterial3D.new()
	_draw_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_draw_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_draw_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_draw_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_draw_material.vertex_color_use_as_albedo = true
	_draw_material.albedo_texture = blob
	# Farbe über die Lebenszeit: bläulich-weißer Kern, dann orange, dann rot und weg
	var colors := Gradient.new()
	colors.offsets = PackedFloat32Array([0.0, 0.2, 0.55, 1.0])
	colors.colors = PackedColorArray([Color(0.35, 0.5, 1.0, 0.9), Color(1.0, 0.65, 0.25, 0.9),
		Color(0.9, 0.3, 0.05, 0.7), Color(0.4, 0.05, 0.0, 0.0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = colors
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.25))
	var scale_texture := CurveTexture.new()
	scale_texture.curve = shrink
	_process_material = ParticleProcessMaterial.new()
	# Nach hinten aus dem Rohr (die Nase des Autos zeigt nach +Z)
	_process_material.direction = Vector3(0.0, 0.05, -1.0)
	_process_material.spread = 12.0
	_process_material.initial_velocity_min = flame_speed * 0.6
	_process_material.initial_velocity_max = flame_speed
	_process_material.gravity = Vector3.ZERO
	_process_material.scale_min = 0.6
	_process_material.scale_max = 1.0
	_process_material.scale_curve = scale_texture
	_process_material.color_ramp = ramp


## Pro Endrohr ein Partikel-System, das Licht in die Mitte der Endrohre
func _build(profile: CarProfile) -> void:
	for flame in _flames:
		flame.queue_free()
	_flames.clear()
	var middle := Vector3.ZERO
	for tip in profile.exhaust_tips:
		var flame := GPUParticles3D.new()
		flame.position = tip + Vector3(0.0, 0.0, -0.03)
		# Viele kleine Partikel, über die Lebenszeit verteilt: ergibt eine kurze Stichflamme
		flame.amount = 16
		flame.lifetime = flame_lifetime
		flame.one_shot = true
		flame.explosiveness = 0.4
		flame.local_coords = true
		flame.emitting = false
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flame.process_material = _process_material
		var quad := QuadMesh.new()
		quad.size = Vector2(flame_size, flame_size)
		quad.material = _draw_material
		flame.draw_pass_1 = quad
		add_child(flame)
		_flames.append(flame)
		middle += tip
	if not _flames.is_empty():
		_light.position = middle / _flames.size() + Vector3(0.0, 0.1, -0.4)


func _on_popped(strength: float) -> void:
	if not _car.sport_exhaust or strength < min_strength:
		return
	for flame in _flames:
		flame.restart()
	_flash = maxf(_flash, strength)


func _process(delta: float) -> void:
	if _flash <= 0.0:
		return
	_light.visible = true
	_light.light_energy = light_energy * _flash
	# Der Blitz ist nach ~60 ms wieder aus
	_flash = move_toward(_flash, 0.0, delta / 0.06)
	if _flash <= 0.0:
		_light.visible = false
