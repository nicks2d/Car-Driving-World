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
- [ ] Meilenstein 4
- [ ] Meilenstein 5
- [ ] Meilenstein 6
- [ ] Meilenstein 7
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
- Fahrwerte laut Testfahrt (Stand M1): 0–100 km/h in 5,8 s, Spitze ca. 220 km/h,
  100–0 km/h in 42 m, ca. 1,2 g in Kurven, kippt nicht um.
- Welt-Formel: `scripts/world_gen.gd` (Resource, im Inspector am Main-Node). Seed 1337.
  Höhe = Talboden (großräumig 60–180 m) + Relief (Hügel + Bergketten bis ~1.900 m).
  Flüsse = Null-Linien eines Rauschens, das Relief wird dort zum Tal abgesenkt.
  Seen = höchstens einer pro 2,5-km-Zelle, Wasserhöhe knapp unter dem tiefsten Randpunkt.
- FastNoiseLite-Falle: Domain Warp hat standardmäßig 5 Stufen mit Faktor 6, das macht
  das Gelände aus der Nähe stachelig. Deshalb `domain_warp_fractal_octaves = 2`.
- Terrain: Kacheln à 256 m, Detailstufen mit 2/4/8/16 m Raster (Grenzen 450/900/1500 m),
  Sichtweite 2 km, Kollision (HeightMapShape3D, skaliert) bis 320 m. Berechnung im
  WorkerThreadPool, max. 2 Kacheln pro Bild einbauen. Schürzen gegen LOD-Lücken.
- Horizont-Ring 1,2–26 km (110 × 720 Punkte), versinkt im Shader unter den Kacheln.
  Ab 700–1500 m blendet der Terrain-Shader auf die Durchschnittsfarben der Texturen um,
  damit Kacheln und Ring gleich aussehen.
- Leistung (M2, Vollbild 2940×1846): ~93 FPS, Ruckler nur beim allerersten Laden.
  Im Fenster lässt macOS V-Sync nicht abschalten, für FPS-Messungen `--fullscreen` nutzen.
- Testen: `Godot --path . -- --shot=NAME --pos=X,Z --heading=G --fly=H --time=H` speichert
  `screenshots/NAME.png`. `-- --bench=20` misst FPS (siehe `scripts/debug_tools.gd`).
- Himmel: eigener Sky-Shader (`shaders/sky.gdshader`), Farben kommen aus Farbverläufen in
  `day_night.gd` (Sonnenhöhe -18° bis +40°). Nachts wird das Sonnenlicht zum Mondlicht.
  Sky-Radiance `process_mode = Incremental` (Realtime kostet merklich FPS).
- Tonemapping AgX, Glow, SSAO, Fernnebel mit Luftperspektive. Volumetrischer Nebel aus
  (Schalter `volumetric_fog` an DayNight, Test mit `--volfog`).
- Render-Skalierung: MetalFX Temporal mit 75 % (Projekteinstellungen > Rendering >
  Scaling 3D). Vollbild Retina: ~98 FPS statt 69 ohne Skalierung.
