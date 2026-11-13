class_name LicensePlate
extends RefCounted
## Deutsche Kennzeichen: Prüfen, Zufallskennzeichen und das Bild (blaues EU-Feld mit Sternenkreis
## und „D“, schwarze Schrift auf Weiß, schwarzer Rand). Die Schrift ist selbst gezeichnet im Stil
## der deutschen Kennzeichenschrift (schmal, eckig): jede Ziffer und jeder Buchstabe als Striche
## auf einem Raster 4 × 8 (x nach rechts, y nach unten), gezeichnet mit kleinen Quadraten.

const WIDTH: int = 520
const HEIGHT: int = 112
## Mesh-Größe in Metern (echtes Kennzeichen 520 × 110 mm)
const SIZE := Vector2(0.52, 0.11)
## So schmal darf unser Schild höchstens werden (passt in US-Mulden von 305 mm Breite)
const SHORT_WIDTH: float = 0.28

## Striche je Zeichen: Liste von Linienzügen, Punkte auf dem Raster 4 × 8
const GLYPHS := {
	"0": [[Vector2(1, 0), Vector2(3, 0), Vector2(4, 1), Vector2(4, 7), Vector2(3, 8), Vector2(1, 8), Vector2(0, 7), Vector2(0, 1), Vector2(1, 0)]],
	"1": [[Vector2(1, 2), Vector2(3, 0), Vector2(3, 8)]],
	"2": [[Vector2(0, 1), Vector2(1, 0), Vector2(3, 0), Vector2(4, 1), Vector2(4, 3), Vector2(0, 8), Vector2(4, 8)]],
	"3": [[Vector2(0, 0), Vector2(4, 0), Vector2(2, 3.5), Vector2(3, 3.5), Vector2(4, 4.5), Vector2(4, 7), Vector2(3, 8), Vector2(1, 8), Vector2(0, 7)]],
	"4": [[Vector2(3, 8), Vector2(3, 0), Vector2(0, 5.5), Vector2(4, 5.5)]],
	"5": [[Vector2(4, 0), Vector2(0.5, 0), Vector2(0, 3.5), Vector2(3, 3.5), Vector2(4, 4.5), Vector2(4, 7), Vector2(3, 8), Vector2(0, 8)]],
	"6": [[Vector2(3.5, 0), Vector2(1, 0), Vector2(0, 1), Vector2(0, 7), Vector2(1, 8), Vector2(3, 8), Vector2(4, 7), Vector2(4, 4.5), Vector2(3, 3.5), Vector2(0, 3.5)]],
	"7": [[Vector2(0, 0), Vector2(4, 0), Vector2(1.5, 8)]],
	"8": [[Vector2(1, 0), Vector2(3, 0), Vector2(4, 1), Vector2(4, 2.8), Vector2(3, 3.8), Vector2(1, 3.8), Vector2(0, 2.8), Vector2(0, 1), Vector2(1, 0)],
		[Vector2(1, 3.8), Vector2(0, 4.8), Vector2(0, 7), Vector2(1, 8), Vector2(3, 8), Vector2(4, 7), Vector2(4, 4.8), Vector2(3, 3.8)]],
	"9": [[Vector2(0.5, 8), Vector2(3, 8), Vector2(4, 7), Vector2(4, 1), Vector2(3, 0), Vector2(1, 0), Vector2(0, 1), Vector2(0, 3.5), Vector2(1, 4.5), Vector2(4, 4.5)]],
	"A": [[Vector2(0, 8), Vector2(0, 2), Vector2(2, 0), Vector2(4, 2), Vector2(4, 8)], [Vector2(0, 4.5), Vector2(4, 4.5)]],
	"B": [[Vector2(0, 8), Vector2(0, 0), Vector2(3, 0), Vector2(4, 1), Vector2(4, 2.8), Vector2(3, 3.8), Vector2(0, 3.8)],
		[Vector2(3, 3.8), Vector2(4, 4.8), Vector2(4, 7), Vector2(3, 8), Vector2(0, 8)]],
	"C": [[Vector2(4, 1), Vector2(3, 0), Vector2(1, 0), Vector2(0, 1), Vector2(0, 7), Vector2(1, 8), Vector2(3, 8), Vector2(4, 7)]],
	"D": [[Vector2(0, 0), Vector2(0, 8), Vector2(2.5, 8), Vector2(4, 6.5), Vector2(4, 1.5), Vector2(2.5, 0), Vector2(0, 0)]],
	"E": [[Vector2(4, 0), Vector2(0, 0), Vector2(0, 8), Vector2(4, 8)], [Vector2(0, 3.8), Vector2(3, 3.8)]],
	"F": [[Vector2(4, 0), Vector2(0, 0), Vector2(0, 8)], [Vector2(0, 3.8), Vector2(3, 3.8)]],
	"G": [[Vector2(4, 1), Vector2(3, 0), Vector2(1, 0), Vector2(0, 1), Vector2(0, 7), Vector2(1, 8), Vector2(3, 8), Vector2(4, 7), Vector2(4, 4.5), Vector2(2, 4.5)]],
	"H": [[Vector2(0, 0), Vector2(0, 8)], [Vector2(4, 0), Vector2(4, 8)], [Vector2(0, 4), Vector2(4, 4)]],
	"I": [[Vector2(2, 0), Vector2(2, 8)]],
	"J": [[Vector2(4, 0), Vector2(4, 7), Vector2(3, 8), Vector2(1, 8), Vector2(0, 7)]],
	"K": [[Vector2(0, 0), Vector2(0, 8)], [Vector2(4, 0), Vector2(0, 4.5)], [Vector2(1.3, 3.2), Vector2(4, 8)]],
	"L": [[Vector2(0, 0), Vector2(0, 8), Vector2(4, 8)]],
	"M": [[Vector2(0, 8), Vector2(0, 0), Vector2(2, 3.5), Vector2(4, 0), Vector2(4, 8)]],
	"N": [[Vector2(0, 8), Vector2(0, 0), Vector2(4, 8), Vector2(4, 0)]],
	"O": [[Vector2(1, 0), Vector2(3, 0), Vector2(4, 1), Vector2(4, 7), Vector2(3, 8), Vector2(1, 8), Vector2(0, 7), Vector2(0, 1), Vector2(1, 0)]],
	"P": [[Vector2(0, 8), Vector2(0, 0), Vector2(3, 0), Vector2(4, 1), Vector2(4, 3.5), Vector2(3, 4.5), Vector2(0, 4.5)]],
	"Q": [[Vector2(1, 0), Vector2(3, 0), Vector2(4, 1), Vector2(4, 7), Vector2(3, 8), Vector2(1, 8), Vector2(0, 7), Vector2(0, 1), Vector2(1, 0)], [Vector2(2.5, 6), Vector2(4.3, 8.3)]],
	"R": [[Vector2(0, 8), Vector2(0, 0), Vector2(3, 0), Vector2(4, 1), Vector2(4, 3.5), Vector2(3, 4.5), Vector2(0, 4.5)], [Vector2(2, 4.5), Vector2(4, 8)]],
	"S": [[Vector2(4, 1), Vector2(3, 0), Vector2(1, 0), Vector2(0, 1), Vector2(0, 2.8), Vector2(1, 3.8), Vector2(3, 4.2), Vector2(4, 5.2), Vector2(4, 7), Vector2(3, 8), Vector2(1, 8), Vector2(0, 7)]],
	"T": [[Vector2(0, 0), Vector2(4, 0)], [Vector2(2, 0), Vector2(2, 8)]],
	"U": [[Vector2(0, 0), Vector2(0, 7), Vector2(1, 8), Vector2(3, 8), Vector2(4, 7), Vector2(4, 0)]],
	"V": [[Vector2(0, 0), Vector2(2, 8), Vector2(4, 0)]],
	"W": [[Vector2(0, 0), Vector2(0.8, 8), Vector2(2, 3.5), Vector2(3.2, 8), Vector2(4, 0)]],
	"X": [[Vector2(0, 0), Vector2(4, 8)], [Vector2(4, 0), Vector2(0, 8)]],
	"Y": [[Vector2(0, 0), Vector2(2, 4), Vector2(4, 0)], [Vector2(2, 4), Vector2(2, 8)]],
	"Z": [[Vector2(0, 0), Vector2(4, 0), Vector2(0, 8), Vector2(4, 8)]],
	"Ä": [[Vector2(0, 8), Vector2(0, 2), Vector2(2, 0), Vector2(4, 2), Vector2(4, 8)], [Vector2(0, 4.5), Vector2(4, 4.5)], [Vector2(1, -1.4), Vector2(1, -1.0)], [Vector2(3, -1.4), Vector2(3, -1.0)]],
	"Ö": [[Vector2(1, 0), Vector2(3, 0), Vector2(4, 1), Vector2(4, 7), Vector2(3, 8), Vector2(1, 8), Vector2(0, 7), Vector2(0, 1), Vector2(1, 0)], [Vector2(1, -1.4), Vector2(1, -1.0)], [Vector2(3, -1.4), Vector2(3, -1.0)]],
	"Ü": [[Vector2(0, 0), Vector2(0, 7), Vector2(1, 8), Vector2(3, 8), Vector2(4, 7), Vector2(4, 0)], [Vector2(1, -1.4), Vector2(1, -1.0)], [Vector2(3, -1.4), Vector2(3, -1.0)]],
	"-": [[Vector2(0.5, 4), Vector2(3.5, 4)]],
}
## Diese Buchstabenpaare gibt es auf deutschen Kennzeichen nicht
const FORBIDDEN := ["HJ", "KZ", "NS", "SA", "SS"]


