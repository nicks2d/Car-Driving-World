# Testen

Alle Startargumente stehen mit Erklärung im Kopf von `scripts/debug_tools.gd`. Testbefehle für
einzelne Themen (Orte, Koordinaten) stehen in der jeweiligen Themen-Datei unter „Testen“.

## Testlauf nach jedem Teil (Pflicht)

- `tools/test.sh` (ca. 100 s): startet das Spiel mit `--selftest` (`scripts/self_test.gd`): 25 s
  Autopilot auf der Landstraße, Sprung auf die Autobahn bei (1200, −4000) mit Ladebildschirm, 25 s
  Autobahn, dann je 3,5 s Regen, Schnee (Winter), Nacht (23 Uhr), Garage (schließt mit „Losfahren“),
  große Karte, Fotomodus, Pausemenü und 12 s Chill-Modus. Danach „SELFTEST ENDE“ und Beenden.
- Ausgewertet werden Rückgabewert, die Zeile „SELFTEST ENDE“ (fehlt sie: stiller Absturz oder
  Hänger; nach 300 s wird abgebrochen) und alle Zeilen mit ERROR, WARNING, Parse Error, leaked im
  Log `screenshots/test.log` (auch aus dem vorherigen `--import`). Ist der Autopilot kaum gefahren
  (Landstraße < 150 m, Autobahn < 300 m), ist das auch ein Fehler. Ergebnis: „OK“ (Rückgabe 0) oder
  die Liste. Bekannte harmlose Meldungen stehen in `KNOWN` im Skript (mit Begründung).
- `tools/test.sh --app` testet die exportierte App in /Applications (Log `screenshots/test_app.log`,
  Fotos dort in `user://selftest/`), `--shots` macht ein Foto pro Schritt
  (`screenshots/selftest_*.png`), weitere Argumente gehen ans Spiel (z. B. `--car=e92`).
- Testläufe speichern nichts: Auch die Garage speichert beim Schließen nur ohne Testargument
  (vorher hätte ein Test das gewählte Auto überschrieben).

## Welt-Prüfer (nach Änderungen an Straßen, Gelände, Tunneln, Dörfern)

- `Godot --headless --path . -s res://tools/world_check.gd -- [--size=40] [--center=X,Z] [--times]`:
  rechnet die Straßen Feld für Feld (4 × 4 km, Schlangenlinie) und baut für jeden Abschnitt Mesh
  und Kollision wie im Spiel, dazu Gelände-Kacheln Stufe 0 mit Bäumen entlang der Straßen.
  Dauer: ein Feld ~20 s (das meiste sind die Gelände-Kacheln mit Bäumen), 12 × 12 km ~3 min,
  40 × 40 km ~25 min.
- Fehlerarten (Stelle = 40-m-Feld): Fahrbahnen überschneiden sich (Fahrstreifen von A liegt auf
  der Fahrfläche von B, Höhenunterschied < 3,5 m; erlaubt an gemeinsamen Enden bis 60 m, nah an der
  eigenen Kreuzung, Rampen auf ihrer Autobahn außerhalb der Hauptfahrbahn ab 9,6 m neben der Mitte),
  Straße durch fremde Kreuzung, Leitplanke/Brüstung bzw. Tunnelwand/Portal in einer fremden
  Fahrbahn (senkrechte Kollisionsflächen, keine Ausnahmen außer der Mittelleitplanke, die im
  nächsten Autobahn-Abschnitt weiterläuft), Loch im Gelände (Dreieck mit NaN-Ecke; Strahl nach
  unten: nichts = „Fall unter die Map“, mehr als 3 m tiefer = „Fall in die Röhre“), Baum/Busch/Fels
  auf Straße oder schwebend (Fuß > 0,15 m über dem Gelände), Haus auf Straße oder schwebend (Ecke
  > 0,6 m über dem Gelände), Straße im Wasser, Kreuzung mit Lücke oder Höhensprung (> 0,25 m) am Arm.
- Ausgabe: Anzahl je Fehlerart, je 4 Beispiele mit Foto-Befehl (`--pos --cam --lookat`), alle
  Stellen in `screenshots/world_check.txt`.

- Loch-Prüfung im Welt-Prüfer: Strahl von 30 m über dem Gelände nach unten. Landung auf dem
  Tunnel-Deckel, dem Sockel oder der offenen Straße vor dem Portal ist in Ordnung (wie ein Sturz von
  einer Böschung); Fehler sind „unter die Map“ (nichts darunter) und „in die Röhre“ (mindestens 1 m
  hinter dem Portal zwischen den Wänden). Häuser „schweben“ erst ab 1,4 m Luft (so tief reicht der
  Sockel). Über das Ende eines Abschnitts hinaus zählt nur 0,5 m Überstand.
- Fehlersuche im Prüfer: `--info=X,Y,Z` (Angaben zu einem Abschnitt, Deckel-Flächen),
  `--probe=X,Z,KX,KY,KZ` (Abstand zu den Leitplanken-Sperrzonen eines Abschnitts); wartet ein Feld
  länger als 40 s auf Straßen, nennt er die unfertigen und laufenden Abschnitte.
- Fallversuch: `-- --droptest=X,Z;X,Z;… --pos=X,Z` setzt das Auto an jeder Stelle 2 m über der
  höchsten Fläche bzw. dem natürlichen Gelände ab und meldet nach 2,5 s „ok“, „DURCHGEFALLEN“ (nichts
  darunter) oder „IN DIE RÖHRE GEFALLEN“ (mindestens zwischen den Röhrenwänden hinter dem Portal);
  `--dropdrive=S` fährt danach S Sekunden geradeaus (`--heading`). Beispiel:
  `--droptest=-1581,-8337;-1874,-8062 --pos=-1562,-8360`.

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
