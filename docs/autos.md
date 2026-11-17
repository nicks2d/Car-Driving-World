# Autos: Fahrphysik, Modelle, Licht, Sound, Prüfstand

## Grundlagen der Fahrphysik

- Auto: Heckantrieb (Nicks Wahl), Godots eingebautes `VehicleBody3D`.
- `VehicleBody3D`: Die Nase zeigt nach +Z, `steering` positiv = links.
  `brake` ist ein Impuls pro Physik-Tick (60 Hz), keine Kraft in Newton.
- Godots Standard-Dämpfung (`linear_damp` 0.1) bremst wie Sirup (max. ~100 km/h).
  Beim Auto daher `linear_damp_mode = Replace` mit 0, Luftwiderstand macht `car.gd` selbst.
- Physik-Interpolation ist an. Was dem Auto folgt (Kamera), bewegt sich in
  `_physics_process`, dann bleibt es auch auf 120-Hz-Bildschirmen flüssig.
- Fahrwerte laut Testfahrt (Stand M1, Platzhalter): 0–100 km/h in 5,8 s, Spitze ca. 220 km/h,
  100–0 km/h in 42 m, ca. 1,2 g in Kurven, kippt nicht um.

## BMW M2 und Fahrwerte

- Auto ab M7 = BMW M2 Competition (F87), `car.gd` heißt `Car`: 1575 kg, 50:50 (Schwerpunkt
  in der Mitte zwischen den Achsen), Radstand 2,69 m, Spur 1,59/1,64 m, Radradius 0,33 m.
  S55-Drehmomentkurve (550 Nm ab 2350, 302 kW bis 7000, Begrenzer 7600), 7-Gang-DKG mit
  echten Übersetzungen (Achse 3,462), Schaltpunkte je nach Gas, Kickdown, 0,12 s Schaltpause.
  Traktionsgrenze `max_drive_force` 11 kN (sonst viel zu schnell: Godots Reifenmodell zählt
  Antriebskraft nur halb gegen den Seitenhalt). Deshalb nachgebildet: Vollgas in schnellen
  Kurven kostet hinten bis 12 % Grip (`power_oversteer`, quadratisch mit dem Gas), eine
  Fahrhilfe nimmt ab 15° Driftwinkel Leistung weg (`drift_angle_limit`).
- Fahrwerte M7 (Test auf flacher Ebene, Skript im Scratchpad): 0–100 in 4,18 s, 0–200 in
  12,4 s, Spitze 250 km/h (abgeregelt), 100–0 in 33,2 m (`brake_strength` 76).
  Kurve + Vollgas: Heck kommt progressiv bis ~15°, fängt sich nach Gas weg.

## Profile und gemessene Fahrwerte

- Autos: acht Profile in `cars/*.tres` (`CarProfile`): M2 (F87), M3 (E30), M3 GTS (E92),
  M5 Competition (F90), M5 (G90), M4 CSL (G82), SL 65 Black Series, C 63 Black Series. Alles Auto-Spezifische steht dort (Modell, Teile-Muster,
  Maße, Motor, Getriebe, Allrad-Anteil `front_drive_share`, Bremsen, Sound). `Car.apply_profile()`
  stellt um, auch während des Spiels. Godot übernimmt den Befestigungspunkt eines Rads nur
  beim Einhängen (ENTER_TREE) und die Physik überschreibt die Lage der Rad-Knoten (beim
  eingefrorenen Auto sogar mit Unsinn): deshalb Räder kurz aus- und einhängen und Radmitten
  immer aus dem Profil rechnen (`Car.resting_wheel_center`).
- Gemessen (flache Ebene): M2 4,18 s / 250 / 33,2 m; E30 6,75 s / 234 / 37,5 m;
  E92 4,37 s / 304 / 34,0 m; F90 3,27 s / 250 / 33,1 m; G90 3,52 s / 250 / 33,4 m
  (0–100, Spitze km/h, Bremsweg 100–0). Stellschraube für 0–100: `max_drive_force`.
  Kurve + Vollgas: E30 ~20°, E92 ~20° Driftwinkel, beide M5 bleiben bei ~3° (Allrad).