## Eingabe in die übliche Form bringen („m cd2026“ → „M-CD 2026“); leer = ungültig.
## Format: 1–3 Buchstaben (Ort), 1–2 Buchstaben, 1–4 Ziffern (nicht mit 0 beginnend).
static func normalize(text: String) -> String:
	var clean := text.strip_edges().to_upper().replace("–", "-")
	var regex := RegEx.create_from_string("^([A-ZÄÖÜ]{1,3})[- ]+([A-Z]{1,2})[ -]*([1-9][0-9]{0,3})$")
	var found := regex.search(clean)
	if found == null:
		return ""
	if found.get_string(2) in FORBIDDEN:
		return ""
	return "%s-%s %s" % [found.get_string(1), found.get_string(2), found.get_string(3)]


## Zufallskennzeichen mit einem Kürzel aus einem Ortsnamen der Welt
static func random(rng: RandomNumberGenerator, place: String) -> String:
	var letters := place.to_upper().replace("Ä", "A").replace("Ö", "O").replace("Ü", "U").replace("ß", "S")
	var only := ""
	for ch in letters:
		if ch >= "A" and ch <= "Z":
			only += ch
	var prefix := only.substr(0, rng.randi_range(1, 3)) if only != "" else "EW"
	var middle := ""
	while middle == "" or middle in FORBIDDEN:
		middle = ""
		for k in rng.randi_range(1, 2):
			middle += char(65 + rng.randi_range(0, 25))
	var digits := str(rng.randi_range(1, 9))
	for k in rng.randi_range(0, 3):
		digits += str(rng.randi_range(0, 9))
	return "%s-%s %s" % [prefix, middle, digits]


