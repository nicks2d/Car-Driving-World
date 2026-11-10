class_name Dam
extends MeshBuilder
## Staumauer einer Talsperre (WorldGen.Lake mit reservoir), entlang der Kronenlinie (dam_a–dam_b),
## gebaut vom WaterManager. Führt die Landstraße darüber (RoadSegment.on_dam), liegt ihre
## Fahrbahn genau auf der Krone; sonst ist dort eine Betonplatte.
## - Krone: Gehwege links und rechts der Fahrbahn, Betonbrüstung mit Handlauf, Laternen
## - Wasserseite: fast senkrechte Wand bis tief unter den Wasserspiegel
## - Talseite: nach unten immer flacher (wie eine Gewichtsstaumauer), in der Mitte nach außen
##   gewölbt (geschwungen), bis ins Gelände
## - Überlauf in der Mitte: dunkle Öffnungen unter der Fahrbahn, darunter fällt das Wasser über
##   die Mauer (eigene Fläche mit dem Wasserfall-Shader) ins alte Flussbett

## Breite des Gehwegs neben dem Bankett, Höhe und Dicke der Brüstung
const WALKWAY: float = 1.6
const PARAPET_HEIGHT: float = 1.05
const PARAPET_THICKNESS: float = 0.35
## Talseite: waagerechter Abstand pro Meter Höhe (unten) und Wölbung in der Mitte
const BATTER: float = 0.72
const BULGE: float = 9.0
## Breite des Überlaufs
const SPILL_WIDTH: float = 18.0
## Laternen alle so viele Punkte (je 4 m), abwechselnd links und rechts
const LAMP_EVERY: int = 8
## Fahrbahn + Bankett (halbe Breite, wie die Landstraßen im RoadNetwork) und so weit reicht die
## Mauer an beiden Enden in den Hang
const ROAD_HALF: float = 6.0
const END_REACH: float = 14.0
## Parkbucht am Ende dam_b auf der Seeseite (Viewpoints._dam_spot): Mitte so weit vor dem Ende,
## so lang ist die Mauer dort breiter (mit Übergang), und so viel breiter
const BAY_CENTER: float = 34.0
const BAY_LENGTH: float = 64.0
const BAY_EXTRA: float = 7.5


