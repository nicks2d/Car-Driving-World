class_name FrameCosts
extends RefCounted
## Rechenzeit pro Bild für die großen Teile (Gelände, Straßen, Verkehr …), um Ruckler zu finden. Die Teile
## melden ihre Zeit mit add(); DebugTools holt sie im Benchmark jedes Bild mit take() ab und gibt am Ende
## die schlechtesten Bilder mit Aufschlüsselung aus. Kostet fast nichts (eine Zeitmessung pro Teil und Bild).

static var _costs: Dictionary = {}


## Zeit seit started (Time.get_ticks_usec) unter diesem Namen dazuzählen
static func add(part: String, started: int) -> void:
	_costs[part] = _costs.get(part, 0) + Time.get_ticks_usec() - started


## Zeiten dieses Bilds (Name -> Mikrosekunden) abholen und zurücksetzen
static func take() -> Dictionary:
	var result := _costs
	_costs = {}
	return result
