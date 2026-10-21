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
