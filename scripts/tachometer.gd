extends Control
## Drehzahlmesser im HUD: runde Skala von 0 bis 8000 1/min mit rotem Bereich,
## Zeiger und dem aktuellen Gang in der Mitte. Wird mit _draw() selbst gezeichnet.

## Das Auto (car.gd), dessen Drehzahl und Gang angezeigt werden
@export var car: VehicleBody3D
## Höchster Wert der Skala und Beginn des roten Bereichs (1/min)
@export var max_rpm: float = 8000.0
@export var red_rpm: float = 7000.0
## Winkel (Grad) für 0 und für max_rpm: von links unten im Uhrzeigersinn nach rechts unten
@export var start_angle: float = 135.0
@export var sweep_angle: float = 270.0

var _shown_rpm: float = 0.0


func _process(delta: float) -> void:
	if not car:
		return
	# Der Zeiger folgt der Drehzahl schnell, aber nicht ruckartig
	_shown_rpm = lerpf(_shown_rpm, car.get("engine_rpm"), clampf(delta * 18.0, 0.0, 1.0))
	queue_redraw()


func _draw() -> void:
	if not car:
		return
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 4.0
	var font := ThemeDB.fallback_font
	# Hintergrund
	draw_circle(center, radius, Color(0.0, 0.0, 0.0, 0.45))
	# Skala: weißer Bogen, roter Bereich
	var red_from := _angle_for(red_rpm)
	draw_arc(center, radius - 8.0, deg_to_rad(start_angle), red_from, 48, Color(1, 1, 1, 0.8), 3.0, true)
	draw_arc(center, radius - 8.0, red_from, _angle_for(max_rpm), 16, Color(0.95, 0.15, 0.1), 6.0, true)
	# Striche alle 500, Zahlen alle 1000 1/min
	for step in int(max_rpm / 500.0) + 1:
		var rpm := step * 500.0
		var direction := Vector2.from_angle(_angle_for(rpm))
		var long := step % 2 == 0
		var inner := radius - (20.0 if long else 14.0)
		var color := Color(0.95, 0.2, 0.15) if rpm >= red_rpm else Color.WHITE
		draw_line(center + direction * inner, center + direction * (radius - 8.0), color, 2.0 if long else 1.0, true)
		if long:
			var label := str(int(rpm / 1000.0))
			var label_pos := center + direction * (radius - 34.0) + Vector2(-6.0, 6.0)
			draw_string(font, label_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, color)
	# Zeiger
	var needle := Vector2.from_angle(_angle_for(clampf(_shown_rpm, 0.0, max_rpm)))
	draw_line(center - needle * 10.0, center + needle * (radius - 14.0), Color(1.0, 0.35, 0.1), 3.0, true)
	draw_circle(center, 6.0, Color(0.15, 0.15, 0.15))
	# Gang in der Mitte, darunter die Einheit
	var gear: int = car.get("gear")
	var gear_text := "R" if gear == -1 else str(gear)
	draw_string(font, center + Vector2(-40.0, 52.0), gear_text, HORIZONTAL_ALIGNMENT_CENTER, 80.0, 34, Color.WHITE)
	draw_string(font, center + Vector2(-40.0, 72.0), "x1000 1/min", HORIZONTAL_ALIGNMENT_CENTER, 80.0, 11, Color(1, 1, 1, 0.7))


## Bildschirmwinkel (Bogenmaß) für eine Drehzahl
func _angle_for(rpm: float) -> float:
	return deg_to_rad(start_angle + sweep_angle * rpm / max_rpm)
