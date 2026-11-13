# Autobahn, Anschlussstellen, Raststätten

## Linienführung und Querschnitt

- Autobahn (`highway_layout.gd`, Art HIGHWAY in `road_segment.gd`): Linien west–ost und
  nord–süd alle ~6 km (75 % gibt es), Stützpunkte alle 1,6 km. Seitenlage = glattes Rauschen
  (Stützwerte alle 4 Stützpunkte, ±900 m, im Tal gesucht) plus ±120 m lokale Suche. Mittellinie
  ohne Wegsuche: gerade Stücke an den Stützpunkten (150 m, an möglichen Anschlussstellen 310 m),
  dazwischen Hermite-Kurve. Warum: Unabhängige Stützpunkte (±400 m) ergaben S-Kurven mit
  ~340 m Radius, der Autopilot flog bei 250 km/h in die Brüstung.
- Autobahn gemessen auf 40 × 40 km: 234 Abschnitte, alle gültig, kleinster Radius 888 m
  (seit Teil 4 des Umbaus: 1109 m), Steigung ≤ 4 % (Notlösung: liegen Stützpunkte zu weit
  übereinander, steigt `max_grade` etwas, einmal 4,2 %, statt einer Lücke), Tunnel 34 %,
  Brücken 14 %. Anschlussstellen: 73 Stück, auf offener Strecke etwa alle 3,2 km (über alles
  ~5 km, weil an Tunneln und hohen Brücken keine gehen).
  Autobahn 0,23 km/km², Landstraßen 0,97 km/km² → **Anteil Autobahn 19 %**.
- Querschnitt 25,5 m: je Richtung 2 × 3,75 m plus 2,5 m Standstreifen, Mittelstreifen mit
  Leitplanke, Leitpfosten alle 48 m mit Rückstrahlern (`reflector.gdshader`, leuchten im
  Scheinwerferlicht), Querneigung bis 2,5 %. Shader `road.gdshader`: `lane_profile` 0/1/2/3 =
  Landstraße/Autobahn/Rampe/Parkplatz.

## Anschlussstellen, Kreuzungen, Schilder

- Anschlussstellen (Raute) an jedem Stützpunkt (`INTERCHANGE_EVERY` 1, vorher jeder 2.), wenn
  ein Ort 220–1100 m daneben liegt und Richtung Autobahn Platz hat (≥ 50° zu seinen Straßen,
  gesucht in 15 Richtungen ±70°). Der Zubringer verlässt den Ort in
  einer freien Richtung, schwenkt im Bogen und überquert die Autobahn rechtwinklig (endet 150 m
  dahinter). Rampen 280 m. Schlüssel: Autobahn (k, Linie, 2 + Achse), Anschlussstelle
  (k, Linie, 10 + 10·Achse + Teil), Teil 0 = Zubringer, 1–4 = Ausfahrt/Einfahrt links/rechts.
  Orte entstehen nicht näher als 220 m an einer Autobahn (`HighwayLayout.is_clear`), haben
  erfundene Namen (`place_name`), Ausfahrt-Nummern zählen pro Linie hoch.
- Kreuzungen: Nord–Süd wartet auf West–Ost, Landstraßen/Zubringer/Rampen auf alle Autobahnen.
  Wer später kommt, führt ≥ 7,5 m darüber (immer als Brücke) oder 7 m unter einer hohen Brücke
  durch; liegt die andere im Tunnel, 9 m Abstand (gilt auch beim Begradigen des Tunnels).
  Die Überlappungsprüfung übergeht Paare mit ≥ 6 m Höhenunterschied.
- Schilder: blaue Schilderbrücken 2000 m und 500 m vor der Ausfahrt (Nummer, Ort, Entfernung),
  Ausfahrt-Schild am Rampenbeginn. Label3D zeigt Text nach +Z: mit
  `Basis.looking_at(Fahrtrichtung)` ist er für den Verkehr lesbar.
- Autobahnkreuz: nicht gebaut. Kreuzungen zweier Autobahnen bleiben Überführungen (die
  Schleifenrampen bräuchten eigene Trassierung zwischen Tunneln und Brücken).

