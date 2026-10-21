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
var road_pads: PackedVector3Array = PackedVector3Array()
var pad_radius: float = 11.0

# --- Ergebnisse ---
## Fertige Mesh-Daten für ArrayMesh.add_surface_from_arrays()
var arrays: Array = []
## Höhen des Rasters (ohne Rand), Zeile für Zeile. Für Kollision und später Vegetation.
var heights: PackedFloat32Array
## Anzahl Rasterpunkte pro Seite
var grid_size: int = 0


func run() -> void:
	var n: int = roundi(chunk_size / spacing)
	var side: int = n + 3  # Raster mit einem Punkt Rand rundherum (für die Normalen)
	var origin := Vector2(coord.x * chunk_size, coord.y * chunk_size)
	var lakes: Array = world_gen.lakes_near(Rect2(origin, Vector2(chunk_size, chunk_size)))
	var roads := RoadQuery.new(road_segments, road_pads, pad_radius,
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
			var forest := world_gen.forest_density(wx, wz, h, 1.0 - normal.y) * (1.0 - near_road)
			verts[v] = Vector3(gx * spacing, h, gz * spacing)
			normals[v] = normal
			# Farbe: Rot = Wald, Grün = Nähe zur Straße
			colors[v] = Color(forest, near_road, 0.0, 1.0)
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

	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices


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
