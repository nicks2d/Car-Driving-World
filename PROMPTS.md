# Prompts für Claude Code

Einfach der Reihe nach kopieren und in Claude Code einfügen.
**Pro Meilenstein am besten eine neue Sitzung starten** (`/clear`), damit Claude
nicht durcheinanderkommt. Alles Wichtige steht ja in der CLAUDE.md.

Erst weitermachen, wenn der aktuelle Meilenstein wirklich läuft und committet ist.

---

## Meilenstein 0 – Setup prüfen

```
Lies die CLAUDE.md. Dann prüf das Setup:
1. Läuft der Godot-MCP-Server? Zeig mir die installierte Godot-Version.
2. Öffnet sich das Projekt ohne Fehler?
3. Leg die Datei .claude/settings.json an, damit du die Godot-MCP-Tools
   und git status/diff/log/add/commit ohne Nachfrage nutzen darfst.
   Pushen und alles andere soll weiterhin nachfragen.
4. Git ist schon eingerichtet. Mach den ersten Commit mit allen Dateien.
Wenn irgendwas fehlt, erklär mir Schritt für Schritt, was ich tun muss.
Danach den Fortschritt in der CLAUDE.md abhaken.
```

## Meilenstein 1 – Auto und Fahrphysik

```
Lies die CLAUDE.md. Wir starten Meilenstein 1.

Ziel: Ein Auto fährt mit glaubwürdiger Fahrphysik auf einer großen, flachen
Ebene. Nimm VehicleBody3D mit vier VehicleWheel3D. Als Karosserie erstmal
eine einfache Box als Platzhalter.

- Steuerung: W/S Gas und Bremse/Rückwärts, A/D lenken, Leertaste Handbremse,
  R setzt das Auto wieder auf die Räder.
- Lenkung wird bei hoher Geschwindigkeit sanfter.
- Kamera folgt weich von hinten, schaut leicht nach vorne in die Fahrtrichtung
  und zoomt bei Tempo etwas raus.
- Geschwindigkeitsanzeige in km/h unten rechts.
- Boden mit Schachbrett- oder Gittertextur, damit man die Bewegung sieht.
- Ein einfaches Licht, damit man was erkennt.

Mach erst einen Plan. Nach dem Bauen: Spiel starten, Fehler prüfen,
mir erklären, wie ich teste, und auf mein Feedback warten.
```

## Meilenstein 2 – Endloses Terrain

```
Lies die CLAUDE.md. Wir starten Meilenstein 2.

Ziel: Die flache Ebene wird durch endloses Gelände ersetzt.

- Höhen aus FastNoiseLite mit mehreren Schichten: große, sanfte Hügel,
  vereinzelt richtige Berge, flachere Täler dazwischen.
- Welt in Chunks aufteilen. Chunks rund um das Auto werden erzeugt,
  weit entfernte wieder gelöscht. Generierung im Hintergrund-Thread,
  damit es beim Fahren nicht ruckelt.
- Jeder Chunk bekommt Kollision, damit das Auto drauf fahren kann.
- Keine Lücken oder Kanten zwischen Chunks.
- Weiter entfernte Chunks mit weniger Detail (LOD).
- Einfacher Terrain-Shader: Gras in flachen Bereichen, Fels an steilen
  Hängen, Schnee auf Gipfeln, weiche Übergänge.
- Das Auto startet sicher auf dem Boden, nicht im Berg.

Mach erst einen Plan, inklusive Chunkgröße und Sichtweite. Danach bauen,
testen, Fehler beheben, erklären.
```

## Meilenstein 3 – Himmel, Licht, Tag und Nacht

```
Lies die CLAUDE.md. Wir starten Meilenstein 3. Das ist der Teil, der die
Stimmung macht, also gib dir Mühe.

- WorldEnvironment mit Himmel (ProceduralSkyMaterial oder eigener Sky-Shader).
- Sonne als DirectionalLight3D mit Schatten, die über den Himmel wandert.
- Kompletter Tag-Nacht-Zyklus: Sonnenaufgang (warm, orange), Mittag (hell,
  klar), Sonnenuntergang (rot, violett), Nacht (dunkelblau mit Mond und Sternen).
  Farben von Himmel, Licht und Nebel ändern sich fließend mit.
- Ein voller Tag dauert standardmäßig 10 Minuten, einstellbar.
  Taste T spult die Zeit schneller vor.
- Nebel in der Ferne, damit das Nachladen der Chunks nicht auffällt.
  Volumetrischer Nebel als Option für die hohe Qualitätsstufe.
- Tonemapping (AgX oder ACES), Glow/Bloom, SSAO.
- Schatten sauber eingestellt (keine flackernden Kanten).

Plan zuerst. Danach bauen, testen. Bitte mich anschließend um Screenshots
bei Tag, Sonnenuntergang und Nacht.
```

## Meilenstein 4 – Straßen

```
Lies die CLAUDE.md. Wir starten Meilenstein 4, den schwierigsten Teil.

Ziel: Ein endloses, prozedurales Straßennetz.

- Straßen werden deterministisch aus dem Seed erzeugt, damit sie an
  Chunk-Grenzen nahtlos weitergehen.
- Mischung aus langen Landstraßen mit weiten Kurven und Serpentinen in den
  Bergen. Keine unrealistisch steilen Steigungen (max. ca. 10–12 %).
- Das Gelände wird unter und neben der Straße angepasst (abgeflacht,
  Böschungen), damit die Straße nicht in der Luft hängt oder im Berg steckt.
- Straßen-Mesh mit Asphalt-Textur, Mittellinie und Randlinien.
- Kreuzungen dürfen erstmal einfach sein.
- Das Auto startet auf einer Straße.

Bevor du Code schreibst: Erklär mir 2–3 mögliche Ansätze für die
Straßengenerierung mit Vor- und Nachteilen und empfiehl einen. Erst nach
meinem OK bauen. Danach testen, Fehler beheben, Screenshots anfordern.
```

