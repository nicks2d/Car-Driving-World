# Fortschritt im Detail

Die Kurzfassung steht in der CLAUDE.md. Hier die ursprüngliche Meilenstein-Liste und alle
erledigten Aufgaben in der Reihenfolge, in der sie gebaut wurden.

## Meilensteine (ursprünglicher Plan)

1. Auto mit guter Fahrphysik auf flacher Ebene, Kamera folgt
2. Endloses Terrain aus Noise in Chunks, mit Kollision
3. Himmel, Sonne, Tag-Nacht-Wechsel, Schatten, Nebel
4. Prozedurales Straßennetz, das sich ans Gelände anpasst
5. Wasser: Seen, Flüsse, Brücken
6. Vegetation: Bäume, Gras, Felsen (MultiMesh, LOD)
7. Echtes Automodell, Scheinwerfer, Rücklichter, Motorsound
8. Grafik-Politur und Qualitätsstufen, FPS-Anzeige, Einstellungsmenü
9. Verkehr (KI-Autos auf den Straßen) und kleine Orte

## Erledigt

- [x] Meilenstein 0: Setup geprüft
- [x] Meilenstein 1 (Feinabstimmung der Fahrwerte nach Nicks Probefahrt möglich)
- [x] Meilenstein 2 (Terrain, Horizont-Ring, FPS-Anzeige, Screenshot-Werkzeug)
- [x] Meilenstein 3 (Himmel-Shader, Tag-Nacht, Nebel, Schatten, MetalFX)
- [x] Meilenstein 4 (Straßennetz mit Serpentinen, Geländeanpassung, Start auf Straße)
- [x] Meilenstein 5 (Flüsse, Seen, Wasser-Shader, Brücken, Auto im Wasser)
- [x] Meilenstein 6 (Bäume, Büsche, Felsen, Gras mit Wind, Stamm-Kollision)
- [x] Meilenstein 7 (BMW M2 Competition: Modell, Antrieb, Licht, Spuren, Rauch, Sound)
- [x] Extra: Autoauswahl mit Garage (5 BMW, Profile, Showroom, Sound pro Motor)
- [x] Extra: Minimap mit Navi (Kartenkacheln, Route über Orts-Graphen, Abbiege-Hinweise)
- [x] Extra: Wetter und Jahreszeiten (6 Wetterlagen, Regen mit SSR, Talnebel, Schnee, 4 Jahreszeiten)
- [x] Extra: Tunnel (statt verworfener Abschnitte, Röhre mit Lampen, Portale, Hall, Augen-Anpassung)
- [x] Extra: HUD im Glas-Stil, Garage in der Welt
- [x] Extra: Autobahn ohne Tempolimit (Anschlussstellen, Schilderbrücken, Leitpfosten, Navi)
- [x] Extra: Aussichtspunkte (Parkbucht, Schild, Entdecken, Karte, Sammlung) und Fotomodus
- [x] Extra: Pops & Bangs mit Flammen, Turbo-Pfeifen mit Ladedruck, Abblasventil
- [x] Extra: Regenbogen, Wolkenschatten, Polarlicht
- [x] Extra: Tunnel-Bug behoben, mehr Grip (Grip-Stufen), Blinker/Warnblinker/Hupe
- [x] Extra: Anschlussstellen an jedem Stützpunkt, Raststätten mit Tankstelle und Rasthof
- [x] Extra: Drei neue Garage-Autos (M4 CSL, SL 65, C 63) mit Marken-Reitern
- [x] Extra: Verkehr mit echten Modellen, Verzögerungs- und Beschleunigungsstreifen
- [x] Extra: Raststätten neu (Tankstellen-Modell, Pkw-/Lkw-Plätze, Inseln, geparkte Fahrzeuge)
- [x] Extra: Wände in langen Tunneln behoben (Horizont-Ring, Schürzen, Vegetation), Prüfwerkzeug erweitert
- [x] Extra: Tempolimits mit Verkehrszeichen und Schilder-Erkennung im HUD, KI und Navi halten sich daran
- [x] Extra: Tempomat mit Abstandsregelung (ACC, 4 Stufen, Warnung, Limits übernehmen)
- [x] Extra: Lichthupe und spontane Rennen gegen KI-Autos, Vorbeifahrt-Geräusche
- [x] Extra: Fenster runter, Wunschkennzeichen, Pfützen mit Fontäne, Herbstlaub
- [x] Extra: Werkstatt mit Leistungsprüfstand (Messlauf, PS-/Nm-Diagramm, Vergleich von 3 Autos)
- [x] Extra: Talsperren mit Staumauer und Stausee, Wasserfälle mit Becken, Gischt und Rauschen
- [x] Extra: Bogen- und Hängebrücken als Landmarke, Badestellen, Campingplätze und Boote an Seen
- [x] Extra: Mondphasen, Sternschnuppen, Lichtverschmutzung (dunkle Nächte fern von Orten)
- [x] Extra: Entdecker-Karte mit Nebel (Sichtlinien von Aussichtspunkten), Orte-Sammlung in der Garage
- [x] Extra: Chill-Modus (Autopilot auf schönen Strecken, Kamera mit Schnitten wie im Film)
- [x] Extra: Mac-App „Car Driving World“ (Logo, Startbild, Build-Skript, gleiche Spielstände)
- [x] Extra: README auf Englisch mit allen neuen Funktionen und Bildern, GitHub aktualisiert
- [x] Meilenstein 8 (Pausemenü, Einstellungen mit 5 Reitern, Qualitätsstufen, Tastenbelegung, Audio-Busse)
- [x] Meilenstein 9 (Dörfer mit Häusern, Ortsschildern, Laternen; Verkehr mit KI-Autos)
- [x] Aufräumen: CLAUDE.md nach docs/ aufgeteilt (13.11.)
- [x] Testlauf tools/test.sh (Selbsttest mit allen Modi) und Welt-Prüfer tools/world_check.gd (13.11.)
- [x] Teil 3–7 (13.11.): Straßen-Bugs und breitere Rampen, Tunnel-Deckel, Reset, Kennzeichen, Autos in der App
- [x] Teil 1 (16.11.): Cockpit- und Ego-Sicht (Tab) mit drehendem Lenkrad, eigenem Kombiinstrument,
  Rückspiegeln mit Kamera, Kopfbewegung, Innenraum, Regentropfen auf den Scheiben
