extends Control
## Drei Glas-Chips oben rechts: Uhrzeit, Wetter mit Temperatur, Jahreszeit.

@export var day_night: DayNight
@export var weather: Weather
@export var car: Car

const CHIP_HEIGHT: float = 42.0
const GAP: float = 12.0
const WEATHER_ICONS := ["sun", "cloud", "rain", "storm", "fog", "snow"]
const WEATHER_COLORS: Array[Color] = [Color("#F5C04A"), Color("#DDE3EC"), Color("#7CC4FF"), Color("#F5C04A"),
	Color("#C9D1DC"), Color("#DCEBFF")]
const SEASON_ICONS := ["sprout", "leaf", "leaf", "snow"]
const SEASON_COLORS: Array[Color] = [Color("#4CC38A"), Color("#4CC38A"), Color("#F08A3C"), Color("#DCEBFF")]

var _glass: Array[GlassPanel] = []
## Pro Chip: [Symbol, Farbe, Text]
var _chips: Array = []
var _timer: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in 3:
		var glass := GlassPanel.new()
		glass.radius = CHIP_HEIGHT * 0.5
		glass.blur = 0.0
		glass.show_behind_parent = true
		add_child(glass)
		_glass.append(glass)


func _process(delta: float) -> void:
	# Zweimal pro Sekunde reicht
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.5
	var chips: Array = []
	if day_night:
		var minutes := int(day_night.time_of_day * 60.0) % (24 * 60)
		chips.append(["clock", UiStyle.TEXT, "%02d:%02d" % [floori(minutes / 60.0), minutes % 60]])
	if weather:
		var height := car.global_position.y if car else 100.0
		var temperature := roundi(weather.temperature(height))
		var text := "%s · %d °C" % [Weather.KIND_NAMES[weather.kind], temperature]
		chips.append([WEATHER_ICONS[weather.kind], WEATHER_COLORS[weather.kind], text.replace("-", "−")])
		chips.append([SEASON_ICONS[weather.season], SEASON_COLORS[weather.season], Weather.SEASON_NAMES[weather.season]])
	if chips != _chips:
		_chips = chips
		_layout()
		queue_redraw()


## Chips von rechts nach links anordnen, jeder so breit wie sein Text
func _layout() -> void:
	var x := size.x
	for i in range(_chips.size() - 1, -1, -1):
		var width := 16.0 + 18.0 + 8.0 + UiStyle.text_width(_chips[i][2], 16, "semibold") + 18.0
		x -= width
		_glass[i].position = Vector2(x, 0.0)
		_glass[i].size = Vector2(width, CHIP_HEIGHT)
		x -= GAP
	for i in range(_chips.size(), _glass.size()):
		_glass[i].visible = false


func _draw() -> void:
	for i in _chips.size():
		var rect := Rect2(_glass[i].position, _glass[i].size)
		var chip: Array = _chips[i]
		UiIcons.draw(self, chip[0], rect.position + Vector2(25.0, CHIP_HEIGHT * 0.5), 18.0, chip[1], 1.8)
		UiStyle.draw_text(self, chip[2], rect.position + Vector2(42.0, 27.0), 16, "semibold", UiStyle.TEXT)
