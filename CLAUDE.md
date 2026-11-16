# Endlose Welt – Projektanweisungen für Claude Code

## Worum es geht

Ein 3D-Spiel in Godot: eine endlose, prozedural generierte Landschaft mit Bergen, Tälern,
Flüssen, Seen und einem Straßennetz, durch die man mit einem Auto fährt. Mit Tag-Nacht-Wechsel
und möglichst stimmungsvoller, realistischer Grafik (Vorbild: GTA, Forza Horizon – in
Indie-Maßstab). Die Welt ist deterministisch: gleicher Seed (1337) = gleiche Welt. Sie wird in
Kacheln rund um den Spieler erzeugt, weit entfernte Kacheln werden wieder entfernt.
Als Mac-App heißt das Spiel „Car Driving World“.

## Über mich (Nick)

- Ich studiere Wirtschaftsinformatik und bin beim Programmieren noch Anfänger
  (Grundlagen in Python). GDScript und Godot sind neu für mich.
- Antworte mir auf Deutsch, locker und verständlich.
- Erklär mir nach jedem Schritt in 2–4 Sätzen, was du gebaut hast und wie ich es teste.
- Wenn du eine Entscheidung triffst, die das Spiel stark beeinflusst
  (z. B. Grafik vs. Performance), sag mir kurz die Optionen.

## Technik

- Godot 4.7.2 (stable, Standard-Edition ohne .NET), nur GDScript mit statischen Typen
  (`var speed: float = 10.0`), Renderer Forward+, 3D-Physik Jolt (in Godot eingebaut).
- Ziel: flüssige 60 FPS auf einem normalen Laptop (MacBook Air M4), auf „Hoch“ mindestens 60.
  Grafik-Features über Qualitätsstufen (Niedrig/Mittel/Hoch/Ultra) schaltbar.

## Arbeitsweise (wichtig!)

1. **Immer nur ein Meilenstein bzw. eine Aufgabe gleichzeitig.** Nicht vorgreifen.
2. **Erst planen, dann bauen.** Zeig mir den Plan und warte auf mein OK.
3. **Kleine Schritte.** Nach jedem Teilschritt das Spiel starten (Godot-MCP `run_project` /
   `get_debug_output` oder Terminal), alle Fehler und Warnungen beheben.
4. **Nach jedem Teil `tools/test.sh` laufen lassen** (und den Welt-Prüfer, wenn Straßen, Gelände
   oder Tunnel betroffen sind). Erst bei „OK“ ist der Teil fertig. Siehe `docs/testen.md`.
5. **Du kannst das Spiel nicht sehen.** Mach Fotos mit `--shot` und schau sie dir an. Wenn es
   um Optik geht, frag mich zusätzlich konkret, worauf ich achten soll.
6. **Commit nach jedem funktionierenden Schritt** mit klarer deutscher Nachricht, z. B.
   „Meilenstein 2: Terrain-Chunks laden nach“. Pushen nur, wenn ich es sage.
   Nie `git add -A`; nicht committen: `AGENTS.md`, `.codex/`, `PROMPTS.md`, `screenshots/`,
   Modelle in `assets/models/`, `docs/screenshots/*.jpg.import`.
7. **Nichts kaputt machen, was schon läuft.** Wenn ein großer Umbau nötig ist, erst fragen.
8. Am Ende jeder Aufgabe „Fortschritt“ unten und die passende Datei in `docs/` aktualisieren
   (Entscheidungen, Zahlen, Messungen, Testbefehle). Hier nur Kurzes, Details nach `docs/`.

## Code-Regeln

- Einfach vor clever. Lieber ein gut lesbares Skript als fünf Klassen-Ebenen. Keine
  Abstraktionen „für später“. Ein Skript pro Aufgabe.
- Kommentare auf Deutsch, Variablen- und Funktionsnamen auf Englisch.
- Jede wichtige Zahl (Sichtweite, Chunkgröße, Fahrzeugwerte) als `@export`-Variable oben im
  Skript, damit ich sie im Godot-Editor selbst verändern kann.
- Prozedurale Generierung immer über `FastNoiseLite` mit festem Seed.
- Schwere Generierung (Terrain-Meshes, Straßen) im `WorkerThreadPool`, nie im Hauptthread.
- Szenen (.tscn) dürfen als Text bearbeitet werden, müssen aber sauber und gültig bleiben.

## Ordner

```
scenes/   .tscn-Szenen (main.tscn, car.tscn, …)     cars/    Auto-Profile (*.tres)
scripts/  .gd-Skripte, eins pro Aufgabe              tools/   Prüf- und Mess-Werkzeuge, Build
shaders/  .gdshader-Dateien                          docs/    Technik-Notizen, README-Bilder
assets/   models/ (nicht im Repo), textures/, hdri/, icon/, CREDITS.md (Quelle + Lizenz)
```

Assets nur mit freier Lizenz (CC0 bevorzugt: Poly Haven, Kenney, ambientCG), jedes in
`assets/CREDITS.md`. Fehlt eins: genau sagen, was ich wo herunterladen und wohin legen soll,
bis dahin Platzhalter. Automodelle liegen wegen ihrer Lizenzen nie im Repo
(`assets/models/README.md`).

## Technik-Notizen: welche Datei für welches Thema

