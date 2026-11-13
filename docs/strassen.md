# Landstraßen, Kreuzungen, Dörfer, Aussichtspunkte

## Ansatz und Wegsuche

- Straßen-Ansatz (M4): **Knoten-Gitter + A*-Wegsuche pro Abschnitt.** Warum: Jeder
  Abschnitt hängt nur von seinen zwei Orten ab, dadurch ist das Netz endlos, nahtlos und
  deterministisch, und die Wegsuche übers Gelände liefert von selbst Landstraßen im Tal und
  Serpentinen am Hang. Rauschen-Linien (keine Steigungskontrolle, keine Ziele) und
  Stadt-Algorithmen (L-Systeme, passen nicht zu Landstraßen) wurden verworfen.
- Straßen-Details: Orte in 1,2-km-Zellen (flach, im Tal, nicht über 300 m Relief).
  A* auf 18-m-Raster mit 48 Schrittrichtungen (sonst keine Serpentinen möglich), Kosten für
  Steigung (>10 % sehr teuer), Wasser und Knicke über 30°; Knicke über 45° pro Schritt sind
  verboten (dann werden Kehren ≥ 40 m breit). Höhenprofil mit max. 10 % Steigung, bei über
  35 m Abtrag/50 m Auftrag wird der Abschnitt verworfen (Gebirge: ~15 % der Abschnitte).
- Straßenbreite (Stand Teil 1 nach M6): Fahrbahn 9 m, Bankett 1,5 m, Böschungskante 1,8 m
  (`road_width`/`shoulder_width` am Roads-Node, der Shader bekommt die Breite beim Start).
- Kurven = Trassierung wie im Straßenbau: Weg aus der Wegsuche vereinfachen (Polygonzug),
  an jedem Knick ein Kreisbogen (Wunsch 60 m, bei kleinen Knicken bis 500 m). Passt er nicht,
  werden Knicke zusammengefasst: unter 20 m immer, unter 60 m nur bei ≤ 15 m Verschiebung.
  Kleinster Radius im Test 26 m, ~3 % der Strecke unter 60 m. Querneigung bis 5 % (3/R),
  sanft über ~50 m aufgebaut; `road_query.gd` berücksichtigt sie beim Gelände.

## Kreuzungen und Überlappungen

- Kreuzungen (`road_junction.gd`): Jeder Ort verteilt Abfahrtsrichtungen für seine bis zu
  4 Straßen (wie Luftlinie, aber ≥ 80° auseinander), die ersten/letzten 50 m führen genau
  dorthin (A*-Kegel ±30° bis 250 m). Die Straßen enden 14 m (bei spitzen Winkeln bis 24 m)
  vor der Mitte, die letzten 24 m liegen flach auf Ortshöhe. Kreuzungsfläche mit
  Bezier-Ecken (sehr weite Winkel/Sackgasse: Kreisbogen), UV2.x = 1 schaltet im Shader die
  Markierungen ab. Kreisverkehre gibt es (noch) nicht.
- Überlappungen: Ein Abschnitt wird erst gebaut, wenn alle Nachbarn berechnet sind
  (Zustände BUILDING → BUILT → CHECKING → CHECKED → MESHING → READY in `road_network.gd`).
  Kommen sich zwei Mittellinien außerhalb von 20 m um gemeinsame Orte näher als ~17,6 m,
  fällt der Abschnitt mit dem größeren Hash weg (deterministisch, unabhängig von der
  Reihenfolge). Dank der Abfahrtsrichtungen passiert das im Test gar nicht mehr.
- Überlappung mit großem Höhenunterschied (`RoadSegment.comes_close`): zählt nur dann nicht, wenn
  die obere Straße dort eine Brücke ist oder die untere im Tunnel liegt. Vorher fuhr eine
  Landstraße am Start (0, −1, 1) 10 m neben und 13 m unter einer Autobahn auf einem Damm entlang,
  mitten in den Damm hinein (Autopilot überschlug sich bei (105, 194)).

## Leitplanken und Brücken

- Leitplanken: außen in Kurven unter 45 m Radius und wo das Gelände 14 m daneben über 4 m
  tiefer liegt (eigenes Material `rail_material`, mit Kollision). Brücken haben Brüstungen.

## Dörfer

