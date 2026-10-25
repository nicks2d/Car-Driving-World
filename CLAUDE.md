# Endlose Welt – Projektanweisungen für Claude Code

## Worum es geht

Ein 3D-Spiel in Godot: eine endlose, prozedural generierte Landschaft mit Bergen,
Tälern, Flüssen, Seen und einem Straßennetz, durch die man mit einem Auto fährt.
Mit Tag-Nacht-Wechsel und möglichst stimmungsvoller, realistischer Grafik
(Vorbild für die Atmosphäre: GTA, Forza Horizon – natürlich in Indie-Maßstab).

Die Welt ist deterministisch: gleicher Seed = gleiche Welt. Sie wird in Kacheln
(Chunks) rund um den Spieler erzeugt und weit entfernte Kacheln werden wieder entfernt.

## Über mich (Nick)

- Ich studiere Wirtschaftsinformatik und bin beim Programmieren noch Anfänger
  (Grundlagen in Python). GDScript und Godot sind neu für mich.
- Antworte mir auf Deutsch, locker und verständlich.
- Erklär mir nach jedem Schritt in 2–4 Sätzen, was du gebaut hast und wie ich es teste.
- Wenn du eine Entscheidung triffst, die das Spiel stark beeinflusst
  (z. B. Grafik vs. Performance), sag mir kurz die Optionen.

## Technik

- Engine: Godot 4 (aktuelle stabile Version, Standard-Edition ohne .NET)
- Sprache: nur GDScript, mit statischen Typen (`var speed: float = 10.0`)
- Renderer: Forward+
- 3D-Physik: Jolt (falls in der installierten Version verfügbar)
- Ziel: flüssige 60 FPS auf einem normalen Laptop. Grafik-Features über
  Qualitätsstufen (niedrig/mittel/hoch) schaltbar machen.

## Ordnerstruktur

```
scenes/      .tscn-Szenen (main.tscn, car.tscn, terrain_chunk.tscn, ...)
scripts/     .gd-Skripte, ein Skript pro Aufgabe
shaders/     .gdshader-Dateien (Terrain, Wasser, Himmel, ...)
assets/
  models/    3D-Modelle (.glb bevorzugt)
  textures/  Texturen
  hdri/      Himmels-Panoramen
  CREDITS.md Quelle + Lizenz jedes Assets
```

## Code-Regeln

- Einfach vor clever. Lieber ein gut lesbares Skript als fünf Klassen-Ebenen.
  Keine Abstraktionen „für später“.
- Kommentare auf Deutsch, Variablen- und Funktionsnamen auf Englisch.
- Jede wichtige Zahl (Sichtweite, Chunkgröße, Fahrzeugwerte) als `@export`-Variable
  oben im Skript, damit ich sie im Godot-Editor selbst verändern kann.
- Prozedurale Generierung immer über `FastNoiseLite` mit festem Seed.
- Schwere Generierung (Terrain-Meshes, Straßen) nicht im Hauptthread,
  sonst ruckelt es beim Fahren. `WorkerThreadPool` nutzen.
- Szenen (.tscn) dürfen direkt als Text bearbeitet werden, aber sauber und
  gültig bleiben. Nach dem Bearbeiten immer mit dem Godot-MCP testen.

## Arbeitsweise (wichtig!)

1. **Immer nur ein Meilenstein gleichzeitig.** Nicht vorgreifen.
2. **Erst planen, dann bauen.** Zeig mir den Plan und warte auf mein OK.
3. **Kleine Schritte.** Nach jedem Teilschritt das Spiel über den Godot-MCP
   starten (`run_project`), die Ausgabe prüfen (`get_debug_output`) und alle
   Fehler und Warnungen beheben, bevor du sagst, dass es fertig ist.
4. **Du kannst das Spiel nicht sehen.** Wenn es um Optik geht, bitte mich um
   einen Screenshot und frag konkret, worauf ich achten soll.
5. **Commit nach jedem funktionierenden Schritt** mit einer klaren deutschen
   Commit-Nachricht, z. B. „Meilenstein 2: Terrain-Chunks laden nach“.
   Pushen nur, wenn ich es sage.
6. **Nichts kaputt machen, was schon läuft.** Wenn ein großer Umbau nötig ist,
   erst fragen.
7. Am Ende jedes Meilensteins den Abschnitt „Fortschritt“ unten aktualisieren.

## Assets

- Nur Assets mit freier Lizenz (CC0 bevorzugt): Poly Haven, Kenney, ambientCG.
- Jedes Asset mit Quelle und Lizenz in `assets/CREDITS.md` eintragen.
- Wenn ein Asset fehlt, sag mir genau, was ich wo herunterladen und in welchen
  Ordner ich es legen soll. Bis dahin mit Platzhaltern (Boxen, einfache Farben) arbeiten.

## Meilensteine