## Meilenstein 5 – Wasser und Flüsse

```
Lies die CLAUDE.md. Wir starten Meilenstein 5.

- Seen in tiefen Senken (Wasserspiegel auf fester Höhe).
- Flüsse, die vom Berg ins Tal fließen und sich ins Gelände eingraben.
- Wasser-Shader: leichte Wellen, Spiegelungen, durchsichtig am Ufer,
  dunkler in der Tiefe, Schaum am Rand.
- Wo eine Straße einen Fluss kreuzt, entsteht eine Brücke.
- Wenn das Auto ins Wasser fährt: wird langsamer, nach ein paar Sekunden
  Reset auf die nächste Straße.

Plan zuerst, dann bauen, testen, Screenshots anfordern.
```

## Meilenstein 6 – Vegetation

```
Lies die CLAUDE.md. Wir starten Meilenstein 6.

- Bäume, Büsche, Felsen und Gras pro Chunk prozedural verteilen
  (deterministisch aus dem Seed).
- Dichte abhängig von Höhe und Steigung: Wälder in Tälern, wenig an steilen
  Hängen, nichts über der Baumgrenze, nichts auf Straßen und im Wasser.
- Unbedingt MultiMeshInstance3D für Gras und Bäume nutzen (Performance!)
  und LOD bzw. Sichtweite pro Typ.
- Gras wiegt leicht im Wind (Shader).
- Bäume haben Kollision, Gras nicht.
- Sag mir, welche Modelle ich von Kenney oder Poly Haven herunterladen soll
  und in welchen Ordner. Bis dahin Platzhalter verwenden.

Plan zuerst, dann bauen, FPS prüfen, Screenshots anfordern.
```

## Meilenstein 7 – Das Auto wird schön

```
Lies die CLAUDE.md. Wir starten Meilenstein 7.

- Platzhalter-Box durch ein echtes Automodell ersetzen (sag mir, welches ich
  wo herunterladen soll). Räder drehen und lenken sichtbar mit.
- Scheinwerfer (SpotLight3D) gehen nachts automatisch an, Taste L schaltet manuell.
- Rücklichter, die beim Bremsen heller leuchten.
- Motorsound, dessen Tonhöhe mit der Drehzahl steigt.
  Reifenquietschen beim Driften.
- Optional: kleine Staubwolke hinter den Reifen auf Schotter/Gras.

Plan zuerst, dann bauen, testen.
```

## Meilenstein 8 – Grafik-Politur

```
Lies die CLAUDE.md. Wir starten Meilenstein 8.

- Qualitätsstufen Niedrig / Mittel / Hoch / Ultra (Schatten, Sichtweite,
  Vegetationsdichte, SSAO, SSIL, SDFGI, volumetrischer Nebel, Glow).
- Einstellungsmenü mit ESC: Qualitätsstufe, Sichtweite, Tageszeit,
  Tageslänge, Seed für eine neue Welt.
- FPS-Anzeige (F3 an/aus).
- Farbkorrektur für einen filmischen Look.
- Prüf die Performance: Wo sind die größten Bremsen? Optimiere sie.

Plan zuerst, dann bauen, testen. Bitte um Screenshots auf jeder Qualitätsstufe.
```

## Meilenstein 9 – Verkehr und Orte

```
Lies die CLAUDE.md. Wir starten Meilenstein 9.

- KI-Autos, die auf der rechten Spur den Straßen folgen, abbremsen,
  wenn was im Weg ist, und in der Ferne wieder verschwinden.
- Kleine Dörfer an manchen Kreuzungen: ein paar einfache Häuser,
  Straßenlaternen, die nachts leuchten.
- Performance im Blick behalten.

Plan zuerst, dann bauen, testen.
```

---

# Hilfreiche Prompts zwischendurch

**Wenn was nicht funktioniert:**
```
Es gibt ein Problem: [beschreib genau, was passiert und was du erwartet hast].
Starte das Spiel über den Godot-MCP, lies die Debug-Ausgabe und finde die
Ursache. Erklär mir kurz, was falsch war, bevor du es behebst.
```

**Wenn es hässlich aussieht** (Screenshot mit reinziehen):
```
Hier ein Screenshot. Mir gefällt [z. B. das Licht / die Farben / das Terrain]
noch nicht, es soll mehr wie [z. B. Forza Horizon bei Sonnenuntergang]
aussehen. Mach mir 3 konkrete Vorschläge, was wir ändern können.
```

**Wenn es ruckelt:**
```
Das Spiel ruckelt, vor allem wenn [z. B. ich schnell fahre]. Finde heraus,
was so viel Leistung frisst, und optimiere es, ohne dass die Grafik
deutlich schlechter wird.
```

**Wenn Claude was kaputt gemacht hat:**
```
Seit der letzten Änderung geht [X] nicht mehr. Schau dir mit git diff an,
was sich geändert hat, und repariere es. Wenn das nicht klappt, setz auf
den letzten funktionierenden Commit zurück.
```

**Projekt auf GitHub hochladen:**
```
Erstell auf GitHub ein privates Repository „endlose-welt“, verbinde es
mit diesem Projekt und pushe den aktuellen Stand.
```

**Eine Spielversion zum Weitergeben bauen:**
```
Erklär mir, wie ich aus dem Projekt eine Version exportiere, die ich
ohne Godot starten und an Freunde schicken kann.
```

---

# Sammel-Prompts (große Brocken)

## Die ganze Welt (Meilensteine 2 bis 6 am Stück)

Großer Prompt, der lange läuft und einiges vom Nutzungslimit braucht.
Am besten in einer frischen Sitzung abschicken.

