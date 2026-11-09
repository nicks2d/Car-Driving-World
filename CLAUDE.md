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
- [x] Extra: Tunnel-Bug behoben, mehr Grip (Grip-Stufen), Blinker/Warnblinker/Hupe
- [x] Extra: Anschlussstellen an jedem Stützpunkt, Raststätten mit Tankstelle und Rasthof
- [x] Extra: Drei neue Garage-Autos (M4 CSL, SL 65, C 63) mit Marken-Reitern
- [x] Extra: Verkehr mit echten Modellen, Verzögerungs- und Beschleunigungsstreifen
- [x] Meilenstein 8 (Pausemenü, Einstellungen mit 5 Reitern, Qualitätsstufen, Tastenbelegung, Audio-Busse)
- [x] Meilenstein 9 (Dörfer mit Häusern, Ortsschildern, Laternen; Verkehr mit KI-Autos)

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
  W A S D / R F bewegen, Mausrad Zoom, 1–4 Filter, ↑ ↓ Belichtung, ← → Tageszeit,
  G Schärfe aufs Auto, Leertaste Foto, O Foto-Ordner, P/Esc zurück), Q Blinker links,
  E Blinker rechts (noch mal = aus), X Warnblinker, H Hupe, Esc Pausemenü (dort Einstellungen;
  alle Tasten außer Esc lassen sich unter Steuerung neu belegen).
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
- Leistung nach Autobahn, Aussichtspunkten, Pops und Himmel (Autobahn-Benchmark 25 s,
  1280×720-Fenster, alles nacheinander auf demselben, inzwischen heißen Mac): Stand Teil 3
  53,7 FPS, vor Teil 6 50,9, mit allem 50,7 (1%-Low ~20). Teil 4–6 kosten also ~5 %; Teil 6
  (Himmel, Wolkenschatten) nichts Messbares. Derselbe Stand Teil 3 lief mit kühlem Mac mit
  147 FPS: Nach Stunden Dauertest drosselt das MacBook Air auf etwa ein Drittel. Messungen für
  „≥ 60 FPS“ nur mit kühlem Mac. Auch die Ladezeit schwankt dann stark (gleicher Code 6,7 s /
  13 s), und nach Shader-Änderungen dauert der erste Start länger (Shader werden neu übersetzt).
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
- Prüfwerkzeug `tools/tunnel_check.gd` (Aufruf im Kopf der Datei): rechnet für jede Röhre
  in der Nähe von 6 Stellen alle Detailstufen wie im Spiel und prüft alle 4 m an 5 Querpunkten,
  ob Gelände zwischen Fahrbahn und Decke liegt, nah am Auto auch die Kollision per Strahl.
  Vorher 108 Stellen (12 in Stufe 0), jetzt 0 bei 34 Röhren / 25 km. Autopilot (`--bench`)
  zählt jetzt auch die Meter im Tunnel. Testtunnel: Landstraße `--pos=-1700,-8262
  --heading=-80`, Autobahn `--pos=-5056,-63 --heading=85 --highway` (272 m).
- Achtung bei eigenen Prüfskripten (`-s`): Ohne Testargument öffnet nach dem Laden die
  Garage und pausiert das Spiel, dann kommt z. B. ein `jump_to` nie an. Garage schließen.
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
- Blinker (`car_signals.gd`, Knoten „Signals“ im Auto): Zustand am Auto (`turn_signal` 1 links /
  -1 rechts, `hazard`, `signal_lit`), Takt 1,5 Hz. Leuchten = kleine orange Kästchen an den
  Punkten aus `indicator_points` (links gemessen, rechts gespiegelt: äußere Ecke der Scheinwerfer
  bzw. Rückleuchten, breitester Punkt oben vor der A-Säule = Spiegel), nachts je Seite zwei
  OmniLights ohne Schatten. Aus nach der Kurve: Lenkrad erst über 0,35, dann unter 0,08.
  Vollbremsung (Bremse ≥ 0,8 über 100 km/h) → Warnblinker, aus nach Stillstand und
  Wiederanfahren über 20 km/h. Klicken = zwei kurze im Code erzeugte WAVs, Hupe =
  AudioStreamGenerator mit zwei Tönen je Auto (`horn_tones`, z. B. M2 410/505 Hz) plus
  Obertönen. HUD: grüne Pfeile oben im Tacho-Panel, rotes Warndreieck. Test: `--signal=left`.
  Fotomodus: rauf/runter jetzt R/F, Schärfe G (Q/E sind die Blinker).
