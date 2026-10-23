# 3D-Modelle (Autos)

Die Automodelle sind **nicht im Git-Repository**: Ihre Lizenzen erlauben keine bzw. nur
eingeschränkte Weitergabe. Fehlt ein Modell, steht das Auto in der Garage ausgegraut
(„Modell fehlt“). Fehlen alle, fährt man mit einer einfachen Platzhalter-Box.

## So kommt ein Modell ins Projekt

1. Den Sketchfab-Link unten öffnen und mit einem (kostenlosen) Sketchfab-Konto auf
   **Download 3D Model** klicken, Format **glTF** wählen (nicht „GLB“ oder „USDZ“).
2. Das ZIP entpacken und den Inhalt in den angegebenen Ordner unter `assets/models/` legen,
   so dass dort `scene.gltf`, `scene.bin`, `textures/` und `license.txt` liegen.
3. Im Terminal im Projektordner nacheinander ausführen (importiert die Modelle, begrenzt die
   Texturen auf 2048 px und schaltet Mipmaps und Kompression ein):

   ```
   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import
   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s res://tools/setup_models.gd
   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import
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

Die NC-Lizenzen (M2, M5 G90) erlauben keine kommerzielle Nutzung.

## Credits (Pflicht laut Lizenz, auch im Spiel unter Garage > Credits)

- This work is based on "BMW M2 Competition [Grays Widebody]" (https://sketchfab.com/3d-models/bmw-m2-competition-grays-widebody-9c752f161d8c42bf85dd2a1ddbddd543) by blakebella (https://sketchfab.com/blakebella) licensed under CC-BY-NC-ND-4.0 (http://creativecommons.org/licenses/by-nc-nd/4.0/)
- This work is based on "[FREE] BMW M3 E30" (https://sketchfab.com/3d-models/free-bmw-m3-e30-ac3c7013434e403e8faff87948caf422) by Martin Trafas (https://sketchfab.com/Bexxie) licensed under CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/)
- This work is based on "2011_bmw_e92_m3_gts" (https://sketchfab.com/3d-models/2011-bmw-e92-m3-gts-5ef0b693916f413ab444fe46b4456a1a) by Car design (https://sketchfab.com/AnswerBlue38) licensed under CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/)
- This work is based on "Bmw M5 F90" (https://sketchfab.com/3d-models/bmw-m5-f90-5478e978bd634337adc8e3dc413fbfa3) by RES1N (https://sketchfab.com/Resinnnn) licensed under CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/)
- This work is based on "2025 BMW M5 Sedan" (https://sketchfab.com/3d-models/2025-bmw-m5-sedan-4ab34c43bada482b8e467be97ebaeba3) by Ddiaz Design (https://sketchfab.com/ddiaz-design) licensed under CC-BY-NC-SA-4.0 (http://creativecommons.org/licenses/by-nc-sa/4.0/)

Für die Spielversion wurden die Modelle verändert (skaliert, Räder getrennt, Teile
ausgeblendet oder zusammengefasst, eigene Materialien). Die Änderungen passieren beim Laden
im Spiel, die Originaldateien bleiben unverändert.