```
Lies die CLAUDE.md und die PROMPTS.md. Meilenstein 0 und 1 sind fertig.
Heute machst du ausnahmsweise mehrere Meilensteine am Stück: 2 (Terrain),
3 (Himmel, Licht, Tag-Nacht), 4 (Straßen), 5 (Wasser) und 6 (Vegetation).
Die genauen Anforderungen pro Meilenstein stehen in der PROMPTS.md.

Ziel am Ende: Ich fahre durch eine endlose, glaubwürdige Landschaft.
Große Bergketten mit Schnee am Horizont, Täler mit Wäldern, Seen und
Flüsse mit Brücken, Landstraßen und Serpentinen, die sauber im Gelände
liegen, und ein Himmel mit Sonnenauf- und -untergang. Die Stimmung soll
an Forza Horizon erinnern. Am Horizont sollen immer Berge zu sehen sein,
auch hinter der Sichtweite (z. B. ein grober, weit entfernter Gelände-Ring),
damit die Welt nicht einfach im Nebel endet.

So gehst du vor:
- Mach zuerst einen Gesamtplan für alle fünf Meilensteine und zeig ihn mir.
  Nach meinem OK arbeitest du alles nacheinander ab, ohne bei jedem
  Meilenstein auf mich zu warten.
- Den Ansatz für die Straßen wählst du selbst. Schreib in der CLAUDE.md
  kurz auf, warum.
- Nach jedem Meilenstein: Spiel über den Godot-MCP starten, Fehler und
  Warnungen beheben, committen, Fortschritt in der CLAUDE.md abhaken.
- Bau dir eine Screenshot-Funktion: ein Startargument, das das Auto an eine
  bestimmte Stelle setzt, die Tageszeit einstellt, nach ein paar Sekunden
  ein PNG speichert und das Spiel beendet. Schau dir die Bilder selbst an
  und verbessere die Optik, bevor du weitermachst. Die Bilder kommen in
  einen Ordner screenshots/, der in die .gitignore gehört.
- Performance: FPS-Anzeige einbauen und nach jedem Meilenstein prüfen.
  Ziel sind 60 FPS auf meinem Mac (Apple Silicon). Wenn es eng wird, lieber
  Sichtweite und Dichte über @export-Werte runterdrehen als Features streichen.
- Das Auto und seine Fahrphysik nicht verändern, außer etwas ist kaputt.
  Das Auto muss immer auf einer Straße starten.
- Assets: Du darfst CC0-Texturen, HDRIs und Modelle von Poly Haven,
  ambientCG und Kenney selbst herunterladen (frag mich vorher) und trägst
  sie in assets/CREDITS.md ein. Wo das nicht geht: Platzhalter nehmen und
  mir am Ende sagen, was ich wo herunterladen soll.
- Wenn du feststeckst oder etwas Großes umbauen musst: aufhören und mich fragen.

Am Ende: kurze Zusammenfassung, was jetzt drin ist, welche Tasten es gibt,
was ich noch herunterladen muss und was dir optisch noch nicht gefällt.
```

## Das Auto als BMW M2 Competition (F87)

Das 3D-Modell liegt schon in `assets/models/bmw_m2/`.
Erst abschicken, wenn der Welt-Prompt fertig ist, und in einer neuen Sitzung.

```
Lies die CLAUDE.md. Wir machen Meilenstein 7: Das Auto soll aussehen und
sich fahren wie ein BMW M2 Competition (F87). Das 3D-Modell liegt unter
assets/models/bmw_m2/ (scene.gltf mit scene.bin und Texturen).

Was ich schon über das Modell weiß:
- „BMW M2 Competition [Grays Widebody]“ von blakebella (Sketchfab),
  Lizenz CC BY-NC-ND 4.0. Den Credit-Text aus license.txt in
  assets/CREDITS.md übernehmen.
- Wegen der Lizenz kommt das Modell nicht ins Git-Repo: Nimm
  assets/models/bmw_m2/ in die .gitignore auf und schreib in eine
  README.md, wo man das Modell herunterlädt und wohin es gehört.
  Ohne das Modell soll das Spiel trotzdem starten (dann mit Platzhalter-Box).
- Es hat ca. 713.000 Dreiecke, viel davon Innenraum, Motor und Auspuff.
  Teile, die man von außen nicht sieht, ausblenden oder vereinfachen und
  LODs nutzen. Das Auto darf die FPS nicht spürbar drücken.
- Die vier Räder sind eigene Gruppen (Nodes „wms13p“ bis „wms13p.003“,
  jeweils Reifen, Felge und Bremsscheibe). Prüf, wo ihr Drehpunkt liegt:
  Zum Drehen und Lenken braucht jedes Rad einen Drehpunkt in der Radmitte.
  Die Bremssättel (polySurface…) drehen sich nicht mit.
- Es ist eine Widebody-Version mit Rennaufklebern (Greddy, Bosch usw.).
  Mach die Aufkleber per Taste K ein- und ausschaltbar, Standard: an.

Modell einbauen:
- Schau dir zuerst an, wie das Modell aufgebaut ist (Nodes, Meshes,
  Materialien, Anzahl Dreiecke), und erzähl mir kurz, was du gefunden hast.
- Platzhalter-Box durch das Modell ersetzen, richtig skalieren (echtes Auto:
  ca. 4,46 m lang, 1,41 m hoch, Radstand ca. 2,69 m; der Widebody ist
  breiter als das Serienauto) und so ausrichten, dass die Nase in
  Fahrtrichtung zeigt. Die Physik-Räder an die Position der Modell-Räder setzen.
- Die vier Räder müssen sich sichtbar drehen und die Vorderräder lenken.
- Kollisionsform an die Karosserie anpassen.

Optik:
- Echter Autolack: metallisch, mit Klarlack (clearcoat) und Spiegelungen
  der Umgebung. Standardfarbe kräftiges Blau, Taste C wechselt durch ein
  paar Farben.
- Scheiben leicht getönt und spiegelnd, Felgen dunkel, Reifen matt.
- Scheinwerfer (SpotLight3D mit Schatten) gehen nachts automatisch an,
  Taste L schaltet manuell. Scheinwerfer und Rücklichter leuchten
  (Emission), Rücklichter beim Bremsen heller.
- Reifenspuren und etwas Rauch, wenn das Heck beim Driften ausbricht.

Fahrgefühl wie ein M2 Competition (die aktuellen Werte stehen in der CLAUDE.md):
- Heckantrieb, ca. 410 PS, 550 Nm, ca. 1.575 kg, Gewicht etwa 50:50 verteilt.
- Ziel: 0–100 km/h in ca. 4,2 s, Spitze 250 km/h (abgeregelt).
- 7-Gang-Automatik mit Drehzahl und Schaltpunkten, Drehzahlmesser im HUD.
- Das Heck darf bei viel Gas in Kurven ausbrechen, soll aber
  kontrollierbar bleiben.
- Danach 0–100, Spitze und Bremsweg neu messen und in die CLAUDE.md eintragen.

Sound:
- Motorsound, der mit Drehzahl und Gas mitgeht (Reihensechszylinder-
  Charakter), Schaltgeräusch, Reifenquietschen beim Driften. Wenn du keine
  passenden CC0-Sounds findest, sag mir, wo ich welche herbekomme.

Plan zuerst, dann bauen. Falls es noch keine Screenshot-Funktion gibt, bau
eine und schau dir das Auto damit bei Tag und bei Nacht selbst an.
Commit nach jedem funktionierenden Schritt.
```

