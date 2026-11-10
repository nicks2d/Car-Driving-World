extends Control
## Tacho unten rechts (Entwurf „Glas“): Drehzahl als 270°-Bogen mit Zahlen pro 1.000/min
## und rotem Bereich (je Auto bis zu dessen Begrenzer), in der Mitte das Tempo groß,
## darunter der Gang im Kästchen und die Drehzahl in Tausend. Oben in der Mitte die
## Verkehrszeichenerkennung (SpeedLimits): das geltende Limit als rundes Schild, „unbegrenzt“
## durchgestrichen; ab 10 km/h zu schnell pulsiert es rot.

@export var car: Car
## Halbmesser des Bogens und Breite der Linie (UI-Einheiten, Panel ist 300 × 300)
@export var arc_radius: float = 112.0
@export var arc_width: float = 8.0
## So schnell folgt der Zeiger der Drehzahl (höher = direkter)
@export var needle_speed: float = 12.0
## Tempo in Meilen pro Stunde statt km/h (Einstellungen > Spiel)
@export var use_mph: bool = false
@export var limits: SpeedLimits
@export var cruise: CruiseControl

const SIGNAL_GREEN := Color("#3FD47A")
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
	var speed := roundi(car.linear_velocity.length() * (2.23694 if use_mph else 3.6))
	UiStyle.draw_text(self, str(speed), center + Vector2(0, 30), 88, "extrabold", UiStyle.TEXT, 0.5)
	UiStyle.draw_text(self, "mph" if use_mph else "km/h", center + Vector2(0, 64), 15, "medium", UiStyle.TEXT_DIM, 0.5)
	# Blinker: grüne Pfeile oben links und rechts im Takt, Warnblinker: rotes Dreieck
	if car.signal_lit:
		if car.hazard or car.turn_signal == 1:
			_draw_signal_arrow(Vector2(34.0, 34.0), -1.0)
		if car.hazard or car.turn_signal == -1:
			_draw_signal_arrow(Vector2(size.x - 34.0, 34.0), 1.0)
	if car.hazard:
		_draw_hazard(Vector2(size.x * 0.5, 100.0), car.signal_lit)
	if cruise and cruise.active:
		_draw_cruise(Vector2(40.0, 214.0))
	if limits and limits.effective_limit >= 0:
		_draw_limit(Vector2(size.x * 0.5, 40.0), limits.effective_limit, car.linear_velocity.length() * 3.6)
	# Unten: Fahrstufe, Gang im Kästchen, Drehzahl in Tausend
	var gear_box := Rect2(center.x - 20.0, 248.0, 40.0, 36.0)
	UiStyle.draw_box(self, gear_box, Color(1, 1, 1, 0.12), 9, Color(1, 1, 1, 0.16), 1)
	var gear_text := "R" if car.gear < 0 else str(car.gear)
	UiStyle.draw_text(self, gear_text, Vector2(center.x, 274.0), 22, "semibold", UiStyle.TEXT, 0.5)
	UiStyle.draw_text(self, "R" if car.gear < 0 else "D", Vector2(center.x - 38.0, 272.0), 15, "semibold", UiStyle.TEXT_DIM, 0.5)
	UiStyle.draw_text(self, ("%.1f" % (_rpm / 1000.0)), Vector2(center.x + 44.0, 272.0), 15, "semibold",
		UiStyle.TEXT_DIM, 0.5)


## Tempomat: Symbol (Tacho mit Pfeil) und Wunschtempo, darunter die Abstandsstufe als Balken
## (hell, wenn ein Vordermann erkannt ist), rot blinkend, wenn er mehr bremsen müsste
func _draw_cruise(at: Vector2) -> void:
	var accent := UiStyle.RED if cruise.warning and fmod(Time.get_ticks_msec() / 250.0, 2.0) < 1.0 else UiStyle.accent
	draw_arc(at, 11.0, PI * 0.8, PI * 2.2, 20, accent, 2.5, true)
	draw_line(at, at + Vector2.from_angle(-PI * 0.3) * 8.0, accent, 2.5, true)
	UiStyle.draw_text(self, str(roundi(cruise.set_speed_kmh)), at + Vector2(0, 30), 17, "semibold", accent, 0.5)
	var bars := cruise.gap_level + 1
	for k in cruise.gaps.size():
		var lit := k < bars
		var color := (accent if cruise.leader_gap >= 0.0 else Color(1, 1, 1, 0.75)) if lit else Color(1, 1, 1, 0.15)
		draw_rect(Rect2(at + Vector2(-14.0, 40.0 + k * 6.0), Vector2(28.0 - k * 4.0, 3.0)), color)


## Erkanntes Limit: weiß mit rotem Rand und Zahl, 0 = unbegrenzt (fünf schräge Striche)
func _draw_limit(center: Vector2, limit: int, speed_kmh: float) -> void:
	var r := 22.0
	if limit > 0 and speed_kmh > limit + 10.0:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU * 1.6)
		draw_circle(center, r + 6.0 + pulse * 3.0, Color(UiStyle.RED, 0.25 + pulse * 0.35))
	draw_circle(center, r, Color.WHITE)
	if limit > 0:
		draw_arc(center, r - 3.0, 0.0, TAU, 40, UiStyle.RED, 6.0, true)
		UiStyle.draw_text(self, str(limit), center + Vector2(0, 7), 19 if limit < 100 else 16, "extrabold",
			Color(0.05, 0.05, 0.05), 0.5)
	else:
		for k in 5:
			var offset := (k - 2) * 4.5
			var direction := Vector2(1, -1).normalized()
			var normal := Vector2(1, 1).normalized() * offset
			var half := sqrt(maxf(r * r - offset * offset, 0.0)) * 0.85
			draw_line(center + normal - direction * half, center + normal + direction * half, Color(0.15, 0.15, 0.15), 1.6, true)
	if limits.current_wet_only and limit == limits.current_limit:
		UiStyle.draw_text(self, "Nässe", center + Vector2(0, r + 14.0), 11, "semibold", UiStyle.TEXT_DIM, 0.5)


## Blinkerpfeil (direction: -1 = nach links, 1 = nach rechts)
func _draw_signal_arrow(center: Vector2, direction: float) -> void:
	var points := PackedVector2Array([Vector2(-13, 0), Vector2(-1, -11), Vector2(-1, -4.5), Vector2(12, -4.5),
		Vector2(12, 4.5), Vector2(-1, 4.5), Vector2(-1, 11)])
	for i in points.size():
		points[i] = center + Vector2(points[i].x * -direction, points[i].y)
	draw_colored_polygon(points, SIGNAL_GREEN)


## Warnblinker-Symbol: rotes Dreieck mit innerem Dreieck, hell im Takt
func _draw_hazard(center: Vector2, lit: bool) -> void:
	var color := UiStyle.RED if lit else Color(UiStyle.RED, 0.35)
	for size_factor: float in [1.0, 0.5]:
		var r := 15.0 * size_factor
		var triangle := PackedVector2Array([center + Vector2(0, -r), center + Vector2(r * 0.87, r * 0.5),
			center + Vector2(-r * 0.87, r * 0.5), center + Vector2(0, -r)])
		draw_polyline(triangle, color, 3.0 if size_factor == 1.0 else 2.0, true)
