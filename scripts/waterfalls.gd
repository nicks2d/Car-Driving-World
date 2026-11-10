class_name Waterfalls
extends Node3D
## Wasserfälle in der Nähe (WorldGen.waterfalls_near): ein Band aus fallendem Wasser
## (waterfall.gdshader) knapp über dem Fels von der Kante bis ins Becken (das Becken ist ein
## kleiner See, den WorldGen ins Gelände gräbt). Nah am Auto zusätzlich Gischt, Nebel und
## Rauschen (3D-Geräusch, im Code erzeugt). make_effects nutzt auch die Staumauer (Überlauf).

@export var car: Node3D
@export var world_gen: WorldGen
## Bis hier ist das Band zu sehen, bis hier gibt es Gischt, Nebel und Rauschen (Meter)
@export var mesh_distance: float = 1800.0
@export var effect_distance: float = 320.0
## So oft nachsehen (Sekunden)
@export var update_interval: float = 0.5

static var _fall_material: ShaderMaterial
static var _sound: AudioStreamWAV
static var _spray_mesh: QuadMesh
static var _mist_mesh: QuadMesh

var _falls: Dictionary = {}  # Zelle -> {"node", "effects", "bottom"}
var _timer: float = 0.0


func _process(delta: float) -> void:
	if car == null or world_gen == null:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = update_interval
	var p := Vector2(car.global_position.x, car.global_position.z)
	var wanted := {}
	for fall: Dictionary in world_gen.waterfalls_near(Rect2(p - Vector2.ONE * mesh_distance, Vector2.ONE * mesh_distance * 2.0)):
		wanted[fall["cell"]] = fall
	for cell: Vector2i in _falls.keys():
		if not wanted.has(cell):
			(_falls[cell]["node"] as Node3D).queue_free()
			_falls.erase(cell)
	for cell: Vector2i in wanted:
		var fall: Dictionary = wanted[cell]
		if not _falls.has(cell):
			var node := MeshInstance3D.new()
			node.mesh = ribbon_mesh(fall["path"], fall["width"])
			node.material_override = fall_material()
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(node)
			_falls[cell] = {"node": node, "effects": null, "bottom": fall["bottom"]}
		# Gischt, Nebel und Rauschen nur in der Nähe
		var entry: Dictionary = _falls[cell]
		var bottom: Vector3 = entry["bottom"]
		var near := Vector2(bottom.x, bottom.z).distance_to(p) < effect_distance
		if near and entry["effects"] == null:
			var effects := make_effects(fall["width"], fall["drop"])
			(entry["node"] as Node3D).add_child(effects)
			effects.global_position = bottom
			entry["effects"] = effects
		elif not near and entry["effects"] != null:
			(entry["effects"] as Node3D).queue_free()
			entry["effects"] = null


