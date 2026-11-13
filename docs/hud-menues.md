# HUD, Menüs, Garage, Karte, Fotomodus, Chill-Modus

## Tasten

- Tasten: WASD fahren, Leertaste Handbremse, R Reset (aufrichten bzw. zurück auf die Straße, 3 s Sperre), T Zeitraffer, F3 FPS,
  C Lackfarbe, K Aufkleber, L Licht, G Garage (← → Auto, C Lack, Enter losfahren, Esc zurück),
  M große Karte (Linksklick Ziel, Rechtsklick
  Ziel löschen, Mausrad zoomen, ziehen verschiebt), F5 Wetter (Automatisch → Klar → Bewölkt →
  Regen → Gewitter → Nebel → Schnee), J Jahreszeit, P Fotomodus (Maus ziehen schwenkt,
  W A S D / R F bewegen, Mausrad Zoom, 1–4 Filter, ↑ ↓ Belichtung, ← → Tageszeit,
  G Schärfe aufs Auto, Leertaste Foto, O Foto-Ordner, P/Esc zurück), Q Blinker links,
  E Blinker rechts (noch mal = aus), X Warnblinker, H Hupe, F Lichthupe, N Tempomat an/aus,
  + / − Wunschtempo (gedrückt halten: 10er-Schritte), B Abstandsstufe, V Fenster auf/zu,
  Esc Pausemenü (dort Einstellungen; alle Tasten außer Esc lassen sich unter Steuerung neu belegen).

## HUD und Glas

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
- Testen: `--nohud` blendet das HUD aus, `--hide=Minimap,Speedometer` einzelne Teile. Messungen
  streuen stark mit der Temperatur des Macs: immer abwechselnd mit/ohne messen.

## Garage

- Garage (`garage.gd`, Taste G, beim Start): eigene 3D-Welt (SubViewport) mit Boden,
  Licht ohne Glanzpunkte (sonst Flecken im Boden), SSR nur dort. Spiel pausiert, Gelände,
  Straßen, Wasser, Gras und Horizont laufen mit `process_mode = Always` weiter (die Welt lädt
  im Hintergrund). Auto und Farbe: `user://einstellungen.cfg`. Tests (`--shot`, `--bench`,
  `--car=ID`) öffnen keine Garage und fahren das angegebene bzw. erste Auto.
- Garage: pausiert das Spiel und zeigt das echte Auto in der Welt (Kamera kreist, Maus ziehen
  dreht), öffnet beim Start erst, wenn die Welt geladen ist. Autowechsel sofort am echten Auto
  (Räder dabei in Ruhelage setzen, sonst stehen sie dort, wo die Physik sie beim Laden
  hingestellt hat). Welt-Umschalter ändern Uhrzeit (`DayNight.set_time`), Wetter und Jahreszeit
  sofort. Gespeichert: Auto, Lack, HUD-Farbe (`hud/akzent`), Sportauspuff (`auto/sportauspuff`).

## Karte und Navi

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

## Entdecker-Karte und Sammlungen

- Entdecker-Karte (`exploration.gd`, `Exploration`, Knoten „Exploration“): Gesehenes in Kacheln à
  2048 m (256 × 256 Pixel, 8 m pro Pixel, LA8: Helligkeit = Wolkenmuster, Deckkraft = Nebel),
  gespeichert als PNG in `user://karte/X_Z.png` (alle 20 s und beim Beenden). Aufgedeckt: 300 m um
  das Auto (alle 0,5 s, wenn > 20 m weiter), weich auslaufend; an Aussichtspunkten und Raststätten
  mit Aussicht (einmal pro Spielstart, auch schon entdeckte) ein Fächer ±55° bis 2,5 km in
  Blickrichtung, aber nur, was man sieht: 111 Sichtstrahlen (1°) mit Prüfpunkten alle 20 m übers
  Gelände (steilster Winkel bisher, knapp darunter halb), dazwischen bilinear überblendet. Alles im
  WorkerThreadPool, ein Auftrag nach dem anderen (der Hauptthread liest nur, `_mutex`).
- Karte (`map_view.gd`, `_draw_fog`): Nebel nach den Straßen, vor Route, Ziel und Symbolen
  (Farbe `fog_color`, Deckkraft 0,985, Wolkenmuster aus nahtlosem FastNoiseLite, für jede Kachel
  gleich). Unbekannte Kacheln teilen sich eine Textur. Raststätten, Talsperren- und Brückennamen
  unter dem Nebel werden nicht gezeichnet, die „?“ der Aussichtspunkte schon (als Anreiz).
  Navi und Route gehen wie vorher. Einstellungen > Spiel „Entdecker-Karte“ (`[spiel] entdecker`).
- Orte-Sammlung: näher als 170 m an einem Ort (`RoadNetwork.node_at`, 3 × 3 Zellen um das Auto)
  = besucht, beim ersten Mal Meldung „Neuer Ort: …, N Orte besucht“. `user://orte.cfg` (Name, Zeit,
  Lage, Foto). Ein Foto im Fotomodus bekommt der nächste besuchte Ort bis 300 m. Garage >
  Sammlung hat jetzt zwei Reiter: Orte und Aussichtspunkte (`Viewpoints.collection_row`,
  Vorschaubilder gemerkt in `Viewpoints.thumbnail`). Testläufe laden und speichern nichts.
