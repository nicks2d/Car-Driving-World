#!/bin/zsh
# Automatischer Testlauf: startet das Spiel mit --selftest (scripts/self_test.gd: Landstraße und
# Autobahn mit dem Autopiloten, Regen, Schnee, Nacht, Garage, Karte, Fotomodus, Pausemenü,
# Chill-Modus) und wertet danach das Log aus. Am Ende steht „OK“ oder die Liste der Fehler und
# Warnungen. Stille Abstürze erkennt er daran, dass die Zeile „SELFTEST ENDE“ fehlt.
#
# Aufruf (im Projektordner):
#   tools/test.sh            im Editor-Godot (vorher einmal --import, damit neue Klassen bekannt sind)
#   tools/test.sh --app      gegen die exportierte App in /Applications
#   tools/test.sh --app="build/download/Car Driving World.app"   gegen eine andere App (z. B. Download-Version)
#   tools/test.sh --shots    zusätzlich ein Foto pro Schritt (screenshots/selftest_*.png)
#   weitere Argumente gehen ans Spiel, z. B. tools/test.sh --car=e92
# Log: screenshots/test.log (bzw. test_app.log). Rückgabe: 0 = OK, 1 = Fehler.
set -u
cd "$(dirname "$0")/.."

GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
APP="/Applications/Car Driving World.app/Contents/MacOS/Endlose Welt"
LIMIT=300          # Sekunden, danach gilt der Lauf als hängengeblieben
USE_APP=0
TEST_ARG="--selftest"
EXTRA=()
for arg in "$@"; do
  case "$arg" in
    --app) USE_APP=1 ;;
    --app=*) USE_APP=1; APP="${arg#--app=}/Contents/MacOS/Endlose Welt" ;;
    --shots) TEST_ARG="--selftest=shots" ;;
    *) EXTRA+=("$arg") ;;
  esac
done

# Meldungen, die bekannt und harmlos sind (Muster für grep -E), mit Begründung:
KNOWN=(
  # Nur die exportierte App, beim Beenden (docs/mac-app.md, „Bekannt“)
  "shaders of type ParticlesShaderRD were never freed"
  "MaterialStorage.*Shader.*leaked|1 RID of type \"Shader\" was leaked"
)

mkdir -p screenshots
if [ $USE_APP -eq 1 ]; then
  LOG="screenshots/test_app.log"
  [ -x "$APP" ] || { echo "FEHLER: App nicht gefunden: $APP"; exit 1; }
  CMD=("$APP" --always-on-top -- "$TEST_ARG" "${EXTRA[@]}")
else
  LOG="screenshots/test.log"
  # Neue class_name-Skripte sind erst nach dem Import bekannt
  "$GODOT" --headless --path . --import > screenshots/test_import.log 2>&1
  CMD=("$GODOT" --path . --always-on-top -- "$TEST_ARG" "${EXTRA[@]}")
fi

echo "Testlauf startet: ${CMD[*]}"
"${CMD[@]}" > "$LOG" 2>&1 &
PID=$!
SECONDS=0
while kill -0 $PID 2>/dev/null; do
  if [ $SECONDS -ge $LIMIT ]; then
    kill $PID 2>/dev/null; sleep 1; kill -9 $PID 2>/dev/null
    echo "HÄNGT: nach $LIMIT s abgebrochen" >> "$LOG"
    break
  fi
  sleep 1
done
wait $PID 2>/dev/null
CODE=$?

# Fehler und Warnungen einsammeln (Godot schreibt „ERROR:“, „WARNING:“, „SCRIPT ERROR:“ …)
PROBLEMS=$( (grep -E "ERROR|WARNING|Parse Error|HÄNGT|leaked|Leaked" "$LOG"; \
  [ $USE_APP -eq 0 ] && grep -E "ERROR|Parse Error" screenshots/test_import.log) 2>/dev/null \
  | grep -v "^SELFTEST" | sort | uniq -c | sort -rn)
KNOWN_HITS=""
for pattern in "${KNOWN[@]}"; do
  hits=$(echo "$PROBLEMS" | grep -E "$pattern")
  [ -n "$hits" ] && KNOWN_HITS+="$hits"$'\n'
  PROBLEMS=$(echo "$PROBLEMS" | grep -vE "$pattern")
done
PROBLEMS=$(echo "$PROBLEMS" | sed '/^\s*$/d')

grep -E "^SELFTEST (gefahren|FPS|ENDE)|Welt geladen" "$LOG"
FAILED=0
if ! grep -q "^SELFTEST ENDE nach" "$LOG"; then
  echo "FEHLER: Keine Zeile „SELFTEST ENDE“ – das Spiel ist abgestürzt oder hängengeblieben (Rückgabe $CODE)."
  echo "Letzte Zeilen:"; tail -8 "$LOG" | sed 's/^/  /'
  FAILED=1
elif [ $CODE -ne 0 ]; then
  echo "FEHLER: Rückgabe $CODE (erwartet 0)"
  FAILED=1
fi
if [ -n "$PROBLEMS" ]; then
  echo "FEHLER/WARNUNGEN im Log ($LOG):"
  echo "$PROBLEMS" | sed 's/^/  /'
  FAILED=1
fi
if [ -n "${KNOWN_HITS//[$'\n ']/}" ]; then
  echo "Bekannt und harmlos:"; echo -n "$KNOWN_HITS" | sed 's/^/  /'
fi
if [ $FAILED -eq 0 ]; then
  echo "OK"
  exit 0
fi
exit 1