## Straßen und Bäume reparieren + BMW (nach Meilenstein 6)

In einer neuen Sitzung abschicken.

```
Lies die CLAUDE.md. Meilensteine 0 bis 6 sind fertig. In dieser Sitzung
machst du zwei Sachen nacheinander: Teil 1 repariert Straßen und Bäume,
Teil 2 ist der BMW (Meilenstein 7). Mach zuerst einen Plan für beide Teile.
Nach meinem OK arbeitest du alles am Stück ab und committest nach jedem
funktionierenden Schritt.

TEIL 1: STRASSEN UND BÄUME

Was mir beim Fahren auffällt:
- Die Straßen sind zu schmal.
- In Kurven sehen sie unsauber aus und werden enger.
- Straßen laufen ineinander, vor allem an Kreuzungen.
- Bäume kommen von unten durch den Boden bzw. die Straße.

Was im Code schon gefunden wurde (bitte prüfen):
- road_query.gd überspringt Brückenstücke komplett (continue bei bridge).
  Dadurch weiß is_on_road() nichts von Brücken, und unter Brücken und
  Viadukten wachsen Bäume und Felsen, die durch die Fahrbahn stechen.
  Für die Geländeanpassung ist das Überspringen richtig, für Bäume und
  Felsen nicht.
- road_segment.gd macht in engen Kurven die Innenseite schmaler
  (inner_limit), statt die Kurve selbst weiter zu machen. Deshalb wird
  die Straße in Kurven eng und unsauber.
- Der Weg aus der A*-Suche wird nur leicht geglättet (_simplify mit 2,5 m,
  Chaikin, _relax). Das lässt kleine Wackler und zu enge Radien übrig.
- Kreuzungen sind nur eine flache runde Scheibe (pad_radius 11 m), die
  3 cm über den Straßenenden liegt. Darunter überlappen sich die Straßen
  samt Markierungen.
- Straßen von verschiedenen Orten können sich unterwegs kreuzen, ohne dass
  dort eine Kreuzung entsteht.

So soll es danach sein:
1. Breiter: Fahrbahn ca. 9 m (zwei Spuren) plus Bankett ca. 1,5 m pro
   Seite, über die @export-Werte einstellbar. Geländeanpassung, Bäume,
   Autopilot und Startposition passen sich automatisch an.
2. Saubere Kurven: Mindestradius für die Mittellinie, auf normalen
   Straßen ca. 60 m, nur in Serpentinen-Kehren kleiner, aber mindestens
   ca. 20 m. Die Breite bleibt in Kurven immer gleich. Idee: den Weg aus
   der Wegsuche auf wenige Kontrollpunkte vereinfachen und dann eine glatte
   Kurve (z. B. Catmull-Rom-Spline) durchlegen. Ziel sind lange Geraden und
   weite, fließende Bögen wie bei echten Landstraßen, keine Schlangenlinien.
3. Leichte Querneigung in Kurven (ein paar Prozent), damit es sich
   natürlich fährt.
4. Echte Kreuzungen statt der Scheibe: Die Straßen enden am Rand der
   Kreuzung, die Kreuzung hat eine eigene Asphaltfläche mit sauberen
   Übergängen, ohne Überlappung und ohne Flackern (Z-Fighting).
   Markierungen enden vor der Kreuzung. Wenn es damit sauberer wird,
   gerne ein kleiner Kreisverkehr bei 3 oder mehr Straßen.
5. Keine Straße darf eine andere unterwegs überlappen. Wenn sich zwei
   Abschnitte kreuzen: entweder richtige Kreuzung auf gleicher Höhe,
   Brücke bei großem Höhenunterschied oder einen der beiden
   deterministisch weglassen. Entscheide selbst, was am saubersten ist,
   und trag es in der CLAUDE.md ein.
6. Bäume und Felsen: Nichts darf durch Fahrbahn, Brücken, Böschungen oder
   Kreuzungen wachsen. Prüf auch, ob Bäume beim Wechsel der Detailstufe
   oder an steilen Hängen schweben oder im Boden versinken.
7. Wenn noch Zeit ist: Leitplanken an hohen Böschungen, auf Brücken und
   in Serpentinen.

Prüfen: Mit dem Screenshot-Werkzeug eine Serpentine, eine Kreuzung, eine
Brücke und eine lange Gerade anschauen, auch von oben (--fly). Mit
--bench=60 sicherstellen, dass der Autopilot weiterhin am Stück
durchfährt. Die FPS dürfen nicht spürbar sinken. Danach committen und die
Notizen in der CLAUDE.md aktualisieren.

TEIL 2: DER BMW

Danach machst du den Abschnitt „Das Auto als BMW M2 Competition (F87)“
aus der PROMPTS.md. Das Modell liegt schon in assets/models/bmw_m2/.
Denk dran: Mein Mac ist ein MacBook Air ohne Lüfter, das Auto darf die
FPS nicht spürbar drücken.

Am Ende: kurze Zusammenfassung, was sich geändert hat, welche Tasten es
gibt und was dir optisch noch nicht gefällt.
```