1. Auto mit guter Fahrphysik auf flacher Ebene, Kamera folgt
2. Endloses Terrain aus Noise in Chunks, mit Kollision
3. Himmel, Sonne, Tag-Nacht-Wechsel, Schatten, Nebel
4. Prozedurales Straßennetz, das sich ans Gelände anpasst
5. Wasser: Seen, Flüsse, Brücken
6. Vegetation: Bäume, Gras, Felsen (MultiMesh, LOD)
7. Echtes Automodell, Scheinwerfer, Rücklichter, Motorsound
8. Grafik-Politur und Qualitätsstufen, FPS-Anzeige, Einstellungsmenü
9. Verkehr (KI-Autos auf den Straßen) und kleine Orte

## Fortschritt

- [x] Meilenstein 0: Setup geprüft
- [x] Meilenstein 1 (Feinabstimmung der Fahrwerte nach Nicks Probefahrt möglich)
- [x] Meilenstein 2 (Terrain, Horizont-Ring, FPS-Anzeige, Screenshot-Werkzeug)
- [x] Meilenstein 3 (Himmel-Shader, Tag-Nacht, Nebel, Schatten, MetalFX)
- [x] Meilenstein 4 (Straßennetz mit Serpentinen, Geländeanpassung, Start auf Straße)
- [x] Meilenstein 5 (Flüsse, Seen, Wasser-Shader, Brücken, Auto im Wasser)
- [x] Meilenstein 6 (Bäume, Büsche, Felsen, Gras mit Wind, Stamm-Kollision)
- [x] Meilenstein 7 (BMW M2 Competition: Modell, Antrieb, Licht, Spuren, Rauch, Sound)
- [x] Extra: Autoauswahl mit Garage (5 BMW, Profile, Showroom, Sound pro Motor)
- [x] Extra: Minimap mit Navi (Kartenkacheln, Route über Orts-Graphen, Abbiege-Hinweise)
- [x] Extra: Wetter und Jahreszeiten (6 Wetterlagen, Regen mit SSR, Talnebel, Schnee, 4 Jahreszeiten)
- [x] Extra: Tunnel (statt verworfener Abschnitte, Röhre mit Lampen, Portale, Hall, Augen-Anpassung)
- [x] Extra: HUD im Glas-Stil, Garage in der Welt
- [x] Extra: Autobahn ohne Tempolimit (Anschlussstellen, Schilderbrücken, Leitpfosten, Navi)
- [x] Extra: Aussichtspunkte (Parkbucht, Schild, Entdecken, Karte, Sammlung) und Fotomodus
- [x] Extra: Pops & Bangs mit Flammen, Turbo-Pfeifen mit Ladedruck, Abblasventil
- [x] Extra: Regenbogen, Wolkenschatten, Polarlicht
- [ ] Meilenstein 8
- [ ] Meilenstein 9

## Notizen / Entscheidungen

(Hier trägt Claude wichtige Entscheidungen ein, z. B. Chunkgröße, Seed, bekannte Probleme.)

- Godot 4.7.2 (stable), Physik-Engine Jolt (in Godot eingebaut).
- Auto: Heckantrieb (Nicks Wahl), Godots eingebautes `VehicleBody3D`.
- `VehicleBody3D`: Die Nase zeigt nach +Z, `steering` positiv = links.
  `brake` ist ein Impuls pro Physik-Tick (60 Hz), keine Kraft in Newton.
- Godots Standard-Dämpfung (`linear_damp` 0.1) bremst wie Sirup (max. ~100 km/h).
  Beim Auto daher `linear_damp_mode = Replace` mit 0, Luftwiderstand macht `car.gd` selbst.
- Physik-Interpolation ist an. Was dem Auto folgt (Kamera), bewegt sich in
  `_physics_process`, dann bleibt es auch auf 120-Hz-Bildschirmen flüssig.
- Fahrwerte laut Testfahrt (Stand M1, Platzhalter): 0–100 km/h in 5,8 s, Spitze ca. 220 km/h,
  100–0 km/h in 42 m, ca. 1,2 g in Kurven, kippt nicht um.
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
- Autos: fünf Profile in `cars/*.tres` (`CarProfile`): M2 (F87), M3 (E30), M3 GTS (E92),
  M5 Competition (F90), M5 (G90). Alles Auto-Spezifische steht dort (Modell, Teile-Muster,
  Maße, Motor, Getriebe, Allrad-Anteil `front_drive_share`, Bremsen, Sound). `Car.apply_profile()`
  stellt um, auch während des Spiels. Godot übernimmt den Befestigungspunkt eines Rads nur
  beim Einhängen (ENTER_TREE) und die Physik überschreibt die Lage der Rad-Knoten (beim
  eingefrorenen Auto sogar mit Unsinn): deshalb Räder kurz aus- und einhängen und Radmitten
  immer aus dem Profil rechnen (`Car.resting_wheel_center`).
