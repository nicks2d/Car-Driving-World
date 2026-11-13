# Tunnel

## Wo Tunnel entstehen

- Tunnel (`road_segment.gd`): Liegt die Fahrbahn mehr als 25 m unter dem Gelände
  (`TUNNEL_DEPTH`), wird ein Tunnel daraus, verlängert bis dorthin, wo es nur noch 12 m sind
  (`PORTAL_DEPTH`, dort sind die Portale). Lücken bis 32 m werden geschlossen, im Tunnel ist die
  Steigung gleichmäßig. Früher fielen solche Abschnitte weg (MAX_CUT 35 m), jetzt nur noch bei
  Tunneln über 3 km. Ist der normale Weg 1,15-mal länger als die Luftlinie (oder ungültig),
  rechnet die Wegsuche eine zweite Variante, die Berge durchbohren darf (Gelände über dem
  tiefsten Punkt im Umkreis von 216 m + 20 m zählt als Tunnel, kostet doppelt + 150 pro Tunnel).
  Sie gewinnt nur mit Tunnel und wenn sie 10 % günstiger ist, sonst bleibt die Straße wie vorher.
  Ergebnis rund um den Start: ~6 % der Abschnitte mit Tunnel, meist 0,5–2,9 km lang.

## Röhre, Portale, Gelände

- Tunnel-Mesh: Röhre (Wand 4,6 m, Scheitel 7,6 m, unten helle Verkleidung mit orangem Streifen,
  Punktfarben, Material ohne Backface-Culling), Portal = Betonkragen + Stirnwand (31 × 12 m),
  Deckenlampen alle 8 m (leuchtendes Material), Lichtpunkte alle 16 m. Fahrbahn im Tunnel bis an
  die Wand, UV2.y = überdacht (Straßen-Shader: trocken, kein Schnee). Wände und Stirnwand mit
  Kollision. Die Röhre wirft beidseitig Schatten (sonst scheint die Sonne hinein).
- Gelände an Tunneln (`road_query.gd`): Tunnelstücke graben nichts ab (der Berg bleibt).
  Hinter der Portal-Ebene wird aus der Böschung eine Felswand mit Steigung 3. Löcher im Gelände
  (`tunnel_hole`): die ersten 4 m hinter dem Portal und überall, wo das Gelände über der Röhre
  zu dünn ist; Dreiecke an Loch-Punkten fallen weg, die Kollision bekommt dort NaN (Jolt lässt
  die Dreiecke weg). Bäume/Felsen/Gras halten 20 m hinter den Portalen Abstand.

## Im Tunnel

- Im Tunnel (`tunnel_effects.gd`): Abdeckung 0–1 aus `RoadNetwork.tunnel_cover()` (ab dem
  Portal über ~20 m), 8 echte OmniLights an den nächsten Lichtpunkten (alle 0,2 s neu verteilt),
  Audio-Bus „Tunnel“ mit Reverb für alle Geräusche des Autos, Weather.shelter (kein Regen,
  trockene Reifen), DayNight: kein Himmelslicht und keine Himmels-Spiegelung, Augen-Anpassung
  (Belichtung bis 2,4-fach, dunkel werden langsamer als hell), ohne Sonnenschatten keine Sonne.
  Abblendlicht geht im Tunnel automatisch an (`Car.in_tunnel`). Karte: Tunnel gestrichelt.

## Behobene Fehler

- Tunnel-Bug „Berg im Tunnel“ (behoben): Ob über einer Röhre ein Loch ins Gelände kommt,
  entscheidet jetzt die fertige Höhe (nach Straßen, Böschungen, Kreuzungen, Parkbuchten und der
  Felswand am Portal), nicht die natürliche. Grobe Detailstufen (4/8/16 m): Rasterpunkte bis
  1,42 × Rasterweite neben der Röhre werden über den Scheitel gehoben (`RoadQuery.tunnel_coarse`),
  nah an Portalen und im Streifen der Röhre bis ~23 m davor gibt es stattdessen Löcher (sonst
  deckt ein grobes Dreieck vom Berg bis in den Einschnitt die Öffnung zu). Tunnelstücke
  überlappen etwas (sonst Keil in Kurven). Autobahn: An Abschnittsenden zählt schon die
  Portaltiefe (12 m) als Tunnel, sonst endete die Röhre des einen Abschnitts mitten im Berg.
  Anschlussstellen nur, wo das Gelände ±340 m um den Stützpunkt höchstens 12 m von der
  Autobahn abweicht (keine Rampen an Tunneln oder hohen Brücken).
