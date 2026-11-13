# Wasser: Flüsse, Seen, Talsperren, Wasserfälle, Brücken

## Flüsse, Seen, Brücken

- Wasser (M5): Seen = Kreisscheibe pro See (`water_manager.gd`), Flüsse = Wasserfläche pro
  Gelände-Kachel (`terrain_chunk_job.gd`, UV = Fließrichtung). Wasserspiegel eines Flusses
  liegt 1,2 m unter dem Talboden. Flussbreite: Abstand = Rauschwert / Steigung, Steigung nach
  unten begrenzt (sonst riesige Wasserflächen, wo das Rauschen flach ist). Bei hohen Bergen
  wird das Flusstal breiter (relief * 0.5), sonst entstehen senkrechte Schluchtwände.
- Brücken: wo die Straße über Wasser oder mehr als 7 m über dem Gelände liegt (+12 m Zugabe).
  Fahrbahnplatte, Brüstungen mit Kollision, Pfeiler alle 24 m. Unter Brücken wird das Gelände
  nicht angepasst. Lange Hangviadukte entstehen gelegentlich, das ist gewollt.
- Auto im Wasser: Bremskraft, nach 3 s Reset auf die nächste Straße (Wasser-Manager,
  `car.gd` bleibt unverändert).

## Talsperren

- Talsperren (`world_gen.gd`, Lake mit `reservoir`): je 10-km-Zelle (Chance 0,8) dort, wo die
  Luftlinie zwischen zwei Ortszellen-Mitten einen vollen Fluss fast quer (> 60°) kreuzt und das Tal
  eng ist (beide Hänge erreichen die Krone 22–36 m über dem Fluss, Mauer ≤ 700 m). Die
  Flussrichtung kommt aus der Null-Linie des Fluss-Rauschens (`river_direction`; `river_flow` ist
  nur das großräumige Gefälle). Stausee = Flutfüllung (40-m-Raster, bis 4,5 km) bis 3 m unter
  die Krone; abgelehnt, wenn er den Rand erreicht, um die Mauer läuft, unter 0,15 km² oder über
  12 km² hat oder einen runden See berührt. Gelände bleibt (das Tal wird nur gefüllt). Nur aus dem
  Gelände, damit die Reihenfolge egal ist. Gemessen: 9 Talsperren auf 50 × 50 km (Flüsse sind
  selten: nur ~36 Stellen, an denen eine Straßenlinie einen vollen Fluss kreuzt), 42 ms pro
  Zelle im Mittel. Prüfen: `tools/landmarks.gd` (Liste mit Foto-Befehlen).
- Der Stausee zählt überall als Wasser (`lakes_near`, `Lake.covers`/`surface_at`, nie hinter der
  Mauer): Orte entstehen nicht darin, Wegsuche und Autobahn weichen aus oder bauen Brücken,
  Karte, Gras, Bäume, Auto im Wasser. Fernsicht (Horizont-Ring, große Karte) nimmt nur schon
  berechnete (`cached_reservoirs_near`), sonst würde sie Flutfüllungen anstoßen.
- Straße über die Krone (`RoadSegment.dam`): Die Wegsuche läuft in zwei Teilen (Ort → Mauerende,
  Mauerende → Ort, `_find_path_via_dam`), dazwischen die Kronenlinie als Gerade mit 90 m Anlauf
  an beiden Enden (dort liegen die Kurven); die Mauerenden sind beim Zusammenfassen von Knicken
  gesperrt (`_locked`). Abfahrtsrichtung am Ort zeigt auf das nahe Mauerende
  (`RoadNetwork.dam_entry`), sonst Haarnadel vor der Kreuzung. Korridor breiter (`min_corridor`).
  Höhe auf der Krone fest; zählt sonst wie Brücke (kein Bankett, keine Böschung, Ceiling darunter),
  nur Platte/Brüstung/Pfeiler baut die Mauer. Talsperren-Straßen gibt es immer und sie gewinnen bei
  Überlappungen (`_priority` −1).
- Staumauer (`dam.gd`, gebaut vom WaterManager aus der Kronenlinie, steht also auch ohne Straße):
  Krone mit Platte, Gehwegen, Betonbrüstung (Kollision) und Handlauf, Laternen alle 32 m
  abwechselnd (nachts 4 echte Lichter bis 180 m), Wasserseite senkrecht bis unter den Spiegel,
  Talseite nach unten flacher (0,72 m pro m) und in der Mitte 9 m nach außen gewölbt, Beton-Shader
  mit Fugen und Wasserspuren (`dam.gdshader`). Überlauf über dem Fluss: dunkle Öffnungen unter der
  Fahrbahn, fallendes Wasser über die Talseite, unten Gischt, Nebel, Rauschen. Am Ende `dam_b`
  ist die Mauer zur Seeseite 7,5 m breiter: dort die Parkbucht als Aussichtspunkt „Talsperre …“
  (ohne eingeebnetes Gelände darunter). Karte: Name „Talsperre <Ort>“ am See.
