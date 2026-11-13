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
