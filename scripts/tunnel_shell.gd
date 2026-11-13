class_name TunnelShell
extends RefCounted
## Deckel über einer Tunnelröhre: Von außen ist der Tunnel überall fest.
##
## Wo das Gelände über der Röhre zu dünn ist und hinter jedem Portal hat es Löcher
## (RoadQuery.tunnel_hole: bis 1 m neben der Röhrenwand, dazu reichen die Dreiecke eines Lochs
## noch eine Rasterweite weiter). Früher hatte die Röhre nur innen an den Wänden Kollision, man
## konnte von außen durch das Loch neben der Röhre unter die Map oder durchs Gewölbe in den
## Tunnel fallen. Jetzt liegt über der ganzen Röhre eine Betonplatte mit Kollision:
## - Oberkante COVER Meter über dem Scheitel: genau so hoch, dass überall dort, wo das Gelände
##   ein Loch hat, die Platte das Loch von unten abschließt (meist liegt sie unsichtbar im Berg)
## - seitlich REACH Meter über die Röhrenwand hinaus, Seitenwände bis unter die Fahrbahn
## - überall gleich hoch, auch hinter den Portalen (dort liegt das Gelände als Felswand höher, man
##   landet dann ein paar Meter tiefer auf dem Deckel). Höher darf er nicht: Straßen kreuzen 9 m
##   über einer Röhre (RoadSegment._apply_crossings), ein höherer Portalkopf ragte durch sie hindurch.
## Die Flächen kommen in das Tunnel-Mesh (Farbe wie der Portalkragen) und in die Kollision.

## Seitlich so weit über die Röhrenwand hinaus (Loch bis 1 m + eine Rasterweite von 2 m)
const REACH: float = 3.5
## Oberkante über dem Scheitel (Löcher gibt es, wo das Gelände tiefer als Scheitel + 1 m liegt;
## die groben Detailstufen heben ihr Gelände genau dorthin, darunter bleibt die Platte unsichtbar)
const COVER: float = 0.9
## Die Seitenwände reichen so tief unter die Fahrbahn
const DEPTH: float = 4.0
const COLOR := Color(0.5, 0.5, 0.47)


## Deckel über dem Tunnelstück r (Punkte r.x bis r.y) bauen
static func build(seg: RoadSegment, r: Vector2i, lefts: PackedVector3Array) -> void:
	var w := seg.tube_half_width() + REACH
	var top := RoadSegment.TUBE_APEX + COVER
	for i in range(r.x, r.y):
		var l0 := seg.side_point(i, lefts[i], w, top) - seg.origin
		var l1 := seg.side_point(i + 1, lefts[i + 1], w, top) - seg.origin
		var r0 := seg.side_point(i, lefts[i], -w, top) - seg.origin
		var r1 := seg.side_point(i + 1, lefts[i + 1], -w, top) - seg.origin
		var down := Vector3(0.0, -(top + DEPTH), 0.0)
		# Oberseite und die beiden Seitenwände
		_face(seg, l0, l1, r1, r0, Vector3.UP)
		_face(seg, l0 + down, l1 + down, l1, l0, lefts[i])
		_face(seg, r0, r1, r1 + down, r0 + down, -lefts[i])


## Viereck ins Tunnel-Mesh und in die Kollision (Kollision gilt von beiden Seiten)
static func _face(seg: RoadSegment, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	seg._tquad(a, b, c, d, normal, COLOR)
	var o := seg.origin
	seg.collision_faces.append_array([a + o, b + o, c + o, a + o, c + o, d + o])