## Autoauswahl, Minimap mit Navi, Wetter und Jahreszeiten, Tunnel (nach Meilenstein 7)

Großer Prompt, in einer neuen Sitzung abschicken. Läuft lange.

```
Lies die CLAUDE.md. Meilensteine 0 bis 7 sind fertig. In dieser Sitzung
baust du vier neue Sachen, in dieser Reihenfolge: (1) Autoauswahl mit
mehreren Modellen, (2) Minimap mit Navi, (3) Wetter und Jahreszeiten,
(4) Tunnel. Mach zuerst einen Plan für alle vier Teile. Nach meinem OK
arbeitest du alles nacheinander ab, ohne bei jedem Teil auf mich zu warten.
Nach jedem Teil: testen, Fehler beheben, committen, CLAUDE.md aktualisieren.
Die FPS dürfen insgesamt nicht unter 60 fallen (MacBook Air ohne Lüfter,
aktuell ca. 71 FPS).

TEIL 1: AUTOAUSWAHL

In assets/models/ liegen jetzt fünf Autos (glTF: scene.gltf, scene.bin,
textures/, license.txt). Was ich schon über die Modelle weiß:
- bmw_m2/: BMW M2 Competition (F87), schon eingebaut, so lassen.
- free_bmw_m3_e30/: BMW M3 E30, CC BY 4.0 (Martin Trafas). 117.000
  Dreiecke, Maßstab stimmt (Meter), Fahrtrichtung entlang Z. Die Räder
  sind pro Ecke eigene Teile (Felge, Reifen, Bremsscheibe, Bremssattel).
  Texturen teils riesig (bis 18 MB, vermutlich 8K): beim Import auf
  höchstens 2048 px begrenzen.
- 2011_bmw_e92_m3_gts/: BMW M3 GTS (E92), CC BY 4.0 (AnswerBlue38). Nur
  46.000 Dreiecke, aber winziger Maßstab (ca. 1:100). Felgen,
  Bremsscheiben, Bremssättel und Reifen (vermutlich Material „phong11“)
  sind jeweils EIN Mesh für alle vier Räder: beim Laden nach Position in
  vier Räder aufteilen.
- bmw_m5_f90/: BMW M5 Competition (F90), CC BY 4.0 (RES1N). 260.000
  Dreiecke, Maßstab Meter, aber Fahrtrichtung entlang X (um 90° drehen).
  Reifen und Felgen sind auch hier je ein Mesh für alle vier Räder
  (aufteilen). Das Teil „gauge_emissive“ ragt 8 m hinter das Auto:
  ausblenden. Motor ausblenden.
- 2025_bmw_m5_sedan/: BMW M5 (G90, 2025), CC BY-NC-SA 4.0 (Ddiaz Design).
  389.000 Dreiecke in über 1.200 Einzelteilen, winziger Maßstab (ca. 1:100).
  Räder sind pro Ecke getrennt, aber in viele kleine Teile zerlegt (nach
  Position gruppieren). Innenraum (95.000 Dreiecke) und Motor (59.000)
  ausblenden oder stark vereinfachen, unbewegliche Teile zusammenführen
  (sonst viel zu viele Draw Calls).

Was ich will:
- Ein Auswahl-Fenster (Garage), beim Spielstart und jederzeit per Taste G.
  Links die Liste der Autos, rechts das Auto als 3D-Vorschau, die sich
  langsam dreht, in schönem Showroom-Licht. Darunter die Daten: Leistung,
  Drehmoment, Gewicht, Antrieb, 0–100, Spitze. Lackfarbe wählen, Knopf
  „Losfahren“. Mit Maus und Tastatur bedienbar. Das Spiel pausiert,
  solange das Fenster offen ist.
- Beim Wechsel steht das neue Auto an derselben Stelle auf der Straße.
  Das zuletzt gewählte Auto und die Farbe werden gespeichert (user://).
- Jedes Auto bekommt ein eigenes Profil (eine Resource pro Auto):
  Modellordner, Dreh- und Maßstab-Korrektur, Fahrwerte, Antrieb, Getriebe,
  Motorsound, Lichtpositionen. Das M2 kommt ins selbe System, ohne dass
  sich sein Fahrgefühl ändert.
- Fahrwerte ungefähr wie bei den echten Autos:
  - M3 E30: ca. 200 PS, 240 Nm, 1.200 kg, Heckantrieb, 5 Gänge,
    0–100 ca. 6,7 s, Spitze ca. 235 km/h. Leicht und verspielt.
  - M3 GTS E92: V8-Sauger, 450 PS, 440 Nm, 1.530 kg, Heckantrieb,
    7-Gang-DKG, dreht über 8.000/min, 0–100 ca. 4,4 s, Spitze ca. 305 km/h.
  - M5 Competition F90: V8-Biturbo, 625 PS, 750 Nm, ca. 1.900 kg, Allrad
    mit Heckbetonung, 8-Gang-Automatik, 0–100 ca. 3,3 s, Spitze 250 km/h.
  - M5 G90: V8-Hybrid, 727 PS, 1.000 Nm, ca. 2.450 kg, Allrad,
    8-Gang-Automatik, 0–100 ca. 3,5 s, Spitze 250 km/h. Schwer, aber brutal.
  Miss bei jedem Auto 0–100, Spitze und Bremsweg und trag die Werte in
  die CLAUDE.md ein.
- Motorsound pro Auto: E30 als Vierzylinder, M2 bleibt Reihensechser,
  E92 als hochdrehender V8-Sauger, die beiden M5 als tiefer V8-Biturbo.
- Nur das gewählte Auto wird geladen, das alte wird freigegeben. Fehlt
  ein Modellordner, steht das Auto ausgegraut in der Liste („Modell fehlt“).
- Lizenzen: Alle Automodelle bleiben aus dem Git-Repo raus (alles in
  assets/models/ außer README.md in die .gitignore). In
  assets/models/README.md für jedes Auto: Sketchfab-Link, Ordnername und
  Credit-Text aus der license.txt. Credits auch in assets/CREDITS.md und
  im Spiel (kleiner „Credits“-Knopf in der Garage), weil CC BY das verlangt.

TEIL 2: MINIMAP MIT NAVI
- Runde Minimap unten links, dreht sich mit dem Auto, zeigt Straßen,
  Kreuzungen, Wasser und das Auto als Pfeil. Zoom passt sich dem Tempo an.
- Taste M öffnet eine große Karte (Spiel pausiert): mit der Maus
  verschieben und zoomen, Linksklick setzt ein Ziel, Rechtsklick löscht es.
- Route über das Straßennetz zum Ziel, auf Minimap und Karte farbig
  eingezeichnet, dazu Entfernung und ungefähre Fahrzeit. Abbiege-Hinweise
  oben in der Mitte („In 300 m rechts“), kurze Meldung bei „Ziel erreicht“.
- Achtung: Straßen werden nur in der Nähe des Autos berechnet (ca. 2,8 km),
  das Ziel kann weiter weg liegen. Plane die Route deshalb auf dem groben
  Orts-Graphen (Orte und Verbindungen sind ohne Wegsuche deterministisch
  bekannt) und verfeinere sie, sobald die Abschnitte geladen sind. Fällt
  ein Abschnitt später weg (zu steil, Überlappung) oder fährt man von der
  Route ab, wird neu berechnet.
- Die Karte darf nicht ruckeln: Kartenbild im Hintergrund zeichnen und
  zwischenspeichern.

TEIL 3: WETTER UND JAHRESZEITEN
Wetter (wechselt alle paar Minuten fließend, man kann es auch festlegen):
- Klar, bewölkt, Regen, Gewitter (Blitze und Donner), Nebel, Schnee.
- Regen: Tropfen um die Kamera (Partikel), nasse Straße (dunkler,
  glänzender, Spiegelungen, Pfützen), weniger Grip (ca. 70 %). Nach dem
  Regen trocknet die Straße langsam ab. Gischt hinter den Reifen.
- Nebel in den Tälern: Bodennebel, der sich in tiefen Lagen sammelt (vor
  allem morgens), oben auf den Bergen klare Sicht.
- Wolken im Himmel-Shader passend zum Wetter, bei Regen dunkler Himmel und
  weniger Sonnenlicht.
- Schnee: Flocken, Schnee auf Gelände und Bäumen (im Shader), auf der
  Straße weniger Grip (ca. 50 %).
Jahreszeiten:
- Frühling: frisches Grün. Sommer: wie jetzt. Herbst: Laubbäume gemischt
  gelb, orange und rot, Gras bräunlicher. Winter: Laubbäume kahl,
  verschneite Landschaft.
- Die Schneegrenze in den Bergen hängt von der Jahreszeit ab (Winter tief,
  Sommer nur die Gipfel).
- Die Jahreszeit beeinflusst das Wetter (Herbst mehr Regen und Nebel,
  Winter Schnee).
- Tasten: F5 schaltet das Wetter durch, J die Jahreszeit. Beides auch in
  der Garage einstellbar.

TEIL 4: TUNNEL
- Bisher wird ein Straßenabschnitt verworfen, wenn er zu tief ins Gelände
  schneiden müsste (MAX_CUT 35 m), und am Hang entstehen lange Umwege.
  Stattdessen soll die Straße dort durch einen Tunnel gehen (ab ca. 25 m
  Überdeckung). Die Wegsuche darf Tunnel bewusst nutzen, wenn ein Berg
  sonst umfahren werden müsste, aber nicht übertreiben.
- Tunnelröhre mit Wänden, Decke, Fahrbahn mit Markierung, Lampen an der
  Decke (Emission plus wenige echte Lichter nur in der Nähe des Autos),
  Betonportale an beiden Enden, sauber in den Hang eingepasst.
- Gelände: Im Tunnelbereich nicht abtragen, nur an den Portalen. Achtung:
  Die Gelände-Kollision (HeightMapShape3D) darf das Auto im Tunnel nicht
  nach oben durch den Berg drücken. Prüf, ob Löcher in der HeightMapShape
  gehen, sonst löse es anders. Das Gelände-Mesh braucht an den Portalen
  eine saubere Öffnung.
- Im Tunnel: Motorsound mit Hall (Reverb auf eigenem Audio-Bus), kein
  Sonnenlicht, kein Regen, Augen-Anpassung beim Ein- und Ausfahren.
- Keine Bäume und Felsen vor den Portalen. Die Minimap zeigt Tunnel
  gestrichelt, das Navi kann durch Tunnel routen.

PRÜFEN
Nach jedem Teil mit dem Screenshot-Werkzeug selbst anschauen: jedes Auto in
der Garage und auf der Straße (Tag und Nacht), Minimap mit Route, Regen
mit nasser Straße, Talnebel am Morgen, Herbst und Winter, ein Tunnel von
außen und innen. --bench=60 muss weiter am Stück durchfahren, FPS
mindestens 60. Neue Tasten in die CLAUDE.md eintragen.

Am Ende: kurze Zusammenfassung, welche Tasten es gibt und was dir optisch
noch nicht gefällt.
```