- Drei neue Garage-Autos (Teil 2): `cars/m4csl.tres` (BMW M4 CSL G82, S58 405 kW/650 Nm,
  8-Gang, 1625 kg), `cars/sl65.tres` (SL 65 AMG Black Series R230, V12 493 kW/1000 Nm, 5-Gang,
  1870 kg), `cars/c63.tres` (C 63 AMG Coupé Black Series C204, Sauger-V8 380 kW/620 Nm bei
  5200, Begrenzer 7200, 7-Gang MCT, 1710 kg), alle Heckantrieb. Blinker-Punkte, Endrohre, Spur
  und Radradius am Modell gemessen. Gemessen (`tools/drive_test.gd`, flache Ebene, 0–100 /
  0–200 / Spitze / 100–0): M4 CSL 3,70 s / 10,4 s / 306 / 32,8 m (Werk 3,7 / 10,7 / 307),
  SL 65 3,80 s / 10,2 s / 319 / 32,9 m (Werk 3,8 / 320), C 63 4,20 s / 11,6 s / 299 / 33,0 m
  (Werk 4,2 / 300); M2 zum Vergleich 4,22 s / 12,5 s / 250 / 33,4 m. Grip-Test (Sport): alle
  1,67–1,68 g bei 80, 1,84–1,89 g bei 130, Power-Drift M4 24°, SL 65 22°, C 63 30° (M2 20°),
  Handbremse 33–38° (fangen sich).
- `CarProfile.brand` (Reiter in der Garage) und `year` (Reihenfolge). Garage: Reiter oben rechts
  (Glas, ↑ ↓ oder Klick), Karten unten rechts nur von der gewählten Marke, nach Baujahr,
  ← → wechselt darin; beim Markenwechsel kommt das dort zuletzt gewählte Auto. Karten so
  schmal wie ihr Text (Unterzeile „Baujahr · PS“), lange Namen im Panel kleiner.
- `CarProfile.min_roughness`: Originalmaterialien mit weniger Rauheit bekommen eine Kopie mit
  diesem Wert (M4 CSL 0,3: das Modell hat viele perfekt spiegelnde Materialien, das gab
  Glitzerpunkte an allen Kanten). Die Material-Zwischenspeicher (Glas, Felge …) werden jetzt pro
  Auto neu angelegt (vorher behielt Glas die Deckkraft des ersten Autos).
- Testen: `--car=m4csl|sl65|c63`, `--garage` macht das Foto mit offener Garage (mit `--car`
  ist dessen Marke gewählt), Fahrwerte `Godot --path . -s res://tools/drive_test.gd --
  --cars=m4csl,sl65,c63`.

## Grip und Fahrhilfen

- Grip (Teil 2, `car.gd`): Grip-Stufen `GRIP_LEVELS` komfort / sport (Standard) / drift =
  Faktor auf den Reifen-Grip (1,3 / 1,18 / 1,0), Anteil Power-Oversteer (0,3 / 0,6 / 1,2),
  Stabilitätshilfe (1 / 0,6 / 0) und Lenkgeschwindigkeit bei 150 km/h (1,5 / 1,9 / 2,8 statt 4
  im Stand; zurück zur Mitte 1,6-mal schneller). Power-Oversteer jetzt kubisch und erst ab
  3 m/s² quer. Stabilitätshilfe: bremst nur eine Drehrate, die über der aus Lenkwinkel und
  Tempo erwarteten liegt (Übersteuern), ab 2,5° Schwimmwinkel. Sie schweigt 1,5 s nach der
  Handbremse und beim provozierten Drift (Heckantrieb, 1./2. Gang, Gas ≥ 0,8; dann
  Power-Oversteer × 1,8). Wetter-Grip wirkt weiter als Faktor (nass 0,7, Schnee 0,5).
- Messwerkzeug `tools/grip_test.gd` (flache Ebene, `--cars=`, `--grip=`, `--wet`, `--snow`).
  Vorher → nachher (Sport): Kurve 80 km/h 1,44–1,47 g → 1,65–1,69 g; Kurve 130 km/h 1,54–1,62 g →
  1,84–1,92 g; Ausweichen 120 km/h (Tastatur voll links/rechts) 9–12° → 5–6° Schwimmwinkel;
  Vollgas in der Kurve bei 100 km/h: E30 34° → 5°, sonst 3–5°; provozierter Power-Drift
  (2. Gang, 40 km/h): M2 8° → 20°, E92 12° → 26°, E30 13° → 32°, beide M5 3–4° (Allrad);
  Handbremse 70 km/h: Hecktriebler drehten sich (76–89°), jetzt 44–60° und fangen sich.
  Komfort: 1,73–1,78 g, Drift kaum. Drift-Stufe = altes Verhalten. Nass (Sport) 1,20 g,
  Power-Drift Heckantrieb 28–41°; Schnee 0,84–0,93 g.

## Modelle laden

- Modell-Lader (`car_model.gd`, `CarModel`): lädt im Hintergrund, teilt Rad-Meshes, die alle
  vier Räder enthalten, nach Ecken (E92, F90; Vertex-Listen werden dabei verkleinert, sonst
  hat jedes Teil die Bounding-Box des Ganzen), stellt eingeschlagene Vorderräder gerade (E30:
  Achse = Richtung kleinster Streuung der Punkte), fasst Teile pro Material zusammen (G90:
  1213 → 33 Draw Calls), trennt Licht-Meshes in vorne/hinten. `measured` enthält die am
  Modell gemessenen Maße (Radstand, Spur, Radradius) zum Abgleich mit dem Profil.
