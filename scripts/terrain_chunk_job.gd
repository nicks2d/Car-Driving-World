class_name TerrainChunkJob
extends RefCounted
## Ein Auftrag für einen Hintergrund-Thread: berechnet die Daten einer Gelände-Kachel
## (Höhen, Normalen, Farben, Dreiecke). Läuft NICHT im Hauptthread und darf deshalb
## keine Nodes anfassen. Der TerrainManager baut aus dem Ergebnis dann das Mesh.

# --- Eingaben (werden vor dem Start gesetzt) ---
var world_gen: WorldGen
var coord: Vector2i
var lod: int
var spacing: float
var chunk_size: float
## Straßen in der Nähe (RoadSegment) und Kreuzungsmittelpunkte
var road_segments: Array = []
var road_pads: PackedVector4Array = PackedVector4Array()
## Bäume, Büsche und Felsen verteilen? (nur für nahe und mittlere Kacheln)
var with_vegetation: bool = false
## Abstand der möglichen Baumplätze und Felsplätze in Metern (kleiner = dichter)
var tree_spacing: float = 7.0
var rock_spacing: float = 22.0

# --- Ergebnisse ---
## Fertige Mesh-Daten für ArrayMesh.add_surface_from_arrays()
var arrays: Array = []
## Höhen des Rasters (ohne Rand), Zeile für Zeile. Für Kollision und später Vegetation.
var heights: PackedFloat32Array
## Anzahl Rasterpunkte pro Seite
var grid_size: int = 0
## Mesh-Daten der Flussoberfläche in dieser Kachel (leer = kein Fluss)
var water_arrays: Array = []
## Pflanzen und Felsen: Art -> MultiMesh-Puffer (je Exemplar 12 Zahlen Transform + 4 Zufallswerte)
var vegetation: Dictionary = {}
## Hindernisse für die Kollision: je 4 Zahlen (x, y, z, Radius) relativ zur Kachel
var colliders: PackedFloat32Array = PackedFloat32Array()