- Gemessen (flache Ebene): M2 4,18 s / 250 / 33,2 m; E30 6,75 s / 234 / 37,5 m;
  E92 4,37 s / 304 / 34,0 m; F90 3,27 s / 250 / 33,1 m; G90 3,52 s / 250 / 33,4 m
  (0–100, Spitze km/h, Bremsweg 100–0). Stellschraube für 0–100: `max_drive_force`.
  Kurve + Vollgas: E30 ~20°, E92 ~20° Driftwinkel, beide M5 bleiben bei ~3° (Allrad).
- Modell-Lader (`car_model.gd`, `CarModel`): lädt im Hintergrund, teilt Rad-Meshes, die alle
  vier Räder enthalten, nach Ecken (E92, F90; Vertex-Listen werden dabei verkleinert, sonst
  hat jedes Teil die Bounding-Box des Ganzen), stellt eingeschlagene Vorderräder gerade (E30:
  Achse = Richtung kleinster Streuung der Punkte), fasst Teile pro Material zusammen (G90:
  1213 → 33 Draw Calls), trennt Licht-Meshes in vorne/hinten. `measured` enthält die am
  Modell gemessenen Maße (Radstand, Spur, Radradius) zum Abgleich mit dem Profil.
- Modell-Texturen: `tools/setup_models.gd` stellt alle auf max. 2048 px, Mipmaps und
  VRAM-Kompression (vorher waren sogar die M2-Texturen unkomprimiert ohne Mipmaps, die
  E30-Texturen 8K). Muss nach jedem neuen Modell-Download einmal laufen (README).
- Garage (`garage.gd`, Taste G, beim Start): eigene 3D-Welt (SubViewport) mit Boden,
  Licht ohne Glanzpunkte (sonst Flecken im Boden), SSR nur dort. Spiel pausiert, Gelände,
  Straßen, Wasser, Gras und Horizont laufen mit `process_mode = Always` weiter (die Welt lädt
  im Hintergrund). Auto und Farbe: `user://einstellungen.cfg`. Tests (`--shot`, `--bench`,
  `--car=ID`) öffnen keine Garage und fahren das angegebene bzw. erste Auto.
- BMW-Modelle (`car_model.gd`): liegen NICHT im Repo (Lizenzen), Anleitung in
  `assets/models/README.md`; ohne Modell fährt die Platzhalter-Box mit gleicher Physik.
  Das Modell wird auf die Physik-Räder skaliert (Radstand). Radgruppen `wms13p*` hängen an
  den VehicleWheel3D (drehen/lenken/federn), Bremssättel `polySurface*` an eigenen Haltern,
  die nur lenken. Die Karosserie heißt im Modell „painted_carbon“ (Carbon-Widebody) und
  bekommt den Lack. Motor ausgeblendet, nur Karosserie/Carbon/Reifen werfen Schatten,
  Innenraum/Felgen/Auspuff mit niedrigerem `lod_bias`. Kostet ca. 3 FPS (74 → 71).
- Licht: zwei SpotLight3D (nur eins mit Schatten), an bei Sonne unter 4° oder per L.
  Rücklicht-Emission wird beim Bremsen heller (`Car.braking`).
- Reifenspuren: MultiMesh-Ringpuffer mit 3000 Stücken, Rauch: GPUParticles3D pro Hinterrad.
  Rutschen pro Rad = `Car.wheel_slip()` (get_skidinfo + Driftwinkel).
- Sound prozedural (`engine_sound.gd`, AudioStreamGenerator 22 kHz): Tabelle mit 6 Zündungen
  pro Arbeitsspiel (720°), je Zylinder etwas andere Lautstärke, Abspielrate = Drehzahl/120.
  Last-/Schub-Tabelle überblendet, dazu Ansaugrauschen, Turbo, Begrenzer, Schaltknall, Quietschen.
- Welt-Formel: `scripts/world_gen.gd` (Resource, im Inspector am Main-Node). Seed 1337.
  Höhe = Talboden (großräumig 60–180 m) + Relief (Hügel + Bergketten bis ~1.900 m).
  Flüsse = Null-Linien eines Rauschens, das Relief wird dort zum Tal abgesenkt.
  Seen = höchstens einer pro 2,5-km-Zelle, Wasserhöhe knapp unter dem tiefsten Randpunkt.
- FastNoiseLite-Falle: Domain Warp hat standardmäßig 5 Stufen mit Faktor 6, das macht
  das Gelände aus der Nähe stachelig. Deshalb `domain_warp_fractal_octaves = 2`.
- Terrain: Kacheln à 256 m, Detailstufen mit 2/4/8/16 m Raster (Grenzen 450/900/1500 m),
  Sichtweite 2 km, Kollision (HeightMapShape3D, skaliert) bis 320 m. Berechnung im
  WorkerThreadPool, max. 2 Kacheln pro Bild einbauen. Schürzen gegen LOD-Lücken.