- Modell-Texturen: `tools/setup_models.gd` stellt alle auf max. 2048 px, Mipmaps und
  VRAM-Kompression (vorher waren sogar die M2-Texturen unkomprimiert ohne Mipmaps, die
  E30-Texturen 8K). Muss nach jedem neuen Modell-Download einmal laufen (README).
- BMW-Modelle (`car_model.gd`): liegen NICHT im Repo (Lizenzen), Anleitung in
  `assets/models/README.md`; ohne Modell fährt die Platzhalter-Box mit gleicher Physik.
  Das Modell wird auf die Physik-Räder skaliert (Radstand). Radgruppen `wms13p*` hängen an
  den VehicleWheel3D (drehen/lenken/federn), Bremssättel `polySurface*` an eigenen Haltern,
  die nur lenken. Die Karosserie heißt im Modell „painted_carbon“ (Carbon-Widebody) und
  bekommt den Lack. Motor ausgeblendet, nur Karosserie/Carbon/Reifen werfen Schatten,
  Innenraum/Felgen/Auspuff mit niedrigerem `lod_bias`. Kostet ca. 3 FPS (74 → 71).
- Neue Modelle (Nov. 2026, alle GLB): Garage M4 CSL, SL 65, C 63; Verkehr (assets/models/verkehr/)
  Audi S3, Accord, Aztek, ID. Buzz, LC 500; Tankstelle (assets/models/raststaette/). Lizenzen in
  `assets/CREDITS.md`, Download in `assets/models/README.md`. `CarModel.model_path` nimmt
  `scene.gltf` oder die `.glb` im Ordner. `tools/setup_models.gd` findet jetzt auch die Bilder,
  die Godot neben eine GLB auspackt, Verkehr max. 1024 px (Tankstellen-Normal-Map 50 → 2,8 MB).
- Kia Stinger weggelassen: Rennversion mit Überrollkäfig ohne Seitenscheiben, nach dem
  Vereinfachen fehlen Teile der hinteren Tür. Seine „edge_color“-Materialien sind Linien
  (SketchUp-Kanten, 280.000 Elemente), keine Flächen.
- Bug behoben: `_merge_attached` (zusammenfassen der Radteile, `merge_static_parts`) hat die
  Platzhalter-Räder (Walze + weißer Balken aus car.tscn) mit eingesammelt, dann waren sie
  sichtbar. Fiel beim M4 CSL auf (Räder wie graue Scheiben), steckte aber auch in M5 F90/G90.
- Blinker-Kästchen sind nur noch zu sehen, solange sie leuchten (aus sieht man das Modell).

## Licht, Spuren, Rauch

- Licht: zwei SpotLight3D (nur eins mit Schatten), an bei Sonne unter 4° oder per L.
  Rücklicht-Emission wird beim Bremsen heller (`Car.braking`).
- Scheinwerfer mit Projektor-Bild (16.11., `CarModel._beam_texture`, 128 × 128, im Code gezeichnet):
  Abblendlicht hell unter einer scharfen Hell-Dunkel-Grenze knapp über der Achse, die rechts mit 15°
  ansteigt (Fahrbahnrand weiter ausgeleuchtet), heller Kern knapp unter der Grenze, breite Streuung
  zur Seite, außerhalb nur 3 %. Lichtkegel 2° nach unten, Helligkeit 16 (vorher 10 ohne Bild),
  Reichweite 95 m: die Straße ist etwa 40–50 m weit hell, dann kommt die Grenze. Erster Versuch mit dem
  hellsten Bereich weiter unten gab nur einen Fleck 15 m vor dem Auto. Fernlicht (Lichthupe F): eigenes Bild ohne
  Grenze, waagerecht, 2,2-mal heller und 1,8-mal weiter. Weiterhin wirft nur ein Scheinwerfer Schatten.
- Leuchten-Material (`shaders/car_lamp.gdshader`) für Scheinwerfer- und Rücklichtglas: Leuchtstärke
  per Parameter, dazu der Blinkerbereich (siehe unten). Tagfahrlicht: Scheinwerferglas leuchtet tags
  schwach (0,6), nachts voll.
- Begrüßungslicht in der Garage (`CarModel.play_welcome`, beim Öffnen und bei jeder Auswahl): nach
  0,25 s Tagfahrlicht, nach 0,9 s Scheinwerfer, nach 1,4 s Rücklicht, nach 1,9 s Motorstart (im Code
  berechnet: Anlasser, Zündungen nach Zylinderzahl, Drehzahl schießt hoch und fällt auf Leerlauf).
  Licht bleibt an, bis die Garage zugeht. Foto: `--garage --car=m2 --time=20 --wait=1.2`.
