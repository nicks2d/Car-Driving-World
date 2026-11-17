class_name ShaderWarmup
extends Node3D
## Shader vorher übersetzen: Während des Ladebildschirms zeigt dieser Knoten ein paar Bilder lang kleine Flächen
## mit allen Materialien, die erst später gebraucht werden (Regen auf den Scheiben, Tropfen und Schnee auf dem
## Lack, Ausblenden beim Wechsel der Detailstufe, Impostoren, Tunnel, Spiegel, Rücklauf …), dazu Regen- und
## Schneepartikel. Godot übersetzt einen Shader erst, wenn er zum ersten Mal gezeichnet wird; ohne das ruckelt
## es beim ersten Regen oder im ersten Tunnel. Danach verschwindet der Knoten wieder.

## So viele Bilder lang bleiben die Flächen stehen
@export var frames: int = 6

var _camera: Camera3D
var _left: int = 0


## Vor der Kamera aufbauen (game.gd ruft das beim Start auf, solange der Ladebildschirm zu sehen ist)
func start(camera: Camera3D, extra_materials: Array[Material]) -> void:
	_camera = camera
	var materials: Array[Material] = []
	for path: String in ["res://shaders/car_glass_rain.gdshader", "res://shaders/car_glass.gdshader",
			"res://shaders/car_paint_fx.gdshader", "res://shaders/foliage_fade.gdshader",
			"res://shaders/terrain_fade.gdshader", "res://shaders/impostor.gdshader",
			"res://shaders/impostor_fade.gdshader", "res://shaders/tunnel_fan.gdshader",
			"res://shaders/car_lamp.gdshader", "res://shaders/car_mirror.gdshader"]:
		var material := ShaderMaterial.new()
		material.shader = load(path)
		materials.append(material)
	materials.append_array(extra_materials)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.05)
	for k in materials.size():
		var mesh := MeshInstance3D.new()
		mesh.mesh = quad
		mesh.material_override = materials[k]
		# Auch mit Schatten (eigene Varianten der Shader)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mesh.position = Vector3((k % 6 - 2.5) * 0.06, (k / 6 - 1.0) * 0.06, -1.0)
		add_child(mesh)
	# Partikel: Regen- und Schnee-Shader des Niederschlags, Funken
	for path: String in ["res://shaders/precipitation.gdshader", "res://shaders/precipitation_motion.gdshader"]:
		var particles := GPUParticles3D.new()
		particles.amount = 4
		particles.lifetime = 0.2
		var process := ParticleProcessMaterial.new()
		particles.process_material = process
		var draw := QuadMesh.new()
		draw.size = Vector2(0.02, 0.02)
		var material := ShaderMaterial.new()
		material.shader = load(path)
		draw.material = material
		particles.draw_pass_1 = draw
		particles.position = Vector3(0.0, -0.15, -1.0)
		add_child(particles)
	_left = frames


func _process(_delta: float) -> void:
	if _camera == null:
		return
	# Immer direkt vor der Kamera (hinter dem Ladebildschirm, deshalb unsichtbar für den Spieler)
	global_transform = _camera.global_transform
	_left -= 1
	if _left <= 0:
		queue_free()
