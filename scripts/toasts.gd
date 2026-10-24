class_name Toasts
extends Control
## Meldungen oben links (Entwurf „Glas“): Symbol, Titel, Unterzeile, rechts optional ein
## Tastenhinweis. Sie gleiten ein, bleiben ein paar Sekunden und blenden wieder aus.
## Melden kann jeder: Toasts.post(get_tree(), "rain", "Regen setzt ein", "Straße wird nass")

## So lange bleibt eine Meldung stehen (Sekunden)
@export var show_seconds: float = 4.0
@export var width: float = 460.0
@export var max_visible: int = 3

const HEIGHT: float = 68.0
const GAP: float = 12.0
const FADE: float = 0.3
const ICON_COLORS := {"rain": Color("#7CC4FF"), "storm": Color("#F5C04A"), "sun": Color("#F5C04A"),
	"cloud": Color("#DDE3EC"), "fog": Color("#C9D1DC"), "snow": Color("#DCEBFF"), "leaf": Color("#F08A3C"),
	"sprout": Color("#4CC38A"), "view": Color("#B79CFF"), "camera": Color("#7CC4FF"), "tunnel": Color("#DDE3EC"),
	"check": Color("#4CC38A"), "warning": Color("#F5C04A"), "pin": Color("#7CC4FF")}

## Eine Meldung: Glasfläche, Texte und wie lange sie schon steht
class Toast:
	var glass: GlassPanel
	var icon: String
	var title: String
	var subtitle: String
	var key: String
	var key_label: String
	var age: float = 0.0
	var y: float = -100.0

var _toasts: Array[Toast] = []


## Meldung von überall aus zeigen (alle Toasts-Nodes im Baum bekommen sie)
static func post(tree: SceneTree, icon: String, title: String, subtitle: String = "", key: String = "",
		key_label: String = "") -> void:
	tree.call_group("toasts", "show_toast", icon, title, subtitle, key, key_label)


func _ready() -> void:
	add_to_group("toasts")
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_toast(icon: String, title: String, subtitle: String = "", key: String = "", key_label: String = "") -> void:
	# Gleiche Meldung steht schon da: nur verlängern
	for toast in _toasts:
		if toast.title == title and toast.subtitle == subtitle:
			toast.age = minf(toast.age, FADE)
			return
	var toast := Toast.new()
	toast.icon = icon
	toast.title = title
	toast.subtitle = subtitle
	toast.key = key
	toast.key_label = key_label
	toast.glass = GlassPanel.new()
	toast.glass.radius = 20.0
	toast.glass.blur = 0.0
	toast.glass.size = Vector2(width, HEIGHT)
	toast.glass.show_behind_parent = true
	toast.glass.modulate.a = 0.0
	add_child(toast.glass)
	_toasts.push_front(toast)
	while _toasts.size() > max_visible:
		var old: Toast = _toasts.pop_back()
		old.glass.queue_free()


func _process(delta: float) -> void:
	if _toasts.is_empty():
		return
	for i in range(_toasts.size() - 1, -1, -1):
		var toast := _toasts[i]
		toast.age += delta
		if toast.age > show_seconds + FADE:
			toast.glass.queue_free()
			_toasts.remove_at(i)
	# Neue oben, ältere rutschen weich nach unten
	for i in _toasts.size():
		var toast := _toasts[i]
		var target_y := i * (HEIGHT + GAP)
		toast.y = target_y if toast.y < -50.0 else lerpf(toast.y, target_y, clampf(delta * 10.0, 0.0, 1.0))
		var fade_in := clampf(toast.age / FADE, 0.0, 1.0)
		var fade_out := clampf((show_seconds + FADE - toast.age) / FADE, 0.0, 1.0)
		toast.glass.modulate.a = minf(fade_in, fade_out)
		toast.glass.position = Vector2(-16.0 * (1.0 - fade_in), toast.y)
	queue_redraw()


func _draw() -> void:
	for toast in _toasts:
		var alpha := toast.glass.modulate.a
		var origin := toast.glass.position
		var icon_color: Color = ICON_COLORS.get(toast.icon, UiStyle.TEXT)
		UiIcons.draw(self, toast.icon, origin + Vector2(34.0, HEIGHT * 0.5), 24.0, Color(icon_color, alpha), 1.9)
		var title_y := 30.0 if toast.subtitle != "" else 40.0
		UiStyle.draw_text(self, toast.title, origin + Vector2(62.0, title_y), 17, "semibold", Color(1, 1, 1, alpha))
		if toast.subtitle != "":
			UiStyle.draw_text(self, toast.subtitle, origin + Vector2(62.0, 52.0), 14, "regular",
				Color(UiStyle.TEXT_DIM, UiStyle.TEXT_DIM.a * alpha))
		if toast.key != "":
			var label_width := UiStyle.text_width(toast.key_label, 14, "medium")
			var right := origin.x + width - 18.0
			UiStyle.draw_text(self, toast.key_label, Vector2(right, origin.y + 39.0), 14, "medium",
				Color(UiStyle.TEXT_DIM, UiStyle.TEXT_DIM.a * alpha), 1.0)
			var key_rect := Rect2(right - label_width - 40.0, origin.y + 21.0, 28.0, 26.0)
			UiStyle.draw_box(self, key_rect, Color(1, 1, 1, 0.08 * alpha), 6, Color(1, 1, 1, 0.3 * alpha), 1)
			UiStyle.draw_text(self, toast.key, Vector2(key_rect.get_center().x, origin.y + 39.0), 13, "semibold",
				Color(1, 1, 1, alpha), 0.5)
