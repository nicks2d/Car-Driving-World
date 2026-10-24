class_name UiIcons
extends RefCounted
## Kleine Symbole für HUD und Menüs, mit Linien gezeichnet (keine Bilddateien).
## Alle Maße sind für ein 24-Punkte-Symbol gedacht und werden auf size skaliert.

static func draw(canvas: CanvasItem, icon: String, center: Vector2, size: float, color: Color, width: float = 2.0) -> void:
	var s := size / 24.0
	var w := width * maxf(s, 0.75)
	var at := func(x: float, y: float) -> Vector2: return center + Vector2(x, y) * s
	match icon:
		"sun":
			canvas.draw_arc(center, 4.5 * s, 0.0, TAU, 20, color, w, true)
			for k in 8:
				var d := Vector2.from_angle(TAU * k / 8.0)
				canvas.draw_line(center + d * 7.5 * s, center + d * 10.0 * s, color, w, true)
		"cloud":
			_cloud(canvas, center, s, color, w)
		"rain":
			_cloud(canvas, center + Vector2(0, -3) * s, s, color, w)
			for x: float in [-4.0, 0.0, 4.0]:
				canvas.draw_line(at.call(x, 6.0), at.call(x - 1.5, 10.0), color, w, true)
		"storm":
			_cloud(canvas, center + Vector2(0, -3) * s, s, color, w)
			canvas.draw_polyline(PackedVector2Array([at.call(1.0, 4.0), at.call(-2.0, 8.0), at.call(1.5, 8.0),
				at.call(-1.0, 12.0)]), color, w, true)
		"fog":
			canvas.draw_line(at.call(-8.0, -4.0), at.call(8.0, -4.0), color, w, true)
			canvas.draw_line(at.call(-9.0, 0.0), at.call(9.0, 0.0), color, w, true)
			canvas.draw_line(at.call(-6.0, 4.0), at.call(6.0, 4.0), color, w, true)
		"snow":
			for k in 3:
				var d := Vector2.from_angle(PI * k / 3.0 + PI * 0.5) * 9.0 * s
				canvas.draw_line(center - d, center + d, color, w, true)
				# Kleine Spitzen an den Enden
				for e: float in [1.0, -1.0]:
					var tip := center + d * e
					var back := -d.normalized() * e * 3.0 * s
					canvas.draw_line(tip, tip + back.rotated(0.7), color, w * 0.8, true)
					canvas.draw_line(tip, tip + back.rotated(-0.7), color, w * 0.8, true)
		"clock":
			canvas.draw_arc(center, 9.0 * s, 0.0, TAU, 28, color, w, true)
			canvas.draw_polyline(PackedVector2Array([at.call(0.0, -5.0), at.call(0.0, 0.0), at.call(3.5, 2.5)]), color, w, true)
		"leaf":
			var points := PackedVector2Array()
			for k in 13:
				var t := k / 12.0
				points.append(_bezier(at.call(-7.0, 8.0), at.call(-9.0, -6.0), at.call(8.0, -8.0), t))
			for k in 13:
				var t := k / 12.0
				points.append(_bezier(at.call(8.0, -8.0), at.call(7.0, 7.0), at.call(-7.0, 8.0), t))
			canvas.draw_polyline(points, color, w, true)
			canvas.draw_line(at.call(-8.0, 9.0), at.call(2.0, -1.0), color, w, true)
		"sprout":
			canvas.draw_line(at.call(0.0, 9.0), at.call(0.0, -2.0), color, w, true)
			var left := PackedVector2Array()
			var right := PackedVector2Array()
			for k in 9:
				var t := k / 8.0
				left.append(_bezier(at.call(0.0, 1.0), at.call(-8.0, 1.0), at.call(-7.0, -6.0), t))
				right.append(_bezier(at.call(0.0, -2.0), at.call(1.0, -9.0), at.call(7.0, -8.0), t))
			canvas.draw_polyline(left, color, w, true)
			canvas.draw_polyline(right, color, w, true)
			canvas.draw_line(at.call(-7.0, -6.0), at.call(-2.0, -3.0), color, w * 0.8, true)
			canvas.draw_line(at.call(7.0, -8.0), at.call(2.0, -5.0), color, w * 0.8, true)
		"tunnel":
			canvas.draw_arc(at.call(0.0, 0.0), 8.0 * s, PI, TAU, 18, color, w, true)
			canvas.draw_line(at.call(-8.0, 0.0), at.call(-8.0, 8.0), color, w, true)
			canvas.draw_line(at.call(8.0, 0.0), at.call(8.0, 8.0), color, w, true)
			canvas.draw_arc(at.call(0.0, 2.0), 3.5 * s, PI, TAU, 10, color, w, true)
			canvas.draw_line(at.call(-3.5, 2.0), at.call(-3.5, 8.0), color, w, true)
			canvas.draw_line(at.call(3.5, 2.0), at.call(3.5, 8.0), color, w, true)
		"check":
			canvas.draw_polyline(PackedVector2Array([at.call(-7.0, 0.0), at.call(-2.0, 5.0), at.call(8.0, -6.0)]), color, w * 1.2, true)
		"view":
			canvas.draw_polyline(PackedVector2Array([at.call(-10.0, 8.0), at.call(-3.0, -2.0), at.call(1.0, 3.0),
				at.call(4.0, -1.0), at.call(10.0, 8.0), at.call(-10.0, 8.0)]), color, w, true)
			canvas.draw_arc(at.call(5.0, -7.0), 2.5 * s, 0.0, TAU, 12, color, w, true)
		"camera":
			var body := Rect2(at.call(-10.0, -5.0), Vector2(20.0, 14.0) * s)
			canvas.draw_rect(body, color, false, w)
			canvas.draw_line(at.call(-4.0, -5.0), at.call(-2.0, -8.0), color, w, true)
			canvas.draw_line(at.call(-2.0, -8.0), at.call(3.0, -8.0), color, w, true)
			canvas.draw_line(at.call(3.0, -8.0), at.call(5.0, -5.0), color, w, true)
			canvas.draw_arc(at.call(0.0, 2.0), 4.0 * s, 0.0, TAU, 16, color, w, true)
		"pin":
			canvas.draw_arc(at.call(0.0, -3.0), 6.0 * s, 0.0, TAU, 20, color, w, true)
			canvas.draw_polyline(PackedVector2Array([at.call(-5.0, 0.5), at.call(0.0, 10.0), at.call(5.0, 0.5)]), color, w, true)
		"warning":
			canvas.draw_polyline(PackedVector2Array([at.call(0.0, -9.0), at.call(10.0, 8.0), at.call(-10.0, 8.0),
				at.call(0.0, -9.0)]), color, w, true)
			canvas.draw_line(at.call(0.0, -3.0), at.call(0.0, 2.5), color, w, true)
			canvas.draw_circle(at.call(0.0, 5.5), w * 0.7, color)