- Dörfer (Teil 5, `village.gd`, `Village`): an jedem Ort 3–8 Häuser (10 % der Orte 10–12), auf
  Bauplätzen 30–150 m entlang der abgehenden Straßen, beidseitig, nah an der Mitte zuerst.
  Abstand: Bankett + Böschungskante + Vorgarten 4–8 m. Nicht auf Straßen (auch Autobahn,
  Rampen), Kreuzungen, Parkbuchten, Wasser, anderen Häusern oder zu steil (Ecken > 3 m
  Unterschied). Haus 8–12 × 7–10 m, ein oder zwei Geschosse, Satteldach 35–45° (First meist
  längs), Fenster mit Rahmen (35 % nachts erleuchtet, `house_window_lit`), 40 % mit
  Fensterläden, Tür; 14 % Scheunen ab 70 m. 70 % mit Gartenzaun (Tor vorne).
  Laternen rechts der Straße alle 32 m bis zum letzten Haus, gelbe Ortsschilder am Eingang
  (hinten mit rotem Strich = Ortsende). Gemessen am Start: 10 Dörfer, 64 Häuser.
- Dorf-Ablauf: `RoadNetwork._village(cell)` plant im WorkerThreadPool, sobald die Kreuzung und
  alle Straßen ±230 m geprüft sind. Ergebnis hängt nur von Ort und Straßen ab. Unter jedem Haus
  ein Pad (wie Kreuzungen): Gelände flach, keine Bäume/Gras. `segments_for_rect` nimmt die Pads
  aller Orte bis 270 m um den Bereich mit (Gelände wartet aufs Dorf). Mesh: eine Fläche pro
  Material für das ganze Dorf (Wände/Zäune/Laternenmasten mit Punktfarben, Dächer, Fenster,
  erleuchtete Fenster, Lampen) = 5 Draw Calls statt MultiMesh pro Teil. Schatten bis 700 m,
  Kollision (eine Box pro Haus) bis 600 m. Nachts 6 echte Lichter (Pool) an den nächsten
  Laternen bis 160 m (`village_light_count`, `village_light_distance`).
- Testen Dörfer: Buchhof `--pos=-546,441 --heading=-77` (Ortsschild), `--pos=-660,459
  --heading=103` (im Ort), Mühlingen von oben `--pos=933,560 --fly=90 --pitch=-50
  --lookat=933,608`, nachts `--pos=933,470 --heading=0 --time=22`.

## Aussichtspunkte

- Aussichtspunkte (`viewpoints.gd`): 22 % der Landstraßen (Seed). Nach dem Berechnen sucht
  der Abschnitt im Hintergrund die beste Stelle (`Viewpoints.find_spot`): Seeufer (Wasser bis
  120 m daneben) vor Passhöhe (400 m davor und danach je 30 m tiefer) vor Aussicht (wo das
  Land im Blickfächer 150–600 m am weitesten abfällt). Nicht auf Brücken, in Tunneln, engen
  Kurven (< 250 m) oder über 6 % Steigung, mind. 140 m von Kreuzungen. Parkbucht 32 m + 2 × 12 m
  Auslauf, 7 m breit (`_build_bay`, mit Kollision), Gelände über drei Kreise flach
  (`bay_pads`, wie Kreuzungen), braunes Schild am Anfang (für den Verkehr auf dieser Seite),
  Bank mit Blick in die Landschaft.
- Entdecken: unter 5 km/h und näher als 25 m → Meldung „1 von 12 in dieser Gegend“
  (Gegend = 6 × 6 Ortszellen), gespeichert in `user://aussichtspunkte.cfg` (Testläufe mit
  Argumenten speichern nichts). Große Karte: entdeckte mit Kamera, übrige bis 6 km als „?“
  (noch nicht berechnete Straße: ungefähr in der Mitte zwischen den Orten). Garage →
  Sammlung: Liste mit Foto (das letzte Foto bis 150 m am Punkt).

## Laden und Vergessen

- Ein Abschnitt, den in den letzten 5 s noch etwas angefordert hat (`Entry.wanted_msec`,
  `WANTED_KEEP_MSEC`), wird nicht vergessen, auch wenn er weiter als `FORGET_DISTANCE` weg ist.
  Vorher gab es eine Endlosschleife (berechnen, vergessen, neu anfordern), z. B. als der Welt-Prüfer
  direkt nach (−16.000, 11.000) sprang: Landstraßen bei x ≈ −10.000 wurden immer wieder neu
  berechnet, die Straßen am Ziel nie fertig (im Spiel: Ladebildschirm ohne Ende nach einem Sprung).
- Beim Beenden wartet das Straßennetz auch auf Dörfer, die gerade geplant werden.
