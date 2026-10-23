extends Control
## Navi-Anzeige oben in der Mitte: Pfeil und „In 300 m rechts“, darunter restliche
## Strecke und ungefähre Fahrzeit. Zeigt auch kurze Meldungen wie „Ziel erreicht“.

@export var navigation: Navigation

var _main_label: Label
var _sub_label: Label
var _direction: int = 0
var _show_arrow: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(420, 84)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.08, 0.78)
	style.set_corner_radius_all(10)
	style.content_margin_left = 80
	style.content_margin_right = 16
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(box)
	_main_label = Label.new()
	_main_label.add_theme_font_size_override("font_size", 26)
	box.add_child(_main_label)
	_sub_label = Label.new()
	_sub_label.add_theme_font_size_override("font_size", 16)
	_sub_label.add_theme_color_override("font_color", Color(0.75, 0.78, 0.82))
	box.add_child(_sub_label)
	# Der Pfeil wird über dem Panel gezeichnet
	move_child(panel, 0)


func _process(_delta: float) -> void:
	if navigation == null:
		visible = false
		return
	if navigation.message_timer > 0.0 and not navigation.has_target:
		visible = true
		_show_arrow = false
		_main_label.text = navigation.message
		_sub_label.text = ""
		queue_redraw()
		return
	visible = navigation.has_target and not navigation.route_points.is_empty()
	if not visible:
		return
	var turn := navigation.next_turn()
	if turn.is_empty():
		_direction = 0
		_main_label.text = "Der Straße folgen"
	else:
		_direction = turn["direction"]
		var distance: float = turn["distance"]
		var action := _action_text(_direction)
		_main_label.text = action if distance < 30.0 else "In %s %s" % [_distance_text(distance), action.to_lower()]
	_show_arrow = true
	var minutes := roundi(navigation.remaining_minutes())
	_sub_label.text = "Ziel: %s · ca. %s" % [_distance_text(navigation.remaining_distance()),
		"%d min" % maxi(minutes, 1) if minutes < 60 else "%d h %02d min" % [floori(minutes / 60.0), minutes % 60]]
	queue_redraw()


func _action_text(direction: int) -> String:
	var side := "links" if direction > 0 else "rechts"
	match absi(direction):
		1:
			return "Leicht " + side
		2:
			return side.capitalize() + " abbiegen"
		3:
			return "Scharf " + side
	return "Geradeaus"


## „300 m“, „1,2 km“ (gerundet wie bei einem Navi)
func _distance_text(meters: float) -> String:
	if meters < 100.0:
		return "%d m" % (roundi(meters / 10.0) * 10)
	if meters < 1000.0:
		return "%d m" % (roundi(meters / 50.0) * 50)
	return ("%.1f km" % (meters / 1000.0)).replace(".", ",")


func _draw() -> void:
	if not _show_arrow:
		return
	# Pfeil: Stiel von unten zur Mitte, dann in die Abbiege-Richtung (positiv = links)
	var base := Vector2(42, size.y * 0.5 + 18)
	var middle := Vector2(42, size.y * 0.5)
	var angles := [0.0, 35.0, 90.0, 150.0]
	var angle := deg_to_rad(angles[absi(_direction)]) * (-1.0 if _direction > 0 else 1.0)
	var direction := Vector2(0, -1).rotated(angle)
	var tip := middle + direction * 18.0
	var color := Color(0.35, 0.75, 1.0)
	draw_polyline(PackedVector2Array([base, middle, tip]), color, 6.0, true)
	var side := Vector2(-direction.y, direction.x)
	draw_colored_polygon(PackedVector2Array([tip + direction * 9.0, tip + side * 9.0, tip - side * 9.0]), color)