- Horizont-Ring 0,4–26 km (110 × 720 Punkte). Er versinkt im Shader nur dort, wo schon
  Gelände-Kacheln liegen (`TerrainManager.chunk_mask`, 32 × 32 Pixel = Kacheln um das Auto,
  wird bei jeder fertigen/gelöschten Kachel neu gezeichnet). Am inneren Rand eine Schürze bis
  -400 m. Früher sank er stur im Umkreis von 1,5 km um die Kamera, mit offenem Innenrand bei
  1,2 km: Fehlten die Kacheln noch, hing dort ein „schwebender Felsbogen“ in der Luft.
  Ab 700–1500 m blendet der Terrain-Shader auf die Durchschnittsfarben der Texturen um,
  damit Kacheln und Ring gleich aussehen.
- Sprünge (Reset, Teleport, > 50 m in einem Bild): Fehlt dort Gelände oder liegt der Ring noch
  nicht passend, zeigt `game.gd` den Ladebildschirm und hält das Auto fest, bis alles da ist.
- Laden in Fahrtrichtung: Gelände-Kacheln und Straßen werden vom Punkt 3 s Fahrweg voraus
  (höchstens 400 m) aus sortiert, fehlende Kacheln vor feineren Detailstufen; ab 150 km/h
  rechnen 8 statt 6 Kacheln gleichzeitig (`lookahead_seconds`, `fast_parallel_jobs`).
- Leistung (M2, Vollbild 2940×1846): ~93 FPS, Ruckler nur beim allerersten Laden.
  Im Fenster lässt macOS V-Sync nicht abschalten, für FPS-Messungen `--fullscreen` nutzen.
- Testen: `Godot --path . -- --shot=NAME --pos=X,Z --heading=G --fly=H --time=H` speichert
  `screenshots/NAME.png`. `-- --bench=20` misst FPS (siehe `scripts/debug_tools.gd`).
  `--carview=G` stellt die Kamera neben das Auto (0 = vorne, 180 = hinten), `--steer=left`
  lenkt dabei (Vorderräder prüfen), `--car=e30` startet mit diesem Auto. `--nowait` macht das
  Foto, ohne auf die Kacheln zu warten, `--jump=X,Z` springt nach dem Laden weit weg.
- Tasten: WASD fahren, Leertaste Handbremse, R aufrichten, T Zeitraffer, F3 FPS,
  C Lackfarbe, K Aufkleber, L Licht, G Garage (← → Auto, C Lack, Enter losfahren, Esc zurück),
  M große Karte (Linksklick Ziel, Rechtsklick
  Ziel löschen, Mausrad zoomen, ziehen verschiebt), F5 Wetter (Automatisch → Klar → Bewölkt →
  Regen → Gewitter → Nebel → Schnee), J Jahreszeit, P Fotomodus (Maus ziehen schwenkt,
  W A S D / Q E bewegen, Mausrad Zoom, 1–4 Filter, ↑ ↓ Belichtung, ← → Tageszeit,
  F Schärfe aufs Auto, Leertaste Foto, O Foto-Ordner, P/Esc zurück).
- Karte und Navi: `map_tiles.gd` rechnet das Kartenbild (Höhenfarbe, Schattierung, Wald,
  Wasser) in Kacheln à 128 px im Hintergrund (Stufen 4/16/64 m pro Pixel, max. 400 gemerkt).
  `map_view.gd` zeichnet darüber Straßen, Route, Ziel, Auto in Weltkoordinaten (eine
  Transform, Straßenlinien pro Abschnitt einmal gemerkt). Minimap unten links (dreht mit,
  Zoom 1,3–4 m/px nach Tempo, runde Maske über `clip_children`), große Karte mit M.
  Navi (`navigation.gd`): A* über den Orts-Graphen (Orte/Verbindungen stehen ohne Wegsuche
  fest); berechnete Abschnitte mit echter Länge, unbekannte mit Luftlinie × 1,35, weggefallene
  (`RoadNetwork._missing`, bleibt gemerkt) gar nicht. Ziel rastet auf eine fertige Straße
  (bis 80 m) oder auf den nächsten Ort mit Verbindung ein (sonst unerreichbar: Orte, deren
  Straßen alle zu steil sind). Suche höchstens doppelte Luftlinie + 5 km. Jede Sekunde:
  weggefallen → neu planen, neu berechnet → Linie verfeinern; > 40 m daneben für 3 s → neu.
  14 km Route: ~25 ms. Geschätzte Teile der Route gestrichelt.
- Leistung: Gelände- und Straßen-Manager prüfen ihre Umgebung nur alle 0,1 s (und sofort,
  wenn ein Auftrag fertig ist), Gelände fragt pro Prüfung höchstens 6 wartende Kacheln nach
  Straßen. Vorher kosteten sie 6,7 ms pro Bild, jetzt ~0,9 ms (`update_interval`).
  Messen: `-- --bench=60` gibt jetzt auch process_ms und physics_ms aus. Achtung: nach einer
  Stunde Dauertest war selbst der alte Stand (M7) headless 2,5-mal langsamer (Wärme).
