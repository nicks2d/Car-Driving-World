class_name KeyHints
extends Control
## Tastenhilfe unten in der Mitte: zeigt passende Tasten, je nachdem wo man gerade ist.
## - Auto steht ein paar Sekunden: „G Garage · P Foto · M Karte · Tab Kamera“
## - langsam auf dem Parkplatz einer Raststätte: Auto wechseln, Zeit vergehen lassen, Foto
## - an einem Aussichtspunkt: Fotomodus und Karte
## - auf dem Prüfstand: Messlauf starten, zurück zur Garage
## Die Tasten sind immer die aktuelle Belegung. Ein Hinweis bleibt ein paar Sekunden und blendet dann aus,
## bis sich die Lage ändert. Abschaltbar in Einstellungen > Spiel > Tastenhilfe.
## Liegt in der Ebene „Messages“ (läuft auch bei angehaltenem Spiel, z. B. auf dem Prüfstand).

@export var car: Car
@export var roads: RoadNetwork
@export var viewpoints: Viewpoints
@export var dyno: Dyno
@export var settings: GameSettings
@export var hud: CanvasLayer
@export var garage: Garage
@export var pause_menu: PauseMenu
@export var big_map: BigMap
@export var photo_mode: PhotoMode
@export var chill_mode: ChillMode
@export var rewind: Rewind
@export var debug_tools: DebugTools

## So lange muss das Auto stehen, bis die Hinweise kommen (Sekunden)
@export var stop_seconds: float = 1.5
## So lange bleibt ein Hinweis stehen, dann blendet er aus, bis sich etwas ändert (Sekunden)
@export var show_seconds: float = 12.0
## Bis zu diesem Tempo gelten Raststätte und Aussichtspunkt (km/h)
@export var slow_kmh: float = 12.0
## So oft wird nachgesehen, wo das Auto ist (Sekunden)
@export var check_interval: float = 0.25

const HEIGHT: float = 46.0
const FADE_SPEED: float = 5.0

var _context: String = ""
var _title: String = ""
## Je Eintrag [Aktion, Text], z. B. ["open_garage", "Garage"]
var _items: Array = []
var _alpha: float = 0.0
var _stopped_time: float = 0.0
var _context_time: float = 0.0
var _check_timer: float = 0.0
## In Testläufen nur mit --hints (sonst stünde die Hilfe auf jedem Testfoto)
var _allowed: bool = true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if debug_tools and debug_tools.is_active():
		_allowed = OS.get_cmdline_user_args().has("--hints")


func _process(delta: float) -> void:
	var speed := car.linear_velocity.length() * 3.6 if car else 0.0
	_stopped_time = _stopped_time + delta if speed < 1.0 and not get_tree().paused else 0.0
	_check_timer -= delta
	# Menüs, Chill-Modus usw. sofort prüfen (billig), den Ort nur alle paar Bilder
	if _hidden():
		_context = ""
	elif _check_timer <= 0.0:
		_check_timer = check_interval
		_set_context(_find_context(speed))
	_context_time += delta
	var wanted := 1.0 if _context != "" and _context_time < show_seconds else 0.0
	var before := _alpha
	_alpha = move_toward(_alpha, wanted, delta * FADE_SPEED)
	if _alpha > 0.0 or before > 0.0:
		queue_redraw()


## Gerade gar keine Hilfe? (abgeschaltet, Menü offen, Chill-Modus, Zurückspulen, HUD aus)
func _hidden() -> bool:
	if not _allowed or settings == null or not settings.get_value("spiel", "tastenhilfe") or car == null:
		return true
	if dyno and dyno.is_open:
		return false
	return (garage and garage.is_open) or (pause_menu and pause_menu.is_open) or (big_map and big_map.is_open) \
		or (photo_mode and photo_mode.is_open) or (chill_mode and chill_mode.active) \
		or (rewind and rewind.rewinding) or (hud and not hud.visible)


## Wo ist das Auto gerade? "" = nichts zeigen
func _find_context(speed: float) -> String:
	if dyno and dyno.is_open:
		return "dyno"
	if speed < slow_kmh:
		if _near_viewpoint():
			return "viewpoint"
		if _on_rest_lot():
			return "rest"
	if _stopped_time >= stop_seconds:
		return "stop"
	return ""