func run() -> void:
	var n: int = roundi(chunk_size / spacing)
	var side: int = n + 3  # Raster mit einem Punkt Rand rundherum (für die Normalen)
	var origin := Vector2(coord.x * chunk_size, coord.y * chunk_size)
	var lakes: Array = world_gen.lakes_near(Rect2(origin, Vector2(chunk_size, chunk_size)))
	var roads := RoadQuery.new(road_segments, road_pads,
		Rect2(origin, Vector2(chunk_size, chunk_size)).grow(spacing * 2.0))
	var has_roads := not roads.is_empty()

	# 1. Alle Höhen berechnen (und an Straßen anpassen)
	var hs := PackedFloat32Array()
	hs.resize(side * side)
	var road_near := PackedFloat32Array()
	road_near.resize(side * side)
	var i := 0
	for gz in range(-1, n + 2):
		var wz := origin.y + gz * spacing
		for gx in range(-1, n + 2):
			var wx := origin.x + gx * spacing
			var h := world_gen.terrain_height(wx, wz, lakes)
			if has_roads:
				var carved := roads.carve(wx, wz, h)
				h = carved.x
				road_near[i] = carved.y
			hs[i] = h
			i += 1

	# 2. Punkte, Normalen und Farben des eigentlichen Rasters
	grid_size = n + 1
	var grid_count := grid_size * grid_size
	var skirt_count := 4 * grid_size
	var verts := PackedVector3Array()
	verts.resize(grid_count + skirt_count)
	var normals := PackedVector3Array()
	normals.resize(grid_count + skirt_count)
	var colors := PackedColorArray()
	colors.resize(grid_count + skirt_count)
	heights = PackedFloat32Array()
	heights.resize(grid_count)

	var v := 0
	for gz in grid_size:
		for gx in grid_size:
			var c := (gz + 1) * side + gx + 1
			var h := hs[c]
			# Normale aus den Nachbarhöhen (links/rechts, vorne/hinten)
			var normal := Vector3(hs[c - 1] - hs[c + 1], 2.0 * spacing, hs[c - side] - hs[c + side]).normalized()
			var wx := origin.x + gx * spacing
			var wz := origin.y + gz * spacing
			var near_road := road_near[c]
			var wet := _wetness(wx, wz, h, lakes)
			var forest := world_gen.forest_density(wx, wz, h, 1.0 - normal.y) * (1.0 - near_road) * (1.0 - wet)
			verts[v] = Vector3(gx * spacing, h, gz * spacing)
			normals[v] = normal
			# Farbe: Rot = Wald, Grün = Nähe zur Straße, Blau = nass (Ufer, Grund von Flüssen und Seen)
			colors[v] = Color(forest, near_road, wet, 1.0)
			heights[v] = h
			v += 1

	# 3. Dreiecke: zwei pro Rasterquadrat
	var indices := PackedInt32Array()
	indices.resize(n * n * 6 + 4 * n * 6)
	var k := 0
	for gz in n:
		for gx in n:
			var a := gz * grid_size + gx
			indices[k] = a
			indices[k + 1] = a + 1
			indices[k + 2] = a + grid_size
			indices[k + 3] = a + 1
			indices[k + 4] = a + grid_size + 1
			indices[k + 5] = a + grid_size
			k += 6

	# 4. „Schürzen“: ein schmaler Streifen am Rand, der nach unten hängt.
	# Er verdeckt kleine Lücken zu Nachbar-Kacheln mit anderer Detailstufe.
	var skirt_depth := spacing * 2.0 + 3.0
	var outward := [Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(1, 0, 0)]
	for edge in 4:
		var first := v
		for e in grid_size:
			var src := _edge_vertex(edge, e)
			verts[v] = verts[src] - Vector3(0.0, skirt_depth, 0.0)
			normals[v] = normals[src]
			colors[v] = colors[src]
			v += 1
		# Reihenfolge der Ecken so wählen, dass die Vorderseite nach außen zeigt
		var flip := _faces_inward(verts[_edge_vertex(edge, 0)], verts[_edge_vertex(edge, 1)], verts[first], outward[edge])
		for e in n:
			var top_a := _edge_vertex(edge, e)
			var top_b := _edge_vertex(edge, e + 1)
			var bottom_a := first + e
			var bottom_b := first + e + 1
			if flip:
				indices[k] = top_a
				indices[k + 1] = bottom_a
				indices[k + 2] = top_b
				indices[k + 3] = top_b
				indices[k + 4] = bottom_a
				indices[k + 5] = bottom_b
			else:
				indices[k] = top_a
				indices[k + 1] = top_b
				indices[k + 2] = bottom_a
				indices[k + 3] = top_b
				indices[k + 4] = bottom_b
				indices[k + 5] = bottom_a
			k += 6

	_build_river_water(origin)
	if with_vegetation:
		_place_vegetation(origin, hs, side, lakes, roads)

	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices


## Höhe an beliebiger Stelle der Kachel (zwischen den Rasterpunkten gemittelt)
## Genau wie im Mesh: Jedes Rasterquadrat besteht aus zwei Dreiecken (Diagonale von
## rechts oben nach links unten), innerhalb eines Dreiecks ist die Fläche eben.
## So stehen Bäume und Felsen exakt auf dem sichtbaren Boden, in jeder Detailstufe.
func _height_at(hs: PackedFloat32Array, side: int, lx: float, lz: float) -> float:
	var fx := lx / spacing + 1.0
	var fz := lz / spacing + 1.0
	var ix := clampi(floori(fx), 0, side - 2)
	var iz := clampi(floori(fz), 0, side - 2)
	var tx := fx - ix
	var tz := fz - iz
	var h00 := hs[iz * side + ix]
	var h10 := hs[iz * side + ix + 1]
	var h01 := hs[(iz + 1) * side + ix]
	var h11 := hs[(iz + 1) * side + ix + 1]
	if tx + tz <= 1.0:
		return h00 + (h10 - h00) * tx + (h01 - h00) * tz
	return h11 + (h01 - h11) * (1.0 - tx) + (h10 - h11) * (1.0 - tz)