## Felsbogen-Bug, neues HUD und Garage, Autobahn, Aussichtspunkte, Pops und Bangs, Himmel

Großer Prompt, in einer neuen Sitzung abschicken. Läuft lange.
Die Entwurfsbilder liegen in screenshots/design_*.png.

```
Lies die CLAUDE.md. Alles bis einschließlich Tunnel ist fertig. In dieser
Sitzung machst du sechs Teile in dieser Reihenfolge. Mach zuerst einen Plan
für alle Teile. Nach meinem OK arbeitest du alles nacheinander ab, ohne bei
jedem Teil auf mich zu warten. Nach jedem Teil: testen, Fehler beheben,
committen, CLAUDE.md aktualisieren. FPS insgesamt mindestens 60 (MacBook Air
ohne Lüfter).

TEIL 1: BUG „SCHWEBENDER FELSBOGEN“
Auf screenshots/nav_drive.png hängt oben links ein riesiger grauer Felsbogen
in der Luft, darunter sieht man Himmel. Im Bild steht „Kacheln: 237 (195 in
Arbeit)“, die Kacheln haben also noch geladen. Meine Vermutung (bitte prüfen):
Das ist der Horizont-Ring. Sein innerer Rand (inner_radius 1.200 m, um die
Stelle gebaut, an der der Ring zuletzt erzeugt wurde) schneidet mitten durch
die Berge und hat nach unten keine Fläche. Solange die Kacheln davor fehlen,
sieht man diesen offenen Rand als schwebenden Bogen.
- Reproduzier den Fehler (z. B. Screenshot direkt nach dem Start oder nach
  einem weiten Sprung, --wait=0) und behebe ihn an der Ursache. Ideen: eine
  Schürze am inneren Ringrand bis unter das tiefste Gelände, den Ring nur
  dort versenken, wo wirklich schon Kacheln liegen, und beim Start und nach
  Sprüngen (R, Wasser-Reset, Autowechsel) kurz ausblenden, bis die Kacheln in
  der Nähe da sind.
- Das Laden muss auch bei 300 km/h hinterherkommen (Teil 3 bringt Autobahnen):
  Kacheln in Fahrtrichtung und je nach Tempo bevorzugt laden.

TEIL 2: NEUES HUD (STIL A „GLAS“) UND NEUE GARAGE
Halte dich so genau wie möglich an die Entwürfe:
screenshots/design_hud_a.png (HUD), screenshots/design_garage.png (Garage),
screenshots/design_bausteine.png (Meldungen, Navi-Hinweise, Wetter-Chips).
Gemeinsamer Stil:
- Schrift Inter (OFL-Lizenz, nach assets/fonts/ holen, in CREDITS.md).
- Milchglas-Flächen: dunkel rgba(14,18,26,0.48), Hintergrund dahinter
  weichgezeichnet (ca. 18 px, Shader mit Bildschirmtextur, günstig halten),
  1 px Rand weiß 14 %, Ecken 22–28 px. Weißer Text, Zahlen mit gleicher Breite.
- Akzentfarbe Standard #3D8BFF, in der Garage wählbar (#22C3A6, #FF7A1A, #E5484D).
- Alles skaliert sauber mit der Fensterhöhe (Entwurf ist 1600 × 900).
HUD:
- Unten rechts 300 × 300 Panel: Drehzahl als 270°-Bogen mit Zahlen pro
  1.000/min und rotem Bereich (je Auto passend zu dessen Begrenzer), in der
  Mitte das Tempo groß (ca. 88 px, extra fett) mit „km/h“, darunter der Gang
  in einem abgerundeten Kästchen.
- Unten links die Minimap im neuen dunklen Stil: Untergrund #111721,
  Wasser #1E3A5C, Straßen grau #8D97A9, Route in Akzentfarbe, N-Plakette,
  darunter „14,4 km · 12 min“ und „M Karte“. Die große Karte (M) im selben Stil.
- Oben mittig die Navi-Karte: Feld mit Abbiege-Pfeil in Akzentfarbe,
  Entfernung groß, Anweisung, zweite Zeile „Danach …“, rechts ANKUNFT mit
  Uhrzeit (Spieluhr + Fahrzeit). Ohne Ziel ausgeblendet.
- Oben rechts drei Chips: Uhrzeit, Wetter mit Symbol und Temperatur, Jahreszeit.
  Temperatur ausrechnen aus Jahreszeit, Tageszeit, Höhe (−0,65 °C pro 100 m)
  und Wetter.
- Meldungen (Toasts) wie im Bausteine-Bild, links oben einblenden, nach ca.
  4 s ausblenden: Wetterwechsel, Jahreszeit, Tunnel voraus, Ziel erreicht,
  Aussichtspunkt entdeckt, Foto gespeichert.
- FPS und Kachel-Zähler nur noch mit F3.
Garage:
- Statt schwarzem Showroom: Das Spiel pausiert, die Kamera kreist langsam um
  das Auto an seiner aktuellen Stelle in der Welt, HUD aus.
- Links ein Glas-Panel: GARAGE, Name groß, Untertitel, fünf Balken (Leistung,
  Drehmoment, Gewicht, 0–100, Spitze im Vergleich zum stärksten Auto), Lack,
  Bereich WELT mit drei Umschaltern (Tageszeit, Wetter, Jahreszeit; ändern die
  Vorschau sofort), großer Knopf „Losfahren“, Credits, Tastenhinweise.
- Unten rechts die Autos als Karten nebeneinander, das gewählte mit Rand in
  Akzentfarbe. Bedienbar mit Maus, Pfeiltasten und Enter.
- Neu in der Garage: Akzentfarbe des HUD, Schalter „Sportauspuff“ (Teil 5)
  und ein Knopf „Sammlung“ (Teil 4).

TEIL 3: AUTOBAHN OHNE TEMPOLIMIT
- Zusätzlich zum Landstraßen-Netz ein Autobahn-Netz: lange, durchgehende
  Strecken quer durch die Welt, deterministisch aus dem Seed, nahtlos über
  Kacheln hinweg. Anteil an der gesamten Straßenlänge ca. 20 %, Landstraßen
  ca. 80 %. Miss den Anteil in einem großen Testgebiet und trag ihn in die
  CLAUDE.md ein.
- Je Richtung zwei Fahrstreifen plus Standstreifen, Mittelleitplanke,
  Leitpfosten mit Reflektoren (leuchten nachts im Scheinwerferlicht),
  passende Markierungen.
- Trassierung für hohes Tempo: Kurvenradien ab ca. 900 m, höchstens 4 %
  Steigung, sanfte Querneigung. Durch Berge lieber Talbrücken und Tunnel als
  Serpentinen.
- Anschlussstellen: Wo Autobahn und Landstraße sich nahekommen, Auf- und
  Abfahrten mit Rampen. Landstraßen kreuzen die Autobahn nie auf gleicher
  Höhe, sondern immer per Brücke oder Unterführung. Die Überlappungs-Prüfung
  im Straßennetz muss das kennen.
- Blaue Schilderbrücken vor den Ausfahrten („Ausfahrt 14 Tannbach 2000 m“)
  und Ausfahrt-Schilder. Die Orte bekommen dafür erfundene, deutsch
  klingende Namen (deterministisch aus dem Seed).
- Minimap und Karte zeigen Autobahnen breiter und in eigener Farbe. Das
  Navi nimmt bei langen Strecken die Autobahn, wenn sie schneller ist
  („Ausfahrt 14 nehmen“).
- Bäume, Gelände-Anpassung, Gras, Brücken und Tunnel funktionieren auch für
  die breite Autobahn. Mit --bench auf der Autobahn bei Vollgas (M3 GTS,
  über 300 km/h) prüfen: keine Lücken, kein Nachladen-Ruckeln, FPS ≥ 60.

TEIL 4: AUSSICHTSPUNKTE UND FOTOMODUS
- Aussichtspunkte: an besonders schönen Stellen nahe einer Straße
  (hoch mit Fernblick, am Seeufer, auf Passhöhen), deterministisch aus dem
  Seed, mit kleiner Parkbucht und Schild. Hält man dort an (unter 5 km/h im
  Umkreis), kommt die Meldung „Aussichtspunkt entdeckt · 3 von 12 in dieser
  Gegend“ und der Hinweis „P Foto“.
- Auf der großen Karte: unentdeckte Punkte in der Nähe als graues
  Fragezeichen, entdeckte als Kamera-Symbol. Fortschritt wird gespeichert
  (user://). In der Garage unter „Sammlung“ alle gefundenen Punkte mit den
  dort gemachten Fotos.
- Fotomodus mit P (überall, nicht nur an Aussichtspunkten): Spiel pausiert,
  HUD aus, freie Kamera um das Auto (Maus und WASD, max. ca. 30 m, nicht durch
  das Gelände), Zoom, Tiefenschärfe mit Fokus aufs Auto, Belichtung, Tageszeit
  verschieben, ein paar Filter (neutral, warm, kühl, schwarz-weiß).
  Leertaste speichert das Foto als PNG nach user://fotos, Meldung „Foto
  gespeichert“ mit Möglichkeit, den Ordner im Finder zu öffnen.

TEIL 5: POPS UND BANGS, TURBO
- Beim Gaswegnehmen aus hoher Drehzahl knallt und blubbert es im Auspuff
  (unregelmäßig, 1–2 s lang), passend zum prozeduralen Motorsound. Stärke je
  Auto im Profil: M2 und M3 GTS kräftig, M5 F90 mittel, M5 G90 und E30 wenig.
- Dazu kleine Flammen an den Endrohren (Partikel plus kurzer Lichtblitz,
  günstig), nachts gut sichtbar. Die Endrohr-Positionen je Auto aus dem
  Modell ermitteln und im Profil speichern.
- Turbo: Bei den beiden M5 deutliches Turbo-Pfeifen, das mit dem Ladedruck
  steigt, und ein Abblasen („Pschh“) beim Gaswegnehmen. Beim M2 nur leise.
  E30 und M3 GTS sind Sauger, also kein Turbo-Geräusch.
- Schalter „Sportauspuff“ in der Garage: aus = kaum Pops, keine Flammen.

TEIL 6: HIMMEL
- Regenbogen: wenn der Regen aufhört und die Sonne tief hinter der Kamera
  steht, ein Regenbogen gegenüber der Sonne (im Himmel-Shader), blendet
  über ein paar Minuten ein und aus.
- Wolkenschatten: Schatten der Wolken ziehen mit dem Wind über Gelände und
  Berge (im Terrain-Shader, passend zur Wolkenmenge des Wetters).
- Polarlicht: in klaren Winternächten (nicht jede Nacht, etwa jede dritte),
  langsam wabernde grüne Vorhänge mit violetten Spitzen am Nordhimmel.

PRÜFEN
Nach jedem Teil mit dem Screenshot-Werkzeug selbst anschauen und mit den
Entwurfsbildern vergleichen: HUD bei Tag, Nacht und Regen, Garage,
Navi-Hinweis, Meldungen, Autobahn mit Schilderbrücke und Anschlussstelle
(auch von oben), Aussichtspunkt, Fotomodus, Flammen nachts, Regenbogen,
Polarlicht. Neue Tasten in die CLAUDE.md.

Am Ende: kurze Zusammenfassung, neue Tasten und was dir optisch noch nicht
gefällt.
```
