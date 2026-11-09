class_name TunnelMask
extends RefCounted
## Karte der Tunnelröhren für den Horizont-Ring (horizon.gdshader): je Feld (16 m) die höchste
## Röhrendecke darunter (+1 m), sonst sehr tief. Der Ring verwirft dort alles, was tiefer liegt.
## Ohne das stünden in langen Tunneln seine abgesenkte Fläche (unter fertigen Kacheln 124 m)
## oder die Schürze an seinem inneren Rand (400 m um die Kamera, bis -400 m) als Wand in der
## Röhre: ohne Kollision, man fährt hindurch.

const SIZE: int = 512
const CELL: float = 16.0
## So weit neben der Röhre (zusätzlich zur halben Röhrenbreite) gilt der Korridor
const MARGIN: float = 12.0
const NONE: float = -100000.0

var origin := Vector2.ZERO
var tops := PackedFloat32Array()
var texture: ImageTexture


## Alle Röhren der Abschnitte (Paare [Schlüssel, RoadSegment]) um center eintragen
func rasterize(segments: Array, center: Vector2) -> void:
	origin = (center / CELL).floor() * CELL - Vector2.ONE * SIZE * CELL * 0.5
	tops.resize(SIZE * SIZE)
	tops.fill(NONE)
	for pair: Array in segments:
		var segment: RoadSegment = pair[1]
		if segment.tunnel_ranges.is_empty():
			continue
		var reach := segment.tube_half_width() + MARGIN
		var cells := ceili(reach / CELL)
		for r in segment.tunnel_ranges:
			for i in range(r.x, r.y + 1):
				var p := segment.points[i]
				var top := p.y + RoadSegment.TUBE_APEX + 1.0
				var cx := floori((p.x - origin.x) / CELL)
				var cz := floori((p.z - origin.y) / CELL)
				for z in range(cz - cells, cz + cells + 1):
					for x in range(cx - cells, cx + cells + 1):
						if x < 0 or z < 0 or x >= SIZE or z >= SIZE:
							continue
						var middle := origin + Vector2(x + 0.5, z + 0.5) * CELL
						if middle.distance_to(Vector2(p.x, p.z)) > reach + CELL * 0.71:
							continue
						var k := z * SIZE + x
						tops[k] = maxf(tops[k], top)
	var image := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RF, tops.to_byte_array())
	if texture == null:
		texture = ImageTexture.create_from_image(image)
	else:
		texture.update(image)


## Würde der Ring an dieser Stelle in dieser Höhe verworfen? (für tools/tunnel_check.gd)
func hides(x: float, z: float, y: float) -> bool:
	var cx := floori((x - origin.x) / CELL)
	var cz := floori((z - origin.y) / CELL)
	if cx < 0 or cz < 0 or cx >= SIZE or cz >= SIZE:
		return false
	return y < tops[cz * SIZE + cx]