- Stausee-Fläche (`WaterManager._reservoir_mesh`): je Rasterzeile lange Streifen, nah an der Mauer
  Zelle für Zelle 6 m vor der Kronenlinie abgeschnitten. Darunter kein Fluss (Chunk-Job).

## Wasserfälle

- Wasserfälle (`world_gen.gd` `waterfalls_near`, `waterfalls.gd`): je 2,5-km-Zelle Chance 0,35,
  steilster von 64 Punkten (Steigung > 1,1) mit Kante in einer Rinne (seitlich höher) und Hang
  darüber (+25 m auf 120 m), nicht im Schnee, Fuß unter der Baumgrenze, 16–55 m hoch. Gemessen:
  18 auf 40 × 40 km. Band aus fallendem Wasser (`waterfall.gdshader`, Streifen laufen nach unten,
  Ränder ausgefranst per Dither) 0,5 m über dem Fels, Becken = kleiner See mit Felsrand
  (`Lake.pool`, gräbt sich ins Gelände), bis 320 m Gischt, Nebel und Rauschen (3D, prozedural).
  Wasserfall bis 300 m an einer Straße → Aussichtspunkt „Wasserfall bei …“.

## Landmarken-Brücken

- Landmarken-Brücken (`landmark_bridge.gd`, `LandmarkBridge`, nach dem Berechnen im Hintergrund,
  `RoadSegment.landmark`): Brücke ab 250 m Länge und 50 m (Landstraße 35 m, die darf höchstens
  50 m über dem Gelände liegen) über dem Tal. Bogen: Rippe 2,6 m dick von Hang zu Hang (wo das Tal
  tiefer als 45 % der Höhe ist), Stützen alle 12 m, dort keine Pfeiler. Hängebrücke ab 450 m und
  45 m: Pylone bei 22/78 % (Höhe 22 % des Hauptfelds, 40–110 m), Tragseile mit Durchhang bis 3 m über
  die Fahrbahn, an den Enden zur Fahrbahn verankert, Hänger alle 8 m. Rote Lampen auf Pylonen bzw.
  am Bogenscheitel, nachts hell. RoadNetwork zeigt sie bis `landmark_distance` (6 km), auch ohne
  Fahrbahn-Mesh; Karte: „Talbrücke …“ / „Hängebrücke …“. Gefunden z. B. Bogen (Autobahn) bei
  (5160, −892), 312 m / 57 m; Hängebrücke bei (−10183, −9442), 1084 m / 45 m.
- `mesh_builder.gd` (`MeshBuilder`): Vierecke, Dreiecke, Kästen, Balken mit Punktfarben, Grundlage
  für Staumauer, Landmarken-Brücken und Seeleben.

## Leben an den Seen

- Leben an den Seen (`lake_life.gd`, `LakeLife`): runde Seen bis 1,4 km um die Kamera. Je See
  (Seed) 40 % Badestelle, 35 % Campingplatz, sonst nichts; die Stelle am Ufer in Richtung der
  nächsten Landstraße (40–380 m), ±35° dort, wo am wenigsten Wald steht. Schotterparkplatz an der
  Straße und Weg zum Ufer. Badestelle: Liegewiese, Holzsteg 26 m mit Plattform, Kiosk, Schirme.
  Campingplatz: 3–5 Wohnwagen, 4–6 Zelte, 4 Laternen (nachts hell), Feuerstelle; nachts bis 160 m
  Flammen (Partikel) und flackerndes Licht. 2–5 Boote je See (55 % Segelboote, Segel quer zum Wind),
  treiben auf Kreisen und schaukeln, im Winter keine. Gelände wird nicht eingeebnet (einzelne
  Bäume können auf der Wiese stehen). Testen: Badestelle `--pos=-1367,-1497 --cam=-1320,-1440,40
  --lookat=-1367,-1497,0`, Campingplatz nachts `--pos=3272,-6100 --cam=3120,-6425,10
  --lookat=3055,-6440,1 --time=22.5`.

## Testen

- Testen: `--cam=X,Z,H --lookat=X,Z,H` freie Kamera (H über dem Gelände), z. B. Talsperre
  Rosenstadt von oben `--pos=2700,4200 --cam=2560,4620,260 --lookat=2700,4200,0`, Krone
  `--pos=2500,4186 --heading=86`, Wasserfall `--pos=1200,4071 --cam=1330,4030,90
  --lookat=1190,4074,10`, Karte `--pos=2700,4300 --map`. Achtung: Ist das Spielfenster ganz
  verdeckt, zeichnet macOS es nicht und das Foto hängt (Hauptthread in nanosleep); Testläufe mit
  `--always-on-top` starten.
