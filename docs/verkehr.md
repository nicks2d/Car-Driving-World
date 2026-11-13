# Verkehr, Tempolimits, Tempomat, Rennen

## KI-Autos

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
- Verkehr: Abfahrer ordnen sich 600 m vorher rechts ein, wechseln am Beginn der Verziehung auf den
  Verzögerungsstreifen (`HW_RAMP` 12,3 m) und bremsen dort auf 90 km/h. Auffahrer bleiben auf
  dem Beschleunigungsstreifen (`merge_end` = Ende des parallelen Teils + halbe Verziehung, das
  Ende wirkt im IDM wie ein stehendes Hindernis), fädeln ein, sobald sie schnell genug sind
  (85 % von min(Wunschtempo, 100 km/h)) oder der Streifen ausgeht und rechts eine Lücke ist.
  Autos auf der rechten Spur wechseln nach links, wenn rechts neben/vor ihnen jemand auffährt.

## Fahrzeuge und Modelle

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

## Tempolimits und Schilder

- Tempolimits (`speed_limits.gd`, `SpeedLimits`, Knoten „SpeedLimits“): `SpeedLimits.compute` läuft beim
  Berechnen jedes Abschnitts mit (Hintergrund) und füllt je Fahrtrichtung `limits_forward/backward`
  (Tempo/5 je Punkt), `wet_*` (nur bei Nässe) und `limit_signs` [Punkt, Richtung, Art, Wert, nass?].
  Landstraße 100, Tunnel 80 (60 m davor), Kurven unter 120 m Radius 70, unter 60 m 50, mit
  Warnschild (Kurve links/rechts, Doppelkurve) 60 m vorher. Autobahn frei; Tunnel 100, Kurven
  unter 1900 m 120, unter 1300 m 100 (35 % davon „bei Nässe“), Gefälle > 3 % über 1 km 120, und je
  Abschnitt und Richtung 14 % ganz 120 und 12 % „100 bei Nässe“. Orte 50 vom Ortsschild bis Ortsende
  (`Village.sign_reach`, beim Nachschauen). Schilder stehen dort, wo sich das Limit ändert
  (überlappende Zonen gehen nicht verloren), kurze Lücken unter 100 m (Autobahn 200 m) werden
  aufgefüllt, nicht in Tunneln/auf Brücken (dann davor). Ende: Aufhebung (Zeichen 278) bzw. „Ende
  aller Streckenverbote“ (282). Gemessen um den Start (5 × 5 km): 100 × „70“, 29 × „50“, 41
  Doppelkurven; vorher fehlten Tunnel-80 und Autobahn-Limits fast ganz (Kurven dort meist > 2 km).
- Schilder (`traffic_signs.gd`, Shader `sign.gdshader`): ein Mesh mit Punktfarben je Abschnitt plus
  Label3D für Zahlen (dreistellig kleiner). Landstraße rechts (Radius 0,32 m, 2 m hoch), Autobahn
  beidseitig (0,42 m, 2,3 m). Warndreieck 8 cm über dem runden Schild. Shader: matt, statt des blauen
  Himmelslichts ein neutrales Grundlicht aus Sonnen-/Mondfarbe (sonst waren weiße Schilder im Schatten
  knallblau), Scheinwerferlicht kommt wie bei Leitpfosten hell zurück.
- HUD: rundes Schild oben im Tacho-Panel (unbegrenzt = Zeichen 282), blinkt rot ab 10 km/h zu schnell,
  „bei Nässe“ zählt nur bei nasser Straße (`effective_limit`). KI: `limit_factor` 0,95–1,1 je Auto,
  schaut 60 m voraus. Navi: Fahrzeit aus den Limits (`nav_seconds_*`).

## Tempomat

