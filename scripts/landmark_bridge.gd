class_name LandmarkBridge
extends RefCounted
## Besondere Brücken als Landmarke: Ist eine Brücke lang und hoch, trägt sie statt der Pfeiler
## alle 24 m ein großer Betonbogen mit Stützen (Bogenbrücke) oder, bei sehr breiten, tiefen
## Tälern, zwei Pylone mit Tragseilen und Hängern (Hängebrücke). Auch auf der Autobahn
## (Talbrücken). Gebaut im Hintergrund nach dem Berechnen des Abschnitts (RoadSegment.build),
## damit RoadNetwork sie schon von weitem zeigen kann (eigene Sichtweite, ohne Fahrbahn).
## Nachts leuchten rote Lampen auf den Pylonen bzw. am Bogenscheitel.

## Ab dieser Länge (Meter) und Höhe über dem Tal (Meter) wird es eine Landmarke; Landstraßen
## dürfen höchstens 50 m über dem Gelände liegen (RoadSegment.MAX_FILL), dort reichen 35 m
const MIN_LENGTH: float = 250.0
const MIN_HEIGHT: float = 50.0
const MIN_HEIGHT_ROAD: float = 35.0
## Hängebrücke ab dieser Länge und Höhe (sonst Bogen)
const SUSPENSION_LENGTH: float = 450.0
const SUSPENSION_HEIGHT: float = 45.0
## Bogen: Dicke (senkrecht) und Abstand der Stützen (Punkte à 4 m)
const ARCH_THICKNESS: float = 2.6
const COLUMN_EVERY: int = 3
## Hängebrücke: Lage der Pylone (Anteil der Länge), Hänger alle so viele Punkte
const PYLON_AT: float = 0.22
const HANGER_EVERY: int = 2


## Erste lange, hohe Brücke des Abschnitts: {"kind", "range" (erster/letzter Punkt), "zone"
## (dort keine normalen Pfeiler), "center", "length", "height"} oder leer
static func find(segment: RoadSegment) -> Dictionary:
	var n := segment.points.size()
	var i := 0
	while i < n:
		if segment.bridge[i] == 0 or (not segment.on_dam.is_empty() and segment.on_dam[i] == 1):
			i += 1
			continue
		var j := i
		while j < n and segment.bridge[j] == 1:
			j += 1
		var length := (j - i) * RoadSegment.POINT_SPACING
		var height := 0.0
		var deepest := i
		for k in range(i, j):
			if segment.points[k].y - segment.ground[k] > height:
				height = segment.points[k].y - segment.ground[k]
				deepest = k
		var min_height := MIN_HEIGHT if segment.kind == RoadSegment.Kind.HIGHWAY else MIN_HEIGHT_ROAD
		if length >= MIN_LENGTH and height >= min_height:
			var kind := "suspension" if length >= SUSPENSION_LENGTH and height >= SUSPENSION_HEIGHT else "arch"
			var zone := Vector2i(i, j - 1)
			if kind == "arch":
				# Der Bogen steht dort, wo das Tal tiefer als 45 % der größten Höhe ist
				var a := i
				var b := j - 1
				while a < deepest and segment.points[a].y - segment.ground[a] < height * 0.45:
					a += 1
				while b > deepest and segment.points[b].y - segment.ground[b] < height * 0.45:
					b -= 1
				zone = Vector2i(a, b)
			else:
				zone = Vector2i(i + roundi((j - i) * PYLON_AT), i + roundi((j - i) * (1.0 - PYLON_AT)))
			return {"kind": kind, "range": Vector2i(i, j - 1), "zone": zone, "center": segment.points[deepest],
				"length": length, "height": height}
		i = j
	return {}


## Mesh-Daten (relativ zu info["center"]): "concrete", "steel", "lamps" und "lights" (Lage der
## Lampen in Weltkoordinaten)
static func build(segment: RoadSegment, info: Dictionary) -> Dictionary:
	var concrete := MeshBuilder.new()
	var steel := MeshBuilder.new()
	var lamps := MeshBuilder.new()
	var lights := PackedVector3Array()
	var o: Vector3 = info["center"]
	var outer := segment.road_width * 0.5 + segment.shoulder_width
	if info["kind"] == "arch":
		_build_arch(segment, info, concrete, lamps, lights, outer, o)
	else:
		_build_suspension(segment, info, concrete, steel, lamps, lights, outer, o)
	return {"concrete": concrete.arrays(), "steel": steel.arrays(), "lamps": lamps.arrays(), "lights": lights}


## Punkt auf der Mittellinie bei gebrochenem Index s
static func _at(segment: RoadSegment, s: float) -> Vector3:
	var k := clampi(floori(s), 0, segment.points.size() - 2)
	return segment.points[k].lerp(segment.points[k + 1], s - k)


static func _left(segment: RoadSegment, s: float) -> Vector3:
	var d := segment.direction_at(clampi(roundi(s), 0, segment.points.size() - 1))
	return Vector3.UP.cross(Vector3(d.x, 0.0, d.z)).normalized()