- [x] Teil 2 (16.11.): Verfolger-Kamera mit Feder und Blick in die Kurve, Sichtfeld 65–75°, Karosserie
  nickt und wankt, Kollisionen mit Funken, Schleifen, Schlag und Kamera-Ruck
- [x] Teil 3 (16.11.): Blinker im Glas der Modelle (Spiegelblinker bei F90 und M4 CSL), Begrüßungslicht
  mit Motorstart in der Garage, Scheinwerfer mit Projektor-Bild (Abblend- und Fernlicht)
- [x] Teil 4 (16.11.): 2WD-Modus für beide M5 (Taste U, Drift 4° → 30°), Zurückspulen bis 10 s mit Verkehr
- [x] Teil 5 (17.11.): Regentropfen auf Lack und Scheiben, Schnee auf dem Auto, vereiste Scheiben am kalten
  Morgen, weicher Kontaktschatten unter eigenem Auto und Verkehr
- [x] Teil 6 (17.11.): Motorsound 48 kHz, Limiter, Signalton mit Ducking bei Ansagen, Hall der Umgebung,
  Pegel per Messung angeglichen
- [x] Teil 1 (17.11.): Vorfahrt an Kreuzungen (Raute, Vorfahrt gewähren, Stopp, Haltelinien, KI wartet),
  Verkehr nach Uhrzeit mit Berufsverkehr und Stau vor Anschlussstellen
- [x] Teil 2 (17.11.): Tunnel-Ausstattung (Notrufnischen, Fluchtweg-Schilder, Ventilatoren, Pannenbuchten,
  Tunnelname am Portal)
- [x] Teil 3 (17.11.): Bäume in drei Stufen (detailliert, mittel, Impostor), weiche Übergänge zwischen den
  Detailstufen, Baumgruppen, Lichtungen, Waldränder, Schilf und Steine am Ufer
- [x] Teil 4 (17.11.): Fels ohne sichtbare Wiederholung, Grasrand am Bankett, Reifenspuren, Flickstellen,
  Kuppen und Senken ausgerundet (bei 250 km/h kein Abheben mehr)
- [x] Teil 5 (17.11., teilweise): Ruckler-Suche pro Bild, Gras und Bäume ruckeln weniger beim Nachladen,
  Shader vorher übersetzen, dünne Teile in der Ferne ausgeblendet. Occlusion Culling noch nicht.
