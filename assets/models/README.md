# 3D-Modelle (Autos, Verkehr, Raststätte)

Die Modelle sind **nicht im Git-Repository**: Ihre Lizenzen erlauben keine bzw. nur
eingeschränkte Weitergabe. Fehlt ein Garage-Modell, taucht das Auto in der Garage nicht auf
(so entsteht auch die Download-Version, siehe docs/mac-app.md). Fehlen alle, stehen alle ausgegraut
(„Modell fehlt“) und man fährt mit einer einfachen Platzhalter-Box. Fehlen die
Verkehrsmodelle oder die Tankstelle, nimmt das Spiel die einfachen, im Code gebauten Formen.

## So kommt ein Modell ins Projekt

1. Den Sketchfab-Link unten öffnen und mit einem (kostenlosen) Sketchfab-Konto auf
   **Download 3D Model** klicken. Format wie in der Tabelle: **glTF** (ZIP mit `scene.gltf`,
   `scene.bin`, `textures/`) oder **GLB** (eine einzelne `.glb`-Datei).
2. glTF: das ZIP entpacken und den Inhalt in den angegebenen Ordner unter `assets/models/`
   legen. GLB: die `.glb`-Datei so, wie sie heißt, in den angegebenen Ordner legen.
3. Im Terminal im Projektordner nacheinander ausführen (importiert die Modelle, begrenzt die
   Texturen auf 2048 px, beim Verkehr auf 1024 px, und schaltet Mipmaps und Kompression ein):

   ```
   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import
   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s res://tools/setup_models.gd
   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import
   ```
4. Nur für Verkehr und Tankstelle (einmal, mit Fenster, dauert ein paar Minuten): bereitet die
   schweren Modelle als leichte Spiel-Versionen vor (Innenraum weg, vereinfacht, echte Größe),
   gespeichert in `prepared/` im jeweiligen Ordner:

   ```
   /Applications/Godot.app/Contents/MacOS/Godot --path . -s res://tools/setup_traffic_models.gd
   ```

Wie jedes Modell ins Spiel eingebaut wird (Drehung, Räder, Materialien, Fahrwerte), steht in
seinem Profil in `cars/`.

## Die Autos

| Auto | Ordner | Sketchfab | Lizenz |
|---|---|---|---|
| BMW M2 Competition (F87) | `bmw_m2/` | https://sketchfab.com/3d-models/bmw-m2-competition-grays-widebody-9c752f161d8c42bf85dd2a1ddbddd543 | CC BY-NC-ND 4.0 |
| BMW M3 (E30) | `free_bmw_m3_e30/` | https://sketchfab.com/3d-models/free-bmw-m3-e30-ac3c7013434e403e8faff87948caf422 | CC BY 4.0 |
| BMW M3 GTS (E92) | `2011_bmw_e92_m3_gts/` | https://sketchfab.com/3d-models/2011-bmw-e92-m3-gts-5ef0b693916f413ab444fe46b4456a1a | CC BY 4.0 |
| BMW M5 Competition (F90) | `bmw_m5_f90/` | https://sketchfab.com/3d-models/bmw-m5-f90-5478e978bd634337adc8e3dc413fbfa3 | CC BY 4.0 |
| BMW M5 (G90, 2025) | `2025_bmw_m5_sedan/` | https://sketchfab.com/3d-models/2025-bmw-m5-sedan-4ab34c43bada482b8e467be97ebaeba3 | CC BY-NC-SA 4.0 |
| BMW M4 CSL (G82, 2023) | `bmw_m4_csl_2023/` (GLB) | https://sketchfab.com/3d-models/bmw-m4-csl-2023-26d05968e63b4fc28205cbb9abb0ea41 | CC BY 4.0 |
| Mercedes-Benz SL 65 AMG Black Series (R230, 2009) | `2009_mercedes-benz_sl65_amg_black_series/` (GLB) | https://sketchfab.com/3d-models/2009-mercedes-benz-sl65-amg-black-series-768964f11377497eb1b3832972eb23e1 | CC BY-NC-SA 4.0 |
| Mercedes-Benz C 63 AMG Coupé Black Series (C204, 2013) | `2013_mercedes-benz_c63_amg_coupe_black_series/` (GLB) | https://sketchfab.com/3d-models/2013-mercedes-benz-c63-amg-coupe-black-series-1e043f59cf2545c88ba6c72fff1701ac | CC BY-NC-SA 4.0 |

