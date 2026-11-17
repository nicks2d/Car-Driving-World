class_name LoadingScreen
extends ColorRect
## Ladebildschirm: Im Hintergrund wechseln Bilder aus dem Spiel (weich überblendet, langsam zoomend), unten
## ein Fortschrittsbalken mit dem echten Ladestand (setzt game.gd mit set_progress: Straßen, Gelände-Kacheln,
## Horizont, Automodell) und wechselnde Tipps zu Tasten und Funktionen (mit der aktuellen Tastenbelegung).
## Die Bilder liegen in assets/loading/ (Fotos aus dem README: nur Autos mit CC-BY-Lizenz).

## So lange bleibt ein Bild bzw. ein Tipp stehen (Sekunden), so lange dauert das Überblenden
@export var image_seconds: float = 5.0
@export var tip_seconds: float = 4.5
@export var fade_seconds: float = 1.2
## Zoom eines Bilds über seine Zeit (1,0 → so viel)
@export var zoom: float = 1.08
## So lange blendet der Ladebildschirm am Ende aus (Sekunden)
@export var fade_out_seconds: float = 0.5

const IMAGES: Array[String] = ["hero", "motorway", "rain", "rainbow", "tunnel", "waterfall", "winter", "village",
	"aurora", "dam"]
## Tipps: [Text mit {Aktion} für die Taste]
const TIPS: Array[String] = [
	"{cycle_camera} wechselt die Kamera: Verfolger, Cockpit und Ego-Sicht.",
	"{rewind} gedrückt halten spult bis zu 10 Sekunden zurück.",
	"{open_garage} öffnet die Garage: anderes Auto, Lackfarbe, Kennzeichen, Prüfstand.",
	"{toggle_map} zeigt die große Karte. Klick setzt ein Navi-Ziel.",
	"{photo_mode} startet den Fotomodus mit Filtern und Tageszeit.",
	"{cycle_weather} wechselt das Wetter, {cycle_season} die Jahreszeit.",
	"{cruise_toggle} schaltet den Tempomat ein, {cruise_distance} ändert den Abstand.",
	"{flash_lights} gibt Lichthupe: Manche Autos nehmen ein Rennen an.",
	"{time_warp} gedrückt halten lässt die Zeit schneller laufen.",
	"{toggle_windows} öffnet die Fenster, dann hört man den Motor besser.",
	"Aussichtspunkte und Orte sammelst du in der Entdecker-Karte (Garage).",
	"Auf der Autobahn gibt es kein Tempolimit, nur Hinweise vor Kurven.",
	"Im Berufsverkehr morgens und am späten Nachmittag wird es auf der Autobahn voll.",
	"{reset_car} richtet das Auto auf oder setzt es zurück auf die Straße.",
	"Esc öffnet das Pausemenü. Dort lassen sich alle Tasten neu belegen.",
]

var _images: Array[TextureRect] = []
var _current: int = 0
var _image_index: int = 0
var _image_time: float = 0.0
var _tip_index: int = 0
var _tip_time: float = 0.0
var _progress: float = 0.0
var _shown_progress: float = 0.0
var _status: String = "Welt wird erzeugt …"
var _rng := RandomNumberGenerator.new()
var _tween: Tween


func _ready() -> void:
	color = Color(0.02, 0.03, 0.05)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Alte Beschriftung aus der Szene nicht mehr nötig
	for child in get_children():
		child.queue_free()
	_rng.randomize()
	_image_index = _rng.randi_range(0, IMAGES.size() - 1)
	_tip_index = _rng.randi_range(0, TIPS.size() - 1)
	for k in 2:
		var image := TextureRect.new()
		image.set_anchors_preset(Control.PRESET_FULL_RECT)
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		image.modulate.a = 0.0
		add_child(image)
		_images.append(image)
	_show_image(_images[0])
	_images[0].modulate.a = 1.0
	# Gezeichnet wird oben drauf (_draw kommt vor den Kindern, deshalb ein eigenes Kind)
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_overlay.bind(overlay))
	add_child(overlay)
	visibility_changed.connect(_on_visibility_changed)


func _on_visibility_changed() -> void:
	if not visible:
		return
	# Wieder gezeigt (Sprung): von vorne zählen, ein laufendes Ausblenden abbrechen
	if _tween:
		_tween.kill()
		_tween = null
	modulate.a = 1.0
	_progress = 0.0
	_shown_progress = 0.0