- Wetter (`weather.gd`): 6 Wetterlagen als Wertetabelle (Wolken, Trübheit, Regen, Schnee,
  Nebelfaktor, Talnebel, Wind, Blitze), Übergang 45 s (F5: 8 s, Garage: sofort), automatischer
  Wechsel alle 3–6 min, Wahrscheinlichkeit je Jahreszeit (Herbst mehr Regen/Nebel, Winter
  Schnee). Gespeichert in `user://einstellungen.cfg` (Abschnitt `welt`). Tests (`--shot`,
  `--bench`) laufen immer klar/Sommer, außer mit `--weather=rain|storm|fog|snow|cloudy` und
  `--season=spring|autumn|winter`.
- Die Shader bekommen Wetter und Jahreszeit über globale Shader-Werte (Projekteinstellungen >
  Shader Globals): `wetness`, `road_snow`, `snow_cover`, `snow_line`, `season_spring/autumn/winter`
  (weiche Gewichte), `rain_amount`, `weather_wind`. Nässe steigt in 40 s Regen auf 1 und trocknet
  in 4 min; Schnee auf der Straße liegt nach 60 s, ist 2 min nach dem Schneefall geräumt.
  Grip: nass 0,7, Schnee 0,5 (`Car.grip_factor`), Gischt hinter den Hinterrädern (`Car.wetness`).
- Regen-Spiegelungen: SSR nur bei Nässe an. Kostet im Vollbild ~2,5 ms (66 → 54 FPS). Deshalb
  schaltet DayNight bei bedecktem Himmel (overcast > 0,75) die Sonnenschatten aus (gibt es bei
  Bedeckung ohnehin nicht). Schlussmessung (Vollbild, `--bench=60`, Mac warm): klar 68,8 FPS,
  Regen 61,3 FPS, 1%-Low ~50 (Ruckler beim Kachel-Laden, wie vorher). SSR abschalten:
  `wet_reflections` am Weather-Node.
- Regen/Schnee (`precipitation.gd`): GPUParticles in einem 36 × 22 × 36-m-Kasten um die Kamera,
  eigener Partikel-Shader schiebt herausfallende Partikel auf die andere Seite (bei jedem Tempo
  gleich dicht). `fixed_fps = 0` und `interpolate = false`, sonst Striche beim Umklappen.
  Regenstriche zeigen in Richtung (Fallgeschwindigkeit − Kamerageschwindigkeit).
- Talnebel (`valley_fog.gdshader`): Bildschirm-Viereck an der Kamera, rechnet aus dem
  Tiefenpuffer die Nebelmenge entlang des Blicks (Dichte nimmt über dem Talboden `ground_level`
  exponentiell ab, Integral exakt). Godots Höhennebel geht nicht: der hängt nicht vom Abstand ab
  und vernebelt das Auto direkt vor der Kamera. Morgens (2–11 Uhr) je nach Jahreszeit/Wetter.
- Jahreszeiten: Laubbäume/Büsche bekommen eine Kopie des Blattmaterials mit `deciduous = true`
  (Frühling hellgrün, Herbst je Baum gelb/orange/rot). Winter: Laubbäume bekommen
  `foliage_bare.gdshader` (Krone per discard ausgedünnt), nur dann, weil discard Leistung kostet.
  Schnee auf Bäumen/Gelände dort, wo die Fläche nach oben zeigt. Schneefallgrenze je Jahreszeit
  750/950/850/250 m. Gras verschwindet unter Schnee.
- Wetter-Geräusche (`weather_sound.gd`): Regen-/Windschleife und 3 Donner, beim Start im
  Hintergrund erzeugt. Donner kommt Entfernung/343 s nach dem Blitz.
- Tunnel (`road_segment.gd`): Liegt die Fahrbahn mehr als 25 m unter dem Gelände
  (`TUNNEL_DEPTH`), wird ein Tunnel daraus, verlängert bis dorthin, wo es nur noch 12 m sind
  (`PORTAL_DEPTH`, dort sind die Portale). Lücken bis 32 m werden geschlossen, im Tunnel ist die
  Steigung gleichmäßig. Früher fielen solche Abschnitte weg (MAX_CUT 35 m), jetzt nur noch bei
  Tunneln über 3 km. Ist der normale Weg 1,15-mal länger als die Luftlinie (oder ungültig),
  rechnet die Wegsuche eine zweite Variante, die Berge durchbohren darf (Gelände über dem
  tiefsten Punkt im Umkreis von 216 m + 20 m zählt als Tunnel, kostet doppelt + 150 pro Tunnel).
  Sie gewinnt nur mit Tunnel und wenn sie 10 % günstiger ist, sonst bleibt die Straße wie vorher.
  Ergebnis rund um den Start: ~6 % der Abschnitte mit Tunnel, meist 0,5–2,9 km lang.
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
- Im Tunnel (`tunnel_effects.gd`): Abdeckung 0–1 aus `RoadNetwork.tunnel_cover()` (ab dem
  Portal über ~20 m), 8 echte OmniLights an den nächsten Lichtpunkten (alle 0,2 s neu verteilt),
  Audio-Bus „Tunnel“ mit Reverb für alle Geräusche des Autos, Weather.shelter (kein Regen,
  trockene Reifen), DayNight: kein Himmelslicht und keine Himmels-Spiegelung, Augen-Anpassung
  (Belichtung bis 2,4-fach, dunkel werden langsamer als hell), ohne Sonnenschatten keine Sonne.
  Abblendlicht geht im Tunnel automatisch an (`Car.in_tunnel`). Karte: Tunnel gestrichelt.