## Mesh-Daten (relativ zu anchor()): {"concrete", "metal", "lamps", "water", "gates"} als
## Arrays für add_surface_from_arrays, "collision" (Weltkoordinaten), "lights" (Laternen),
## "spill_top" und "spill_bottom" (Weltkoordinaten, Mitte des Überlaufs oben und unten)
static func build(lake: WorldGen.Lake, world_gen: WorldGen) -> Dictionary:
	var length := lake.dam_a.distance_to(lake.dam_b)
	var along2 := (lake.dam_b - lake.dam_a) / length
	var lakes: Array = world_gen.lakes_near(Rect2(lake.dam_a, Vector2.ZERO).expand(lake.dam_b).grow(120.0), false)
	var hw := ROAD_HALF + WALKWAY
	var road_edge := ROAD_HALF
	# Kronenlinie alle 4 m, an beiden Enden ein Stück in den Hang
	var crest_points: Array[Vector3] = []
	var count := ceili((length + END_REACH * 2.0) / 4.0)
	for k in count + 1:
		var q := lake.dam_a - along2 * END_REACH + along2 * (k * (length + END_REACH * 2.0) / count)
		crest_points.append(Vector3(q.x, lake.crest, q.y))
	var first := 0
	var last := crest_points.size() - 1
	var forward3 := Vector3(along2.x, 0.0, along2.y)
	# Der Überlauf liegt über dem Fluss (nicht unbedingt in der Mitte der Mauer)
	var spill_t := clampf((lake.dam_center - lake.dam_a).dot(lake.dam_b - lake.dam_a) / (length * length), 0.1, 0.9)
	var concrete := Dam.new()
	var metal := Dam.new()
	var lamps := Dam.new()
	var water := Dam.new()
	var gates := Dam.new()
	var collision := PackedVector3Array()
	var lights := PackedVector3Array()
	var o := anchor(lake)
	# Spalten: je Punkt die Querschnitte (oben Wasserseite → Krone → Talseite unten)
	var up_rows: Array = []
	var down_rows: Array = []
	var spill_top := Vector3.ZERO
	var spill_bottom := Vector3.ZERO
	var spill_count := 0
	for k in range(first, last + 1):
		var c := crest_points[k]
		var forward := forward3
		var left := Vector3.UP.cross(forward).normalized()
		# Zur Wasserseite zeigt die Seite gegen die Fließrichtung
		var up_side := left if left.dot(Vector3(-lake.flow.x, 0.0, -lake.flow.y)) > 0.0 else -left
		var t := clampf((Vector2(c.x, c.z) - lake.dam_a).dot(lake.dam_b - lake.dam_a) / (length * length), 0.0, 1.0)
		var top := lake.crest - 0.08
		# Für die Parkbucht ist die Mauer am Ende dam_b zur Seeseite breiter
		var up_width := hw + bay_widening(lake, Vector2(c.x, c.z))
		# Wasserseite: fast senkrecht bis tief unter den Wasserspiegel
		var u_top := Vector3(c.x, top, c.z) + up_side * up_width
		var u_foot2 := Vector2(u_top.x, u_top.z) + Vector2(up_side.x, up_side.z) * 2.5
		var u_bottom := minf(world_gen.terrain_height(u_foot2.x, u_foot2.y, lakes), lake.level) - 6.0
		up_rows.append([u_top, Vector3(u_foot2.x, u_bottom, u_foot2.y)])
		# Talseite: Fußpunkt aus der Höhe über dem Gelände, nach unten flacher, Mitte gewölbt
		var down := -up_side
		var probe := Vector3(c.x, 0.0, c.z) + down * (hw + 20.0)
		var height := maxf(top - world_gen.terrain_height(probe.x, probe.z, lakes), 0.0)
		var reach := height * BATTER + BULGE * (1.0 - pow(2.0 * t - 1.0, 2.0))
		var row: Array = []
		for f: float in [0.0, 0.12, 0.35, 0.65, 1.0]:
			var p := Vector3(c.x, top - height * f, c.z) + down * (hw + reach * pow(f, 1.7))
			if f == 1.0:
				p.y = world_gen.terrain_height(p.x, p.z, lakes) - 2.5
			row.append(p)
		down_rows.append(row)
		# Überlauf: Mitte des Wassers merken
		if absf(t - spill_t) * length < SPILL_WIDTH * 0.5:
			spill_top += row[0]
			spill_bottom += row[4]
			spill_count += 1
		# Laternen am Gehweg, abwechselnd links und rechts
		var inside := (Vector2(c.x, c.z) - lake.dam_a).dot(along2) > 0.0 and (Vector2(c.x, c.z) - lake.dam_b).dot(along2) < 0.0
		if (k - first) % LAMP_EVERY == 4 and inside:
			var sgn := 1.0 if floori(float(k - first) / LAMP_EVERY) % 2 == 0 else -1.0
			var foot := Vector3(c.x, lake.crest + 0.15, c.z) + left * sgn * (hw - 0.45)
			lights.append(foot + Vector3.UP * 6.2 - left * sgn * 1.1)
			metal.box(foot + Vector3.UP * 3.1, Vector3(0.16, 6.2, 0.16), forward, o)
			metal.box(foot + Vector3.UP * 6.2 - left * sgn * 0.6, Vector3(0.1, 0.1, 1.2), forward.rotated(Vector3.UP, PI * 0.5), o)
			lamps.box(foot + Vector3.UP * 6.12 - left * sgn * 1.1, Vector3(0.5, 0.12, 0.3), forward, o)
	if spill_count > 0:
		spill_top /= spill_count
		spill_bottom /= spill_count
	# Flächen zwischen den Spalten
	for j in range(up_rows.size() - 1):
		var k := first + j
		var a: Array = up_rows[j]
		var b: Array = up_rows[j + 1]
		concrete.quad(a[0], b[0], b[1], a[1], o, Vector2(j * 4.0, 0.0), Vector2(4.0, 1.0))
		var da: Array = down_rows[j]
		var db: Array = down_rows[j + 1]
		for r in 4:
			concrete.quad(db[r], da[r], da[r + 1], db[r + 1], o, Vector2(j * 4.0, 0.0), Vector2(4.0, 1.0))
		# Krone: Gehwege (etwas erhöht) und Brüstungen auf beiden Seiten
		var c0 := crest_points[k]
		var c1 := crest_points[k + 1]
		var l0 := Vector3.UP.cross(forward3).normalized()
		var l1 := l0
		# Platte unter der Fahrbahn (die Straße liegt darauf, ohne Straße ist sie die Krone)
		var deck := Vector3.DOWN * 0.1
		concrete.quad(c0 + l0 * road_edge + deck, c1 + l1 * road_edge + deck, c1 - l1 * road_edge + deck,
			c0 - l0 * road_edge + deck, o, Vector2.ZERO, Vector2(4.0, 1.0))
		var up_sgn := 1.0 if l0.dot(Vector3(-lake.flow.x, 0.0, -lake.flow.y)) > 0.0 else -1.0
		for sgn: float in [1.0, -1.0]:
			# Seeseite am Ende dam_b: breiter für die Parkbucht, dort ohne Bordstein auf Fahrbahnhöhe
			var widen0 := bay_widening(lake, Vector2(c0.x, c0.z)) if sgn == up_sgn else 0.0
			var widen1 := bay_widening(lake, Vector2(c1.x, c1.z)) if sgn == up_sgn else 0.0
			var y := lake.crest + 0.15 if widen0 + widen1 == 0.0 else lake.crest - 0.1
			var in0 := Vector3(c0.x, y, c0.z) + l0 * sgn * road_edge
			var in1 := Vector3(c1.x, y, c1.z) + l1 * sgn * road_edge
			var out0 := Vector3(c0.x, y, c0.z) + l0 * sgn * (hw + widen0 - PARAPET_THICKNESS)
			var out1 := Vector3(c1.x, y, c1.z) + l1 * sgn * (hw + widen1 - PARAPET_THICKNESS)
			concrete.quad(in0, in1, out1, out0, o, Vector2.ZERO, Vector2(4.0, 1.0))
			# Bordstein zur Fahrbahn
			var drop := Vector3.DOWN * 0.2
			concrete.quad(in0 + drop, in1 + drop, in1, in0, o, Vector2.ZERO, Vector2.ONE)
			# Brüstung: Innenseite, Oberkante, Außenseite (bis zur Mauerfläche)
			var w0 := out0 + Vector3.UP * PARAPET_HEIGHT
			var w1 := out1 + Vector3.UP * PARAPET_HEIGHT
			var e0 := Vector3(c0.x, y, c0.z) + l0 * sgn * (hw + widen0)
			var e1 := Vector3(c1.x, y, c1.z) + l1 * sgn * (hw + widen1)
			var lift := Vector3.UP * PARAPET_HEIGHT
			concrete.quad(out0, out1, w1, w0, o, Vector2.ZERO, Vector2.ONE)
			concrete.quad(w0, w1, e1 + lift, e0 + lift, o, Vector2.ZERO, Vector2.ONE)
			concrete.quad(e0 + lift, e1 + lift, e1 + Vector3.DOWN * 0.3, e0 + Vector3.DOWN * 0.3, o, Vector2.ZERO, Vector2.ONE)
			# Handlauf aus Metall auf der Brüstung
			var r0 := (w0 + e0 + Vector3.UP * PARAPET_HEIGHT) * 0.5 + Vector3.UP * 0.1
			var r1 := (w1 + e1 + Vector3.UP * PARAPET_HEIGHT) * 0.5 + Vector3.UP * 0.1
			metal.quad(r0 - l0 * 0.06, r1 - l1 * 0.06, r1 + l1 * 0.06, r0 + l0 * 0.06, o, Vector2.ZERO, Vector2.ONE)
			# Die Brüstung hält das Auto auf der Krone
			collision.append_array([out0, out1, w1, out0, w1, w0])
	# Überlauf: Wasser über die Talseite, oben dunkle Öffnungen unter der Fahrbahn
	for j in range(down_rows.size() - 1):
		var a: Array = down_rows[j]
		var b: Array = down_rows[j + 1]
		var k := first + j
		var ta := clampf((Vector2(crest_points[k].x, crest_points[k].z) - lake.dam_a).dot(lake.dam_b - lake.dam_a) / (length * length), 0.0, 1.0)
		var tb := clampf((Vector2(crest_points[k + 1].x, crest_points[k + 1].z) - lake.dam_a).dot(lake.dam_b - lake.dam_a) / (length * length), 0.0, 1.0)
		if absf(ta - spill_t) * length > SPILL_WIDTH * 0.5 or absf(tb - spill_t) * length > SPILL_WIDTH * 0.5:
			continue
		var travelled := 0.0
		for r in 4:
			var pa: Vector3 = a[r]
			var pb: Vector3 = b[r]
			var qa: Vector3 = a[r + 1]
			var qb: Vector3 = b[r + 1]
			var normal := (pb - pa).cross(qa - pa).normalized()
			if normal.y < 0.0:
				normal = -normal
			var lift := normal * 0.25
			var top_y := lake.level + 0.6
			if r == 0:
				pa.y = minf(pa.y, top_y)
				pb.y = minf(pb.y, top_y)
			var step := pa.distance_to(qa)
			water.quad(pb + lift, pa + lift, qa + lift, qb + lift, o, Vector2(j * 4.0 / SPILL_WIDTH, travelled), Vector2(4.0 / SPILL_WIDTH, step))
			travelled += step
		var g0: Vector3 = a[0]
		var g1: Vector3 = b[0]
		var gate := Vector3.DOWN * 2.2
		gates.quad(g1 + Vector3.DOWN * 0.3, g0 + Vector3.DOWN * 0.3, g0 + gate, g1 + gate, o, Vector2.ZERO, Vector2.ONE)
	return {"concrete": concrete.arrays(), "metal": metal.arrays(), "lamps": lamps.arrays(), "water": water.arrays(),
		"gates": gates.arrays(), "collision": collision, "lights": lights, "spill_top": spill_top, "spill_bottom": spill_bottom}


## So viel breiter ist die Krone hier zur Seeseite (Parkbucht am Ende dam_b, weich übergehend)
static func bay_widening(lake: WorldGen.Lake, p: Vector2) -> float:
	var along := (lake.dam_b - lake.dam_a).normalized()
	var d := (lake.dam_b - p).dot(along)
	return BAY_EXTRA * smoothstep(-2.0, 6.0, d) * (1.0 - smoothstep(BAY_LENGTH - 8.0, BAY_LENGTH, d))


## Bezugspunkt der Mesh-Koordinaten: Mitte der Krone
static func anchor(lake: WorldGen.Lake) -> Vector3:
	return Vector3(lake.dam_center.x, lake.crest, lake.dam_center.y)