## Verkehr und Raststätte

| Modell | Ordner | Sketchfab | Lizenz |
|---|---|---|---|
| Kia Stinger | `verkehr/kia_stinger/` (GLB) | https://sketchfab.com/3d-models/kia-stinger-b1493e68069f4b869743de7a4220a4f4 | CC BY 4.0 |
| Audi S3 Limousine (2014) | `verkehr/2014_audi_s3_limousine/` (GLB) | https://sketchfab.com/3d-models/2014-audi-s3-limousine-33056acd771241638ebe74109ba2777a | CC BY 4.0 |
| Pontiac Aztek (2005) | `verkehr/2005_pontiac_aztek/` (GLB) | https://sketchfab.com/3d-models/2005-pontiac-aztek-12b60d84bd044960881f72d079fabdc8 | CC BY-NC-SA 4.0 |
| Honda Accord (2021) | `verkehr/2021_honda_accord/` (GLB) | https://sketchfab.com/3d-models/2021-honda-accord-e742636e46814de5af1568542e7c9bdb | CC BY-NC-SA 4.0 |
| VW ID. Buzz GTX (2023) | `verkehr/2023_volkswagen_id_buzz_gtx/` (GLB) | https://sketchfab.com/3d-models/2023-volkswagen-id-buzz-gtx-3cc84dbea5b2495ba1f9468e8b4668d9 | CC BY-NC 4.0 |
| Lexus LC 500 (2017) | `verkehr/2017_lexus_lc_500/` (GLB) | https://sketchfab.com/3d-models/2017-lexus-lc-500-06f7ccfdf2aa4ef7afce64da59cacb16 | CC BY-NC-SA 4.0 |
| Tankstelle (Small Red Gas Station) | `raststaette/small_red_gas_station/` (GLB) | https://sketchfab.com/3d-models/small-red-gas-station-1a0feafb044148e585bfe588afe617b8 | CC BY 4.0 |

Die NC-Lizenzen (M2, M5 G90, SL 65, C 63, Aztek, Accord, ID. Buzz, LC 500) erlauben keine
kommerzielle Nutzung. Bilder im README auf GitHub nur mit CC-BY-Modellen.

## Credits (Pflicht laut Lizenz, auch im Spiel unter Garage > Credits)

