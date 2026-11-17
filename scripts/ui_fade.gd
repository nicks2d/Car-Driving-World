class_name UiFade
extends RefCounted
## Weiches Ein- und Ausblenden ganzer Bildschirm-Ebenen (CanvasLayer: Pausemenü, Garage, Karte, Fotomodus,
## HUD). Eine Ebene selbst hat keine Deckkraft, deshalb bekommen ihre obersten Flächen eine kurze
## Animation. Beim Ausblenden bleibt die Ebene sichtbar, bis die Animation fertig ist; in der Zeit fängt
## eine unsichtbare Fläche alle Klicks ab, damit niemand aus Versehen einen Knopf im verschwindenden Menü
## trifft. Die Menüs entscheiden weiter selbst über is_open (sofort), nur das Bild läuft nach.

## Dauer in Sekunden (Menüs öffnen etwas schneller, als sie schließen)
const IN_SECONDS: float = 0.18
const OUT_SECONDS: float = 0.22
const BLOCKER_NAME := "UiFadeBlocker"


## Ebene zeigen (shown = true) oder ausblenden. Läuft gerade die Gegenrichtung, geht es von dort aus weiter.
static func set_shown(layer: CanvasLayer, shown: bool) -> void:
	if layer.has_meta("ui_fade"):
		var running := layer.get_meta("ui_fade") as Tween
		if running:
			running.kill()
		layer.remove_meta("ui_fade")
	_remove_blocker(layer)
	var items := _items(layer)
	if shown:
		if not layer.visible:
			for item in items:
				item.modulate.a = 0.0
			layer.visible = true
		_animate(layer, items, 1.0, IN_SECONDS)
		return
	if not layer.visible:
		return
	var blocker := Control.new()
	blocker.name = BLOCKER_NAME
	blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(blocker)
	# Tastatur-Fokus loslassen (sonst könnte Leertaste oder Enter noch einen Knopf drücken)
	if layer.is_inside_tree():
		layer.get_viewport().gui_release_focus()
	var tween := _animate(layer, items, 0.0, OUT_SECONDS)
	if tween:
		tween.chain().tween_callback(_finish_hide.bind(layer))
	else:
		_finish_hide(layer)


## Läuft gerade eine Animation auf dieser Ebene? (Fotos warten darauf)
static func is_fading(layer: CanvasLayer) -> bool:
	return layer.has_meta("ui_fade")


## Zwei Flächen weich tauschen (z. B. Reiter in den Einstellungen): die alte verschwindet sofort, die neue
## blendet von leicht durchsichtig ein
static func swap_in(item: CanvasItem) -> void:
	if not item.is_inside_tree():
		return
	item.modulate.a = 0.0
	var tween := item.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(item, "modulate:a", 1.0, IN_SECONDS)


static func _animate(layer: CanvasLayer, items: Array[CanvasItem], alpha: float, seconds: float) -> Tween:
	if items.is_empty() or not layer.is_inside_tree():
		for item in items:
			item.modulate.a = alpha
		return null
	var tween := layer.create_tween()
	# Menüs halten das Spiel an: die Animation läuft trotzdem
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	for item in items:
		tween.tween_property(item, "modulate:a", alpha, seconds)
	layer.set_meta("ui_fade", tween)
	# Nur die Nummer der Animation merken (die Animation selbst festzuhalten wäre ein Kreis, der nie frei wird)
	tween.finished.connect(_on_finished.bind(layer, tween.get_instance_id()))
	return tween


static func _on_finished(layer: CanvasLayer, tween_id: int) -> void:
	if not is_instance_valid(layer) or not layer.has_meta("ui_fade"):
		return
	var current := layer.get_meta("ui_fade") as Tween
	if current == null or current.get_instance_id() == tween_id:
		layer.remove_meta("ui_fade")


static func _finish_hide(layer: CanvasLayer) -> void:
	layer.visible = false
	_remove_blocker(layer)
	for item in _items(layer):
		item.modulate.a = 1.0
	if layer.has_meta("ui_fade"):
		layer.remove_meta("ui_fade")


static func _remove_blocker(layer: CanvasLayer) -> void:
	var blocker := layer.get_node_or_null(BLOCKER_NAME)
	if blocker:
		layer.remove_child(blocker)
		blocker.queue_free()


## Die obersten sichtbaren Flächen der Ebene (ohne den Klick-Fänger)
static func _items(layer: CanvasLayer) -> Array[CanvasItem]:
	var result: Array[CanvasItem] = []
	for child in layer.get_children():
		var item := child as CanvasItem
		if item and child.name != BLOCKER_NAME:
			result.append(item)
	return result