func _set_context(context: String) -> void:
	if context == _context:
		return
	# Erst ausblenden, dann mit dem neuen Inhalt wieder einblenden
	if _alpha > 0.05 and context != "":
		_context = ""
		return
	_context = context
	_context_time = 0.0
	match context:
		"dyno":
			_title = "Prüfstand"
			_items = [["ui_accept", "Messlauf starten"], ["ui_cancel", "Zurück zur Garage"]]
		"viewpoint":
			_title = "Aussichtspunkt"
			_items = [["photo_mode", "Fotomodus"], ["toggle_map", "Karte"]]
		"rest":
			_title = "Raststätte"
			_items = [["open_garage", "Auto wechseln"], ["time_warp", "halten: Zeit vergeht"], ["photo_mode", "Foto"]]
		"stop":
			_title = ""
			_items = [["open_garage", "Garage"], ["photo_mode", "Foto"], ["toggle_map", "Karte"],
				["cycle_camera", "Kamera"]]


## Steht das Auto an einem Aussichtspunkt (Parkbucht mit Aussicht)?
func _near_viewpoint() -> bool:
	if roads == null or viewpoints == null:
		return false
	var p := car.global_position
	for pair: Array in roads.loaded_segments(Rect2(p.x - 60.0, p.z - 60.0, 120.0, 120.0)):
		var segment: RoadSegment = pair[1]
		if segment.viewpoint.is_empty():
			continue
		var center: Vector3 = segment.viewpoint["center"]
		if Vector2(center.x - p.x, center.z - p.z).length() < viewpoints.discover_radius:
			return true
	return false


## Ist das Auto auf dem Parkplatz einer Raststätte?
func _on_rest_lot() -> bool:
	if roads == null:
		return false
	var p := Vector2(car.global_position.x, car.global_position.z)
	for pair: Array in roads.loaded_segments(Rect2(p.x - 120.0, p.y - 120.0, 240.0, 240.0)):
		var key: Vector3i = pair[0]
		if not RoadNetwork.is_rest_key(key) or RoadNetwork.rest_part(key) != 0:
			continue
		var segment: RoadSegment = pair[1]
		var reach := segment.road_width * 0.5 + 14.0
		for point in segment.points:
			if Vector2(point.x - p.x, point.z - p.y).length() < reach:
				return true
	return false


## Name der Taste für eine Aktion (Esc und Enter für die Menü-Aktionen)
func _key_text(action: String) -> String:
	match action:
		"ui_accept":
			return "Enter"
		"ui_cancel":
			return "Esc"
	return GameSettings.action_key(action)


func _draw() -> void:
	if _alpha <= 0.0 or _items.is_empty():
		return
	# Breite ausrechnen: Titel, dann je Eintrag Tastenkästchen und Text
	var parts: Array = []
	var total := 0.0
	if _title != "":
		total += UiStyle.text_width(_title, 15, "semibold") + 18.0
	for item: Array in _items:
		var key := _key_text(item[0])
		var key_width := maxf(28.0, UiStyle.text_width(key, 13, "semibold") + 16.0)
		var text_width := UiStyle.text_width(item[1], 15, "medium")
		parts.append([key, key_width, item[1], text_width])
		total += key_width + 8.0 + text_width
	total += 22.0 * (_items.size() - 1) + 40.0
	var x := (size.x - total) * 0.5
	var top := size.y - HEIGHT
	# Leicht von unten hereingleiten
	top += (1.0 - _alpha) * 8.0
	var a := _alpha
	UiStyle.draw_box(self, Rect2(x, top, total, HEIGHT), Color(UiStyle.GLASS, UiStyle.GLASS_FLAT_ALPHA * a), 23,
		Color(UiStyle.BORDER, UiStyle.BORDER.a * a), 1)
	x += 20.0
	var baseline := top + HEIGHT * 0.5 + 5.5
	if _title != "":
		x += UiStyle.draw_text(self, _title, Vector2(x, baseline), 15, "semibold", Color(UiStyle.accent, a)) + 18.0
	for i in parts.size():
		var part: Array = parts[i]
		if i > 0:
			canvas_dot(Vector2(x - 11.0, top + HEIGHT * 0.5), a)
		var key_rect := Rect2(x, top + (HEIGHT - 26.0) * 0.5, part[1], 26.0)
		UiStyle.draw_box(self, key_rect, Color(1, 1, 1, 0.08 * a), 6, Color(1, 1, 1, 0.3 * a), 1)
		UiStyle.draw_text(self, part[0], Vector2(key_rect.get_center().x, baseline - 0.5), 13, "semibold",
			Color(1, 1, 1, a), 0.5)
		x += part[1] + 8.0
		x += UiStyle.draw_text(self, part[2], Vector2(x, baseline), 15, "medium",
			Color(UiStyle.TEXT_DIM, UiStyle.TEXT_DIM.a * a)) + 22.0


## Trennpunkt zwischen zwei Einträgen
func canvas_dot(center: Vector2, alpha: float) -> void:
	draw_circle(center, 1.6, Color(1, 1, 1, 0.35 * alpha))