- Reifenspuren: MultiMesh-Ringpuffer mit 3000 Stücken, Rauch: GPUParticles3D pro Hinterrad.
  Rutschen pro Rad = `Car.wheel_slip()` (get_skidinfo + Driftwinkel).

## Sound, Pops & Bangs, Turbo, Flammen

- Sound prozedural (`engine_sound.gd`, AudioStreamGenerator 22 kHz): Tabelle mit 6 Zündungen
  pro Arbeitsspiel (720°), je Zylinder etwas andere Lautstärke, Abspielrate = Drehzahl/120.
  Last-/Schub-Tabelle überblendet, dazu Ansaugrauschen, Turbo, Begrenzer, Schaltknall, Quietschen.
- Pops & Bangs (`engine_sound.gd`): Gas schnell weg (von > 0,5 auf < 0,15) über 3000/min →
  1–2 s lang zufällige Knalle (Rauschen + 55-Hz-Schlag, ~35 ms), je höher die Drehzahl, desto
  öfter. Stärke pro Auto `pops_strength` (M3 GTS 1,0, M2 0,9, M5 F90 0,55, E30 und M5 G90 0,15),
  ohne Sportauspuff (Garage) nur 12 % und keine Flammen. Signal `popped(Stärke)`.
- Turbo: Ladedruck baut sich mit Gas und Drehzahl verzögert auf (1,4/s, ab 4,0/s), das Pfeifen
  steigt mit ihm (1400 → 6600 Hz, Lautstärke ∝ Druck²). Abblasventil (`blow_off_volume`):
  helles Zischen ~0,4 s, wenn bei Ladedruck das Gas weggeht. Beide M5 laut, M2 leise,
  E30/M3 GTS gar nicht (Sauger). Geprüft per Aufnahme (AudioEffectRecord, WAV ausgewertet).
- Flammen (`exhaust_flames.gd`): pro Endrohr 16 additive Partikel (blauer Kern → orange → rot,
  0,09 s, 5 m/s nach hinten), dazu ein orangefarbenes Licht ohne Schatten für ~60 ms, ab
  Knallstärke 0,3. Endrohre (`exhaust_tips`) aus den Modellen gemessen (Punktdichte der
  Auspuff-Materialien ganz hinten unten): M2 zwei mittig, E30 zwei links, M3 GTS vier mittig,
  beide M5 je zwei pro Seite. Test: `--flames` (knallt vor dem Foto ständig).

## Blinker, Hupe, Lichthupe

- Blinker (`car_signals.gd`, Knoten „Signals“ im Auto): Zustand am Auto (`turn_signal` 1 links /
  -1 rechts, `hazard`, `signal_lit`), Takt 1,5 Hz. Punkte aus `indicator_points` (links gemessen,
  rechts gespiegelt: äußere Ecke der Scheinwerfer bzw. Rückleuchten, Spiegel). Seit 16.11. leuchtet
  CarModel den Blinker im Glas des Modells: ein Bereich (Radius `indicator_radius`, 9 cm) um den Punkt
  im Scheinwerfer- bzw. Rücklichtglas, leicht orange getönt, beim Blinken orange leuchtend. Liegt der
  Punkt knapp daneben (bis 25 cm, C 63 vorne, M4 CSL vorne, G90/M2/SL 65/M4 CSL hinten), rückt der
  Bereich auf die nächste Stelle des Glases. Eigene Blinkergläser (`indicator_materials`: F90
  „blinkerfront“, M4 CSL „M4xNME_signal_L/R“ mit Spiegelblinkern, SL 65 „orange_glass“) leuchten ganz.
  Kästchen gibt es nur noch, wo nichts davon passt (derzeit keins); Spiegelblinker nur bei F90 und
  M4 CSL. Nachts je Seite zwei OmniLights ohne Schatten. Verkehrsautos: weiter leuchtende Kästchen an
  den äußeren Lampenecken (ihre Lichtmaterialien sind für alle Autos gemeinsam). Aus nach der Kurve: Lenkrad erst über 0,35, dann unter 0,08.
  Vollbremsung (Bremse ≥ 0,8 über 100 km/h) → Warnblinker, aus nach Stillstand und
  Wiederanfahren über 20 km/h. Klicken = zwei kurze im Code erzeugte WAVs, Hupe =
  AudioStreamGenerator mit zwei Tönen je Auto (`horn_tones`, z. B. M2 410/505 Hz) plus
  Obertönen. HUD: grüne Pfeile oben im Tacho-Panel, rotes Warndreieck. Test: `--signal=left`.
  Fotomodus: rauf/runter jetzt R/F, Schärfe G (Q/E sind die Blinker).

## Fenster und Kennzeichen

