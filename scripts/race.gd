class_name Race
extends CanvasLayer
## Spontane Rennen per Lichthupe: Gibt man einem KI-Auto bis 40 m hinter oder neben ihm
## Lichthupe, nimmt es meistens an (die Schnellen und der LC 500 fast immer). Es blinkt zurück
## und gibt Gas. Ziel ist das nächste Ortsschild auf seiner Straße (auf der Autobahn die nächste
## Ausfahrt); es steht als Navi-Ziel auf Minimap und Karte. Wer zuerst dort ist, gewinnt.
## Abbruch bei einem Zusammenstoß oder wenn einer mehr als 600 m zurückliegt (dann gewinnt der
## andere). Ergebnis als Meldung, Statistik in user://einstellungen.cfg (Garage > Rennen).

@export var car: Car
@export var traffic: Traffic
@export var roads: RoadNetwork
@export var navigation: Navigation
@export var debug_tools: DebugTools
## Ab diesem Rückstand ist das Rennen entschieden (Meter)
@export var give_up_distance: float = 600.0
## So nah am Ziel gilt es als erreicht (Meter)
@export var finish_radius: float = 18.0
## Mindestlänge eines Rennens (Meter bis zum Ziel)
@export var min_length: float = 400.0

const SETTINGS_PATH := "user://einstellungen.cfg"

var racing: bool = false
var opponent: Traffic.TrafficCar
var opponent_name: String = ""
var finish := Vector3.ZERO
var finish_name: String = ""
var _start_time: float = 0.0
var _player_time: float = -1.0
var _opponent_time: float = -1.0
var _had_target: bool = false
var _old_target := Vector3.ZERO
## Tempo der letzten 0,2 s (Unfall erkennen)
var _speeds: Array[float] = []
var _panel: Control
var _label: Label

const NAMES := {"s3": "Audi S3", "accord": "Honda Accord", "id_buzz": "VW ID. Buzz", "aztek": "Pontiac Aztek",
	"lc500": "Lexus LC 500"}


func _ready() -> void:
	layer = 5
	if car:
		car.flashed.connect(_on_flashed)
	# Anzeige oben in der Mitte (Glas wie das HUD)
	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_panel.position = Vector2(-230.0, 120.0)
	_panel.size = Vector2(460.0, 54.0)
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glass := GlassPanel.new()
	glass.blur = 0.0
	glass.radius = 18.0
	glass.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(glass)
	_label = UiStyle.label("", 18, "semibold")
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_panel.add_child(_label)
	add_child(_panel)


func _on_flashed() -> void:
	if racing or traffic == null:
		return
	var candidate := traffic.race_candidate(car.global_position, car.global_basis.z)
	if candidate == null or randf() >= traffic.race_chance(candidate):
		return
	start(candidate)


## Rennen gegen dieses Auto starten (false = kein passendes Ziel voraus)
func start(candidate: Traffic.TrafficCar) -> bool:
	if not _find_finish(candidate):
		return false
	opponent = candidate
	opponent_name = NAMES.get(candidate.type, "Auto")
	traffic.start_race(candidate)
	racing = true
	_start_time = Time.get_ticks_msec() / 1000.0
	_player_time = -1.0
	_opponent_time = -1.0
	_speeds.clear()
	if navigation:
		_had_target = navigation.has_target
		_old_target = navigation.target
		navigation.set_target(finish)
	Toasts.post(get_tree(), "check", "Rennen gegen %s!" % opponent_name, "Ziel: %s" % finish_name)
	_panel.visible = true
	return true


## Ziel: Ortsschild am Ende seines Stücks (sonst die Kreuzung), auf der Autobahn die Spitze der
## nächsten Ausfahrt, die mindestens min_length voraus liegt
func _find_finish(c: Traffic.TrafficCar) -> bool:
	var leg := c.leg
	if leg.kind == Traffic.Kind.ROAD:
		var end_cell := roads.edge_end_cell(leg.key) if leg.forward else Vector2i(leg.key.x, leg.key.y)
		var reach := -1.0
		var village: Village = roads.get("_villages").get(end_cell)
		if village:
			reach = village.sign_reach(leg.segment)
		var s_finish := leg.to - (maxf(reach, 0.0) if reach > 0.0 else 0.0)
		if s_finish - c.s < min_length:
			return false
		finish = traffic.point_on_leg(c, s_finish)
		finish_name = ("Ortsschild " + roads.highways.place_name(end_cell)) if reach > 0.0 else "nächste Kreuzung"
		return true
	if leg.kind == Traffic.Kind.HIGHWAY:
		var axis := RoadNetwork.highway_axis(leg.key)
		var dir := 1 if leg.forward else -1
		var at := leg.key.x + 1 if leg.forward else leg.key.x
		for step in 4:
			var k := at + step * dir
			var interchange := roads.highways.interchange_at(axis, leg.key.y, k)
			if interchange.is_empty():
				continue
			var gore := roads.ramp_ends(axis, leg.key.y, k, 3 if dir > 0 else 1)[0]
			var point := Vector3(gore.x, c.position.y, gore.y)
			var to := point - c.position
			if to.dot(c.forward) > min_length:
				finish = point
				finish_name = "Ausfahrt %d" % interchange["number"]
				return true
	return false


