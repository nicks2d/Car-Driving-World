class_name CarProfile
extends Resource
## Alles, was ein Auto ausmacht: Modell, Maße, Fahrwerte, Getriebe, Sound und Daten fürs
## Datenblatt in der Garage. Ein Profil pro Auto liegt in cars/ (z. B. cars/m2.tres) und
## lässt sich im Godot-Editor im Inspector bearbeiten.
##
## Teile des Modells werden über Muster erkannt (Groß/Klein egal, * = beliebig viele
## Zeichen). Geprüft werden der Name des Mesh-Knotens, die Namen seiner Eltern-Knoten und
## die Namen seiner Materialien.

@export_group("Allgemein")
## Kurzer Schlüssel (wird gespeichert, z. B. "m2")
@export var id: String = ""
@export var display_name: String = ""
## Zweite Zeile in der Garage, z. B. „F87 · 2018“
@export var subtitle: String = ""
## Ordner unter assets/models/ mit scene.gltf
@export var model_folder: String = ""
## Credit-Text aus der license.txt (Pflicht bei CC BY)
@export_multiline var credit: String = ""

@export_group("Datenblatt")
## Werte für die Anzeige in der Garage (gemessen bzw. laut Hersteller)
@export var power_ps: int = 0
@export var drive_text: String = "Heckantrieb"
@export var gearbox_text: String = ""
@export var engine_text: String = ""
@export var measured_0_100: float = 0.0

@export_group("Modell")
## Drehung um die Hochachse, damit die Nase nach +Z zeigt (Grad)
@export var model_rotation_deg: float = 0.0
## Räder, die sich mitdrehen (Reifen, Felgen, Bremsscheiben)
@export var wheel_parts: PackedStringArray = []
## Teile, die lenken und federn, sich aber nicht drehen (Bremssättel)
@export var caliper_parts: PackedStringArray = []
## Teile, die man nicht sieht oder die stören (Motor, Hilfsobjekte)
@export var hidden_parts: PackedStringArray = []
## Aufkleber (Taste K)
@export var sticker_parts: PackedStringArray = []
## Materialien, die durch eigene ersetzt werden
@export var paint_materials: PackedStringArray = []
@export var glass_materials: PackedStringArray = []
@export var tire_materials: PackedStringArray = []
@export var rim_materials: PackedStringArray = []
@export var exhaust_materials: PackedStringArray = []
@export var headlight_materials: PackedStringArray = []
@export var taillight_materials: PackedStringArray = []
## Nur diese Teile werfen Schatten (große Karosserieteile, Reifen)
@export var shadow_parts: PackedStringArray = []
## Diese Teile wechseln früher auf vereinfachte Versionen (Innenraum, Felgen)
@export var low_detail_parts: PackedStringArray = []
## Unbewegliche Teile pro Material zu einem Mesh zusammenfassen (weniger Draw Calls).
## Für Modelle mit sehr vielen Einzelteilen.
@export var merge_static_parts: bool = false
## Die Vorderräder sind im Modell eingeschlagen: beim Laden gerade stellen
@export var straighten_front_wheels: bool = false
## Wie undurchsichtig die Scheiben sind (0 = klar, 1 = schwarz)
@export_range(0.0, 1.0) var glass_opacity: float = 0.55

@export_group("Lack")
## Farben für die Lackauswahl (die erste ist die Standardfarbe)
@export var paint_colors: Array[Color] = []
@export_range(0.0, 1.0) var paint_metallic: float = 0.6
@export_range(0.0, 1.0) var paint_roughness: float = 0.38

@export_group("Maße und Fahrwerk")
@export var mass: float = 1500.0
## Abstand der Achsen, Spurweiten und Radradius (Meter)
@export var wheelbase: float = 2.7
@export var track_front: float = 1.6
@export var track_rear: float = 1.6
@export var wheel_radius: float = 0.33
@export var suspension_stiffness: float = 40.0
@export var suspension_rest_length: float = 0.2
@export var suspension_travel: float = 0.2
@export var suspension_max_force: float = 15000.0
@export var damping_compression: float = 2.0
@export var damping_relaxation: float = 3.0
@export var roll_influence: float = 0.5
## Reifen-Grip vorne und hinten (Godots friction_slip)
@export var grip_front: float = 1.3
@export var grip_rear: float = 1.3
## Kollision: untere Box (Karosserie) und obere Box (Kabine), Größe und Mitte
@export var body_size: Vector3 = Vector3(1.86, 0.69, 4.3)
@export var body_center: Vector3 = Vector3(0.0, 0.04, -0.05)
@export var cabin_size: Vector3 = Vector3(1.37, 0.42, 2.15)
@export var cabin_center: Vector3 = Vector3(0.0, 0.6, -0.45)

@export_group("Motor")
@export var max_torque_nm: float = 550.0
@export var max_power_kw: float = 302.0
@export var idle_rpm: float = 900.0
## Ab dieser Drehzahl liegt das volle Drehmoment an
@export var torque_plateau_start_rpm: float = 2350.0
## Bis hier hält der Motor seine volle Leistung, danach fällt sie bis zum Begrenzer ab
@export var power_end_rpm: float = 7000.0
@export var redline_rpm: float = 7600.0
## Drehmoment unten herum als Anteil des Höchstwerts (Turbo/Sauger: wenig, Hybrid: viel)
@export_range(0.0, 1.0) var low_end_torque: float = 0.6
@export_range(0.5, 1.0) var drivetrain_efficiency: float = 0.88
## Traktionsgrenze: höchste Antriebskraft am Boden (Newton)
@export var max_drive_force: float = 11000.0
## Anteil der Antriebskraft an der Vorderachse (0 = Heckantrieb, 0.4 = Allrad 40:60)
@export_range(0.0, 1.0) var front_drive_share: float = 0.0
## Abregelung (Höchstgeschwindigkeit)
@export var top_speed_kmh: float = 250.0
## Luftwiderstand und Anpressdruck
@export var air_drag: float = 0.4
@export var downforce: float = 0.5

@export_group("Getriebe")
@export var gear_ratios: Array[float] = [4.806, 2.593, 1.701, 1.277, 1.0, 0.844, 0.671]
@export var final_drive: float = 3.462
@export var shift_up_rpm: float = 7200.0
@export var shift_down_rpm: float = 3200.0
@export var shift_time: float = 0.12
## So weit dreht der Motor beim Anfahren über den Leerlauf (schleifende Kupplung)
@export var launch_rpm: float = 3300.0

@export_group("Bremsen und Fahrverhalten")
@export var brake_strength: float = 76.0
@export var handbrake_strength: float = 30.0
@export var power_oversteer: float = 0.12
@export var drift_angle_limit: float = 15.0
@export var max_steer_angle: float = 35.0
@export var high_speed_steer_angle: float = 4.0

@export_group("Sound")
## Zylinderzahl und Bauart: bestimmt, wie viele Zündungen pro Umdrehung zu hören sind
@export var cylinders: int = 6
## Ungleichmäßigkeit zwischen den Zylindern (V8 mit Kreuzwelle: viel, Reihenmotor: wenig)
@export_range(0.0, 1.0) var firing_unevenness: float = 0.1
## Wie hart die Druckstöße klingen (größer = heller, rauer)
@export var sound_sharpness: float = 18.0
## Tiefe/Bass: Anteil des Grundtons pro Arbeitsspiel (V8 blubbert)
@export_range(0.0, 1.0) var sound_rumble: float = 0.1
@export_range(0.0, 1.0) var turbo_volume: float = 0.04
@export_range(0.0, 1.0) var intake_volume: float = 0.18