## Wie stark steigt der Boden an (Meter pro Meter, 0 = flach)?
func _gradient_at(hs: PackedFloat32Array, side: int, lx: float, lz: float) -> float:
	var gx := (_height_at(hs, side, lx + spacing, lz) - _height_at(hs, side, lx - spacing, lz)) / (2.0 * spacing)
	var gz := (_height_at(hs, side, lx, lz + spacing) - _height_at(hs, side, lx, lz - spacing)) / (2.0 * spacing)
	return sqrt(gx * gx + gz * gz)


## Darf hier nichts wachsen? Nicht auf oder neben Straßen, Brücken und Kreuzungen
## (margin = Abstand ab dem Bankett, z. B. Kronenradius) und nicht auf Böschungen,
## also dort, wo das Gelände für die Straße verändert wurde.
func _blocked_by_road(x: float, z: float, margin: float, roads: RoadQuery, lakes: Array) -> bool:
	if roads.is_empty():
		return false
	# Die Böschungskante reicht 1,3 m über den flachen Teil hinaus
	if roads.is_on_road(x, z, margin + 1.3):
		return true
	# Weiter weg als die breiteste Böschung: Gelände ist sicher unverändert
	if not roads.is_on_road(x, z, RoadSegment.MAX_BANK):
		return false
	var natural := world_gen.terrain_height(x, z, lakes)
	return absf(roads.carve(x, z, natural).x - natural) > 0.4


