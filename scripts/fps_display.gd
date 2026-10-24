extends Label
## FPS-Anzeige unten in der Mitte, mit ein paar Infos zum Gelände. Erst mit F3 sichtbar.

@export var terrain: TerrainManager

var _timer: float = 0.0


func _ready() -> void:
	visible = false
	add_theme_font_override("font", UiStyle.font("semibold"))


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("toggle_fps"):
		visible = not visible
	_timer += delta
	if not visible or _timer < 0.25:
		return
	_timer = 0.0
	var info := "FPS: %d" % Engine.get_frames_per_second()
	if terrain:
		info += "    Kacheln: %d (%d in Arbeit)" % [terrain.chunk_count(), terrain.pending_count()]
	text = info