- Raststätten (Teil 4, `HighwayLayout.rest_area_at`): je Fahrtrichtung in einem Fenster von
  5 Stützpunkten alle 11 (17,6 km), am ersten Stützpunkt, an dem Autobahn und Parkplatz an der
  Oberfläche liegen (Gelände ±12 m, trocken), bevorzugt dort, wo keine Anschlussstelle geht
  (beide schließen sich aus). Gemessen auf 40 × 40 km: 26 Raststätten, auf offener Strecke
  etwa alle 17–20 km je Richtung, 11 mit Bergblick. Name „Rastanlage“ + Ortsname der Zelle.
  Schlüssel (k, Linie, 40 + 10·Achse + 0/5 je Richtung + Teil), Teil 0 = Parkplatz, 1 =
  Ausfahrt, 2 = Einfahrt (Art RAMP, Bezier, flach auf Stützpunkt-Höhe).
- Parkplatz (`_make_rest_segment`, Shader-Profil 3): 220 × 46 m, 78 m neben der Autobahn-Mitte.
  Quer vom autobahnseitigen Rand: Fahrgasse 0–9 m, drei Reihen Stellplätze (along 12–145),
  dahinter die Tankstelle ohne Markierung, ab 34 m heller gepflasterter Vorplatz. Gerade
  Enden (`RoadSegment.square_ends`, Kappe 2 in `road_query.gd`): sonst ebnen die Halbkreise der
  Stücke einen 25-m-Erdfleck hinter das Parkplatzende.
- Ausstattung (`RoadNetwork._add_rest_props`, Kästchen wie die Schilder): Tankstellendach
  20 × 34 m mit leuchtender Unterseite, 3 Zapfsäulen-Inseln, Kasse, Mast „Tankstelle“, Rasthof
  (10 × 34 m, Fensterfront), Laternen alle 40 m, Bänke, Bäume, bei Aussicht braunes Schild
  „Seeblick“/„Bergblick“. Nachts: Leucht-Materialien heller (`_update_night_glow`, alle 0,25 s)
  und 3 OmniLights ohne Schatten pro Raststätte, nur bis `rest_light_distance` (260 m) am Auto.
  Schilder: blau 2000 m und 500 m vorher (Ort, „Rastanlage“, Zapfsäule und Tasse, Entfernung),
  „Rastanlage“ am Beginn der Ausfahrt.
- Karte: Zapfsäule im Kreis an jeder Raststätte (bis 24 m/px, gesucht pro 4-km-Feld, höchstens
  zwei neue Felder pro Bild). Navi: Klick bis 150 m an eine Raststätte = Ziel; Route über den
  Stützpunkt davor, Ausfahrt, Parkplatz (Ansage „Zur Rastanlage“). Steht man schon davor oder
  darin, direkt. Raststätten mit Aussicht zählen als Aussichtspunkt („R…“-Kennung, entdeckt
  unter 5 km/h bis 110 m an der Mitte), auf der Karte als Abzeichen neben der Zapfsäule.