## Wolke aus drei Bögen und einer Grundlinie
static func _cloud(canvas: CanvasItem, center: Vector2, s: float, color: Color, w: float) -> void:
	canvas.draw_arc(center + Vector2(-5.5, 2.5) * s, 3.5 * s, PI * 0.5, PI * 1.5, 10, color, w, true)
	canvas.draw_arc(center + Vector2(0.5, -0.5) * s, 6.0 * s, PI * 1.05, PI * 1.95, 14, color, w, true)
	canvas.draw_arc(center + Vector2(6.0, 2.5) * s, 3.5 * s, PI * 1.5, PI * 2.5, 10, color, w, true)
	canvas.draw_line(center + Vector2(-5.5, 6.0) * s, center + Vector2(6.0, 6.0) * s, color, w, true)


static func _bezier(a: Vector2, control: Vector2, b: Vector2, t: float) -> Vector2:
	return a.lerp(control, t).lerp(control.lerp(b, t), t)


## Abbiege-Pfeil: Stiel von unten, dann in die Richtung (-3..3, positiv = links), mit Spitze
static func draw_turn_arrow(canvas: CanvasItem, direction: int, center: Vector2, size: float, color: Color) -> void:
	var s := size / 24.0
	var angles := [0.0, 40.0, 90.0, 140.0]
	var angle := deg_to_rad(angles[clampi(absi(direction), 0, 3)]) * (-1.0 if direction > 0 else 1.0)
	var heading := Vector2(0.0, -1.0).rotated(angle)
	var base := center + Vector2(-heading.x * 3.0, 9.0) * s
	var bend := center + Vector2(-heading.x * 3.0, 0.0) * s
	var tip := bend + heading * 8.0 * s
	var w := 2.6 * s
	canvas.draw_polyline(PackedVector2Array([base, bend, tip]), color, w, true)
	var side := Vector2(-heading.y, heading.x)
	canvas.draw_line(tip, tip - heading * 4.5 * s + side * 4.5 * s, color, w, true)
	canvas.draw_line(tip, tip - heading * 4.5 * s - side * 4.5 * s, color, w, true)