## Verzögerungs- und Beschleunigungsstreifen

- Verzögerungs- und Beschleunigungsstreifen (Teil 4): Die Autobahn selbst wird breiter
  (`RoadSegment.aux_lanes`, gesetzt von `RoadNetwork._aux_lanes_at` für jede Rampe der
  Anschlussstellen und Raststätten). Je Punkt `extra_left/right` (Meter) und `marks_left/right`
  (`RoadSegment.Mark`: Blockmarkierung, Sperrfläche, Verziehung). Aus dem 2,5-m-Standstreifen wird
  mit 1,65 m mehr (`AUX_EXTRA`) ein 3,5-m-Fahrstreifen mit eigener Randlinie. Ausfahrt (in
  Fahrtrichtung): 60 m Verziehung (`AUX_TAPER`), 250 m parallel (`AUX_PARALLEL`), Blockmarkierung
  (Breitstrich 6 m/6 m), ab dem Rampenbeginn Sperrfläche (schräg schraffiert): Breite noch 25 m,
  dann über 30 m weg (unter der abschwenkenden Rampe), Schraffur 20 m weiter. Einfahrt gespiegelt,
  die Verziehung am Ende schraffiert mit Blockmarkierung. Der Shader (`road.gdshader`, Profil 1)
  bekommt das als Punktfarbe (COLOR.r/g = Breite/10, b/a = Markierung/3; andere Straßen haben
  keine Punktfarbe, dann wird sie ignoriert). Mesh, Kollision, Brücken, Leitplanken, Leitpfosten
  und die Gelände-Anpassung (`road_query.gd`, flacher Teil breiter) rechnen die Zusatzbreite mit.
- Rampen beginnen/enden jetzt im Zusatzstreifen (`RAMP_LATERAL` 12,45 m statt 15,55 m neben der
  Mitte: ihre innere Randlinie liegt auf der Randlinie der Autobahn) und dort 4 cm höher
  (`RAMP_LIFT`, sonst flimmern die übereinander liegenden Flächen).
- Ausstattung (`_add_signs`): Ankündigungsbaken 300/200/100 m vor dem Rampenbeginn (weiße Tafel mit
  3/2/1 roten Schrägstreifen), an der Spitze der Sperrfläche (`_gore_nose`: wo zwischen Fahrbahnrand
  und Rampe 0,6 m Platz ist, rechnet die Bezier-Kurve der Rampe nach) ein gelber Anpralldämpfer,
  Leitpfosten auf der Insel und das blaue Schild „Ausfahrt N“ bzw. „Rastanlage“ mit Pfeil ↗
  (statt früher am Rampenbeginn). Die Insel ist Gelände mit Gras.

## Raststätten

- Raststätten (Teil 4, `HighwayLayout.rest_area_at`): je Fahrtrichtung in einem Fenster von
  5 Stützpunkten alle 11 (17,6 km), am ersten Stützpunkt, an dem Autobahn und Parkplatz an der
  Oberfläche liegen (Gelände ±12 m, trocken), bevorzugt dort, wo keine Anschlussstelle geht
  (beide schließen sich aus). Gemessen auf 40 × 40 km: 26 Raststätten, auf offener Strecke
  etwa alle 17–20 km je Richtung, 11 mit Bergblick. Name „Rastanlage“ + Ortsname der Zelle.
  Schlüssel (k, Linie, 40 + 10·Achse + 0/5 je Richtung + Teil), Teil 0 = Parkplatz, 1 =
  Ausfahrt, 2 = Einfahrt (Art RAMP, Bezier, flach auf Stützpunkt-Höhe).
- Parkplatz (`_make_rest_segment`, Shader-Profil 3 = nur Asphalt): 46 m breit, 78 m neben der
  Autobahn-Mitte, groß 280 m lang (`REST_HALF_LARGE`, wenn das Gelände an 6 Prüfstellen passt),
  sonst 220 m (`HighwayLayout.LOT_CHECKS_*`, `rest["large"]`, `rest["half_length"]`). Gerade
  Enden (`RoadSegment.square_ends`, Kappe 2 in `road_query.gd`).