- Autobahnkreuz: nicht gebaut. Kreuzungen zweier Autobahnen bleiben Überführungen (die
  Schleifenrampen bräuchten eigene Trassierung zwischen Tunneln und Brücken).
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
- Verkehr (Teil 5, `traffic.gd`, Knoten „Traffic“): KI-Autos fahren kinematisch (keine
  Fahrphysik, sonst zu teuer und unberechenbar) auf Stücken (`Leg`: Abschnitt, Richtung, von/bis
  in Metern, Spur rechts der Mittellinie). Spuren: Landstraße 2,25 m, Autobahn rechts 8,375 /
  links 4,625 m (wie im Shader), Rampenanfang 15,55 m, Fahrgasse Raststätte −18,5 m. Am Ende
  eines Stücks: nächstes wählen (an Kreuzungen zufällig, Sackgasse = wenden) und eine kurze
  Hermite-Kurve dorthin fahren. Tempo: IDM (Abstand 4 m + 1,4 s, angenehm 3 m/s² bremsen,
  höchstens 9), Wunschtempo Landstraße 65–100 (Lkw 62–80), Orte 50 (170 m um die Ortsmitte),
  Autobahn Lkw 82–89 rechts, Pkw 110–175, 12 % „Schnelle“ 185–230 bleiben gern links;
  Kurven √(2,6 m/s² · R); Nässe/Schnee bis 30 % langsamer (`Car.grip_factor`).
- Autobahn: rechts fahren, bei langsamerem Vordermann links überholen (Spur frei? schnellere
  Autos von hinten zählen weiter), zurück nach rechts, wenn dort 2 s frei ist (Schnelle 6 s).
  Blinker bei jedem Spurwechsel. Abfahren wird beim Einfahren in einen Autobahn-Abschnitt
  gewürfelt: Raststätte 15 % (Ausfahrt → Parkplatz → Einfahrt → weiter), Anschlussstelle 15 %
  (Rampe → Zubringer → Ort); an Orten mit Zubringer 30 % auf die Autobahn. Vor der Ausfahrt
  260 m lang rüber auf die Rampe, 900 m vorher nicht mehr überholen.
- Dichte: Landstraße 1 Auto pro 2,5 km je Richtung, Autobahn 1 pro 450 m je Richtung (im
  Umkreis von 1 km gezählt), höchstens 25, mal `density` (0/0,5/1). Entstehen 280–1050 m weg,
  unter 650 m nur hinter der Kamera; verschwinden über 1300 m, über 650 m hinter der Kamera
  oder wenn ihre Straße nicht mehr geladen ist. Nach dem Ladebildschirm 1,5 s „Füllen“: dann
  auch 60–400 m vom Spieler (die Welt ist sofort belebt).
- Fahrzeuge (Teil 3 der Modell-Sitzung): Pkw sind echte Modelle (`TYPES` in `traffic.gd`):
  Audi S3 und Accord häufig (je 30/26 von 100 auf Landstraße/Autobahn), ID. Buzz mittel (16/11),
  Aztek (7/5) und LC 500 (5/7) selten; der LC 500 ist zu 60 % einer der „Schnellen“ links
  (sonst 5–12 %). Kombi und gebauter Transporter entfallen, der Lkw bleibt gebaut. Lackfarben
  gewichtet (`PAINTS`): je ~19 % Weiß/Schwarz, 16 % Grau, 14 % Silber, selten Blau, Rot, Grün,
  Beige, Bordeaux. Jedes Modell wird einmal im Hintergrund geladen (`load_threaded_request`,
  bis dahin die gebaute Version). Drei Stufen über Godots Sichtbarkeitsbereiche (kein Skript
  pro Bild): bis `near_distance` 60 m das volle Modell (~50–70k Dreiecke, eigene Rad-Meshes, die
  sich drehen), bis `mid_distance` 220 m die mittlere Stufe (Räder als Zylinder), dahinter die
  gebaute Kiste in Lackfarbe (auch Ersatz, wenn das Modell fehlt). Je Stufe 6–7 Draw Calls
  (eine Fläche pro Rolle). Schatten nur bis 120 m (nah/mittel), die ferne Kiste nie.
  Bremslicht = Material-Tausch der Fläche „tail“, Blinker am Modell = zwei kleine Kästchen je
  Seite an `front_corner`/`rear_corner`, nur sichtbar, solange sie leuchten. Materialien ohne
  Backface-Culling (viele Modellteile sind einseitig). Kollision = Box aus Länge/Breite/Höhe.
- Accord hatte keine eigene Scheinwerfer-Fläche: `setup_traffic_models.gd` nimmt dann die
  Karosserie-Dreiecke direkt hinter der vorderen Leuchten-Abdeckung als Scheinwerfer.
