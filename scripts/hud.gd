extends Label
## Tacho: zeigt das Tempo des Autos in km/h an.

## Das Auto, dessen Tempo angezeigt wird
@export var car: VehicleBody3D


func _process(_delta: float) -> void:
	if not car:
		return
	# linear_velocity ist in Metern pro Sekunde, mal 3,6 ergibt km/h
	var speed_kmh: float = car.linear_velocity.length() * 3.6
	text = "%d km/h" % roundi(speed_kmh)