- Fenster (V, `open_windows.gd`, `car_glass.gdshader`): Seitenscheiben fahren in 1,6 s weg (Shader
  verwirft Glas mit Normale quer zum Auto über der Gürtellinie). Lauter: Motor-Bus +6 dB, Umgebung
  +7 dB, Tunnel-Hall +0,25, Fahrtwind. Aufnahme Autobahn 130 km/h: zu −22,3 dBFS, offen −10,8 (mit
  Wind −13 dB jetzt etwas weniger). SL 65: kein Dach zum Abnehmen, das Carbon-Dach gehört im Modell
  zur Karosserie (kein eigenes Teil), deshalb wie alle nur Fenster.
- Kennzeichen (`license_plate.gd`, `LicensePlate`): eigene Strich-Schrift (4 × 8-Raster, an die
  FE-Schrift angelehnt, keine Schriftdatei), EU-Feld mit Sternen und „D“, Format 1–3 Buchstaben, 1–2
  Buchstaben, 1–4 Ziffern (`normalize`). Garage: Eingabefeld, pro Auto gespeichert (`[kennzeichen]`).
  KI: zufällige Kennzeichen mit erfundenen Kürzeln aus den Ortsnamen, nur am nahen Modell.
- Kennzeichen-Lage (seit 13.11., Teil 6): pro Auto im Profil (`CarProfile` Gruppe „Kennzeichen“:
  `plate_front/rear_position`, `_size`, `_tilt` in Grad), gemessen mit `tools/plate_measure.gd` und per
  Foto geprüft. Gemessen wird an den eigenen Kennzeichen-Teilen des Modells (`plate_hide`: Material-
  oder Teilname enthält „manufacturerpla“ – bei C 63 ist der Name abgeschnitten,
  „…ManufacturerPla_0c896ed1“ –, „=Object_60“ = genau dieser Teilname, E92-Mulde), sonst an der
  Stoßstange (vorne 0,40 m, hinten 0,55 m). Die Original-Teile sind immer unsichtbar, nie doppelt.
  Vorher doppelt: C 63 hinten (weißes AMG-Schild im Kofferraumdeckel), E92 hinten (leere Mulde oben,
  unser Schild unten an der Stoßstange).
- Größe (`LicensePlate.fit_size`): Höhe immer 11 cm wie ein deutsches Kennzeichen, Breite wie das
  Original minus 1 cm, zwischen 28 und 52 cm. US-Mulden (30,5 × 15 cm: M2, M5 G90, SL 65, C 63 hinten)
  bekommen ein 29,5-cm-Schild, die E92-Mulde ein 43-cm-Schild. Die Textur wird für die Breite neu
  gezeichnet (`make_texture(text, pixel_width)`), die Schrift nie verzerrt (bei Bedarf kleiner). Lage
  auf der Außenfläche des Originals (nicht in seiner Mitte: ein 34-cm-Schild in der Mitte einer 30,5-cm-
  Mulde verschwand mit den Rändern in den Muldenwänden, „1-EW“ statt „M-EW“), Neigung wie das
  Original (10–17° hinten), `LicensePlate.place`.
- Gemessen (Profile, Höhe über der Auto-Mitte): vorne alle an der Stoßstange (keins der Modelle hat
  vorne ein eigenes Schild); hinten M2 0,245 m / 10°, M5 G90 0,279 / 13°, SL 65 0,234 / 17°, C 63 0,332 /
  13°, E92 0,362 / 14°, E30, M5 F90, M4 CSL an der Stoßstange.
- „Kein Kennzeichen“ (Garage, Schalter „KEINS“ neben dem Eingabefeld, pro Auto in `[kennzeichen_aus]`):
  dann auch keins vom Modell. `CarModel.plates_enabled`, Test `--noplate`.
- Verkehr: `tools/setup_traffic_models.gd` hat die Rolle „plate“ (Audi S3 „ext_plate“, Accord
  „plate_phong9“, Aztek „licplate“ (vier Farbvarianten übereinander), LC 500 „manufacturerplate“): Diese
  Teile fliegen aus den Meshes, ihre Lage steht in `PreparedModel.plate_spots`, das Spiel setzt sein
  Schild genau dorthin (`Traffic._plate_spots_of`, gleiche Regel für die Größe). ID. Buzz hat kein eigenes Kennzeichen, vorne aber eine Mulde in der
  Karosserie: `plate_front_height` 0,51 m / `plate_front_width` 0,45 m in MODELS (vorderste Stelle der
  Karosserie in dieser Höhe), hinten Stoßstange. Nach Änderungen am Werkzeug die Modelle neu vorbereiten
  (`--only=NAME`).

## Cockpit- und Ego-Sicht (16.11.)

- Taste Tab (umbelegbar, Aktion `cycle_camera`): Verfolger → Cockpit (vom Fahrersitz, Armaturen,
  Lenkrad und Spiegel sichtbar) → Ego (näher an der Scheibe, Motorhaube und oberer Teil des
  Lenkrads). Kamera: `scripts/follow_camera.gd` (Klasse FollowCamera), alles im Auto:
  `scripts/cockpit.gd` (Knoten Cockpit im Auto), Lenkrad und Innenraum: `CarModel`.