- Aufbau (Teil 5, `RoadNetwork._add_rest_props`, wie eine deutsche Rastanlage; along in
  Fahrtrichtung, across vom autobahnseitigen Rand): Fahrgasse 0–8 m (Verkehr bei 4,5 m), Pkw in
  Doppelreihen quer (2,5 × 5 m, across 8–18) in Gruppen à 10 mit Inseln (Baum), kurz vor der
  Tankstelle, in der letzten Gruppe drei breitere Plätze (3,33 m); zweite Fahrgasse 18–24 m;
  Lkw schräg 45° (4 × 18 m, across 24–40) im vorderen Teil; Grünstreifen 40,5–46 m mit Bäumen,
  Büschen, Bänken. Groß: 60 Pkw + 26 Lkw, klein: 40 Pkw + 16 Lkw. Tankstelle (Modell, 38 ×
  22,9 m, Mitte bei along L−47, across 21) am Ende vor der Einfahrt, daneben ein gepflasterter
  Platz mit Bänken, Gehweg-Block und Zebrastreifen zu den Pkw. Leitplanke zur Autobahn, Laternen
  alle 35 m an der Fahrgasse und im Grünstreifen, Pfeile auf beiden Fahrgassen.
- `lot_mesh.gd` (`LotMesh`): sammelt Markierungen (flache Rechtecke 1,5 cm über dem Asphalt, so
  gehen auch die schrägen Lkw-Plätze), Inseln/Gehwege (14 cm hoch, Bordstein-Seiten), Leitplanke,
  Laternen, Bänke und Baumstämme und baut ein Mesh mit einer Fläche pro Material (~8 Draw
  Calls). Inseln, Gehwege und Leitplanke bekommen Kollision im StaticBody3D der Raststätte.
- Geparkte Fahrzeuge: 20–50 % der Pkw- und 25–55 % der Lkw-Plätze, fest pro Raststätte
  (Zufall aus dem Schlüssel), 70 % vorwärts eingeparkt. `Traffic.make_parked` baut sie mit denselben
  Stufen wie der Verkehr (nah/mittel/fern, fern nur bis 400 m), lädt das Modell noch, kommt es
  nach (`_upgrade_parked`). Je ein Kollisionskasten. Typ und Farbe: `Traffic.random_car_type`,
  `random_paint` (gleiche Anteile wie im Verkehr).
- Tankstellen-Modell (`STATION_MODEL`): nah bis 180 m, dann mittlere Stufe; 22 Kollisionskästen
  aus dem Modell; die leuchtenden Materialien (Dach-Unterseite, Leuchtkästen) werden nachts heller
  (`_station_glow` in `_update_night_glow`). Fehlt das Modell, steht die alte gebaute Tankstelle
  (Dach, drei Zapfsäulen-Inseln, Kasse) dort. Rasthof, Mast und alle anderen alten Kästen sind weg.
  Echte Lichter: 3 OmniLights pro Raststätte (Tankstelle, Pkw, Lkw), nur bis 260 m am Auto.
- Tankstelle: 616.000 → 201.700 Dreiecke ohne Asphaltfläche und Ladenregale (Cube.006/.038,
  390.000 Dreiecke), vereinfacht nah 51.600 / mittel 8.650 (mittel ohne Teile unter 1,5 m).
  Echte Marken: Regal-Fotos (Coca-Cola, Fanta, Sprite, Cheerios, Chex) und Werbetafel „MILES+“
  (Circle K) → im Werkzeug neutral erzeugte Bilder. Maße 38 × 6,6 × 22,9 m, lichte Höhe unter den
  Leuchtkästen 4,81 m (echte Größe), 22 einfache Kollisionsformen (Laden, Stützen, Inseln,
  Zapfsäulen). Leuchtende Materialien: glowin (Dach-Unterseite), Material.026/.027/.029.
- Schilder: blau 2000 m und 500 m vorher (Ort, „Rastanlage“, Zapfsäule und Tasse, Entfernung),
  Ankündigungsbaken und „Rastanlage ↗“ auf der Insel (wie an Anschlussstellen).