- Tempomat (`cruise_control.gd`, `CruiseControl`): N ab 30 km/h (übernimmt das Tempo), + / − 1 km/h,
  gedrückt nächster Zehner alle 0,4 s, Bremse aus, Gas überstimmt. Abstand nach dem IDM wie die KI
  (`Traffic.leader_ahead`), Stufen 1,0/1,4/1,8/2,4 s (B), selbst höchstens 2 m/s² beschleunigen und
  3,5 m/s² bremsen, sonst Warnton + rotes Symbol. Der Vordermann wird mit Kursvorhersage aus der
  Drehrate gesucht (wie ein Radar) und mit Höhentoleranz 4 m + 6 % des Abstands (sonst verlor er ihn
  am Hang und in Kurven: erst bei 101 statt 210 m erkannt). Erkannte Limits werden übernommen
  (Einstellungen > Steuerung „Tempolimits übernehmen“), unbegrenzt = selbst gewähltes Tempo.
  `Car.assist_throttle/assist_brake` (−1 = aus) gehen vor die Tasten.
- Gemessen (`--cruise`, Autobahn, Lkw 300 m voraus mit 80 km/h, M2): bei 130 erkannt in 210 m, bremst
  sanft (höchstens 1,1 m/s² über eine Sekunde), hält dann 47–48 m = 2,15 s (Stufe 2) bzw. 29 m = 1,29 s
  (Stufe 0), Tempo 79–80. Notfall 170 → Lkw mit 50: Warnung, 3,9 m/s², hält dann 29 m bei 50 km/h.
  Landstraße: Wunsch 85 → 70 (Kurvenschild) → 100 (Aufhebung) → 50 (Ort).

## Lichthupe-Rennen und Vorbeifahrt

- Lichthupe (F, `car_signals.gd`): Fernlicht 0,35 s (gedrückt halten länger), 2,5-fach heller, 1,6-fach
  weiter und waagerecht statt 3° nach unten. Rennen (`race.gd`, `Race`): Lichthupe auf ein KI-Auto bis
  40 m vor oder neben einem → Zusage mit Lichthupe zurück (LC 500 und „Schnelle“ 80 %, Audi S3 50 %,
  sonst 12 %). Ziel: nächstes
  Ortsschild bzw. nächste Kreuzung (Landstraße, mindestens 400 m), Autobahn: nächste Ausfahrt (bis 4
  Stützpunkte voraus). HUD-Zeile unter dem Navi, Ziel als Navi-Ziel (danach das alte zurück). Ende:
  Ziel (Vorsprung in s), 600 m Abstand oder Unfall (> 7 m/s Tempoverlust in 0,2 s; einzelne
  Physikschritte springen, deshalb nicht pro Schritt). Statistik in `[rennen]`, Garage > Rennen.
  Test Autobahn: `--bench=70 --race --acc --highway --pos=1200,-4000 --heading=90` → „Verloren gegen
  Lexus LC 500 (2,4 s Vorsprung)“ (Ziel Ausfahrt 86).
- Vorbeifahrt-Geräusche (`passby_sound.gd`): die 6 nächsten KI-Autos bis 220 m bekommen je einen
  AudioStreamPlayer3D (Motor, Reifen, Wind; Lkw tiefer und lauter), Doppler, Bus „Umgebung“.

## Testen und Messungen

- Testen Verkehr: `--boxcars` (ohne Modelle), `--lineup=M` stellt vor dem Foto von jedem Typ ein
  stehendes Auto M Meter vor den Spieler (Autobahn abwechselnd rechts/links, jedes zweite
  blinkt, jedes dritte Warnblinker), z. B. `--pos=8790,-4056 --highway --heading=90 --fly=2.2
  --pitch=-4 --lineup=8 --traffic=0.01` (nachts `--time=22.5`).
- Gemessen (Prüfskripte, 90 s): an der Raststätte Falkenweiler 7 von 19 Autobahn-Autos über
  den Parkplatz, an der Anschlussstelle bei (3200, −4060) Ab- und Auffahrten (Rampe 4,
  Zubringer 5), 13–32 Spurwechsel, kein Auto festgefahren, kleinster Abstand in einer Spur 4 m.
  Autopilot 60 s mit Verkehr (Fenster): Landstraße 139 FPS, Autobahn 121 FPS, keine Fehler.
- Leistung Modelle vs. Kästchen (Autobahn-Benchmark 30 s, Verkehr Normal, Hoch, `--full`,
  abwechselnd gemessen, Mac heiß auf Akku 37 %): Kästchen 23,4 / 24,1 FPS, Modelle 22,9 / 23,3
  FPS (1%-Low 14 beide) → Modelle kosten ~3 %. Absolutwerte nur mit kühlem Mac vergleichbar.
