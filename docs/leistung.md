# Leistung und Messungen

Ziel: flüssige 60 FPS auf einem normalen Laptop (hier MacBook Air M4 ohne Lüfter), auf „Hoch“
mindestens 60. Einzelne Kosten (SSR, Glas, Modelle …) stehen auch bei ihrem Thema.

## Wie man misst

- Befehl: `Godot --path . -- --bench=30 --highway --full --quality=hoch` (Autobahn-Benchmark mit
  Verkehr). Ausgabe: `BENCH frames … fps_avg … fps_1pct_low … worst_frame_ms`, dazu process_ms
  und physics_ms. Im Fenster zählt `process_ms` die V-Sync-Wartezeit mit, das ist kein echter Wert.
- Vollbild-Messungen: Godots `--fullscreen` übergeht macOS beim Start oft, und im echten
  Vollbild (auch exklusiv) bremst macOS auf genau 60 FPS, obwohl V-Sync aus ist. Deshalb
  `--full`: randloses Fenster in Bildschirmgröße (gleich viele Bildpunkte, keine Bremse),
  der Benchmark beginnt erst, wenn die Größe stimmt. Im Akkubetrieb ist alles etwas langsamer.
- Achtung (13.11.): macOS bremst manchmal auch im Fenster und mit `--full` auf genau 60 FPS,
  sogar ein leeres Godot-Projekt ohne V-Sync (dann zeigt auch „Niedrig“ 60,0). Ob gebremst wird,
  wechselt zwischen zwei Läufen. Deshalb zusätzlich die GPU-Auslastung messen: `ioreg -r -d 1 -c
  IOAccelerator` → „Device Utilization %“ (ohne Passwort), jede Sekunde während der Fahrt, im
  Leerlauf zum Vergleich (dort ~45 %, die Claude-App zeichnet mit). Unter ~85 % = Luft nach oben.
- Wärme: Das MacBook Air drosselt nach mehreren Benchmarks hintereinander deutlich (98 → 65 FPS,
  nach Stunden Dauertest auf etwa ein Drittel; nach einer Stunde Dauertest war selbst der alte
  Stand M7 headless 2,5-mal langsamer). Für Vergleiche und „≥ 60 FPS“ nur mit kühlem Mac messen,
  immer abwechselnd mit/ohne (Messungen streuen stark mit der Temperatur). Auch die Ladezeit
  schwankt dann stark (gleicher Code 6,7 s / 13 s), und nach Shader-Änderungen dauert der erste
  Start länger (Shader werden neu übersetzt).

- Zwei Stände vergleichen: `tools/bench_compare.sh [REF] [RUNDEN] [QUALITÄT]` misst abwechselnd alt
  und neu (Autobahn-Benchmark, `--full`, mit GPU-Auslastung) und gibt eine Tabelle aus. Der alte Stand
  wird als git worktree neben dem Projekt angelegt (Automodelle per Verknüpfung), `… REF 0` bereitet
  nur vor. Aufräumen: `git worktree remove ~/Godot-Projekte/.endlose-welt-vergleich-REF`.

## Einstellungen, die Leistung kosten

- Render-Skalierung: MetalFX Temporal mit 75 % (Projekteinstellungen > Rendering >
  Scaling 3D). Vollbild Retina: ~98 FPS statt 69 ohne Skalierung.
- Gelände- und Straßen-Manager prüfen ihre Umgebung nur alle 0,1 s (und sofort, wenn ein Auftrag
  fertig ist), Gelände fragt pro Prüfung höchstens 6 wartende Kacheln nach Straßen. Vorher
  kosteten sie 6,7 ms pro Bild, jetzt ~0,9 ms (`update_interval`).
- Stellschrauben: `vegetation_max_lod`, `tree_spacing`, Gras `radius`/`density`,
  Render-Skalierung, Qualitätsstufen (siehe `hud-menues.md`, Einstellungen).

## Messungen (alt nach neu)

- Stand M6 (Vollbild 2940×1846, MetalFX 75 %, Mac schon warm): ~68 FPS im Schnitt, 1%-Low ~55.
  Nach dem Straßen-Umbau: 74 FPS, 1%-Low 57.
- M2 (Vollbild 2940×1846): ~93 FPS, Ruckler nur beim allerersten Laden.
  Im Fenster lässt macOS V-Sync nicht abschalten, für FPS-Messungen damals `--fullscreen`.
- Nach Autobahn, Aussichtspunkten, Pops und Himmel (Autobahn-Benchmark 25 s,
  1280×720-Fenster, alles nacheinander auf demselben, inzwischen heißen Mac): Stand Teil 3
  53,7 FPS, vor Teil 6 50,9, mit allem 50,7 (1%-Low ~20). Teil 4–6 kosten also ~5 %; Teil 6
  (Himmel, Wolkenschatten) nichts Messbares. Derselbe Stand Teil 3 lief mit kühlem Mac mit
  147 FPS.
