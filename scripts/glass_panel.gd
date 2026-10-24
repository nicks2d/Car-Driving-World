class_name GlassPanel
extends ColorRect
## Milchglas-Fläche (glass.gdshader): weichgezeichneter Hintergrund, dunkle Tönung,
## runde Ecken, feiner Rand. Inhalte (Labels usw.) kommen als Kinder darüber.
## Ein- und Ausblenden über modulate.a.
## Die Bildschirmkopie für die Unschärfe kostet auf dem Mac ca. 1,7 ms pro Bild (Godot muss
## dafür das Zeichnen unterbrechen). Deshalb nur, wo das Spiel ohnehin pausiert (Garage,
## große Karte, Fotomodus). Im HUD beim Fahren: blur = 0, dann nur getönt (glass_tint.gdshader).

@export var radius: float = 24.0:
	set(value):
		radius = value
		_refresh()
@export var tint: Color = UiStyle.GLASS:
	set(value):
		tint = value
		_refresh()
@export var border: Color = UiStyle.BORDER:
	set(value):
		border = value
		_refresh()
## 0 = nur getönt (ohne Bildschirmkopie, günstig), 1 = Hintergrund weichzeichnen
@export_range(0.0, 1.0) var blur: float = 1.0:
	set(value):
		blur = value
		_refresh()

static var _shader: Shader
static var _tint_shader: Shader


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _shader == null:
		_shader = load("res://shaders/glass.gdshader")
		_tint_shader = load("res://shaders/glass_tint.gdshader")
	var shader_material := ShaderMaterial.new()
	shader_material.shader = _shader
	material = shader_material
	resized.connect(_refresh)


func _ready() -> void:
	_refresh()


func _refresh() -> void:
	var shader_material := material as ShaderMaterial
	if shader_material == null:
		return
	shader_material.shader = _shader if blur > 0.0 else _tint_shader
	shader_material.set_shader_parameter("rect_size", size)
	shader_material.set_shader_parameter("radius", radius)
	# Ohne Unschärfe etwas dichter, sonst wirkt der Hintergrund unruhig
	shader_material.set_shader_parameter("tint", tint if blur > 0.0 else Color(tint, maxf(tint.a, UiStyle.GLASS_FLAT_ALPHA)))
	shader_material.set_shader_parameter("border_color", border)
	shader_material.set_shader_parameter("blur", blur)
