# Wetter, Jahreszeiten, Himmel, Licht

## Himmel und Licht

- Himmel: eigener Sky-Shader (`shaders/sky.gdshader`), Farben kommen aus Farbverläufen in
  `day_night.gd` (Sonnenhöhe -18° bis +40°). Nachts wird das Sonnenlicht zum Mondlicht.
  Sky-Radiance `process_mode = Incremental` (Realtime kostet merklich FPS).
- Tonemapping AgX, Glow, SSAO, Fernnebel mit Luftperspektive. Volumetrischer Nebel aus
  (Schalter `volumetric_fog` an DayNight, Test mit `--volfog`).
- Himmel (Teil 3): `DayNight.moon_age` (Spieltage, Zyklus 29,53, läuft mit der Uhr, gespeichert in
  `[welt] mondalter`, Garage: 6 Knöpfe Neumond … abnehmende Sichel, `set_moon_phase`). Shader
  (`sky.gdshader`): Scheibe als Kugel beleuchtet (Winkel aus der Phase, zunehmend rechts hell),
  dunkler Teil 1,2 % (Erdschein), Mondhof und Mondlicht mal Beleuchtung (Neumond 5 %).
  Sternschnuppen: in klaren Nächten (Sonne unter −10°, Bewölkung < 0,3) alle 15–50 s eine, zu 25 %
  ein Schwarm aus 3–4 aus einer Richtung; bis zu 4 gleichzeitig (Shader-Arrays `meteors`,
  `meteor_dirs`, 0,6–1,2 s). Lichtverschmutzung: Dörfer (nach Häusern) und Raststätten bis 4 km um
  die Kamera (`RoadNetwork.light_sources`), alle 2 s, weich übergeblendet; weniger und
  schwächere Sterne (Schwelle 0,9945 → 0,9988) und warmer Schein am Horizont zu den Lichtern.
  Testen: `--moon=0.5 --lookmoon --cam=X,Z,H --time=23.5`, `--meteors`.
- Regenbogen (`sky.gdshader`): Hauptbogen 40–42,8° um den Gegenpunkt der Sonne (rot außen),
  schwacher Nebenbogen 50–53,5° (umgekehrt). Weather startet ihn, wenn ein Regen aufhört
  (4 min, die letzten 2,5 min blendet er aus), DayNight zeigt ihn nur bei Sonnenhöhe 1–41° und
  wenn es aufgeklart ist. Test: `--rainbow --time=18`, Blick nach Osten.
- Polarlicht (`sky.gdshader`, `aurora_light`): 14 Schichten übereinander, jede ein welliger
  Streifen am Nordhimmel (−Z), unten grün, oben violett; Strahlen hängen vom Azimut ab (laufen
  im Zenit zusammen wie echte). In klaren Winternächten, jeden Abend mit Chance 1/3 gewürfelt,
  blendet über 1,5 min ein. Test: `--aurora --season=winter --time=23`, Blick nach Norden.

## Wetter

- Wetter (`weather.gd`): 6 Wetterlagen als Wertetabelle (Wolken, Trübheit, Regen, Schnee,
  Nebelfaktor, Talnebel, Wind, Blitze), Übergang 45 s (F5: 8 s, Garage: sofort), automatischer
  Wechsel alle 3–6 min, Wahrscheinlichkeit je Jahreszeit (Herbst mehr Regen/Nebel, Winter
  Schnee). Gespeichert in `user://einstellungen.cfg` (Abschnitt `welt`). Tests (`--shot`,
  `--bench`) laufen immer klar/Sommer, außer mit `--weather=rain|storm|fog|snow|cloudy` und
  `--season=spring|autumn|winter`.
- Die Shader bekommen Wetter und Jahreszeit über globale Shader-Werte (Projekteinstellungen >
  Shader Globals): `wetness`, `road_snow`, `snow_cover`, `snow_line`, `season_spring/autumn/winter`
  (weiche Gewichte), `rain_amount`, `weather_wind`. Nässe steigt in 40 s Regen auf 1 und trocknet
  in 4 min; Schnee auf der Straße liegt nach 60 s, ist 2 min nach dem Schneefall geräumt.
  Grip: nass 0,7, Schnee 0,5 (`Car.grip_factor`), Gischt hinter den Hinterrädern (`Car.wetness`).
