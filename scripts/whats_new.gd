class_name WhatsNew
extends CanvasLayer
## Fenster „Was ist neu“: zeigt den Abschnitt der aktuellen Version aus CHANGELOG.md (liegt mit in der App).
## Erscheint einmal pro Version beim Start (auch beim allerersten Start), nie in Testläufen. Die zuletzt
## gezeigte Version steht in user://einstellungen.cfg ([info] version_gesehen). Im Pausemenü lässt es sich
## über „Was ist neu?“ jederzeit wieder öffnen.

signal closed

@export var debug_tools: DebugTools
@export var window_size: Vector2 = Vector2(760.0, 620.0)

const SETTINGS_PATH := "user://einstellungen.cfg"
const CHANGELOG_PATH := "res://CHANGELOG.md"

var is_open: bool = false
var _text: RichTextLabel
var _title: Label
var _button: Button


## Versionsnummer des Spiels (Projekteinstellungen > Anwendung > Konfiguration > Version)
static func version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "1.0.0"))


func _ready() -> void:
	layer = 36
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false


## Beim Start (game.gd, sobald die Welt da ist): einmal pro Version zeigen, nie in Testläufen
func show_if_new() -> void:
	# Nie in Testläufen und Prüfwerkzeugen: alles mit Argumenten (auch Welt-Prüfer, --quitafter) oder ohne
	# Bildschirm, sonst wäre die Version als „gesehen“ gespeichert, bevor Nick das Fenster je sieht
	if (debug_tools and debug_tools.is_active()) or not OS.get_cmdline_user_args().is_empty() \
			or DisplayServer.get_name() == "headless":
		return
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	if str(config.get_value("info", "version_gesehen", "")) == version():
		return
	config.set_value("info", "version_gesehen", version())
	config.save(SETTINGS_PATH)
	open()


func open() -> void:
	if is_open:
		return
	is_open = true
	_fill()
	_button.add_theme_stylebox_override("normal", _button_style(UiStyle.accent))
	_button.add_theme_stylebox_override("hover", _button_style(UiStyle.accent.lightened(0.12)))
	UiFade.set_shown(self, true)


func close() -> void:
	if not is_open:
		return
	is_open = false
	UiFade.set_shown(self, false)
	closed.emit()


## Vor allen anderen (auch vor der Garage darunter): Esc oder Enter schließt
func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept"):
		close()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# Inhalt aus CHANGELOG.md
# ---------------------------------------------------------------------------

func _fill() -> void:
	var section := _changelog_section(version())
	_title.text = "Version %s" % version()
	if section.is_empty():
		_text.text = "Keine Notizen zu dieser Version gefunden."
		return
	# Erste Zeile: „## 1.0.0 – 17.11.2026“ → Datum neben dem Titel
	var heading: String = section[0]
	var dash := heading.find("–")
	if dash >= 0:
		_title.text += "  ·  " + heading.substr(dash + 1).strip_edges()
	_text.text = _to_bbcode(section.slice(1))


## Zeilen des Abschnitts „## VERSION …“ bis zum nächsten „## “
static func _changelog_section(wanted: String) -> PackedStringArray:
	var result := PackedStringArray()
	var file := FileAccess.open(CHANGELOG_PATH, FileAccess.READ)
	if file == null:
		return result
	var inside := false
	for line in file.get_as_text().split("\n"):
		if line.begins_with("## "):
			if inside:
				break
			var heading := line.substr(3).strip_edges()
			inside = heading == wanted or heading.begins_with(wanted + " ")
		if inside:
			result.append(line)
	return result


## Einfaches Markdown (### Überschrift, - Punkt, **fett**, eingerückte Fortsetzung) als BBCode
func _to_bbcode(lines: PackedStringArray) -> String:
	var parts: Array[String] = []
	for line in lines:
		var text := line.strip_edges()
		if text == "":
			continue
		if line.begins_with("### "):
			var color := UiStyle.accent.to_html(false)
			parts.append("\n[font_size=13][color=#%s]%s[/color][/font_size]" % [color, text.substr(4).to_upper()])
		elif text.begins_with("- "):
			parts.append("[indent]•  %s[/indent]" % _bold(text.substr(2)))
		elif not parts.is_empty() and parts[-1].ends_with("[/indent]"):
			# Fortsetzung des letzten Punkts (eingerückte Zeile)
			parts[-1] = parts[-1].trim_suffix("[/indent]") + " " + _bold(text) + "[/indent]"
		else:
			parts.append(_bold(text))
	return "\n".join(parts).strip_edges()


static func _bold(text: String) -> String:
	var result := text
	while result.count("**") >= 2:
		var a := result.find("**")
		var b := result.find("**", a + 2)
		result = result.substr(0, a) + "[b]" + result.substr(a + 2, b - a - 2) + "[/b]" + result.substr(b + 2)
	return result


# ---------------------------------------------------------------------------
# Aufbau
# ---------------------------------------------------------------------------

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	var window := Control.new()
	window.size = window_size
	window.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	root.add_child(window)
	var glass := GlassPanel.new()
	glass.radius = 28.0
	glass.tint = Color(UiStyle.GLASS, 0.78)
	glass.set_anchors_preset(Control.PRESET_FULL_RECT)
	window.add_child(glass)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 34)
	window.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	box.add_child(UiStyle.label("WAS IST NEU", 13, "semibold", UiStyle.TEXT_DIM, 2))
	_title = UiStyle.label("", 26, "extrabold")
	box.add_child(_title)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, 6.0)
	box.add_child(gap)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.scroll_active = true
	_text.selection_enabled = false
	_text.add_theme_font_override("normal_font", UiStyle.font("regular"))
	_text.add_theme_font_override("bold_font", UiStyle.font("semibold"))
	_text.add_theme_font_size_override("normal_font_size", 16)
	_text.add_theme_font_size_override("bold_font_size", 16)
	_text.add_theme_color_override("default_color", Color(1, 1, 1, 0.86))
	_text.add_theme_constant_override("line_separation", 5)
	box.add_child(_text)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	box.add_child(footer)
	var hint := UiStyle.label("Esc oder Enter schließt", 14, "medium", UiStyle.TEXT_FAINT)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(hint)
	_button = Button.new()
	_button.text = "Los geht's"
	_button.focus_mode = Control.FOCUS_NONE
	_button.custom_minimum_size = Vector2(180.0, 48.0)
	_button.add_theme_font_override("font", UiStyle.font("semibold"))
	_button.add_theme_font_size_override("font_size", 17)
	_button.add_theme_color_override("font_color", UiStyle.TEXT)
	_button.add_theme_color_override("font_hover_color", UiStyle.TEXT)
	_button.add_theme_stylebox_override("pressed", _button_style(UiStyle.accent))
	_button.pressed.connect(close)
	footer.add_child(_button)


func _button_style(color: Color) -> StyleBoxFlat:
	var style := UiStyle.box(color, 14)
	style.content_margin_left = 20
	style.content_margin_right = 20
	return style