## Bild des Kennzeichens (WIDTH × HEIGHT)
## Bild des Kennzeichens; pixel_width < WIDTH für kürzere Schilder (gleiche Höhe, Schrift wird
## nicht verzerrt, bei Bedarf etwas kleiner)
static func make_texture(text: String, pixel_width: int = WIDTH) -> ImageTexture:
	var w := clampi(pixel_width, 300, WIDTH)
	var image := Image.create(w, HEIGHT, false, Image.FORMAT_RGB8)
	image.fill(Color.BLACK)
	image.fill_rect(Rect2i(4, 4, w - 8, HEIGHT - 8), Color(0.96, 0.96, 0.94))
	# EU-Feld: blau, Kreis aus 12 gelben Sternen (als Punkte), darunter „D“
	image.fill_rect(Rect2i(4, 4, 46, HEIGHT - 8), Color(0.0, 0.2, 0.6))
	for k in 12:
		var a := TAU * k / 12.0
		var star := Vector2(27, 36) + Vector2(cos(a), sin(a)) * 13.0
		image.fill_rect(Rect2i(roundi(star.x) - 2, roundi(star.y) - 2, 4, 4), Color(1.0, 0.85, 0.0))
	_draw_text(image, "D", Vector2(20, 66), 4.0, 3, Color.WHITE)
	# Schrift: Höhe 64 px, schmal; Bindestrich und Leerzeichen etwas schmaler
	var units := 0.0
	for ch in text:
		units += 3.0 if ch == " " else (5.5 if ch == "-" else 6.2)
	var scale := minf(8.0, (w - 66.0) / maxf(units, 1.0))
	var width := units * scale
	var x := 50.0 + maxf((w - 58.0 - width) * 0.5, 4.0)
	_draw_text(image, text, Vector2(x, 24 + (8.0 - scale) * 4.0), scale, 4, Color.BLACK)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