func _physics_process(delta: float) -> void:
	if not racing:
		return
	if not traffic.is_alive(opponent):
		_finish_race("abgebrochen", "Gegner ist weg")
		return
	var now := Time.get_ticks_msec() / 1000.0 - _start_time
	var player_left := Vector2(car.global_position.x - finish.x, car.global_position.z - finish.z).length()
	var opponent_left := Vector2(opponent.position.x - finish.x, opponent.position.z - finish.z).length()
	if _player_time < 0.0 and player_left < finish_radius:
		_player_time = now
	if _opponent_time < 0.0 and opponent_left < finish_radius:
		_opponent_time = now
	# Zusammenstoß (mit dem Gegner oder hart irgendwo dagegen): mehr als 7 m/s Tempo in 0,2 s
	# verloren (Vollbremsung schafft ~2,4). Einzelne Physikschritte springen, deshalb über 0,2 s.
	var speed := car.linear_velocity.length()
	_speeds.append(speed)
	if _speeds.size() > roundi(0.2 / delta):
		_speeds.remove_at(0)
	if opponent.crash_timer > 0.0:
		_finish_race("abgebrochen", "Zusammenstoß mit dem Gegner")
		return
	if _speeds.max() - speed > 7.0:
		_finish_race("abgebrochen", "Unfall")
		return
	var lead := opponent_left - player_left
	if _player_time >= 0.0 or _opponent_time >= 0.0:
		var player_first := _player_time >= 0.0 and (_opponent_time < 0.0 or _player_time <= _opponent_time)
		# Vorsprung: Zeit, bis der andere auch da ist (ungefähr aus Restweg und Tempo)
		var behind_left := opponent_left if player_first else player_left
		var behind_speed := maxf(opponent.speed if player_first else speed, 5.0)
		var margin := behind_left / behind_speed
		_finish_race("gewonnen" if player_first else "verloren", "%s s Vorsprung" % ("%.1f" % margin).replace(".", ","))
		return
	if absf(lead) > give_up_distance:
		_finish_race("gewonnen" if lead > 0.0 else "verloren", "%s abgehängt" % ("Gegner" if lead > 0.0 else "Du bist"))
		return
	_label.text = "Rennen · %s · %s %d m · Ziel %d m" % [opponent_name, "vorne" if lead >= 0.0 else "hinten",
		roundi(absf(lead)), roundi(player_left)]


func _finish_race(result: String, detail: String) -> void:
	racing = false
	_panel.visible = false
	if opponent:
		traffic.end_race(opponent)
	if navigation:
		if _had_target:
			navigation.set_target(_old_target)
		else:
			navigation.clear_target()
	var title: String = {"gewonnen": "Gewonnen gegen %s", "verloren": "Verloren gegen %s",
		"abgebrochen": "Rennen gegen %s abgebrochen"}[result] % opponent_name
	Toasts.post(get_tree(), "check" if result == "gewonnen" else "warning", title, detail)
	print("Rennen: %s (%s)" % [title, detail])
	_save_result(result, detail)


## Statistik: Siege, Niederlagen, Abbrüche und das letzte Ergebnis (Testläufe speichern nichts)
func _save_result(result: String, detail: String) -> void:
	if debug_tools and debug_tools.is_active():
		return
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	var key: String = {"gewonnen": "siege", "verloren": "niederlagen", "abgebrochen": "abbrueche"}[result]
	config.set_value("rennen", key, int(config.get_value("rennen", key, 0)) + 1)
	config.set_value("rennen", "letztes", "%s: %s gegen %s (%s)" % [Time.get_date_string_from_system(), result,
		opponent_name, detail])
	config.save(SETTINGS_PATH)


## Für die Garage: [Siege, Niederlagen, Abbrüche, letztes Ergebnis]
static func statistics() -> Array:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	return [config.get_value("rennen", "siege", 0), config.get_value("rennen", "niederlagen", 0),
		config.get_value("rennen", "abbrueche", 0), config.get_value("rennen", "letztes", "")]
