class_name PreparedModel
extends Resource
## Ein für das Spiel vorbereitetes Modell (tools/setup_traffic_models.gd): Innenraum und Technik
## entfernt, echte Größe, mittig auf dem Boden, Nase nach +Z, vereinfacht. Das Spiel lädt nur
## diese Datei, nie die riesige GLB.
## Flächen der Meshes heißen nach ihrer Rolle: "body" (Farben als Punktfarben), "paint" (Lack,
## bekommt im Spiel die Farbe des Autos), "glass", "head" (Scheinwerfer), "tail" (Rücklicht),
## "wheels" (nur in der mittleren Stufe, nah drehen sich eigene Rad-Meshes). Bei der Tankstelle
## behalten die Flächen ihre Materialien (mit Texturen).

## Nah (bis ca. 60.000 Dreiecke) und mittlere Stufe (ca. 10.000)
@export var near_mesh: ArrayMesh
@export var mid_mesh: ArrayMesh
## Räder für die nahe Stufe: je Ecke ein Mesh um die Radmitte (vorne links, vorne rechts,
## hinten links, hinten rechts), dreht sich um X
@export var wheel_meshes: Array[ArrayMesh] = []
@export var wheel_centers: PackedVector3Array = PackedVector3Array()
## Maße (Breite, Höhe, Länge) in Metern
@export var size: Vector3 = Vector3.ZERO
## Leuchten für Blinker: äußere Ecken vorne und hinten (links, x > 0)
@export var front_corner: Vector3 = Vector3.ZERO
@export var rear_corner: Vector3 = Vector3.ZERO
## Tankstelle: einfache Kollisionsformen [Mitte, Größe] in Modell-Koordinaten
@export var collision_boxes: Array[AABB] = []
## Kennzeichen des Original-Modells (vorne, hinten): {"center": Vector3, "size": Vector2 (Breite,
## Höhe), "tilt": Grad (positiv = oben nach hinten)} oder leer. Das Original ist aus den Meshes
## entfernt, das Spiel setzt sein eigenes Schild genau dorthin.
@export var plate_spots: Array = []
## Freie Angaben (z. B. lichte Höhe unter dem Dach)
@export var info: Dictionary = {}


## Nummer der Fläche mit diesem Namen (-1 = keine)
static func surface_index(mesh: ArrayMesh, role: String) -> int:
	if mesh == null:
		return -1
	for i in mesh.get_surface_count():
		if mesh.surface_get_name(i) == role:
			return i
	return -1
