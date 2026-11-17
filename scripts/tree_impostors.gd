class_name TreeImpostors
extends Node
## Impostoren für ferne Bäume: Beim Start wird jede Baumart einmal aus 8 Blickwinkeln (rundherum, leicht
## von oben) in ein Bild gezeichnet, einmal die Farbe und einmal die Normalen. Ferne Bäume sind dann nur
## noch ein Viereck, das sich zur Kamera dreht und das passende Bild zeigt (shaders/impostor.gdshader).
## Gezeichnet wird in einem eigenen SubViewport mit eigener Welt (die Spielwelt sieht davon nichts).

signal baked

## Größe eines Bilds (Bildpunkte) und Anzahl der Blickwinkel
@export var frame_size := Vector2i(192, 256)
@export var frames: int = 8

## Größe eines Bilds in Modell-Einheiten (Bäume sind 1 hoch): so breit und so hoch (unten etwas Rand)
const FRAME_WORLD := Vector2(0.7875, 1.05)
const FRAME_BOTTOM: float = -0.025

var ready_to_use: bool = false
## Je Baumart: [Farbbild, Normalenbild]
var atlases: Dictionary = {}
var _quad: ArrayMesh


## Bilder für diese Meshes backen (Art -> Mesh), mit dem Rauschen für das Blattmuster
func bake(meshes: Dictionary, leaf_noise: Texture2D) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(frame_size.x * frames, frame_size.y)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world_env := WorldEnvironment.new()
	world_env.environment = environment
	viewport.add_child(world_env)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = FRAME_WORLD.y
	camera.near = 1.0
	camera.far = 20.0
	# Leicht von oben (8°), Mitte des Bilds auf halber Baumhöhe
	camera.rotation = Vector3(deg_to_rad(-8.0), 0.0, 0.0)
	camera.position = Vector3(0.0, FRAME_BOTTOM + FRAME_WORLD.y * 0.5, 0.0) + camera.basis.z * 10.0
	viewport.add_child(camera)
	camera.current = true
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/impostor_bake.gdshader")
	material.set_shader_parameter("leaf_noise", leaf_noise)
	for kind: String in meshes:
		var trees: Array[MeshInstance3D] = []
		for k in frames:
			var tree := MeshInstance3D.new()
			tree.mesh = meshes[kind]
			tree.material_override = material
			# Bild k zeigt den Baum aus der Richtung k × 45° (Modell-Raum): Baum um −k × 45° gedreht
			tree.transform = Transform3D(Basis(Vector3.UP, -TAU * k / frames),
				Vector3((k - (frames - 1) * 0.5) * FRAME_WORLD.x, 0.0, 0.0))
			viewport.add_child(tree)
			trees.append(tree)
		var images: Array[Image] = []
		for normals: bool in [false, true]:
			material.set_shader_parameter("normals", normals)
			viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var image := viewport.get_texture().get_image()
			# Durchsichtige Ränder mit der Farbe daneben füllen: Sonst mischt sich beim Verkleinern (Mipmaps)
			# der schwarze Hintergrund hinein und ferne Bäume werden dunkel
			image.fix_alpha_edges()
			image.generate_mipmaps()
			images.append(image)
		atlases[kind] = [ImageTexture.create_from_image(images[0]), ImageTexture.create_from_image(images[1])]
		# Zum Prüfen: --impostordump speichert die Bilder nach screenshots/
		if OS.get_cmdline_user_args().has("--impostordump"):
			images[0].save_png(ProjectSettings.globalize_path("res://screenshots/impostor_%s_farbe.png" % kind))
			images[1].save_png(ProjectSettings.globalize_path("res://screenshots/impostor_%s_normale.png" % kind))
		for tree in trees:
			tree.queue_free()
		await get_tree().process_frame
	viewport.queue_free()
	ready_to_use = true
	baked.emit()


## Viereck für die Impostoren (Mitte unten, wird im Shader zur Kamera gedreht)
func quad_mesh() -> ArrayMesh:
	if _quad:
		return _quad
	var half := FRAME_WORLD.x * 0.5
	var top := FRAME_BOTTOM + FRAME_WORLD.y
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-half, FRAME_BOTTOM, 0.0), Vector3(half, FRAME_BOTTOM, 0.0),
		Vector3(half, top, 0.0), Vector3(-half, top, 0.0)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1, 0, 3, 2])
	_quad = ArrayMesh.new()
	_quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# Die Kiste des Vierecks muss den ganzen gedrehten Baum umfassen, sonst wird er zu früh weggelassen
	_quad.custom_aabb = AABB(Vector3(-half, FRAME_BOTTOM, -half), Vector3(half * 2.0, FRAME_WORLD.y, half * 2.0))
	return _quad


## Material für eine Baumart (fade = Variante zum gerasterten Ausblenden)
func material_for(kind: String, deciduous: bool, leaf_noise: Texture2D, fade: bool) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/impostor_fade.gdshader") if fade else preload("res://shaders/impostor.gdshader")
	material.set_shader_parameter("albedo_atlas", atlases[kind][0])
	material.set_shader_parameter("normal_atlas", atlases[kind][1])
	material.set_shader_parameter("leaf_noise", leaf_noise)
	material.set_shader_parameter("frames", float(frames))
	material.set_shader_parameter("deciduous", deciduous)
	return material