## Bäume, Büsche und Felsen auf einem leicht zufällig verschobenen Raster verteilen.
## Pro Platz werden immer gleich viele Zufallszahlen gezogen: So stehen die Bäume bei
## gleichem Seed immer an derselben Stelle, egal in welcher Detailstufe die Kachel ist.
func _place_vegetation(origin: Vector2, hs: PackedFloat32Array, side: int, lakes: Array, roads: RoadQuery) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_gen.hash_cell(coord.x, coord.y, 404)
	var conifers := PackedFloat32Array()
	var broadleafs := PackedFloat32Array()
	var bushes := PackedFloat32Array()
	# Hinweis: Packed-Arrays sind Werte. In einem Array verändert append() nur eine Kopie,
	# deshalb drei einzelne Variablen für die drei Felsformen.
	var rocks_a := PackedFloat32Array()
	var rocks_b := PackedFloat32Array()
	var rocks_c := PackedFloat32Array()
	var tree_line := world_gen.tree_line
	var cells := floori(chunk_size / tree_spacing)
	for cz in cells:
		for cx in cells:
			var lx := (cx + rng.randf()) * tree_spacing
			var lz := (cz + rng.randf()) * tree_spacing
			var accept := rng.randf()
			var kind := rng.randf()
			var size := rng.randf()
			var angle := rng.randf() * TAU
			var shade := Color(rng.randf(), rng.randf(), rng.randf(), 0.0)
			if accept > 0.9:
				continue
			var x := origin.x + lx
			var z := origin.y + lz
			var h := _height_at(hs, side, lx, lz)
			var gradient := _gradient_at(hs, side, lx, lz)
			var slope := 1.0 - 1.0 / sqrt(1.0 + gradient * gradient)
			var low := 1.0 - smoothstep(tree_line - 100.0, tree_line, h)
			var gentle := 1.0 - smoothstep(0.25, 0.4, slope)
			var tree_chance := world_gen.forest_density(x, z, h, slope) * 0.8 + 0.02 * low * gentle
			var bush_chance := 0.035 * gentle * (1.0 - smoothstep(tree_line, tree_line + 120.0, h))
			if accept >= tree_chance + bush_chance:
				continue
			if _is_wet(x, z, h, lakes):
				continue
			if accept < tree_chance:
				# Weiter oben mehr Nadelbäume, im Tal mehr Laubbäume
				var conifer_share := clampf(0.4 + (h - 250.0) / 500.0 + world_gen.variation(x, z) * 0.3, 0.1, 0.95)
				var conifer := kind < conifer_share
				var height := lerpf(13.0, 27.0, size) if conifer else lerpf(9.0, 17.0, size)
				# Kronenradius und Stammradius aus den Modellen (vegetation_meshes.gd)
				var crown := height * (0.23 if conifer else 0.34)
				var trunk := height * (0.022 if conifer else 0.035)
				if _blocked_by_road(x, z, crown, roads, lakes):
					continue
				# Am Hang den Stamm so weit einsinken lassen, dass er talseitig nicht schwebt
				var base := h - 0.3 - gradient * trunk
				if conifer:
					conifers.append_array(_instance(lx, base, lz, angle, height * 0.95, height, height * 0.95, shade))
				else:
					broadleafs.append_array(_instance(lx, base, lz, angle, height, height, height, shade))
				colliders.append_array([lx, h, lz, 0.4])
			else:
				var scale := lerpf(1.0, 2.6, size)
				if _blocked_by_road(x, z, scale * 0.9, roads, lakes):
					continue
				bushes.append_array(_instance(lx, h - 0.2 - gradient * scale * 0.6, lz, angle, scale, scale * 0.8, scale, shade))
	# Felsen: seltener, häufiger an steilen Hängen und über der Baumgrenze
	var rock_cells := floori(chunk_size / rock_spacing)
	for cz in rock_cells:
		for cx in rock_cells:
			var lx := (cx + rng.randf()) * rock_spacing
			var lz := (cz + rng.randf()) * rock_spacing
			var accept := rng.randf()
			var kind := rng.randi_range(0, 2)
			var size := rng.randf()
			var angle := rng.randf() * TAU
			var stretch := rng.randf()
			var x := origin.x + lx
			var z := origin.y + lz
			var h := _height_at(hs, side, lx, lz)
			var gradient := _gradient_at(hs, side, lx, lz)
			var slope := 1.0 - 1.0 / sqrt(1.0 + gradient * gradient)
			var chance := 0.04 + smoothstep(0.12, 0.35, slope) * 0.45 + smoothstep(tree_line, tree_line + 300.0, h) * 0.3
			if accept >= chance:
				continue
			if _is_wet(x, z, h, lakes):
				continue
			var scale := lerpf(0.6, 3.8, size * size) * (1.0 + slope)
			if _blocked_by_road(x, z, scale * lerpf(0.8, 1.3, stretch) * 0.6, roads, lakes):
				continue
			var shade := Color(stretch, 0.0, 0.0, 0.0)
			var row := _instance(lx, h - scale * 0.2 - gradient * scale * 0.4, lz, angle,
				scale * lerpf(0.8, 1.3, stretch), scale * lerpf(0.6, 1.0, size), scale, shade)
			if kind == 0:
				rocks_a.append_array(row)
			elif kind == 1:
				rocks_b.append_array(row)
			else:
				rocks_c.append_array(row)
			if scale > 1.3:
				colliders.append_array([lx, h, lz, scale * 0.45])
	vegetation = {"conifer": conifers, "broadleaf": broadleafs, "bush": bushes,
		"rock0": rocks_a, "rock1": rocks_b, "rock2": rocks_c}


## Eine Zeile für den MultiMesh-Puffer: Drehung um die Hochachse, Größe, Position, Zufallswerte
func _instance(x: float, y: float, z: float, angle: float, sx: float, sy: float, sz: float, custom: Color) -> PackedFloat32Array:
	var c := cos(angle)
	var s := sin(angle)
	return PackedFloat32Array([c * sx, 0.0, s * sz, x, 0.0, sy, 0.0, y, -s * sx, 0.0, c * sz, z,
		custom.r, custom.g, custom.b, custom.a])