- Temperatur (`Weather.temperature`): Jahreszeit 12/22/11/−1 °C, ±5 °C über den Tag (am
  wärmsten 15 Uhr), −0,65 °C pro 100 m über 100 m, Wetter −2 bis −5 °C, beim Schneien ≤ 1 °C.
- Wetter-Geräusche (`weather_sound.gd`): Regen-/Windschleife und 3 Donner, beim Start im
  Hintergrund erzeugt. Donner kommt Entfernung/343 s nach dem Blitz.

## Regen, Schnee, Nebel

- Regen/Schnee (`precipitation.gd`): GPUParticles in einem 36 × 22 × 36-m-Kasten um die Kamera,
  eigener Partikel-Shader schiebt herausfallende Partikel auf die andere Seite (bei jedem Tempo
  gleich dicht). `fixed_fps = 0` und `interpolate = false`, sonst Striche beim Umklappen.
  Regenstriche zeigen in Richtung (Fallgeschwindigkeit − Kamerageschwindigkeit).
- Talnebel (`valley_fog.gdshader`): Bildschirm-Viereck an der Kamera, rechnet aus dem
  Tiefenpuffer die Nebelmenge entlang des Blicks (Dichte nimmt über dem Talboden `ground_level`
  exponentiell ab, Integral exakt). Godots Höhennebel geht nicht: der hängt nicht vom Abstand ab
  und vernebelt das Auto direkt vor der Kamera. Morgens (2–11 Uhr) je nach Jahreszeit/Wetter.
- Regen-Spiegelungen: SSR nur bei Nässe an. Kostet im Vollbild ~2,5 ms (66 → 54 FPS). Deshalb
  schaltet DayNight bei bedecktem Himmel (overcast > 0,75) die Sonnenschatten aus (gibt es bei
  Bedeckung ohnehin nicht). Schlussmessung (Vollbild, `--bench=60`, Mac warm): klar 68,8 FPS,
  Regen 61,3 FPS, 1%-Low ~50 (Ruckler beim Kachel-Laden, wie vorher). SSR abschalten:
  `wet_reflections` am Weather-Node.
- Pfützen (`puddles.gd`, `road.gdshader`): `RoadSegment.sag` = Senke im Höhenprofil (nur Landstraße,
  nicht auf Brücken/in Tunneln) als Punktfarbe → Shader zeigt dort nach Regen Pfützen, die mit der
  Straße trocknen. Ab Nässe 0,4, 25 km/h und Senke 0,45: Fontäne an den Vorderrädern (300 weiche
  Tropfen, seitlich/nach hinten), Platschen, kurzer Ruck am Lenkrad. Regenfahrt 1 km: 4 Fontänen.

## Jahreszeiten

- Jahreszeiten: Laubbäume/Büsche bekommen eine Kopie des Blattmaterials mit `deciduous = true`
  (Frühling hellgrün, Herbst je Baum gelb/orange/rot). Winter: Laubbäume bekommen
  `foliage_bare.gdshader` (Krone per discard ausgedünnt), nur dann, weil discard Leistung kostet.
  Schnee auf Bäumen/Gelände dort, wo die Fläche nach oben zeigt. Schneefallgrenze je Jahreszeit
  750/950/850/250 m. Gras verschwindet unter Schnee.
- Herbstlaub (`autumn_leaves.gd`): Partikel hinter dem Auto nach Herbst-Gewicht × Laubwald (Formel wie
  die Bäume) × Tempo, starten mit 40–75 % des Tempos (Sog), werden schnell langsamer (Dämpfung 7–13)
  und taumeln zu Boden. Blattform als Ellipse, näher als 1,5–4 m an der Kamera ausgeblendet (sonst
  große Flächen im Bild).

## Wolkenschatten

- Wolkenschatten (`cloud_shadow.gdshaderinc`, in Gelände, Straßen, Bäumen und Gras): Rauschmuster
  (`assets/textures/cloud_shadows.tres`, globaler Shader-Wert) im 1,4-km-Maßstab, zieht mit dem
  Wind (`cloud_shadow_wind` × Wetter-Wind). Bedeckung aus dem Wetter: klar ~15 %, bewölkt gut die
  Hälfte im Schatten, darin 50 % dunkler; bei Regen/Nacht aus. Bäume und Gras nehmen den Wert
  an ihrem Standort (Vertex-Shader).