- Werte pro Auto im Profil (Gruppe „Cockpit“): Augen `eye_position`, Lenkrad (Mitte, Halbmesser
  0,18–0,2 m, Tiefe ±7 cm, Säulenwinkel 17–28°), Kombiinstrument (Mitte, Größe, Neigung),
  Innen- und linker Außenspiegel (der rechte ist gespiegelt). Gemessen mit
  `tools/cockpit_measure.gd`: Schnittbilder jedes Autos mit 10-cm-Raster (Seite bei x, oben bei y,
  hinten bei z, Blick wie der Fahrer), die Werte sind eingezeichnet (rot Augen, türkis Lenkrad, grün
  Display, gelb Spiegel). `--parts` listet Teile ums Lenkrad und alle Spiegel-Teile, `--showall`
  zeigt ausgeblendete Teile. Danach per Foto im Spiel geprüft (`--view=cockpit|ego`).
- Lenkrad: Übersetzung 14:1 (`steering_ratio`), dreht sich um die Lenksäule, auch von außen zu sehen.
  Bei M5 F90 (`*steer_stiches*` usw.) und M4 CSL (`*steer_stitch*`) sind es eigene Teile, beim F90
  wird zusätzlich der Rest im Zylinder geschnitten. Bei allen anderen schneidet CarModel beim Laden
  alle Dreiecke im Zylinder um die Säule aus den Meshes heraus (nur Meshes, die wirklich Punkte darin
  haben; die Reste verlieren ihre Detailstufen).
- Innenraum: C 63, M5 G90 und SL 65 hatten ihren Innenraum (`*InteriorA_Material1`) ganz
  ausgeblendet. Jetzt ist er `interior_parts`: nur in Cockpit und Ego sichtbar, von außen weiter aus
  (gleiche Leistung wie vorher). Im Cockpit haben alle `low_detail_parts` volle Detailstufe
  (`lod_bias` 2 statt 0,35).
- Kombiinstrument: Kein Modell hat drehbare Zeiger, deshalb ein eigenes Display an der Stelle des
  Originals (2D-Bild 512 × 192, 30 Bilder pro Sekunde, nur im Cockpit): Tacho links, Drehzahl rechts
  mit rotem Bereich, Gang groß in der Mitte, Tempo, Blinkerpfeile. Leuchtet (tags 1,6, nachts 0,7),
  nachts zusätzlich ein sehr schwaches Innenlicht (OmniLight 0,025, Reichweite 0,8 m, ohne Schatten; 0,18 machte den Innenraum hell wie am Tag).
- Spiegel: Eine Rückkamera (576 × 192, 30 Bilder pro Sekunde, 110° breit) auf Augenhöhe in der
  Wagenmitte, Blick nach hinten, nur im Cockpit. Das eigene Auto liegt auf Bild-Ebene 11
  (`CarModel.OWN_CAR_LAYER`), die diese Kamera auslässt. Sie rendert in HDR ohne Tonemapping (das
  macht das Hauptbild für die Spiegel mit), mit einer Kopie der Umgebung (alle 0,25 s, ohne SSAO, SSR,
  Glow). Innenspiegel zeigt die Mitte (30–70 %), die Außenspiegel je ein Drittel, alles gespiegelt
  (`shaders/car_mirror.gdshader`). Die Spiegelflächen schauen zum Auge und hängen 4 cm vor der Stelle aus
  dem Profil (das Glas des Modells steht meist schräger, sonst taucht das Bild halb dahinter ab).
  Eine automatische Suche nach dem Spiegelglas im Modell (Dreiecke, die zum Auge zeigen) habe ich
  ausprobiert und verworfen: Sie fand bei M2, F90 und G90 Teile von Dach und Gehäuse. Spiegel und
  Display entstehen erst beim ersten Blick aus dem Cockpit.
- Kopf: Feder mit Dämpfer (1,7 Hz, Dämpfung 0,55), 5 cm Auslenkung pro g (senkrecht halb), dazu
  2,2° Neigung pro g, Zittern nach Drehzahl und Tempo (abseits der Straße 3,5-mal so stark), ein
  kurzer Ruck nach vorne beim Hochschalten unter Last und 5° Blick in die Kurve. Sichtfeld 58°
  (Ego 62°) plus 4° bei vollem Tempo, nahe Grenze 3 cm.
- Scheiben: von innen nur 10 % Deckkraft (statt 55 %). Bei Regen zeichnet der Glas-Shader Tropfen,
  die das Bild dahinter brechen: ruhende (werden alle paar Sekunden neu verteilt) und laufende, die im
  Stand nach unten rutschen und beim Fahren vom Fahrtwind nach hinten über die Scheibe gedrückt
  werden (ab 90 km/h voll). Das gilt auch von außen.

