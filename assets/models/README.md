# 3D-Modelle

## BMW M2 Competition (Spielerauto)

Das Automodell ist **nicht im Git-Repository**, weil seine Lizenz (CC BY-NC-ND 4.0)
keine Weitergabe erlaubt. Ohne das Modell startet das Spiel trotzdem, dann fährt man
mit einer einfachen Platzhalter-Box.

So kommt das Modell ins Projekt:

1. Auf Sketchfab „BMW M2 Competition [Grays Widebody]“ von blakebella öffnen:
   https://sketchfab.com/3d-models/bmw-m2-competition-grays-widebody-9c752f161d8c42bf85dd2a1ddbddd543
2. Mit einem (kostenlosen) Sketchfab-Konto auf **Download 3D Model** klicken und das
   Format **glTF** wählen (nicht „GLB“ oder „USDZ“).
3. Das ZIP entpacken und den Inhalt nach `assets/models/bmw_m2/` legen, so dass dort liegen:
   - `assets/models/bmw_m2/scene.gltf`
   - `assets/models/bmw_m2/scene.bin`
   - `assets/models/bmw_m2/textures/` (mit den PNG-Dateien)
   - `assets/models/bmw_m2/license.txt`
4. Godot einmal im Editor öffnen (oder `Godot --headless --path . --import` ausführen),
   damit das Modell importiert wird.

`scripts/car_model.gd` erkennt das Modell beim Start automatisch und ersetzt die Box.

Credit (Pflicht laut Lizenz): This work is based on "BMW M2 Competition [Grays Widebody]"
(https://sketchfab.com/3d-models/bmw-m2-competition-grays-widebody-9c752f161d8c42bf85dd2a1ddbddd543)
by blakebella (https://sketchfab.com/blakebella) licensed under CC-BY-NC-ND-4.0
(http://creativecommons.org/licenses/by-nc-nd/4.0/)
