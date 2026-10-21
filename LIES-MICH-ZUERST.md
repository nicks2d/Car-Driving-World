# Endlose Welt – So legst du los

Alles, was Claude Code braucht, liegt schon in diesem Ordner:

| Datei | Wofür |
|---|---|
| `CLAUDE.md` | Das „Gehirn“ des Projekts: Ziel, Regeln, Meilensteine. Claude Code liest das bei jedem Start automatisch. |
| `PROMPTS.md` | Alle Prompts zum Kopieren, Meilenstein für Meilenstein, plus Notfall-Prompts. |
| `project.godot` | Das leere Godot-Projekt. |

Auf deinem Mac ist schon fast alles da: Node.js, Git, Homebrew und Claude Code.
Git ist im Projektordner auch schon eingerichtet.
**Es fehlen nur noch Godot selbst und die Godot-Verbindung für Claude Code (Schritt 3).**

---

## Schritt 1: Godot installieren

Lade die **Standard-Version** (nicht die .NET-Version) für macOS herunter:
https://godotengine.org/download/macos/

Die ZIP entpacken und `Godot.app` in den Ordner **Programme** ziehen.
Wichtig: Sie muss genau dort liegen (`/Applications/Godot.app`), sonst findet
Claude Code sie nicht.

Alternativ im Terminal: `brew install --cask godot`

Einen Account brauchst du dafür übrigens nicht.

## Schritt 2: Projekt einmal in Godot öffnen

1. Godot starten. Falls macOS meckert, dass die App aus dem Internet stammt:
   Rechtsklick auf Godot.app → **Öffnen** → **Öffnen**.
2. Im Projektmanager auf **Importieren** klicken und die Datei
   `project.godot` aus diesem Ordner auswählen.
3. Projekt öffnet sich mit einer leeren Szene. Das ist richtig so.
   Godot wieder schließen (oder offen lassen, ist egal).

## Schritt 3: Claude Code mit Godot verbinden

Terminal öffnen und diese zwei Befehle nacheinander eingeben
(den zweiten am Stück kopieren, ist eine lange Zeile):

```
cd ~/Godot-Projekte/endlose-welt
```

```
claude mcp add godot --scope project -e GODOT_PATH=/Applications/Godot.app/Contents/MacOS/Godot -- npx -y @coding-solo/godot-mcp
```

Das legt im Projekt eine Datei `.mcp.json` an. Die sorgt dafür, dass Claude Code
Godot selbst starten, das Spiel laufen lassen und Fehlermeldungen lesen kann.
Du musst das nur ein einziges Mal machen.

## Schritt 4: Claude Code starten

Im selben Terminal:

```
claude
```

Beim ersten Start fragt Claude Code, ob du dem Ordner vertraust → **Ja**.
Dann fragt es, ob es den MCP-Server „godot“ aus der `.mcp.json` nutzen darf → **Ja**.

Kurz prüfen, ob die Godot-Verbindung steht: `/mcp` eintippen.
Dort sollte **godot** als verbunden auftauchen.

## Schritt 5: Loslegen

Öffne `PROMPTS.md`, kopiere den Prompt für **Meilenstein 0** und schick ihn ab.
Der richtet auch noch die Rechte ein, damit Claude Code nicht bei jedem
Godot-Befehl nachfragt.
Danach Meilenstein 1, 2, 3 …

**Faustregeln:**
- Pro Meilenstein eine frische Sitzung (`/clear`).
- Erst weitermachen, wenn der aktuelle Meilenstein läuft.
- Wenn's um Optik geht: Screenshot machen (Cmd + Shift + 4) und einfach
  ins Terminal ziehen.
- Wenn Claude was kaputt macht: Es gibt nach jedem Schritt einen Commit,
  man kann immer zurück.

---

## Wichtige Links

**Werkzeuge**
- Godot herunterladen: https://godotengine.org/download/macos/
- Godot-Dokumentation: https://docs.godotengine.org/en/stable/
- Godot-MCP-Server (die Brücke zwischen Claude Code und Godot): https://github.com/Coding-Solo/godot-mcp
- Claude-Code-Dokumentation: https://code.claude.com/docs

**Kostenlose Assets (alle CC0, frei nutzbar)**
- Poly Haven – fotorealistische Texturen, Himmels-Panoramen (HDRIs), Modelle: https://polyhaven.com
- Kenney – Autos, Straßenteile, Bäume, viele Modelle: https://kenney.nl/assets
- ambientCG – Texturen für Asphalt, Gras, Fels, Schnee: https://ambientcg.com

---

## Falls was nicht klappt

**`/mcp` zeigt godot nicht an oder mit Fehler**
→ Liegt Godot wirklich unter `/Applications/Godot.app`? Wenn nicht, verschieben
oder in `.mcp.json` den Pfad bei `GODOT_PATH` anpassen. Danach Claude Code neu starten.
→ Hast du den Befehl aus Schritt 3 wirklich im Ordner `endlose-welt` ausgeführt?
Mit `ls -a` prüfen, ob dort eine `.mcp.json` liegt.

**Claude Code fragt bei jedem Godot-Befehl um Erlaubnis**
→ Einmal „immer erlauben“ wählen, dann ist Ruhe.

**Das Spiel ruckelt extrem**
→ Prompt „Wenn es ruckelt“ aus der `PROMPTS.md` nehmen.