- Testen: Tunnel nahe am Start, z. B. `-- --shot=t --pos=-1562,-8360 --heading=-29` (vor dem
  Portal, 500 m lang), innen `--pos=-1798,-8254 --heading=-64`. Leistung im Vollbild: Tunnel-
  strecke 67 FPS, Startstrecke 66,8 (Mac warm). Im Fenster begrenzt macOS auf 60 (V-Sync).
- HUD und Menüs (Entwurf „Glas“, `screenshots/design_*.png`): gemeinsamer Stil in `ui_style.gd`
  (Farben, Akzentfarbe, Schrift Inter mit gleich breiten Ziffern über OpenType „tnum“), Symbole
  werden gezeichnet (`ui_icons.gd`, keine Bilddateien). Grundgröße 1600 × 900, Stretch
  „canvas_items“ skaliert alles mit dem Fenster (Fenster startet mit 1280 × 720). Teile:
  `speedometer.gd`, `minimap.gd`, `nav_banner.gd`, `status_chips.gd`, `toasts.gd` (Meldungen
  von überall: `Toasts.post(get_tree(), Symbol, Titel, Text, Taste, Tastentext)`).
- Glas (`glass_panel.gd`): Echte Unschärfe (`glass.gdshader`, Bildschirmtextur) kostet auf dem
  Mac ~1,7 ms pro Bild, egal wie viele Panels: Godot muss dafür das Zeichnen unterbrechen
  (gemessen abwechselnd, 1280×720-Fenster: ohne HUD 134,7 FPS, mit unscharfem HUD ~110).
  Deshalb nur, wo das Spiel pausiert (Garage, große Karte, Fotomodus). Das HUD beim Fahren ist
  nur getönt (`glass_tint.gdshader`, Deckkraft 0,64) und kostet praktisch nichts. Umschalten:
  `blur` am GlassPanel. Mipmaps der Bildschirmtextur waren noch teurer; BackBufferCopy mit
  Ausschnitt lieferte in dieser Anordnung nur Schwarz.
- Garage: pausiert das Spiel und zeigt das echte Auto in der Welt (Kamera kreist, Maus ziehen
  dreht), öffnet beim Start erst, wenn die Welt geladen ist. Autowechsel sofort am echten Auto
  (Räder dabei in Ruhelage setzen, sonst stehen sie dort, wo die Physik sie beim Laden
  hingestellt hat). Welt-Umschalter ändern Uhrzeit (`DayNight.set_time`), Wetter und Jahreszeit
  sofort. Gespeichert: Auto, Lack, HUD-Farbe (`hud/akzent`), Sportauspuff (`auto/sportauspuff`).
- Temperatur (`Weather.temperature`): Jahreszeit 12/22/11/−1 °C, ±5 °C über den Tag (am
  wärmsten 15 Uhr), −0,65 °C pro 100 m über 100 m, Wetter −2 bis −5 °C, beim Schneien ≤ 1 °C.
- Testen: `--nohud` blendet das HUD aus, `--hide=Minimap,Speedometer` einzelne Teile. Messungen
  streuen stark mit der Temperatur des Macs: immer abwechselnd mit/ohne messen.
- Autobahn (`highway_layout.gd`, Art HIGHWAY in `road_segment.gd`): Linien west–ost und
  nord–süd alle ~6 km (75 % gibt es), Stützpunkte alle 1,6 km. Seitenlage = glattes Rauschen
  (Stützwerte alle 4 Stützpunkte, ±900 m, im Tal gesucht) plus ±120 m lokale Suche. Mittellinie
  ohne Wegsuche: gerade Stücke an den Stützpunkten (150 m, an möglichen Anschlussstellen 310 m),
  dazwischen Hermite-Kurve. Warum: Unabhängige Stützpunkte (±400 m) ergaben S-Kurven mit
  ~340 m Radius, der Autopilot flog bei 250 km/h in die Brüstung.
- Autobahn gemessen auf 40 × 40 km: 234 Abschnitte, alle gültig, kleinster Radius 888 m,
  Steigung ≤ 4 % (Notlösung: liegen Stützpunkte zu weit übereinander, steigt `max_grade` etwas,
  einmal 4,2 %, statt einer Lücke), Tunnel 34 %, Brücken 14 %, Anschlussstelle etwa alle 5 km.
  Autobahn 0,23 km/km², Landstraßen 0,97 km/km² → **Anteil Autobahn 19 %**.
- Querschnitt 25,5 m: je Richtung 2 × 3,75 m plus 2,5 m Standstreifen, Mittelstreifen mit
  Leitplanke, Leitpfosten alle 48 m mit Rückstrahlern (`reflector.gdshader`, leuchten im
  Scheinwerferlicht), Querneigung bis 2,5 %. Shader `road.gdshader`: `lane_profile` 0/1/2 =
  Landstraße/Autobahn/Rampe.