## Bogen: ein breiter Rippenbogen unter der Fahrbahn von Hang zu Hang, darauf senkrechte Stützen
## bis unter die Platte; am Scheitel eine rote Lampe
static func _build_arch(segment: RoadSegment, info: Dictionary, concrete: MeshBuilder, lamps: MeshBuilder,
		lights: PackedVector3Array, outer: float, o: Vector3) -> void:
	var zone: Vector2i = info["zone"]
	var a := float(zone.x)
	var b := float(zone.y)
	var y_a := segment.ground[zone.x] + 1.0
	var y_b := segment.ground[zone.y] + 1.0
	var middle := (a + b) * 0.5
	var crown := _at(segment, middle).y - RoadSegment.DECK_THICKNESS - 1.2
	var lift := crown - (y_a + y_b) * 0.5
	var half := outer * 0.75
	var steps := maxi(ceili((b - a) * 1.5), 8)
	var previous := []
	for step in steps + 1:
		var u := float(step) / steps
		var s := lerpf(a, b, u)
		var c := _at(segment, s)
		var y := lerpf(y_a, y_b, u) + lift * 4.0 * u * (1.0 - u)
		# Nie über der Unterseite der Fahrbahnplatte
		y = minf(y, c.y - RoadSegment.DECK_THICKNESS - 0.6)
		var left := _left(segment, s)
		var section := [Vector3(c.x, y, c.z) + left * half, Vector3(c.x, y, c.z) - left * half,
			Vector3(c.x, y - ARCH_THICKNESS, c.z) - left * half, Vector3(c.x, y - ARCH_THICKNESS, c.z) + left * half]
		if not previous.is_empty():
			for f in 4:
				concrete.quad(previous[f], section[f], section[(f + 1) % 4], previous[(f + 1) % 4], o, Vector2.ZERO, Vector2.ONE)
		previous = section
	# Stützen auf dem Bogen, links und rechts
	for k in range(zone.x + COLUMN_EVERY, zone.y - 1, COLUMN_EVERY):
		var u := (k - a) / (b - a)
		var c := segment.points[k]
		var y := minf(lerpf(y_a, y_b, u) + lift * 4.0 * u * (1.0 - u), c.y - RoadSegment.DECK_THICKNESS - 0.6)
		var top := c.y - RoadSegment.DECK_THICKNESS
		if top - y < 1.5:
			continue
		var left := _left(segment, k)
		for side: float in [1.0, -1.0]:
			var foot := Vector3(c.x, y, c.z) + left * side * half * 0.8
			concrete.box(foot + Vector3.UP * (top - y) * 0.5, Vector3(1.2, top - y, 1.2), segment.direction_at(k), o)
	# Rote Lampe am Bogenscheitel (unter der Platte, von weitem zu sehen)
	var crown_point := _at(segment, middle)
	var lamp := Vector3(crown_point.x, crown - 0.2, crown_point.z)
	lamps.box(lamp, Vector3(1.2, 1.2, 1.2), segment.direction_at(roundi(middle)), o)
	lights.append(lamp)


## Hängebrücke: zwei Pylone (je zwei Beine und Querriegel), Tragseile über die Pylonspitzen mit
## Durchhang bis knapp über die Fahrbahn, senkrechte Hänger; rote Lampen auf den Pylonen
static func _build_suspension(segment: RoadSegment, info: Dictionary, concrete: MeshBuilder, steel: MeshBuilder,
		lamps: MeshBuilder, lights: PackedVector3Array, outer: float, o: Vector3) -> void:
	var r: Vector2i = info["range"]
	var zone: Vector2i = info["zone"]
	var main_span := (zone.y - zone.x) * RoadSegment.POINT_SPACING
	var pylon_height := clampf(main_span * 0.22, 40.0, 110.0)
	var leg_offset := outer + 1.6
	var tops: Array[Vector3] = []
	for k: int in [zone.x, zone.y]:
		var c := segment.points[k]
		var left := _left(segment, k)
		var forward := segment.direction_at(k)
		var bottom := segment.ground[k] - 3.0
		var top_y := c.y + pylon_height
		for side: float in [1.0, -1.0]:
			var leg := Vector3(c.x, 0.0, c.z) + left * side * leg_offset
			concrete.box(Vector3(leg.x, (bottom + top_y) * 0.5, leg.z), Vector3(2.8, top_y - bottom, 2.8), forward, o)
			var lamp := Vector3(leg.x, top_y + 0.5, leg.z)
			lamps.box(lamp, Vector3(1.4, 1.4, 1.4), forward, o)
			lights.append(lamp)
		# Querriegel unter der Fahrbahn und oben
		for y: float in [c.y - RoadSegment.DECK_THICKNESS - 1.5, top_y - 5.0]:
			concrete.box(Vector3(c.x, y, c.z), Vector3(leg_offset * 2.0 + 2.8, 2.2, 2.2), forward, o)
		tops.append(Vector3(c.x, top_y, c.z))
	# Tragseile: Hauptfeld mit Durchhang, an den Enden abwärts zur Fahrbahn (Verankerung)
	for side: float in [1.0, -1.0]:
		var previous := Vector3.INF
		for k in range(r.x, r.y + 1):
			var c := segment.points[k]
			var left := _left(segment, k)
			var y: float
			if k < zone.x:
				y = lerpf(c.y + 1.0, tops[0].y, float(k - r.x) / maxf(zone.x - r.x, 1))
			elif k > zone.y:
				y = lerpf(tops[1].y, c.y + 1.0, float(k - zone.y) / maxf(r.y - zone.y, 1))
			else:
				var u := float(k - zone.x) / (zone.y - zone.x)
				var chord := lerpf(tops[0].y, tops[1].y, u)
				var low := c.y + 3.0
				y = chord - (chord - low) * 4.0 * u * (1.0 - u)
			var point := Vector3(c.x, y, c.z) + left * side * leg_offset
			if previous != Vector3.INF:
				steel.beam(previous, point, 0.55, o)
			previous = point
			# Hänger zur Fahrbahnkante
			if k > zone.x and k < zone.y and (k - zone.x) % HANGER_EVERY == 0:
				var deck := Vector3(c.x, c.y + RoadSegment.WALL_HEIGHT, c.z) + left * side * leg_offset
				steel.beam(deck, point, 0.16, o)