- Leistung Modelle vs. Kästchen (Autobahn-Benchmark 30 s, Verkehr Normal, Hoch, `--full`,
  abwechselnd gemessen, Mac heiß auf Akku 37 %): Kästchen 23,4 / 24,1 FPS, Modelle 22,9 / 23,3
  FPS (1%-Low 14 beide) → Modelle kosten ~3 %. Absolutwerte nur mit kühlem Mac vergleichbar.
- Testen Verkehr: `--boxcars` (ohne Modelle), `--lineup=M` stellt vor dem Foto von jedem Typ ein
  stehendes Auto M Meter vor den Spieler (Autobahn abwechselnd rechts/links, jedes zweite
  blinkt, jedes dritte Warnblinker), z. B. `--pos=8790,-4056 --highway --heading=90 --fly=2.2
  --pitch=-4 --lineup=8 --traffic=0.01` (nachts `--time=22.5`).
- Gemessen (Prüfskripte, 90 s): an der Raststätte Falkenweiler 7 von 19 Autobahn-Autos über
  den Parkplatz, an der Anschlussstelle bei (3200, −4060) Ab- und Auffahrten (Rampe 4,
  Zubringer 5), 13–32 Spurwechsel, kein Auto festgefahren, kleinster Abstand in einer Spur 4 m.
  Autopilot 60 s mit Verkehr (Fenster): Landstraße 139 FPS, Autobahn 121 FPS, keine Fehler.
- Pausemenü (Teil 6, `pause_menu.gd`, Esc): Glas mit echter Unschärfe (Spiel pausiert),
  Weiterfahren, Garage, Karte, Fotomodus, Einstellungen, Spiel beenden (zweiter Klick).
  Esc öffnet nur, wenn nichts anderes pausiert hat; in den Einstellungen geht Esc zurück.
- Einstellungen (`game_settings.gd`, Knoten „Settings“): Reiter Grafik, Anzeige, Steuerung,
  Audio, Spiel; alles wirkt sofort, gespeichert in `user://einstellungen.cfg` (Abschnitte
  grafik, anzeige, steuerung, tasten, audio, spiel), „Zurücksetzen“ je Reiter. HUD-Farbe und
  Sportauspuff bleiben bei der Garage ([hud]/[auto]), automatisches Wetter = `Weather.mode`.
  Testläufe (Argumente) nehmen die Standardwerte und speichern nichts; `--quality=niedrig|
  mittel|hoch|ultra` wählt die Stufe, `--pause=0..5` macht ein Foto mit Menü (0 = Pause,
  1–5 = Reiter).
- Qualitätsstufen (`GameSettings.PRESETS`): Render-Auflösung 55/65/75/100 %, Sichtweite
  1,3/1,7/2,0/2,6 km, Schatten Niedrig/Mittel/Mittel/Hoch (150/300/300/500 m, Karte
  2048/4096), Vegetation 60/80/100/100 %, Gras Wenig/Normal/Normal/Viel (40/56/56/72 m),
  SSAO aus/aus/an/an, Regen-Spiegelungen aus/an/an/an, Volumennebel nur Ultra, Wolkenschatten
  ab Mittel. Weicht ein Regler ab: „Eigene Einstellung“.
- Wie die Regler wirken: Sichtweite = `TerrainManager.set_detail` (Kachel-Umkreis, LOD-Grenzen
  ×0,65–1,3, Bäume bis Stufe 1/2/3) und `RoadNetwork.mesh_distance`; Vegetation = Baumabstand
  7 m / √Dichte, geänderte Vegetation baut alle Kacheln nach und nach neu (`_generation`, die
  alten bleiben bis dahin sichtbar, Stamm-Kollision wird erneuert); Gras = `GrassManager.
  set_level` (alle Felder neu); Schatten aus = `DayNight.shadows_allowed`; Wolkenschatten =
  `Weather.cloud_shadows`. Schwere Regler wirken 0,35 s nach dem letzten Ziehen.
