# Mac-App und GitHub

## Mac-App bauen

- Mac-App „Car Driving World“ (Teil 6): bauen mit `tools/build_mac_app.sh` → `build/Car Driving
  World.app` (`/build/` ist in .gitignore). Export-Vorlage `export_presets.cfg` („macOS“): Bundle-ID
  `io.github.nicks2d.cardrivingworld`, Version 1.0, Architektur „universal“ (die offizielle Vorlage
  hat nur Universal-Programme, „arm64“ bricht ab). Das Skript macht danach mit `lipo -thin arm64`
  eine reine Apple-Silicon-App, setzt CFBundleName/CFBundleDisplayName auf „Car Driving World“
  (Godot nimmt den Projektnamen) und signiert ad-hoc neu (`codesign --sign -`). Filter: ohne Original-GLBs von Verkehr und Tankstelle (es reichen
  die vorbereiteten `prepared/model.res`), ohne `kia_stinger`, `screenshots/`, `docs/` (hat
  `.gdignore`) und `tools/`; `*.icns` kommt mit. Die App enthält die Automodelle (teils NC/ND):
  nur für Nicks Mac, nicht hochladen, kein Release.
- Export für arm64 verlangt `rendering/textures/vram_compression/import_etc2_astc=true` (Texturen
  zusätzlich als ASTC; die App nimmt ASTC, der Editor weiter S3TC/BPTC). Export-Vorlagen 4.7.2:
  nur `macos.zip` + `version.txt` in `~/Library/Application Support/Godot/export_templates/
  4.7.2.stable/` (aus dem offiziellen .tpz).
- Logo (`assets/icon/`): `icon.svg` (Lichtspur bei Nacht, selbst gezeichnet), `icon.png` (1024 px,
  Fenster-/Dock-Icon `application/config/icon`), `icon.icns` (mit `iconutil` aus 16–1024 px, für
  Export und `config/macos_native_icon`), `splash.png` (1600 × 900, Startbildschirm, Hintergrund
  #050B1A). Entwürfe und Generator lagen im Scratchpad (Serpentine im Sonnenuntergang, Lichtspur,
  Endlos-Schleife).
- Name: Der Projektname bleibt „Endlose Welt“, denn danach heißt der Speicherordner
  (`~/Library/Application Support/Godot/app_userdata/Endlose Welt`): Editor und App teilen sich so
  Einstellungen, Karte, Orte, Aussichtspunkte und Fotos. Der Fenstertitel kommt aus
  `Game.APP_TITLE` („Car Driving World“).
- Exportierte Projekte: `DirAccess.get_files_at("res://…")` sieht dort nur die umgewandelten
  Dateien. Deshalb sucht `CarModel.model_path` die .glb mit `ResourceLoader.list_directory`.

## Messungen und Bekanntes

- Gemessen (12.11., Akku 60 %, Mac warm, `--bench=30 --highway --full --quality=hoch`, 2940 × 1912,
  abwechselnd): Editor 62,4 / 64,6 FPS (1%-Low 43,7 / 42,6), App 60,5 / 59,9 FPS (40,9 / 37,8).
  Die App ist ~5 % langsamer, vermutlich wegen ASTC statt S3TC/BPTC. App starten mit Argumenten:
  `"/Applications/Car Driving World.app/Contents/MacOS/Endlose Welt" -- --bench=30 …`.
- Spielstände nach App-Start und Tests verglichen (Sicherung vorher): unverändert, die App schreibt
  ihr Protokoll in denselben Ordner (`logs/godot.log`). `--quitafter=S` startet das Spiel ganz
  normal (Garage, Spielstände) und beendet es nach S Sekunden sauber (zum Prüfen von Start/Ende).
- Bekannt: Nur die exportierte App meldet beim Beenden „1 shaders of type ParticlesShaderRD were
  never freed“ und einen nicht freigegebenen Shader. Harmlos (passiert erst beim Schließen). Im
  Editor nicht, in einem leeren Testprojekt mit Partikeln auch nicht; Regen-Partikel waren es
  nicht. Ursache noch offen.

## README-Bilder

- README-Bilder (`docs/screenshots/*.jpg`, 1280 × 720, JPG 86 %): nur CC-BY-Modelle (E30, E92, F90,
  M4 CSL, Audi S3, Tankstelle), also immer `--car=e92|m4csl|f90|e30` (ohne `--car` fährt im Test der
  M2!) und `--traffic=0` bzw. `--boxcars` (Raststätte: geparkte Autos als Kästen). `docs/` hat eine
  `.gdignore` (Godot importiert die Bilder nicht). Neue Bilder: garage, dam, waterfall, bridge
  (Hängebrücke `--pos=-10183,-9442 --cam=-10183,-10100,30 --lookat=-10183,-9442,35`), bath, moon,
  dyno, rest-area, village (Buchhof nachts `--pos=-660,459 --heading=103 --time=22`), explorer-map
  (`--bench=60 --highway --map`), chill (`--bench=62 --chill --car=m4csl --pos=2400,4180`).

## Autos unsichtbar in der App (behoben 13.11., Teil 7)

- Befund: In der exportierten App waren Garage-Autos unsichtbar (nur das Kennzeichen schwebte über
  der Straße), Log ohne Fehler. `--meshcheck` (Spielerauto, Verkehrsmodell, Tankstelle zählen) zeigte:
  Modell geladen, 96 sichtbare Meshes statt 67 im Editor, und die Listen `wheel_parts`, `caliper_parts`,
  `hidden_parts` des Profils waren leer (Editor: „wms13p*“ usw.).
- Ursache: Godots Umwandlung der Text-Ressourcen (`.tres`) in Binärdateien beim Export
  (`editor/export/convert_text_resources_to_binary`, Standard an) verliert die `PackedStringArray`-Werte
  der Autoprofile. Ohne Rad-Muster findet `CarModel._build` keine Räder, der Radstand des Modells ist 0,
  `_fit` skaliert mit unendlich → Auto unsichtbar. (Die Vorbelegung `= []` statt `PackedStringArray()`
  war es nicht, getestet; die steht jetzt trotzdem sauber da.)
- Lösung: `editor/export/convert_text_resources_to_binary=false` in project.godot. Danach in der App
  wie im Editor 67 Meshes, Fotos aus der App: M4 CSL, Garage (SL 65), Audi S3 im Verkehr, Raststätte mit
  Tankstelle. Verkehr und Tankstelle (vorbereitete `.res`, schon binär) waren nicht betroffen.
- `CarModel` meldet jetzt eine Warnung, wenn ein Modell nicht geladen werden kann (vorher still
  der Platzhalter).
- Testen gegen die App: `tools/test.sh --app` (OK), Fotos aus der App landen in `user://screenshots`
  (`~/Library/Application Support/Godot/app_userdata/Endlose Welt/screenshots`), z. B.
  `"/Applications/Car Driving World.app/Contents/MacOS/Endlose Welt" --always-on-top -- --shot=NAME
  --meshcheck --car=m2`.
- Hinweis zur Messung vom 12.11. („App ~5 % langsamer“): Damals fehlten in der App die Automodelle
  (unsichtbar), der Vergleich war also nicht fair.
