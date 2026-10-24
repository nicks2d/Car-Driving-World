extends Control
## Tacho unten rechts (Entwurf „Glas“): Drehzahl als 270°-Bogen mit Zahlen pro 1.000/min
## und rotem Bereich (je Auto bis zu dessen Begrenzer), in der Mitte das Tempo groß,
## darunter der Gang im Kästchen und die Drehzahl in Tausend.

@export var car: Car
## Halbmesser des Bogens und Breite der Linie (UI-Einheiten, Panel ist 300 × 300)
@export var arc_radius: float = 112.0
@export var arc_width: float = 8.0
## So schnell folgt der Zeiger der Drehzahl (höher = direkter)
@export var needle_speed: float = 12.0

const START_ANGLE: float = PI * 0.75
const SWEEP: float = PI * 1.5

var _rpm: float = 0.0
var _max_rpm: float = 8000.0
var _red_rpm: float = 7000.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glass := GlassPanel.new()
	glass.radius = 28.0
	glass.blur = 0.0
	glass.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(glass)
	# Das Glas liegt unter dem, was _draw zeichnet
	glass.show_behind_parent = true


func _process(delta: float) -> void:
	if car == null or car.profile == null:
		return
	# Skala passend zum Auto: bis knapp über den Begrenzer, roter Bereich kurz davor
	var redline := car.profile.redline_rpm
	_max_rpm = ceilf((redline + 300.0) / 1000.0) * 1000.0
	_red_rpm = floorf((redline - 400.0) / 500.0) * 500.0
	_rpm = lerpf(_rpm, car.engine_rpm, clampf(delta * needle_speed, 0.0, 1.0))
	queue_redraw()


func _angle(rpm: float) -> float:
	return START_ANGLE + SWEEP * clampf(rpm / _max_rpm, 0.0, 1.0)


func _draw() -> void:
	if car == null:
		return
	var center := Vector2(size.x * 0.5, 150.0)
	var accent := UiStyle.accent
	# Spur, roter Bereich, gefüllter Teil bis zur aktuellen Drehzahl
	draw_arc(center, arc_radius, START_ANGLE, START_ANGLE + SWEEP, 72, Color(1, 1, 1, 0.12), arc_width, true)
	draw_arc(center, arc_radius, _angle(_red_rpm), START_ANGLE + SWEEP, 24, Color(UiStyle.RED, 0.75), arc_width, true)
	var fill_color := UiStyle.RED if _rpm >= _red_rpm else accent
	draw_arc(center, arc_radius, START_ANGLE, _angle(_rpm), 72, fill_color, arc_width, true)
	# Striche und Zahlen pro 1.000/min (innen)
	for k in int(_max_rpm / 1000.0) + 1:
		var rpm := k * 1000.0
		var direction := Vector2.from_angle(_angle(rpm))
		var red := rpm >= _red_rpm
		var tick_color := Color(UiStyle.RED, 0.9) if red else Color(1, 1, 1, 0.55)
		draw_line(center + direction * (arc_radius - 14.0), center + direction * (arc_radius - 7.0), tick_color, 2.0, true)
		var number_pos := center + direction * (arc_radius - 30.0)
		UiStyle.draw_text(self, str(k), number_pos + Vector2(0, 5), 13, "medium",
			Color(UiStyle.RED, 0.95) if red else UiStyle.TEXT_DIM, 0.5)
	# Tempo groß in der Mitte
	var kmh := roundi(car.linear_velocity.length() * 3.6)
	UiStyle.draw_text(self, str(kmh), center + Vector2(0, 30), 88, "extrabold", UiStyle.TEXT, 0.5)
	UiStyle.draw_text(self, "km/h", center + Vector2(0, 64), 15, "medium", UiStyle.TEXT_DIM, 0.5)
	# Unten: Fahrstufe, Gang im Kästchen, Drehzahl in Tausend
	var gear_box := Rect2(center.x - 20.0, 248.0, 40.0, 36.0)
	UiStyle.draw_box(self, gear_box, Color(1, 1, 1, 0.12), 9, Color(1, 1, 1, 0.16), 1)
	var gear_text := "R" if car.gear < 0 else str(car.gear)
	UiStyle.draw_text(self, gear_text, Vector2(center.x, 274.0), 22, "semibold", UiStyle.TEXT, 0.5)
	UiStyle.draw_text(self, "R" if car.gear < 0 else "D", Vector2(center.x - 38.0, 272.0), 15, "semibold", UiStyle.TEXT_DIM, 0.5)
	UiStyle.draw_text(self, ("%.1f" % (_rpm / 1000.0)), Vector2(center.x + 44.0, 272.0), 15, "semibold",
		UiStyle.TEXT_DIM, 0.5)