## Verfolger-Kamera, Karosserie in Bewegung, Kollisionen (16.11.)

- Verfolger (`follow_camera.gd`): schwenkt wie an einer Feder hinter das Auto (Eigenfrequenz 3,2 rad/s,
  Dämpfung 0,72: nach einer Kurve schwingt sie leicht nach), schaut seitlich in die Kurve (2,2 m pro rad/s
  Drehrate, höchstens 3 m) und weitet das Sichtfeld von 65° im Stand auf 75° bei 250 km/h (vorher 70° →
  82° bei 200 km/h).
- Karosserie (`CarModel._update_body_motion`): Wanken zur Kurvenaußenseite (2,4° pro g) und Nicken
  (Bremsen: Nase runter, 1,5° pro g), Feder 1,5 Hz mit Dämpfung 0,45, Drehpunkt 10 cm unter der Auto-Mitte.
  Nur das Modell bewegt sich (Physik und Räder bleiben), deshalb hängen Kennzeichen, Scheinwerfer und
  Lenkrad jetzt am Modell. In der Cockpit-Sicht ruht die Karosserie (dort bewegt sich der Kopf).
- Kollisionen (`scripts/collision_effects.gd`, Knoten CollisionEffects im Auto): Das Auto meldet seine
  Berührungen (`contact_monitor`, 6 Stellen). Aufprall ab 0,8 m/s Geschwindigkeitsänderung (voll bei 9 m/s):
  dumpfer Schlag (Lautstärke nach Wucht), Funkenschauer, Kamera-Ruck (Verfolger wackelt bis 35 cm, im Auto
  wird der Kopf weggestoßen). Schrammen ab 1,5 m/s Rutschen: Funkenstrom an der Berührstelle und
  Schleifgeräusch, lauter und heller mit dem Tempo. Gelände, Bäume und Felsen sind weich: nur ein leiserer
  Schlag, keine Funken. Funken: GPUParticles3D (240, 0,45 s, leuchtend über Emission, damit sie glühen).
  Schlag und Schleifen werden beim Start berechnet (tiefer Ton mit Knirschen und Klingen, Rauschen mit
  Resonanz und Knacken), Bus „Motor“. Gilt für Leitplanken, Wände, Häuser und Verkehrsautos.
- Test: `--bench=12 --highway --crashtest` lenkt nach 8 s mit Vollgas in die rechte Planke (Fotos
  `crash_0` beim Einlenken bis `crash_3`). Ergebnis 16.11.: Aufprall bei 118 km/h mit voller Stärke, 3 s
  Schrammen; in der Aufnahme (`--record`) liegt der Schlag 5 dB über dem Motor, das Schleifen 3 dB.

## 2WD-Modus der M5 und Zurückspulen (16.11.)

- 2WD (Taste U, nur M5 F90 und M5 G90: `two_wd_switch`, nur unter 10 km/h): Die ganze Antriebskraft geht
  nach hinten, Stabilitätshilfe und Leistungsbegrenzung im Drift sind aus, HUD-Chip „2WD · ESP aus“.
  Übersteuern beim Gasgeben nimmt dann `two_wd_oversteer` (0,14, wie ein Hecktriebler) statt
  `power_oversteer` (F90 0,07, G90 0,05, passend zum Allrad), und es zählt der ganze Hinterachs-Anteil.
  Allrad fährt sich unverändert.
- Messung (`tools/grip_test.gd --cars=f90,g90`, Stufe sport, 16.11.): Power-Drift-Schwimmwinkel Allrad
  4° / 4°, 2WD 30° / 31° (zum Vergleich M4 CSL 24°, M2 20°). Ausweichen 6–7°, Handbremse 33° bzw. 31°
  (am Ende 26° / 27° statt 21° / 19°), Kurvengrenze unverändert 1,68 g. Mit `--drifttest --car=f90 --2wd`
  im Spiel: bei 49 km/h Vollgas mit halbem Lenkeinschlag dreht sich der F90 bis 105° (ganz herum).
  Das Messwerkzeug hat jetzt `--2wd` und `--trace`; beim ersten Auto wirkte eine Einstellung vor dem
  ersten Test nicht (dessen `_ready` läuft erst später), deshalb setzt `_start` sie jetzt.
