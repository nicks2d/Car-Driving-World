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