| Thema | Datei |
|---|---|
| Gelände, Kacheln, Horizont-Ring, Bäume, Gras, Felsen | `docs/gelaende.md` |
| Landstraßen, Wegsuche, Kreuzungen, Leitplanken, Dörfer, Aussichtspunkte | `docs/strassen.md` |
| Autobahn, Anschlussstellen, Rampen, Streifen, Raststätten | `docs/autobahn.md` |
| Tunnel (Entstehung, Röhre, Löcher im Gelände, Prüfwerkzeug) | `docs/tunnel.md` |
| Flüsse, Seen, Talsperren, Wasserfälle, Landmarken-Brücken, Seeleben | `docs/wasser.md` |
| Fahrphysik, Profile, Modelle, Licht, Sound, Kennzeichen, Prüfstand, Cockpit-Sicht | `docs/autos.md` |
| KI-Verkehr, Tempolimits, Schilder, Tempomat, Rennen | `docs/verkehr.md` |
| Wetter, Jahreszeiten, Himmel, Mond, Polarlicht, Wolkenschatten | `docs/wetter-himmel.md` |
| HUD, alle Tasten, Garage, Karte/Navi, Entdecker-Karte, Fotomodus, Chill-Modus, Einstellungen | `docs/hud-menues.md` |
| FPS messen, Qualitätsstufen, Messungen | `docs/leistung.md` |
| Testbefehle, Testlauf, Prüfwerkzeuge | `docs/testen.md` |
| Mac-App bauen, Logo, README-Bilder | `docs/mac-app.md` |
| Alle erledigten Aufgaben im Detail, ursprüngliche Meilensteine | `docs/fortschritt.md` |

## Wichtigste Tasten

WASD fahren, Leertaste Handbremse, R Reset, Esc Pausemenü (Einstellungen), G Garage, M Karte,
P Fotomodus, L Licht, F Lichthupe, Q/E Blinker, X Warnblinker, H Hupe, N Tempomat (+/−, B Abstand),
V Fenster, Tab Kamera (Verfolger/Cockpit/Ego), F5 Wetter, J Jahreszeit, T Zeitraffer, F3 FPS.
Alle Tasten: `docs/hud-menues.md`.

## Wichtigste Testbefehle

```
G=/Applications/Godot.app/Contents/MacOS/Godot
$G --path . --always-on-top -- --shot=NAME --pos=X,Z --heading=G   # Foto nach screenshots/
$G --path . -- --shot=NAME --car=m2 --view=cockpit --steer=left      # Cockpit-Foto (oder --view=ego)
$G --path . -- --bench=30 --highway --full --quality=hoch          # FPS (docs/leistung.md)
$G --headless --path . --import                                    # nach neuen class_name
tools/build_mac_app.sh                                             # Mac-App (docs/mac-app.md)
tools/test.sh [--app] [--shots]                                    # Testlauf: OK oder Fehlerliste
$G --headless --path . -s res://tools/world_check.gd -- --size=12  # Welt-Prüfer (40 = alles, ~25 min)
```

Alle Argumente im Kopf von `scripts/debug_tools.gd`, mehr in `docs/testen.md`.

## Fortschritt

- [x] M0 Setup · M1 Fahrphysik · M2 Terrain-Chunks · M3 Himmel, Tag-Nacht, Nebel, Schatten ·
  M4 Straßennetz · M5 Flüsse, Seen, Brücken · M6 Vegetation · M7 BMW M2 mit Licht, Spuren,
  Sound · M8 Pausemenü, Einstellungen, Qualitätsstufen · M9 Dörfer und KI-Verkehr
- [x] Extras: Garage mit 8 Autos (BMW, Mercedes-AMG) und Prüfstand · Minimap und Navi · Wetter
  und Jahreszeiten · Tunnel · HUD im Glas-Stil · Autobahn ohne Tempolimit mit Anschlussstellen,
  Streifen und Raststätten · Aussichtspunkte und Fotomodus · Pops & Bangs, Turbo · Regenbogen,
  Wolkenschatten, Polarlicht, Mondphasen, Sternschnuppen · Grip-Stufen, Blinker, Hupe ·
  Verkehr mit echten Modellen · Tempolimits, Tempomat mit ACC · Lichthupe-Rennen · Fenster,
  Kennzeichen, Pfützen, Herbstlaub · Talsperren, Wasserfälle, Landmarken-Brücken, Seeleben ·
  Entdecker-Karte, Orte-Sammlung · Chill-Modus · Mac-App „Car Driving World“ · README auf
  Englisch, GitHub (nicks2d/Car-Driving-World)
- [x] Aufräumen: CLAUDE.md nach `docs/` aufgeteilt · Testlauf `tools/test.sh` und Welt-Prüfer
- [x] Straßen-Bugs, breitere Rampen · Tunnel von außen dicht · Reset mit sicheren Stellen ·
  Kennzeichen an der Stelle des Originals · Autos in der Mac-App sichtbar (Export-Einstellung)
- [x] Cockpit- und Ego-Sicht (Tab): Lenkrad 14:1, Kombiinstrument, Spiegel, Kopfbewegung ·
  Kamera mit Feder, Karosserie nickt und wankt, Kollisionen mit Funken und Schleifen ·
  Blinker im Lampenglas, Begrüßungslicht, Scheinwerfer mit Hell-Dunkel-Grenze