- Zurückspulen (`scripts/rewind.gd`, Taste Rücktaste halten): bis zu 10 s, doppelt so schnell wie die
  Zeit lief. Jeden Physik-Schritt aufgezeichnet: Lage, Tempo, Drehung, Lenkung, Lenkwinkel, Gang, Drehzahl,
  Gas und die Lage der Kamera. Beim Spulen ist das Auto eingefroren und wird Schritt für Schritt
  zurückgesetzt, die Kamera steht dort, wo sie damals war (auch im Cockpit), Motorsound folgt der
  Drehzahl. Beim Loslassen fährt es mit dem damaligen Tempo weiter, die spätere Aufzeichnung fällt weg.
  Der Verkehr spult mit: Jedes Auto speichert jeden Physik-Schritt seinen Fahrzustand (Stück, Lage,
  Spur, Tempo, Plan, Kurve, Blinker …, `Traffic.record`), beim Spulen wird er zurückgeholt; Autos, die
  es damals noch nicht gab, sind unsichtbar und werden danach entfernt. Wetter und Uhrzeit laufen weiter.
  Springt das Auto (Reset, Karte, Garage), beginnt die Aufzeichnung neu. Bildeffekt
  (`shaders/rewind.gdshader`): fast schwarz-weiß, bläulich, Streifen, Störband, „◀◀ ZURÜCK“; Ton:
  Rauschen mit Pfeifen, das beim Spulen tiefer wird (1,25 → 0,55). Test: `--rewindtest` (nach 2,5 s
  Spulen steht das Auto wieder dort, wo es 5 s vorher war).

## Prüfstand

- Prüfstand (`dyno.gd`, `Dyno`, Garage > Prüfstand): eigene 3D-Welt (SubViewport), im Code gebaut:
  Sichtbeton, Glasfront, LED-Bänder (leuchtend, Glow), glänzender Boden (SSR), Grube mit je zwei
  Rollen unter den angetriebenen Rädern (Allrad vorne und hinten), Gebläse, Absaugschlauch,
  Bildschirm mit Drehzahl/PS. Messlauf: Vollgas im 4. Gang von 2000/min bis zum Begrenzer,
  Drehzahlanstieg = Drehmoment × 0,85 × Übersetzung² / (Radradius² × Masse) (wie eine Rolle mit der
  Masse des Autos), dann Gas weg (Pops, Flammen an den Endrohren). Der echte Motorsound läuft dabei
  (`EngineSound` mit `PROCESS_MODE_ALWAYS`, Drehzahl/Gas vom Prüfstand). Diagramm: PS (durchgezogen)
  und Nm (gestrichelt) aus `Car.torque_curve`, die letzten drei gemessenen Autos übereinander mit
  Legende. Gespeichert pro Auto in `[pruefstand]`, Testläufe nur im Speicher.
- Gemessen (Prüfstand): SL 65 670 PS bei 5400 / 1000 Nm ab 2200 (Lauf 14,3 s), M4 CSL 551 PS bei
  6200 / 650 Nm (7,5 s), C 63 517 PS bei 6800 / 620 Nm bei 5200 (14,1 s), M2 411 PS / 550 Nm (12,3 s).

## Reset (Taste R) und Sicherheitsnetz (13.11.)

- `car_reset.gd` (`CarReset`, Knoten „CarReset“ in main.tscn, übernimmt die Taste R von `car.gd`
  über `Car.external_reset`). Merkt sich alle 0,1 s sichere Stellen (alle vier Räder auf einer
  Straßen-Kollision mit Meta `road_segment`, Auto aufrecht, nicht im Portal: `tunnel_cover` 0,02–0,98
  ausgeschlossen, innerhalb der Fahrbahn mit 0,6 m Rand, auf Brücken 1,2 m), alle 4 m eine, höchstens
  80 (320 m). Ausrichtung = Richtung der Straße, wie das Auto fuhr.
- R: Steht das Auto auf der Straße (Strahl 4 m nach unten trifft Straße oder Kreuzung) und fährt
  langsamer als 3 m/s, wird es am Platz aufgerichtet (Blickrichtung bleibt). Sonst geht es zur neuesten
  gemerkten Stelle, die mindestens 10 m (`back_distance`) vor der letzten sicheren liegt, ohne Tempo,
  0,6 m darüber; neuere Stellen werden vergessen (ein zweiter Reset geht weiter zurück). Danach 3 s
  Sperre (`cooldown`), Meldungen im HUD („Zurück auf die Straße“, „Aufgerichtet“, „Reset gesperrt“).
- Sicherheitsnetz: alle 0,25 s, wenn das Auto mit mehr als 3 m/s fällt und ein Strahl 2,5 km nach unten
  nichts trifft (unter das Gelände gefallen) → sofort zurück auf die Straße. Der Wasser-Manager nutzt
  nach 3 s im Wasser ebenfalls `back_to_road()`. `fall_limit_y` in car.gd bleibt als letzte Reserve.
- Test: `--bench=30 --resettest` (Fotos `reset_vorher`/`reset_nachher`). Ergebnis 13.11.: im Hang 22 m
  neben der Straße → R → 14 m vor der Abkommstelle auf der Fahrspur, 0 km/h; R in der Sperre blockiert;
  auf dem Dach → aufgerichtet am Platz; 40 m unter das Gelände → sofort zurück auf die Straße.