- Anzeige: Fenster/Vollbild, Fenstergröße 1280×720 bis 2560×1440 (mittig), V-Sync, FPS-Grenze
  30/60/120/unbegrenzt (`Engine.max_fps`), FPS-Anzeige. Steuerung: Grip-Stufe,
  Lenkempfindlichkeit 50–150 %, 20 Tasten neu belegbar (physische Taste, Name nach Layout über
  `keyboard_get_label_from_physical`, Doppelbelegung wird rot angezeigt, Esc bleibt frei).
- Messung Qualitätsstufen (3.11., Mac nach einer Woche Pause kühl, aber auf Akku; Autobahn-
  Benchmark 30 s mit Verkehr, `--bench=30 --highway --full --quality=…`, 2940 × 1912):
  Niedrig 129,6 FPS (1%-Low 91), Mittel 88,9 (62), Hoch 63,5 und zur Kontrolle am Ende 66,4
  (46–48), Ultra 36,5 (29). Ziele erreicht (Niedrig > 90, Mittel ~75, Hoch ≥ 60), Hoch aber
  knapp; der Sprung Mittel → Hoch kommt von Render-Auflösung 65 → 75 % und SSAO.
- Absturz-Suche („stiller Lauf ohne Ausgabe“): 10 Starts mit `--weather=rain`, 8 mit Pausemenü,
  3 ohne Argumente: alle mit Exit-Code 0, Foto bzw. „Welt geladen“, keine Fehler. Die früheren
  Läufe ohne Ausgabe hatten weder Absturzbericht (macOS) noch Fehlerzeile im Godot-Log, nur die
  Kopfzeilen: passt zu einem geschlossenen Fenster, nicht zu einem Absturz. Prüfskripte dafür
  (Exit-Code, Foto, Fehlerzeilen) lagen im Scratchpad.
- Vollbild-Messungen: Godots `--fullscreen` übergeht macOS beim Start oft, und im echten
  Vollbild (auch exklusiv) bremst macOS auf genau 60 FPS, obwohl V-Sync aus ist. Deshalb
  `--full`: randloses Fenster in Bildschirmgröße (gleich viele Bildpunkte, keine Bremse),
  der Benchmark beginnt erst, wenn die Größe stimmt. Im Akkubetrieb ist alles etwas langsamer.
- Audio-Busse (`default_bus_layout.tres`): Master, Motor (alle Auto-Geräusche, über den
  Tunnel-Bus mit Hall), Umgebung (Regen, Wind, Donner), Musik (vorbereitet, noch keine Musik).
  Spiel: HUD-Farbe, Sportauspuff, km/h oder mph (Tacho), automatisches Wetter, Tageslänge.
- Testen: Raststätte Falkenweiler `--pos=9560,-3988 --heading=90` (auf dem Parkplatz),
  von oben `--pos=9450,-3988 --highway --heading=90 --fly=110 --pitch=-55 --lookat=9604,-3988`,
  Schild 500 m `--pos=8790,-4056 --highway --heading=90`, Navi `--target=9604,-3982`,
  Bergblick Fichtenstein `--pos=-6420,-10337 --heading=90`.
- Neue Modelle (Nov. 2026, alle GLB): Garage M4 CSL, SL 65, C 63; Verkehr (assets/models/verkehr/)
  Audi S3, Accord, Aztek, ID. Buzz, LC 500; Tankstelle (assets/models/raststaette/). Lizenzen in
  `assets/CREDITS.md`, Download in `assets/models/README.md`. `CarModel.model_path` nimmt
  `scene.gltf` oder die `.glb` im Ordner. `tools/setup_models.gd` findet jetzt auch die Bilder,
  die Godot neben eine GLB auspackt, Verkehr max. 1024 px (Tankstellen-Normal-Map 50 → 2,8 MB).
- Kia Stinger weggelassen: Rennversion mit Überrollkäfig ohne Seitenscheiben, nach dem
  Vereinfachen fehlen Teile der hinteren Tür. Seine „edge_color“-Materialien sind Linien
  (SketchUp-Kanten, 280.000 Elemente), keine Flächen.