- Qualitätsstufen (3.11., Mac nach einer Woche Pause kühl, aber auf Akku; Autobahn-
  Benchmark 30 s mit Verkehr, `--bench=30 --highway --full --quality=…`, 2940 × 1912):
  Niedrig 129,6 FPS (1%-Low 91), Mittel 88,9 (62), Hoch 63,5 und zur Kontrolle am Ende 66,4
  (46–48), Ultra 36,5 (29). Ziele erreicht (Niedrig > 90, Mittel ~75, Hoch ≥ 60), Hoch aber
  knapp; der Sprung Mittel → Hoch kommt von Render-Auflösung 65 → 75 % und SSAO.
- Ausgangswert 13.11. (Netzteil, Mac kühl, Hoch, `--full`): 60,1 / 59,7 FPS (gebremst, 1%-Low
  45), dritter Lauf ungebremst 65,7 FPS (1%-Low 48), GPU-Auslastung 93 %: Hoch ist GPU-begrenzt.
- Nach Teil 3–7 (14.11., Mac nach vielen Stunden Dauerlast heiß, Akku 10 % am Netzteil, `--full`,
  Hoch): 58,2 / 60,2 FPS (1%-Low 34,8 / 34,1), GPU-Auslastung 90 / 91 %. GPU-Last also nicht höher als
  vorher (93 %), aber die Ruckler (1%-Low) sind deutlich schlechter als am Anfang (45). Ob das an der
  Wärme liegt oder an Teil 3–7 (Tunnel-Deckel, breitere Rampen, mehr Kollision), ist offen: mit kühlem
  Mac abwechselnd gegen den Stand vor Teil 3 (Commit c71aa75) messen: `tools/bench_compare.sh`
  (vorbereitet, der alte Stand liegt importiert in `~/Godot-Projekte/.endlose-welt-vergleich-c71aa75`).
- Vergleich abwechselnd (16.11., Mac nach zwei Tagen Pause kühl, Akku 98 %, Hoch, `--full`,
  `tools/bench_compare.sh`): vor Teil 3 (c71aa75) 61,7 / 59,8 FPS (1%-Low 44,9 / 42,2), jetzt 61,2 / 58,8
  (43,1 / 35,9), GPU 91–93 %. Teil 3–7 kosten also ~1–2 %; die schlechten Werte vom 14.11. lagen vor
  allem an der Wärme. Auf Akku liegt Hoch knapp um 60 FPS, Runde 2 ist schon wärmer.
- Cockpit-Sicht (16.11., Mac nach vielen Fotos warm, Akku 81 %, Hoch, `--full`, Autobahn): Rückspiegel
  (576 × 192, 30 Bilder/s) kosten nur 1–2 FPS (Cockpit mit Spiegeln 53,5 / 33,0, ohne 54,1 / 34,8; der
  Unterschied zwischen den Runden ist die Wärme). Teuer war dagegen der erste Glas-Shader: Er griff mit
  `hint_screen_texture` (mit Mipmaps) immer das ganze Bild ab, auch ohne Regen (Cockpit 32 FPS gegen
  Verfolger 50). Jetzt gibt es zwei Varianten (`car_glass.gdshader` trocken, `car_glass_rain.gdshader`
  mit Tropfen, ohne Mipmaps), CarModel nimmt die mit Tropfen nur, solange es regnet. Messung mit
  kühlem Mac steht noch aus (Ende der Sitzung). Messbefehl: `--bench=30 --highway --full --view=cockpit`,
  `--mirrorfps=0` schaltet die Spiegel ab.
- Nach den sechs Teilen Cockpit bis Sound (17.11., Mac nach vielen Stunden Tests warm, Akku 48 → 45 %, Hoch,
  `--full`, Verfolger-Kamera, Autobahn mit Verkehr) gegen den Stand vom Sitzungsbeginn (0c0e765):
  `tools/bench_compare.sh 0c0e765 2 hoch` (immer alt zuerst): alt 63,0 / 49,4, neu 54,4 / 43,7 FPS. Weil die
  Wärme stark und ungleichmäßig drückt (alt allein −22 % von Runde 1 zu 2), zusätzlich in der Reihenfolge
  neu–alt–alt–neu: 60,5 / 57,0 / 45,1 / 36,9 FPS (1%-Low 40,7 / 30,8 / 24,8 / 20,5), GPU 84–91 %. Im Schnitt
  kostet das Neue also etwa 0–5 %, genauer geht es mit warmem Mac nicht. Einzelkosten gemessen: Motorsound
  48 kHz 0,53 ms pro Bild (22 kHz: 0,25), Rücklauf-Aufzeichnung 0,05 ms pro Physik-Schritt (Auto und
  11 Verkehrsautos, `BENCH rueckspulen_ms`), Spiegel im Cockpit 1–2 FPS. Kontaktschatten, Lack-Tropfen
  (nur bei Nässe) und Glas-Tropfen (nur bei Nässe) sind einzeln nicht gemessen. Offen: Messung mit kühlem
  Mac am Netzteil (der alte Stand liegt importiert in `~/Godot-Projekte/.endlose-welt-vergleich-0c0e765`).