- Testen: `--bench=60 --map` (Karte mit Nebel nach der Fahrt, Foto `bench_ende.png`),
  `--bench=4 --map --pos=433,-861 --heading=57` (Blick vom Aussichtspunkt), `--bench=90
  --collection=0 --pos=-660,459 --heading=103` (Orte-Sammlung nach der Fahrt durch Buchhof und
  Mühlingen), `--collection=1` = Reiter Aussichtspunkte.

## Fotomodus

- Fotomodus (`photo_mode.gd`, Taste P): pausiert, HUD aus, eigene Kamera (max. 30 m vom Auto,
  Strahl Auto→Kamera verhindert Gelände/Wände dazwischen, nicht unter den Boden). Schärfe
  = DOF der Kamera auf die Entfernung zum Auto, Belichtung = `exposure_multiplier`, Filter =
  Bildschirm-Shader (`photo_filter.gdshader`). Foto ohne Bedienfeld und Meldungen nach
  `user://fotos/foto_DATUM_ZEIT.png`; die Tageszeit wird beim Verlassen zurückgestellt.
- Testen: `--photo --filter=1` macht das Foto im Fotomodus, `--map` mit großer Karte. Beide
  halten das Spiel an, dann läuft DebugTools mit `PROCESS_MODE_ALWAYS` weiter.
  Aussichtspunkt am Start: `--pos=433,-861 --heading=57` (Aussicht bei Bergmünster).

## Chill-Modus

- Chill-Modus (`chill_mode.gd`, `ChillMode`, Pausemenü „Chill-Modus“): übernimmt die normale
  Fahrkamera (`set_physics_process(false)`, dann laufen Regen, Talnebel usw. mit) und gibt ihr
  eigene Kamera-Attribute (leichte Tiefenunschärfe hinter dem Auto). Kein HUD, keine Meldungen,
  schwarze Balken oben/unten (je 8,5 %). Einstellungen alle 10–20 s: „heli“ (26 m hinten seitlich,
  12 m hoch, kreist langsam), „side“ (6 m daneben zur Fahrbahnmitte), „low_front“ (10 m voraus,
  0,35 m hoch, Blick zurück), „bumper“ (Stoßstange, Blick nach vorn), „roadside“ (fest am Rand
  80–140 m voraus, auf dem geradesten Stück, Landstraße auf der tieferen Seite, Autobahn am
  Mittelstreifen; Schnitt, sobald das Auto 45 m vorbei ist). Überblendung: das letzte Bild wird
  festgehalten (`get_image`, ein kurzer Hänger pro Schnitt) und über 1,4 s ausgeblendet.
- Chill-Autopilot: drückt dieselben Tasten wie ein Spieler. Route `RoadNetwork.route_from(…,
  scenic = true, avoid)`: an Kreuzungen Punkte für Aussichtspunkte (Pass/See/Wasserfall mehr),
  Talsperren, Landmarken-Brücken, Tunnel, dazu Zufall; die letzten 16 Abschnitte werden gemieden.
  Auf der Autobahn bleibt er auf der Autobahn (wechselt nicht von selbst auf sie). Landstraße 2 m
  rechts der Mitte, Wunschtempo 95 / Autobahn 150 km/h, Kurven 3 / 4,5 m/s² quer, Bremsen 2,5 m/s²,
  Tempolimits (`SpeedLimits.effective_limit`), Abstand Mindestabstand + 2 s, Autobahn links
  überholen mit Blinker. Im Stand Handbremse statt Bremse (Bremse im Stand = Rückwärtsgang).
  Sackgasse: ausrollen, beim nächsten Schnitt um 180° drehen (unter der Überblendung).
  Festgefahren, gekippt oder > 18 m neben der Route für 4 s: beim Schnitt auf die nächste Straße.
- Beenden: jede Taste, Mausklick, Joypad oder > 40 px Mausbewegung (die ersten 0,8 s nicht, sonst
  beendet ihn der Klick im Menü). Zeitraffer: Einstellungen > Spiel „Chill-Modus: Zeitraffer“
  (normal / 4-fach / 12-fach, `[spiel] chill_zeit`), teilt `DayNight.day_length_minutes` solange.
- Testen: `--bench=120 --chill --benchshot=10,25,40` (Chill-Modus fährt, Fotos, Ausgabe alle 5 s
  „Chill: Einstellung, Tempo, Position“), z. B. Landstraße mit Sackgasse `--pos=-660,459
  --heading=103`, Talsperre `--pos=2400,4180 --heading=86`. Gemessen 150 s ab Buchhof: 96–127 FPS
  (Fenster), Sackgasse bei Mühlingen gewendet, durch Buchhof mit ~50 km/h.

## Pausemenü und Einstellungen

- Pausemenü (Teil 6, `pause_menu.gd`, Esc): Glas mit echter Unschärfe (Spiel pausiert),
  Weiterfahren, Garage, Karte, Fotomodus, Chill-Modus, Einstellungen, Spiel beenden (zweiter Klick).
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
- Audio-Busse (`default_bus_layout.tres`): Master, Motor (alle Auto-Geräusche, über den
  Tunnel-Bus mit Hall), Umgebung (Regen, Wind, Donner), Musik (vorbereitet, noch keine Musik).
  Spiel: HUD-Farbe, Sportauspuff, km/h oder mph (Tacho), automatisches Wetter, Tageslänge.