- This work is based on "BMW M2 Competition [Grays Widebody]" (https://sketchfab.com/3d-models/bmw-m2-competition-grays-widebody-9c752f161d8c42bf85dd2a1ddbddd543) by blakebella (https://sketchfab.com/blakebella) licensed under CC-BY-NC-ND-4.0 (http://creativecommons.org/licenses/by-nc-nd/4.0/)
- This work is based on "[FREE] BMW M3 E30" (https://sketchfab.com/3d-models/free-bmw-m3-e30-ac3c7013434e403e8faff87948caf422) by Martin Trafas (https://sketchfab.com/Bexxie) licensed under CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/)
- This work is based on "2011_bmw_e92_m3_gts" (https://sketchfab.com/3d-models/2011-bmw-e92-m3-gts-5ef0b693916f413ab444fe46b4456a1a) by Car design (https://sketchfab.com/AnswerBlue38) licensed under CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/)
- This work is based on "Bmw M5 F90" (https://sketchfab.com/3d-models/bmw-m5-f90-5478e978bd634337adc8e3dc413fbfa3) by RES1N (https://sketchfab.com/Resinnnn) licensed under CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/)
- This work is based on "2025 BMW M5 Sedan" (https://sketchfab.com/3d-models/2025-bmw-m5-sedan-4ab34c43bada482b8e467be97ebaeba3) by Ddiaz Design (https://sketchfab.com/ddiaz-design) licensed under CC-BY-NC-SA-4.0 (http://creativecommons.org/licenses/by-nc-sa/4.0/)
- This work is based on "BMW m4 CSL 2023" (https://sketchfab.com/3d-models/bmw-m4-csl-2023-26d05968e63b4fc28205cbb9abb0ea41) by Black Snow (https://sketchfab.com/BlackSnow02) licensed under CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/)
- This work is based on "2009 Mercedes-Benz SL65 AMG Black Series" (https://sketchfab.com/3d-models/2009-mercedes-benz-sl65-amg-black-series-768964f11377497eb1b3832972eb23e1) by Ddiaz Design (https://sketchfab.com/ddiaz-design) licensed under CC-BY-NC-SA-4.0 (http://creativecommons.org/licenses/by-nc-sa/4.0/)
- This work is based on "2013 Mercedes-Benz C63 AMG Coupe Black Series" (https://sketchfab.com/3d-models/2013-mercedes-benz-c63-amg-coupe-black-series-1e043f59cf2545c88ba6c72fff1701ac) by Ddiaz Design (https://sketchfab.com/ddiaz-design) licensed under CC-BY-NC-SA-4.0 (http://creativecommons.org/licenses/by-nc-sa/4.0/)
- This work is based on "Kia Stinger" (https://sketchfab.com/3d-models/kia-stinger-b1493e68069f4b869743de7a4220a4f4) by Car2022 (https://sketchfab.com/Car2022) licensed under CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/)
- This work is based on "2014 Audi S3 Limousine" (https://sketchfab.com/3d-models/2014-audi-s3-limousine-33056acd771241638ebe74109ba2777a) by tonielpro520 (https://sketchfab.com/tonielpro520) licensed under CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/)
- This work is based on "2005 Pontiac Aztek" (https://sketchfab.com/3d-models/2005-pontiac-aztek-12b60d84bd044960881f72d079fabdc8) by OUTPISTON (https://sketchfab.com/outpiston) licensed under CC-BY-NC-SA-4.0 (http://creativecommons.org/licenses/by-nc-sa/4.0/)
- This work is based on "2021 Honda Accord" (https://sketchfab.com/3d-models/2021-honda-accord-e742636e46814de5af1568542e7c9bdb) by Ddiaz Design (https://sketchfab.com/ddiaz-design) licensed under CC-BY-NC-SA-4.0 (http://creativecommons.org/licenses/by-nc-sa/4.0/)
- This work is based on "2023 Volkswagen ID Buzz GTX" (https://sketchfab.com/3d-models/2023-volkswagen-id-buzz-gtx-3cc84dbea5b2495ba1f9468e8b4668d9) by BloxBloger (https://sketchfab.com/BloxBloger) licensed under CC-BY-NC-4.0 (http://creativecommons.org/licenses/by-nc/4.0/)
- This work is based on "2017 Lexus LC 500" (https://sketchfab.com/3d-models/2017-lexus-lc-500-06f7ccfdf2aa4ef7afce64da59cacb16) by Ddiaz Design (https://sketchfab.com/ddiaz-design) licensed under CC-BY-NC-SA-4.0 (http://creativecommons.org/licenses/by-nc-sa/4.0/)
- This work is based on "Small Red Gas Station" (https://sketchfab.com/3d-models/small-red-gas-station-1a0feafb044148e585bfe588afe617b8) by SmashedBones (https://sketchfab.com/SmashedBones) licensed under CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/)

Für die Spielversion wurden die Modelle verändert (skaliert, Räder getrennt, Teile
ausgeblendet oder zusammengefasst, eigene Materialien). Die Änderungen passieren beim Laden
im Spiel, die Originaldateien bleiben unverändert.