## Liegt die Stelle im oder direkt am Wasser?
func _is_wet(x: float, z: float, h: float, lakes: Array) -> bool:
	var level := world_gen.river_surface_near(x, z, 10.0)
	for lake: WorldGen.Lake in lakes:
		if Vector2(x, z).distance_to(lake.center) < lake.radius + 15.0:
			level = maxf(level, lake.level)
	return level > WorldGen.NO_WATER and h < level + 1.0


## Wie nass ist der Boden hier? 1 = unter Wasser, zum Ufer hin weniger
func _wetness(x: float, z: float, h: float, lakes: Array) -> float:
	var level := world_gen.river_surface_near(x, z, 14.0)
	for lake: WorldGen.Lake in lakes:
		if Vector2(x, z).distance_to(lake.center) < lake.radius + 60.0:
			level = maxf(level, lake.level)
	if level <= WorldGen.NO_WATER:
		return 0.0
	return 1.0 - smoothstep(0.0, 2.5, h - level)


## Flussoberfläche: ein Raster, in dem nur die Quadrate am Fluss verwendet werden.
## Sie reicht etwas unter das Ufer, damit man ihren Rand nicht sieht.
## In UV steht die Fließrichtung (für den Wasser-Shader).
func _build_river_water(origin: Vector2) -> void:
	var step := clampf(spacing * 2.0, 4.0, 8.0)
	var count := roundi(chunk_size / step) + 1
	var levels := PackedFloat32Array()
	levels.resize(count * count)
	var any_water := false
	for gz in count:
		for gx in count:
			var level := world_gen.river_surface_near(origin.x + gx * step, origin.y + gz * step, 7.0)
			levels[gz * count + gx] = level
			if level > WorldGen.NO_WATER:
				any_water = true
	if not any_water:
		return
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	for gz in count:
		for gx in count:
			var level := levels[gz * count + gx]
			var x := origin.x + gx * step
			var z := origin.y + gz * step
			verts.append(Vector3(gx * step, level, gz * step))
			normals.append(Vector3.UP)
			uvs.append(world_gen.river_flow(x, z) if level > WorldGen.NO_WATER else Vector2.ZERO)
	var indices := PackedInt32Array()
	for gz in count - 1:
		for gx in count - 1:
			var a := gz * count + gx
			if levels[a] > WorldGen.NO_WATER and levels[a + 1] > WorldGen.NO_WATER \
					and levels[a + count] > WorldGen.NO_WATER and levels[a + count + 1] > WorldGen.NO_WATER:
				indices.append_array([a, a + 1, a + count, a + 1, a + count + 1, a + count])
	if indices.is_empty():
		return
	water_arrays.resize(Mesh.ARRAY_MAX)
	water_arrays[Mesh.ARRAY_VERTEX] = verts
	water_arrays[Mesh.ARRAY_NORMAL] = normals
	water_arrays[Mesh.ARRAY_TEX_UV] = uvs
	water_arrays[Mesh.ARRAY_INDEX] = indices


## Index des e-ten Rasterpunkts an einer Kante (0 = vorne, 1 = hinten, 2 = links, 3 = rechts)
func _edge_vertex(edge: int, e: int) -> int:
	match edge:
		0:
			return e
		1:
			return (grid_size - 1) * grid_size + e
		2:
			return e * grid_size
		_:
			return e * grid_size + grid_size - 1


## Zeigt das Dreieck (a, b, c) mit seiner Vorderseite nach innen statt nach außen?
## Godot zeigt Dreiecke von der Seite, von der aus die Ecken im Uhrzeigersinn liegen.
func _faces_inward(a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> bool:
	var front_normal := (c - a).cross(b - a)
	return front_normal.dot(outward) < 0.0