- Anschlussstellen (Raute) an jedem 2. Stützpunkt, wenn ein Ort 220–900 m daneben liegt und
  Richtung Autobahn Platz hat (≥ 50° zu seinen Straßen). Der Zubringer verlässt den Ort in
  einer freien Richtung, schwenkt im Bogen und überquert die Autobahn rechtwinklig (endet 150 m
  dahinter). Rampen 280 m. Schlüssel: Autobahn (k, Linie, 2 + Achse), Anschlussstelle
  (k, Linie, 10 + 10·Achse + Teil), Teil 0 = Zubringer, 1–4 = Ausfahrt/Einfahrt links/rechts.
  Orte entstehen nicht näher als 220 m an einer Autobahn (`HighwayLayout.is_clear`), haben
  erfundene Namen (`place_name`), Ausfahrt-Nummern zählen pro Linie hoch.
- Kreuzungen: Nord–Süd wartet auf West–Ost, Landstraßen/Zubringer/Rampen auf alle Autobahnen.
  Wer später kommt, führt ≥ 7,5 m darüber (immer als Brücke) oder 7 m unter einer hohen Brücke
  durch; liegt die andere im Tunnel, 9 m Abstand (gilt auch beim Begradigen des Tunnels).
  Die Überlappungsprüfung übergeht Paare mit ≥ 6 m Höhenunterschied.
- Gelände: Böschungs-Halbkreise an Stückenden entfallen, wenn in ihrer Reichweite eine Brücke
  oder ein Tunnel beginnt (sonst Erdbuckel quer über der Fahrbahn am Brückenanfang).
- Schilder: blaue Schilderbrücken 2000 m und 500 m vor der Ausfahrt (Nummer, Ort, Entfernung),
  Ausfahrt-Schild am Rampenbeginn. Label3D zeigt Text nach +Z: mit
  `Basis.looking_at(Fahrtrichtung)` ist er für den Verkehr lesbar.
- Navi mit Autobahn: Knoten = Orte und Autobahn-Stützpunkte je Fahrtrichtung (Vector4i),
  Kosten = Fahrzeit (Landstraße 70, Autobahn 130 km/h). Ansagen „Auf die Autobahn“ und
  „Ausfahrt 5 nehmen“ mit Ortsname. Test 17 km: 8,5 min über die Autobahn statt 26 min,
  Planen 13 ms. Karte: Autobahn breit und gelb, Rampen schmal.
- Laden: Abschnitte außer Landstraßen werden erst 4,5 km weiter weg vergessen
  (`HIGHWAY_FORGET_EXTRA`), sonst Endlosschleife (Abhängigkeit gebaut und sofort vergessen).
- Testen: `--highway` startet auf der Autobahn (rechte Spur), mit `--bench` fährt der
  Autopilot dort Vollgas (Kurven mit 9 m/s², 700 m Vorausschau). `--target=X,Z` setzt vor dem
  Foto ein Navi-Ziel. M3 GTS (`--car=e92`, 70 s): 4,8 km, Spitze 304 km/h, max. 2 m neben der
  Spur, ~147 FPS, 1%-Low 84, schlechtestes Bild 16–20 ms, kein Nachlade-Ruckler (Fenster
  1280 × 720; macOS übergeht `--fullscreen` beim Benchmark). Im Fenster zählt `process_ms` die
  V-Sync-Wartezeit mit (~21 ms), das ist kein echter Wert.
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
- Fotomodus (`photo_mode.gd`, Taste P): pausiert, HUD aus, eigene Kamera (max. 30 m vom Auto,
  Strahl Auto→Kamera verhindert Gelände/Wände dazwischen, nicht unter den Boden). Schärfe
  = DOF der Kamera auf die Entfernung zum Auto, Belichtung = `exposure_multiplier`, Filter =
  Bildschirm-Shader (`photo_filter.gdshader`). Foto ohne Bedienfeld und Meldungen nach
  `user://fotos/foto_DATUM_ZEIT.png`; die Tageszeit wird beim Verlassen zurückgestellt.
- Testen: `--photo --filter=1` macht das Foto im Fotomodus, `--map` mit großer Karte. Beide
  halten das Spiel an, dann läuft DebugTools mit `PROCESS_MODE_ALWAYS` weiter.
  Aussichtspunkt am Start: `--pos=433,-861 --heading=57` (Aussicht bei Bergmünster).
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
- Regenbogen (`sky.gdshader`): Hauptbogen 40–42,8° um den Gegenpunkt der Sonne (rot außen),
  schwacher Nebenbogen 50–53,5° (umgekehrt). Weather startet ihn, wenn ein Regen aufhört
  (4 min, die letzten 2,5 min blendet er aus), DayNight zeigt ihn nur bei Sonnenhöhe 1–41° und
  wenn es aufgeklart ist. Test: `--rainbow --time=18`, Blick nach Osten.
