extends Control
## Navi-Karte oben in der Mitte (Entwurf „Glas“): links ein Feld in Akzentfarbe mit dem
## Abbiege-Pfeil, daneben die Entfernung groß und die Anweisung, darunter „Danach …“,
## rechts die Ankunftszeit (Spieluhr plus Fahrzeit). Ohne Ziel ausgeblendet.

@export var navigation: Navigation
@export var day_night: DayNight

var _direction: int = 0
var _distance_text: String = ""
var _action_text: String = ""
var _after_text: String = ""
var _arrival_text: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glass := GlassPanel.new()
	glass.radius = 24.0
	glass.blur = 0.0
	glass.set_anchors_preset(Control.PRESET_FULL_RECT)
	glass.show_behind_parent = true
	add_child(glass)


func _process(_delta: float) -> void:
	visible = navigation != null and navigation.has_target and not navigation.route_points.is_empty()
	if not visible:
		return
	var turn := navigation.next_turn()
	if turn.is_empty():
		_direction = 0
		_distance_text = Navigation.format_distance(navigation.remaining_distance())
		_action_text = "bis zum Ziel"
		_after_text = "Der Straße folgen"
	else:
		_direction = turn["direction"]
		var distance: float = turn["distance"]
		var action := _action(_direction)
		if distance < 30.0:
			_distance_text = "Jetzt"
		else:
			_distance_text = Navigation.format_distance(distance)
		_action_text = action
		var after := navigation.turn_after_next()
		if after.is_empty() or after["direction"] == 0:
			_after_text = "Danach %s bis zum Ziel" % Navigation.format_distance(after.get("distance", 0.0))
		else:
			_after_text = "Danach %s geradeaus" % Navigation.format_distance(after["distance"])
	# Ankunft: Spieluhr plus geschätzte Fahrzeit
	var hour := day_night.time_of_day if day_night else 12.0
	var minutes := roundi(hour * 60.0 + navigation.remaining_minutes()) % (24 * 60)
	_arrival_text = "%02d:%02d" % [floori(minutes / 60.0), minutes % 60]
	queue_redraw()


func _action(direction: int) -> String:
	var side := "links" if direction > 0 else "rechts"
	match absi(direction):
		1:
			return "leicht " + side
		2:
			return side + " abbiegen"
		3:
			return "scharf " + side
	return "geradeaus"


func _draw() -> void:
	# Feld mit dem Pfeil
	var icon_rect := Rect2(16.0, 15.0, 64.0, 64.0)
	UiStyle.draw_box(self, icon_rect, UiStyle.accent, 16)
	UiIcons.draw_turn_arrow(self, _direction, icon_rect.get_center(), 34.0, Color.WHITE)
	# Entfernung groß, Anweisung daneben, darunter „Danach …“
	var width := UiStyle.draw_text(self, _distance_text, Vector2(96.0, 52.0), 32, "extrabold", UiStyle.TEXT)
	UiStyle.draw_text(self, _action_text, Vector2(96.0 + width + 12.0, 51.0), 20, "medium", UiStyle.TEXT)
	UiStyle.draw_text(self, _after_text, Vector2(96.0, 76.0), 15, "regular", UiStyle.TEXT_DIM)
	# Ankunft rechts, durch eine feine Linie getrennt
	var column := size.x - 108.0
	draw_line(Vector2(column - 18.0, 22.0), Vector2(column - 18.0, size.y - 22.0), Color(1, 1, 1, 0.16), 1.0)
	UiStyle.draw_text(self, "ANKUNFT", Vector2(column, 40.0), 12, "semibold", UiStyle.TEXT_DIM, 0.0, 1)
	UiStyle.draw_text(self, _arrival_text, Vector2(column, 67.0), 23, "semibold", UiStyle.TEXT)