## Ruckler suchen und Shader vorbereiten (17.11.)

- Ruckler-Suche (`scripts/frame_costs.gd`, `FrameCosts`): Die großen Teile (Gelände, Straßen, Gras, Verkehr,
  Horizont, Karten, Tag/Nacht, Motorsound …) messen ihre Zeit pro Bild; jeder Benchmark gibt am Ende die 12
  langsamsten Bilder mit Aufschlüsselung aus (`BENCH langsam N: ms | Teil ms, …`, ab 1 ms). Ergebnis
  (Autobahn, Hoch, warm): Die meisten langsamen Bilder (26–30 ms) haben unter 2 ms Skriptzeit, sind also von der
  Grafikkarte begrenzt (dichte Ansichten). Echte Ruckler: Gras-Felder einbauen bis 14 ms (wenn viele zugleich
  fertig wurden), Gelände-Pflanzen einbauen 10–15 ms pro Kachel, Verkehrsautos mit Modell bis 25–36 ms.
- Gemacht: Gras baut höchstens 2 fertige Felder pro Bild ein (`max_builds_per_frame`); die nahen Bäume werden
  im Hintergrund-Auftrag nach Vierteln aufgeteilt (vorher im Hauptthread); MultiMeshes der Pflanzen bekommen
  ihre Kiste vorgegeben (`custom_aabb`, Höhenbereich aus dem Auftrag). Das Einbauen eines MultiMesh-Knotens
  kostet trotzdem noch bis 10–19 ms (vermutlich wartet Godot dabei auf den Render-Thread); offen.
- Shader vorbereiten (`scripts/shader_warmup.gd`): hinter dem Ladebildschirm 6 Bilder lang kleine Flächen mit
  allen später gebrauchten Shadern (Regen auf den Scheiben, Tropfen/Schnee auf dem Lack, Ausblend-Varianten,
  Impostoren, Tunnel-Ventilatoren, Leuchten, Spiegel) und Regen-/Schnee-Partikeln. Test `--bench=16 --highway
  --rainat=10` (Regen setzt nach 10 s ein), `--nowarmup` zum Vergleich: Godot 4.7 übersetzt ohnehin vieles im
  Hintergrund; beim Regenbeginn mit Vorbereitung höchstens 27–29 ms, ohne 35–36 ms (eine Messung, streut).
- Flimmern: Leitplanken nur bis 700 m, Leitpfosten bis 320 m (`rail_distance`, `post_distance`); ferne Bäume
  sind Impostoren mit Mipmaps (keine dünnen Äste mehr in der Ferne), MetalFX Temporal glättet Kanten. Ein
  Video-Vergleich fehlt (Fotos zeigen kein Flimmern).
- Nicht gemacht: Occlusion Culling. Die Messung zeigt, dass die langsamen Bilder von der Grafikkarte begrenzt
  sind; Verdecker für das Gelände müssten mit jeder nachgeladenen Kachel neu eingebaut werden (Godot baut dann
  seine Verdecker-Struktur neu, das droht neue Ruckler). Das wäre ein eigener, größerer Schritt mit Messung im
  Tal, Tunnel und Dorf.
- Messung am Ende der Sitzung (17.11., Mac nach vielen Stunden Dauerlast heiß, am Netzteil, Hoch, `--full`):
  `tools/bench_compare.sh 65856d4 2 hoch` (Sitzungsbeginn gegen jetzt): alt 45,9 / 37,5 FPS (1%-Low 24,4 / 21,0),
  neu 29,9 / 33,0 (15,9 / 18,5), GPU 83–85 %. Gleicher Stand zweimal hintereinander gemessen: 38,1 und 29,7 FPS
  – die Wärme verschiebt mehr als die Unterschiede. Kosten einzeln (`--nonear`, `--noimpostor`, je einmal):
  im Rauschen. Gültig ist erst die Messung mit kühlem Mac (nach einer Pause, Netzteil, abwechselnd):
  `tools/bench_compare.sh 65856d4 2 hoch`, dazu `--nonear` und `--noimpostor`, wenn „neu“ langsamer ist.