- Karte: Zapfsäule im Kreis an jeder Raststätte (bis 24 m/px, gesucht pro 4-km-Feld, höchstens
  zwei neue Felder pro Bild). Navi: Klick bis 150 m an eine Raststätte = Ziel; Route über den
  Stützpunkt davor, Ausfahrt, Parkplatz (Ansage „Zur Rastanlage“). Steht man schon davor oder
  darin, direkt. Raststätten mit Aussicht zählen als Aussichtspunkt („R…“-Kennung, entdeckt
  unter 5 km/h bis 110 m an der Mitte), auf der Karte als Abzeichen neben der Zapfsäule.

## Navi und Laden

- Navi mit Autobahn: Knoten = Orte und Autobahn-Stützpunkte je Fahrtrichtung (Vector4i),
  Kosten = Fahrzeit (Landstraße 70, Autobahn 130 km/h). Ansagen „Auf die Autobahn“ und
  „Ausfahrt 5 nehmen“ mit Ortsname. Test 17 km: 8,5 min über die Autobahn statt 26 min,
  Planen 13 ms. Karte: Autobahn breit und gelb, Rampen schmal.
- Laden: Abschnitte außer Landstraßen werden erst 4,5 km weiter weg vergessen
  (`HIGHWAY_FORGET_EXTRA`), sonst Endlosschleife (Abhängigkeit gebaut und sofort vergessen).

## Testen und Messungen

- Testen: `--highway` startet auf der Autobahn (rechte Spur), mit `--bench` fährt der
  Autopilot dort Vollgas (Kurven mit 9 m/s², 700 m Vorausschau). `--target=X,Z` setzt vor dem
  Foto ein Navi-Ziel. M3 GTS (`--car=e92`, 70 s): 4,8 km, Spitze 304 km/h, max. 2 m neben der
  Spur, ~147 FPS, 1%-Low 84, schlechtestes Bild 16–20 ms, kein Nachlade-Ruckler (Fenster
  1280 × 720; macOS übergeht `--fullscreen` beim Benchmark). Im Fenster zählt `process_ms` die
  V-Sync-Wartezeit mit (~21 ms), das ist kein echter Wert.
- Testen: Raststätte Falkenweiler `--pos=9560,-3988 --heading=90` (auf dem Parkplatz),
  von oben `--pos=9450,-3988 --highway --heading=90 --fly=110 --pitch=-55 --lookat=9604,-3988`,
  Schild 500 m `--pos=8790,-4056 --highway --heading=90`, Navi `--target=9604,-3982`,
  Bergblick Fichtenstein `--pos=-6420,-10337 --heading=90`.
- Testen: Raststätte Falkenweiler, Verzögerungsstreifen Richtung Osten `--pos=9250,-4032
  --highway --heading=90 --fly=3.5 --pitch=-8`, Sperrfläche `--pos=9330,-4032 --highway
  --heading=90 --fly=7 --pitch=-18`. Prüffahrt: `--bench=60 --highway --exitdrive
  --benchshot=10,20,30` (Autopilot über Ausfahrt, Zubringer, Einfahrt auf der Gegenseite,
  `RoadNetwork.exit_route`, auf dieser Route Kurven mit 4 m/s² wie auf der Landstraße).
- Gemessen: Anschlussstelle bei (3200, −4060), 150 s mit hochgesetzten Ab-/Auffahr-Chancen
  (`tools/_traffic_check.gd`, nicht im Repo): 8 Ausfahrten, 4 Auffahrten, alle 4 nach 99–236 m
  auf dem Beschleunigungsstreifen eingefädelt, kein Auto fest, kleinster Abstand 30 m.
  Prüffahrt M4 CSL: Autobahn 172 km/h → Verzögerungsstreifen → Ausfahrt (bremst auf ~60) →
  Zubringer über die Brücke → Einfahrt → Gegenrichtung mit 147 km/h, 1,5 km. An der engen
  Ecke Rampe/Zubringer schneidet der Test-Autopilot die Kurve (setzt einmal zurück), das ist
  dessen Zielpunkt-Lenkung, nicht die Straße.