## Band entlang des Pfads (Weltkoordinaten), 0,5 m über dem Fels, nach unten etwas breiter
static func ribbon_mesh(path: PackedVector3Array, width: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var travelled := 0.0
	for i in path.size():
		var a := path[maxi(i - 1, 0)]
		var b := path[mini(i + 1, path.size() - 1)]
		var along := (b - a).normalized()
		var across := Vector3(along.z, 0.0, -along.x).normalized()
		var normal := across.cross(along).normalized()
		if normal.y < 0.0:
			normal = -normal
		if i > 0:
			travelled += path[i].distance_to(path[i - 1])
		var half := width * (0.5 + 0.25 * float(i) / maxf(path.size() - 1, 1))
		var lift := normal * 0.5
		verts.append_array([path[i] + lift - across * half, path[i] + lift + across * half])
		normals.append_array([normal, normal])
		uvs.append_array([Vector2(0.0, travelled), Vector2(1.0, travelled)])
		if i > 0:
			var k := i * 2
			indices.append_array([k - 2, k - 1, k, k - 1, k + 1, k])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func fall_material(soft_edges: bool = true) -> ShaderMaterial:
	if _fall_material == null:
		_fall_material = ShaderMaterial.new()
		_fall_material.shader = load("res://shaders/waterfall.gdshader")
	if soft_edges:
		return _fall_material
	var hard := _fall_material.duplicate() as ShaderMaterial
	hard.set_shader_parameter("soft_edges", false)
	return hard


## Gischt (Tropfen), Nebel (große weiche Flächen, steigen langsam) und Rauschen; der Knoten
## kommt an den Fuß des Falls. width = Breite des Wassers, drop = Fallhöhe (lauter und mehr
## Nebel bei hohen Fällen).
static func make_effects(width: float, drop: float) -> Node3D:
	var node := Node3D.new()
	var spray := GPUParticles3D.new()
	spray.amount = 140
	spray.lifetime = 1.4
	spray.visibility_aabb = AABB(Vector3(-15, -3, -15), Vector3(30, 18, 30))
	var spray_process := ParticleProcessMaterial.new()
	spray_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	spray_process.emission_box_extents = Vector3(width * 0.5, 0.3, width * 0.5)
	spray_process.direction = Vector3.UP
	spray_process.spread = 55.0
	spray_process.initial_velocity_min = 1.5
	spray_process.initial_velocity_max = 2.5 + drop * 0.08
	spray_process.gravity = Vector3(0.0, -6.0, 0.0)
	spray_process.scale_min = 0.5
	spray_process.scale_max = 1.5
	spray_process.color_ramp = _fade_ramp(0.8)
	spray.process_material = spray_process
	spray.draw_pass_1 = _particle_mesh(0.08)
	node.add_child(spray)
	var mist := GPUParticles3D.new()
	mist.amount = 26
	mist.lifetime = 6.0
	mist.preprocess = 6.0
	mist.visibility_aabb = AABB(Vector3(-25, -3, -25), Vector3(50, 30, 50))
	var mist_process := ParticleProcessMaterial.new()
	mist_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mist_process.emission_sphere_radius = width * 0.7
	mist_process.direction = Vector3.UP
	mist_process.spread = 30.0
	mist_process.initial_velocity_min = 0.4
	mist_process.initial_velocity_max = 1.2
	mist_process.gravity = Vector3(0.3, 0.15, 0.0)
	mist_process.scale_min = 1.0
	mist_process.scale_max = 2.2 + drop * 0.02
	mist_process.color_ramp = _fade_ramp(0.22)
	mist.process_material = mist_process
	mist.draw_pass_1 = _particle_mesh(3.0)
	node.add_child(mist)
	var sound := AudioStreamPlayer3D.new()
	sound.stream = _waterfall_sound()
	sound.bus = "Umgebung"
	sound.unit_size = 6.0 + drop * 0.15
	sound.max_distance = 300.0
	sound.volume_db = -4.0
	sound.autoplay = true
	node.add_child(sound)
	return node


## Weicher runder Partikel (Verlauf), weiß, unbeleuchtet, Größe in Metern
static func _particle_mesh(size: float) -> QuadMesh:
	var cached := _spray_mesh if size < 1.0 else _mist_mesh
	if cached:
		return cached
	var dot := Gradient.new()
	dot.set_color(0, Color(1, 1, 1, 1))
	dot.set_color(1, Color(1, 1, 1, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = dot
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 32
	texture.height = 32
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = texture
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.albedo_color = Color(0.92, 0.95, 0.98, 1.0)
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = material
	if size < 1.0:
		_spray_mesh = quad
	else:
		_mist_mesh = quad
	return quad


static func _fade_ramp(alpha: float) -> GradientTexture1D:
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.0))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	fade.add_point(0.2, Color(1, 1, 1, alpha))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	return ramp


## Rauschen eines Wasserfalls: tiefes und helles Rauschen gemischt, 3 s, nahtlos (im Code erzeugt)
static func _waterfall_sound() -> AudioStreamWAV:
	if _sound:
		return _sound
	var rate := 22050
	var count := rate * 3
	var fade := int(rate * 0.3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var samples := PackedFloat32Array()
	samples.resize(count)
	var low := 0.0
	var mid := 0.0
	for i in count:
		var white := rng.randf_range(-1.0, 1.0)
		low += (white - low) * 0.04
		mid += (white - mid) * 0.35
		var surge := 0.85 + 0.15 * sin(TAU * i / rate * 0.7)
		samples[i] = (low * 3.2 + mid * 0.6 + white * 0.12) * surge
	for i in fade:
		var w := float(i) / fade
		samples[i] = samples[i] * w + samples[count - fade + i] * (1.0 - w)
	var data := PackedByteArray()
	data.resize((count - fade) * 2)
	for i in count - fade:
		data.encode_s16(i * 2, int(clampf(samples[i] * 0.7, -1.0, 1.0) * 30000.0))
	_sound = AudioStreamWAV.new()
	_sound.format = AudioStreamWAV.FORMAT_16_BITS
	_sound.mix_rate = rate
	_sound.data = data
	_sound.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_sound.loop_end = count - fade
	return _sound