- `tools/setup_traffic_models.gd` (mit Fenster, einmal nach dem Download): je Verkehrsmodell
  `prepared/model.res` (`PreparedModel`) + Vorschaubilder. Ablauf: auf echte Länge skalieren,
  Teile nach Material einordnen (Tabelle `MODELS`: Lack, Glas, Licht, Reifen, Felge, weg),
  Sichtbarkeitstest (48 Richtungen × 140² Strahlen, Teile der Karosserie mit < 3 Treffern
  fliegen raus; Räder nie, sie stecken oft hinter Radkappen), Glas vorne/hinten unter 0,95 m =
  fast klare Leuchten-Abdeckung („cover“), Reifen/Felge nur in Radnähe, sonst Karosserie.
  Je Rolle eine Fläche (Karosserie mit Punktfarben = Materialfarbe × mittlere Texturfarbe),
  vereinfacht mit `ImporterMesh.generate_lods` (Budget nach Dreiecken × Gewicht, Lack 2,2):
  Stufe nur nehmen, solange Lack/Glas ≥ 85 % ihrer Fläche behalten (sonst Löcher in Türen).
  Normalen ganz zu verschmelzen ging weiter, riss aber Löcher. Räder nah je Ecke ein Mesh
  (dreht sich), mittel einfache Zylinder (12 Seiten).
- Ergebnis (nah / mittel Dreiecke): S3 49.800 / 17.500, Accord 52.100 / 29.000, Aztek
  70.900 / 31.600 (von 3,1 Mio.), ID. Buzz 61.100 / 15.300, LC 500 55.900 / 6.100. Die mittlere
  Stufe liegt meist über den gewünschten ~10.000, sonst reißt sie auf.
- Tankstelle: 616.000 → 201.700 Dreiecke ohne Asphaltfläche und Ladenregale (Cube.006/.038,
  390.000 Dreiecke), vereinfacht nah 51.600 / mittel 8.650 (mittel ohne Teile unter 1,5 m).
  Echte Marken: Regal-Fotos (Coca-Cola, Fanta, Sprite, Cheerios, Chex) und Werbetafel „MILES+“
  (Circle K) → im Werkzeug neutral erzeugte Bilder. Maße 38 × 6,6 × 22,9 m, lichte Höhe unter den
  Leuchtkästen 4,81 m (echte Größe), 22 einfache Kollisionsformen (Laden, Stützen, Inseln,
  Zapfsäulen). Leuchtende Materialien: glowin (Dach-Unterseite), Material.026/.027/.029.
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
- Bug behoben: `_merge_attached` (zusammenfassen der Radteile, `merge_static_parts`) hat die
  Platzhalter-Räder (Walze + weißer Balken aus car.tscn) mit eingesammelt, dann waren sie
  sichtbar. Fiel beim M4 CSL auf (Räder wie graue Scheiben), steckte aber auch in M5 F90/G90.
- Blinker-Kästchen sind nur noch zu sehen, solange sie leuchten (aus sieht man das Modell).
- Testen: `--car=m4csl|sl65|c63`, `--garage` macht das Foto mit offener Garage (mit `--car`
  ist dessen Marke gewählt), Fahrwerte `Godot --path . -s res://tools/drive_test.gd --
  --cars=m4csl,sl65,c63`.
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
- Verkehr: Abfahrer ordnen sich 600 m vorher rechts ein, wechseln am Beginn der Verziehung auf den
  Verzögerungsstreifen (`HW_RAMP` 12,3 m) und bremsen dort auf 90 km/h. Auffahrer bleiben auf
  dem Beschleunigungsstreifen (`merge_end` = Ende des parallelen Teils + halbe Verziehung, das
  Ende wirkt im IDM wie ein stehendes Hindernis), fädeln ein, sobald sie schnell genug sind
  (85 % von min(Wunschtempo, 100 km/h)) oder der Streifen ausgeht und rechts eine Lücke ist.
  Autos auf der rechten Spur wechseln nach links, wenn rechts neben/vor ihnen jemand auffährt.
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
