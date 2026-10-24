class_name UiStyle
extends RefCounted
## Gemeinsamer Stil für HUD und Menüs (Entwurf „Glas“): Schrift Inter, Farben, Akzentfarbe.
## Alles ist für eine Bildgröße von 1600 × 900 gebaut. Godot skaliert es mit dem Fenster
## (Projekteinstellungen > Anzeige > Fenster > Stretch: canvas_items).

## Milchglas: dunkle Tönung und feiner heller Rand
const GLASS := Color(14.0 / 255.0, 18.0 / 255.0, 26.0 / 255.0, 0.48)
const BORDER := Color(1.0, 1.0, 1.0, 0.14)
## Deckkraft der Glas-Flächen ohne Unschärfe (HUD beim Fahren)
const GLASS_FLAT_ALPHA: float = 0.64
## Kästchen innerhalb von Glas-Flächen (z. B. Gang, Segmente)
const INSET := Color(1.0, 1.0, 1.0, 0.07)
const TEXT := Color(1.0, 1.0, 1.0)
const TEXT_DIM := Color(1.0, 1.0, 1.0, 0.62)
const TEXT_FAINT := Color(1.0, 1.0, 1.0, 0.4)
const RED := Color("#E5484D")
const GREEN := Color("#2F9E5B")
## Wählbare Akzentfarben (Garage), die erste ist der Standard
const ACCENTS: Array[Color] = [Color("#3D8BFF"), Color("#22C3A6"), Color("#FF7A1A"), Color("#E5484D")]
const FONT_FILES := {"regular": "Regular", "medium": "Medium", "semibold": "SemiBold", "extrabold": "ExtraBold"}

## Aktuelle Akzentfarbe (Route, Navi-Pfeil, Drehzahl, Knöpfe)
static var accent: Color = Color("#3D8BFF")
static var _fonts: Dictionary = {}


## Inter in einer Stärke: "regular", "medium", "semibold" oder "extrabold".
## Ziffern sind gleich breit (OpenType „tnum“), damit Zahlen beim Hochzählen nicht wackeln.
## spacing = zusätzlicher Abstand zwischen den Buchstaben (für Überschriften wie „GARAGE“)
static func font(weight: String = "regular", spacing: int = 0) -> Font:
	var key := "%s/%d" % [weight, spacing]
	if not _fonts.has(key):
		var variation := FontVariation.new()
		variation.base_font = load("res://assets/fonts/Inter-%s.ttf" % FONT_FILES[weight])
		variation.opentype_features = {TextServerManager.get_primary_interface().name_to_tag("tnum"): 1}
		variation.spacing_glyph = spacing
		_fonts[key] = variation
	return _fonts[key]


## Fertiges Label mit Schrift, Größe und Farbe
static func label(text: String, size: int, weight: String = "regular", color: Color = TEXT,
		spacing: int = 0) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_override("font", font(weight, spacing))
	result.add_theme_font_size_override("font_size", size)
	result.add_theme_color_override("font_color", color)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result


## Text in einer Zeile zeichnen. align: 0 = links, 0.5 = Mitte, 1 = rechts (bezogen auf pos.x).
## pos.y ist die Grundlinie.
static func draw_text(canvas: CanvasItem, text: String, pos: Vector2, size: int, weight: String,
		color: Color, align: float = 0.0, spacing: int = 0) -> float:
	var f := font(weight, spacing)
	var width := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	canvas.draw_string(f, Vector2(pos.x - width * align, pos.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
	return width


## Breite eines Texts
static func text_width(text: String, size: int, weight: String) -> float:
	return font(weight).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## Abgerundetes Rechteck als StyleBox (für Knöpfe und Kästchen)
static func box(color: Color, radius: int, border: Color = Color(0, 0, 0, 0), border_width: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.border_color = border
	style.set_border_width_all(border_width)
	style.anti_aliasing = true
	return style


## Abgerundetes Rechteck zeichnen (gefüllt, optional mit Rand)
static func draw_box(canvas: CanvasItem, rect: Rect2, color: Color, radius: int,
		border: Color = Color(0, 0, 0, 0), border_width: int = 0) -> void:
	canvas.draw_style_box(box(color, radius, border, border_width), rect)

