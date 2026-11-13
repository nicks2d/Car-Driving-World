# Testen

Alle Startargumente stehen mit Erklärung im Kopf von `scripts/debug_tools.gd`. Testbefehle für
einzelne Themen (Orte, Koordinaten) stehen in der jeweiligen Themen-Datei unter „Testen“.

## Grundregeln

- Godot im Projektordner: `/Applications/Godot.app/Contents/MacOS/Godot --path . -- ARGUMENTE`
  (alles nach `--` sind Spiel-Argumente).
- Testläufe mit Argumenten nehmen die Standard-Einstellungen, laden und speichern keine Spielstände
  (Karte, Orte, Aussichtspunkte, Prüfstand nur im Speicher) und laufen klar/Sommer, außer mit
  `--weather=…` / `--season=…`. Ohne `--car` fährt der M2.
- Testläufe mit `--always-on-top` starten: Ist das Spielfenster ganz verdeckt, zeichnet macOS es
  nicht und das Foto hängt (Hauptthread in nanosleep).
- Achtung bei eigenen Prüfskripten (`-s`): Ohne Testargument öffnet nach dem Laden die
  Garage und pausiert das Spiel, dann kommt z. B. ein `jump_to` nie an. Garage schließen.
- Neue `class_name`-Skripte erst nach `Godot --headless --path . --import` bekannt, sonst
  meldet ein Start ohne Editor „Could not find type“.
- `--heading`: 0° = +Z (Süden), 90° = +X (Osten).

## Foto- und Benchmark-Befehle

- Testen: `Godot --path . -- --shot=NAME --pos=X,Z --heading=G --fly=H --time=H` speichert
  `screenshots/NAME.png`. `-- --bench=20` misst FPS (siehe `scripts/debug_tools.gd`).
  `--carview=G` stellt die Kamera neben das Auto (0 = vorne, 180 = hinten), `--steer=left`
  lenkt dabei (Vorderräder prüfen), `--car=e30` startet mit diesem Auto. `--nowait` macht das
  Foto, ohne auf die Kacheln zu warten, `--jump=X,Z` springt nach dem Laden weit weg.
- Freie Kamera: `--cam=X,Z,H --lookat=X,Z,H` (H über dem Gelände), Überblick `--fly=H --pitch=G
  --lookat=X,Z`.
- `-- --bench=60` fährt per Autopilot die Straßen ab (Stand M4: 4 km am Stück, ~80 km/h im
  Schnitt, Vollbild ~98 FPS, 1%-Low 77 FPS). `--highway` startet auf der Autobahn (Autopilot
  Vollgas), `--benchshot=10,20` Fotos während der Fahrt, `--shotevery=M` alle M Meter.
- Weitere: `--signshot=curve|limit|end_limit|end_all|wet|tunnel` Foto 9 m vor dem nächsten
  Schild dieser Art, `--cruise=KMH,D,V` (mit `--bench`: echter Tempomat, Lkw D m voraus mit V km/h,
  `--gap=0..3`), `--acc[=KMH]` Autopilot mit Abstand und Überholen, `--race`, `--flash`,
  `--windows[=S]`, `--record=PFAD.wav` (mit `--bench`/`--dyno`), `--splash`, `--shotevery=M`,
  `--dyno=sl65,m4csl,c63` (mit `--shot`, Foto im ersten Lauf und am Ende). Beispiele:
  `--shot=s --pos=300,286 --heading=60 --signshot=curve`, `--bench=75 --highway --pos=6500,-3950
  --heading=90 --cruise=130,300,80 --traffic=0.01` (Verkehr 0 räumt auch Test-Autos weg),
  `--shot=dyno --car=sl65 --dyno=sl65,m4csl,c63`.
- Menüs und Modi: `--garage`, `--map`, `--photo --filter=N`, `--pause=0..5`, `--collection=0|1`,
  `--chill` (mit `--bench`), `--quality=niedrig|mittel|hoch|ultra`, `--nohud`, `--hide=A,B`,
  `--quitafter=S` (normaler Start mit Garage und Spielständen, beendet sich nach S Sekunden).

## Prüfwerkzeuge (`tools/`)

- `tunnel_check.gd`: liegt etwas Sichtbares in einer Tunnelröhre? (siehe `tunnel.md`)
- `drive_test.gd`: Fahrwerte auf flacher Ebene (0–100, 0–200, Spitze, Bremsweg), `--cars=`
  (siehe `autos.md`)
- `grip_test.gd`: Kurven-g, Schwimmwinkel, Drift (`--cars=`, `--grip=`, `--wet`, `--snow`)
- `landmarks.gd`: Talsperren, Wasserfälle, Brücken mit Foto-Befehlen (siehe `wasser.md`)
- `setup_models.gd`, `setup_traffic_models.gd`: nach jedem Modell-Download (siehe `autos.md`,
  `verkehr.md`)
- `build_mac_app.sh`: Mac-App bauen (siehe `mac-app.md`)

## Absturz-Suche

- Absturz-Suche („stiller Lauf ohne Ausgabe“): 10 Starts mit `--weather=rain`, 8 mit Pausemenü,
  3 ohne Argumente: alle mit Exit-Code 0, Foto bzw. „Welt geladen“, keine Fehler. Die früheren
  Läufe ohne Ausgabe hatten weder Absturzbericht (macOS) noch Fehlerzeile im Godot-Log, nur die
  Kopfzeilen: passt zu einem geschlossenen Fenster, nicht zu einem Absturz. Prüfskripte dafür
  (Exit-Code, Foto, Fehlerzeilen) lagen im Scratchpad.