- Polarlicht (`sky.gdshader`, `aurora_light`): 14 Schichten übereinander, jede ein welliger
  Streifen am Nordhimmel (−Z), unten grün, oben violett; Strahlen hängen vom Azimut ab (laufen
  im Zenit zusammen wie echte). In klaren Winternächten, jeden Abend mit Chance 1/3 gewürfelt,
  blendet über 1,5 min ein. Test: `--aurora --season=winter --time=23`, Blick nach Norden.
- Wolkenschatten (`cloud_shadow.gdshaderinc`, in Gelände, Straßen, Bäumen und Gras): Rauschmuster
  (`assets/textures/cloud_shadows.tres`, globaler Shader-Wert) im 1,4-km-Maßstab, zieht mit dem
  Wind (`cloud_shadow_wind` × Wetter-Wind). Bedeckung aus dem Wetter: klar ~15 %, bewölkt gut die
  Hälfte im Schatten, darin 50 % dunkler; bei Regen/Nacht aus. Bäume und Gras nehmen den Wert
  an ihrem Standort (Vertex-Shader).
- Neue `class_name`-Skripte erst nach `Godot --headless --path . --import` bekannt, sonst
  meldet ein Start ohne Editor „Could not find type“.
- Himmel: eigener Sky-Shader (`shaders/sky.gdshader`), Farben kommen aus Farbverläufen in
  `day_night.gd` (Sonnenhöhe -18° bis +40°). Nachts wird das Sonnenlicht zum Mondlicht.
  Sky-Radiance `process_mode = Incremental` (Realtime kostet merklich FPS).
- Tonemapping AgX, Glow, SSAO, Fernnebel mit Luftperspektive. Volumetrischer Nebel aus
  (Schalter `volumetric_fog` an DayNight, Test mit `--volfog`).
- Render-Skalierung: MetalFX Temporal mit 75 % (Projekteinstellungen > Rendering >
  Scaling 3D). Vollbild Retina: ~98 FPS statt 69 ohne Skalierung.
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
- Leitplanken: außen in Kurven unter 45 m Radius und wo das Gelände 14 m daneben über 4 m
  tiefer liegt (eigenes Material `rail_material`, mit Kollision). Brücken haben Brüstungen.
- Gelände an Straßen (`road_query.gd`): Fahrbahn ist immer „hart“, daneben Böschung mit
  Neigung 0,65; bei mehreren Straßen müssen alle Höhenbereiche gleichzeitig gelten
  (sonst Wände zwischen Serpentinen-Ästen).
- Gelände-Kacheln warten, bis alle Straßen in ihrer Nähe berechnet sind.
- Testen: `-- --bench=60` fährt per Autopilot die Straßen ab (Stand M4: 4 km am Stück,
  ~80 km/h im Schnitt, Vollbild ~98 FPS, 1%-Low 77 FPS).
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
- Leistung: Das MacBook Air (ohne Lüfter) drosselt nach mehreren Benchmarks hintereinander
  deutlich (98 → 65 FPS). Für Vergleiche immer mit kühlem Mac messen.
- Vegetation (M6): Modelle werden im Code gebaut (`vegetation_meshes.gd`), weil Poly Havens
  Bäume Millionen Dreiecke haben und Kenney Comic-Stil ist. Fichte ~180, Laubbaum ~150
  Dreiecke, ferne Versionen ~15. Bäume/Büsche/Felsen verteilt die Gelände-Kachel im
  Hintergrund (festes Zufallsraster pro Kachel, deterministisch), MultiMesh pro Art und Kachel,
  bis Detailstufe 2 (~1,5 km), Schatten nur Detailstufe 0. Gras: `grass_manager.gd`,
  16-m-Felder bis 56 m ums Auto, 3 Büschel/m².
- Bäume/Büsche/Felsen halten Abstand zur Straße nach Kronenradius (+ Böschungskante), wachsen
  nicht unter Brücken, auf Kreuzungen oder wo das Gelände für die Straße verändert wurde.
  Höhe exakt wie im Mesh (zwei Dreiecke pro Quadrat), Stämme sinken am Hang etwas ein.
- Vertex-Farben kommen im eigenen Shader unverändert an (kein sRGB → linear). Deshalb rechnet
  `foliage.gdshader` sie selbst um, sonst sind die Bäume knallgrün.
- Kollision von Stämmen/Felsen direkt über den PhysicsServer, ein Körper pro 64 × 64 m.
  Ein Körper mit 1000 Formen kostete 33 ms (Ruckler), so sind es ~3,5 ms pro Kachel.
- Leistung (Stand M6, Vollbild 2940×1846, MetalFX 75 %, Mac schon warm): ~68 FPS im
  Schnitt, 1%-Low ~55. Nach dem Straßen-Umbau: 74 FPS, 1%-Low 57. Stellschrauben: `vegetation_max_lod`, `tree_spacing`,
  Gras `radius`/`density`, Render-Skalierung.