static func _draw_text(image: Image, text: String, origin: Vector2, scale: float, half: int, color: Color) -> void:
	var x := origin.x
	for ch in text:
		if ch == " ":
			x += 3.0 * scale
			continue
		for stroke: Array in GLYPHS.get(ch, []):
			for k in stroke.size() - 1:
				var a: Vector2 = origin + Vector2(x - origin.x, 0) + (stroke[k] as Vector2) * scale
				var b: Vector2 = origin + Vector2(x - origin.x, 0) + (stroke[k + 1] as Vector2) * scale
				var steps := maxi(ceili(a.distance_to(b) / 1.5), 1)
				for s in steps + 1:
					var p := a.lerp(b, float(s) / steps)
					image.fill_rect(Rect2i(roundi(p.x) - half, roundi(p.y) - half, half * 2, half * 2), color)
		x += (5.5 if ch == "-" else 6.2) * scale


## Kennzeichen als Fläche (Mitte bei 0, Vorderseite nach +Z)
static func make_mesh(text: String, size: Vector2 = SIZE) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = size if size.x > 0.05 and size.y > 0.02 else SIZE
	var material := StandardMaterial3D.new()
	material.albedo_texture = make_texture(text, pixels_for(quad.size))
	material.roughness = 0.5
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	quad.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = quad
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


## Bildbreite (Pixel) für ein Schild dieser Größe (Höhe immer HEIGHT)
static func pixels_for(size: Vector2) -> int:
	return roundi(HEIGHT * size.x / maxf(size.y, 0.01))


## Größe unseres Schilds für ein gemessenes Original-Kennzeichen bzw. eine Mulde: so breit wie das
## Original (1 cm Rand), 280–520 mm, immer 110 mm hoch wie ein deutsches Kennzeichen. US-Mulden
## (305 × 152 mm) bekommen ein kurzes Schild, das in die Mulde passt; die Schrift bleibt unverzerrt
## (bei Bedarf kleiner).
static func fit_size(measured: Vector2) -> Vector2:
	if measured.x <= 0.0:
		return SIZE
	return Vector2(clampf(measured.x - 0.01, SHORT_WIDTH, SIZE.x), SIZE.y)


## Schild an eine Stelle setzen: Mitte, vorne (Blick nach +Z) oder hinten, Neigung in Grad
## (positiv = oben nach hinten geneigt, die Fläche schaut etwas nach oben)
static func place(plate: MeshInstance3D, center: Vector3, front: bool, tilt_degrees: float) -> void:
	plate.position = center
	plate.rotation = Vector3(-deg_to_rad(tilt_degrees), 0.0 if front else PI, 0.0)