## Laden fertig: weich ausblenden (soft) oder sofort weg (Tests, damit Fotos nichts davon zeigen)
func finish(soft: bool) -> void:
	_progress = 1.0
	_shown_progress = 1.0
	if not soft:
		visible = false
		return
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 0.0, fade_out_seconds)
	_tween.tween_callback(_hide_after_fade)


func _hide_after_fade() -> void:
	_tween = null
	visible = false
	modulate.a = 1.0


## Ladestand 0–1 (game.gd, jedes Bild) und was gerade geladen wird
func set_progress(value: float, status: String) -> void:
	_progress = maxf(_progress, clampf(value, 0.0, 1.0))
	_status = status


func _process(delta: float) -> void:
	if not visible:
		return
	_shown_progress = move_toward(_shown_progress, _progress, delta * 0.8)
	_image_time += delta
	# Langsam zoomen (Mitte bleibt)
	for image in _images:
		image.pivot_offset = size * 0.5
	var current := _images[_current]
	current.scale = Vector2.ONE * lerpf(1.0, zoom, clampf(_image_time / (image_seconds + fade_seconds), 0.0, 1.0))
	if _image_time > image_seconds:
		# Nächstes Bild auf der anderen Fläche einblenden
		var next := _images[1 - _current]
		if next.modulate.a == 0.0:
			_image_index = (_image_index + 1) % IMAGES.size()
			_show_image(next)
			next.scale = Vector2.ONE
		next.modulate.a = clampf((_image_time - image_seconds) / fade_seconds, 0.0, 1.0)
		if next.modulate.a >= 1.0:
			current.modulate.a = 0.0
			_current = 1 - _current
			_image_time = 0.0
	_tip_time += delta
	if _tip_time > tip_seconds:
		_tip_time = 0.0
		_tip_index = (_tip_index + 1) % TIPS.size()
	get_child(get_child_count() - 1).queue_redraw()


func _show_image(image: TextureRect) -> void:
	image.texture = load("res://assets/loading/%s.jpg" % IMAGES[_image_index])


func _draw_overlay(canvas: Control) -> void:
	var area := canvas.size
	# Unten dunkler Verlauf (glatt über die Eckfarben), damit Schrift und Balken lesbar sind
	var clear := Color(0.0, 0.02, 0.05, 0.0)
	var dark := Color(0.0, 0.02, 0.05, 0.88)
	var top := area.y * 0.5
	canvas.draw_polygon(PackedVector2Array([Vector2(0.0, top), Vector2(area.x, top), Vector2(area.x, area.y),
		Vector2(0.0, area.y)]), PackedColorArray([clear, clear, dark, dark]))
	var left := 72.0
	var bottom := area.y - 64.0
	UiStyle.draw_text(canvas, "Car Driving World", Vector2(left, bottom - 120.0), 40, "extrabold", UiStyle.TEXT)
	# Tipp (weich ein- und ausgeblendet)
	var tip_alpha := clampf(minf(_tip_time / 0.4, (tip_seconds - _tip_time) / 0.4), 0.0, 1.0)
	UiStyle.draw_text(canvas, "TIPP", Vector2(left, bottom - 80.0), 13, "semibold", Color(UiStyle.accent, tip_alpha),
		0.0, 2)
	UiStyle.draw_text(canvas, _tip_text(TIPS[_tip_index]), Vector2(left, bottom - 54.0), 19, "medium",
		Color(1, 1, 1, 0.9 * tip_alpha))
	# Fortschrittsbalken mit Prozent und was gerade geladen wird
	var bar := Rect2(left, bottom - 18.0, area.x - left * 2.0, 6.0)
	canvas.draw_rect(bar, Color(1, 1, 1, 0.15))
	canvas.draw_rect(Rect2(bar.position, Vector2(bar.size.x * _shown_progress, bar.size.y)), UiStyle.accent)
	UiStyle.draw_text(canvas, _status, Vector2(left, bottom + 16.0), 15, "regular", UiStyle.TEXT_DIM)
	UiStyle.draw_text(canvas, "%d %%" % roundi(_shown_progress * 100.0), Vector2(bar.end.x, bottom + 16.0), 15,
		"semibold", UiStyle.TEXT_DIM, 1.0)


## {aktion} durch die Taste ersetzen, mit der sie gerade belegt ist
func _tip_text(template: String) -> String:
	var text := template
	while text.contains("{"):
		var a := text.find("{")
		var b := text.find("}", a)
		if b < 0:
			break
		text = text.substr(0, a) + GameSettings.action_key(text.substr(a + 1, b - a - 1)) + text.substr(b + 1)
	return text