- Lange Tunnel, „Wände zum Durchfahren“ (behoben, 9.11.): Ursache war der Horizont-Ring. Er sinkt
  unter fertigen Kacheln nur 124 m ab, und die Schürze an seinem inneren Rand (400 m um die
  Kamera) hängt bis −400 m. In jedem Tunnel, der länger als ~400 m ist, stand sie deshalb als
  Wand ohne Kollision in der Röhre. Jetzt hat der Ring einen eigenen Shader
  (`horizon.gdshader` = `terrain.gdshaderinc` mit `HORIZON_RING`) mit Tunnel-Maske
  (`tunnel_mask.gd`, `TunnelMask`): Je 16-m-Feld steht dort die höchste Röhrendecke, und der Ring
  verwirft alles darunter. Sie wird alle 2 s aus den geladenen Tunneln neu gezeichnet
  (512 × 512 Felder um das Auto). `discard` steht nur im Ring-Shader, die Kacheln bleiben ohne
  (das kostet auf dem Mac Leistung).
- Außerdem (vom Prüfwerkzeug gefunden): Kachel-Schürzen (2 × Rasterweite + 3 m, in Stufe 3 bis
  35 m) hingen in groben Detailstufen in die Röhre. Über Röhren reichen sie jetzt nur bis knapp über
  die Decke (`RoadQuery.tube_top`, Abstand bis eine Rasterweite). Bäume, Büsche und Felsen
  wachsen nicht mehr dort, wo ihr Fuß bis in die Röhre reicht (`_over_tube`).

## Prüfwerkzeug und Testen

- Prüfwerkzeug `tools/tunnel_check.gd` (Aufruf im Kopf der Datei): rechnet für jede Röhre
  in der Nähe von 6 Stellen (oder `--grid=5`: 25 Stellen auf 40 × 40 km) alle Detailstufen wie im
  Spiel und prüft alle 4 m an 5 Querpunkten, ob etwas Sichtbares zwischen Fahrbahn und Decke
  liegt: Gelände aller Stufen, Schürzen, die echten geladenen Kacheln, Horizont-Ring (Fläche und
  Schürze, abgesenkt 124 bzw. 4 m, mit der Maske wie im Spiel; `--nomask` = alter Stand), Wasser,
  Bäume/Büsche/Felsen, nah am Auto die Kollision per Strahl. Nennt auch die längsten Tunnel.
- Ergebnisse: erste Fassung (nur Gelände) vorher 108 Stellen (12 in Stufe 0), danach 0 bei
  34 Röhren / 25 km. Mit allem Sichtbaren vorher 4.650 Stellen (zwei Prüfstellen, fast alles
  Ring-Schürze), nachher auf 40 × 40 km 0 Stellen bei 140 Röhren / 125 km, Kollision 0.
  Längste: Landstraße 2.980 m bei (−4118, 4048) → (−4334, 5640), Autobahn 1.668 m bei
  (1600, 104) → (3200, −356).
- Autopilot (`--bench`) zählt auch die Meter im Tunnel. Testtunnel: Landstraße `--pos=-1700,-8262
  --heading=-80`, Autobahn `--pos=-5056,-63 --heading=85 --highway` (272 m).
- Fotos alle 100 m (`--shotevery=100` mit `--bench`): durch den 2.980-m- und den 2.628-m-
  Landstraßen-Tunnel und den 1.668-m-Autobahn-Tunnel, keine Wand. Achtung `--heading`: 0° = +Z
  (Süden), 90° = +X (Osten); Start am besten 200 m in der Röhre, sonst biegt der Autopilot am
  Portal ab. Beispiel: `--bench=130 --pos=-4145,4246 --heading=-8 --shotevery=100 --nohud`.
- Testen: Tunnel nahe am Start, z. B. `-- --shot=t --pos=-1562,-8360 --heading=-29` (vor dem
  Portal, 500 m lang), innen `--pos=-1798,-8254 --heading=-64`. Leistung im Vollbild: Tunnel-
  strecke 67 FPS, Startstrecke 66,8 (Mac warm). Im Fenster begrenzt macOS auf 60 (V-Sync).
