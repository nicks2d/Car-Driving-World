#!/bin/zsh
# Vergleicht die FPS zweier Stände abwechselnd (alt, neu, alt, neu …), damit die Wärme des Macs
# beide gleich trifft. Mit kühlem Mac am Netzteil starten!
#
# Aufruf (im Projektordner):
#   tools/bench_compare.sh [REF] [RUNDEN] [QUALITÄT]     Standard: c71aa75 (Stand vor Teil 3), 2, hoch
#   tools/bench_compare.sh c71aa75 0                     nur vorbereiten (ohne Messung)
#
# Der alte Stand wird einmal als git worktree neben das Projekt gelegt
# (~/Godot-Projekte/.endlose-welt-vergleich-REF, außerhalb des Projekts, damit Godot ihn nicht
# mitimportiert). Die Automodelle (nicht im Repo) bekommt er per Verknüpfung aus diesem Projekt.
# Gemessen wird der Autobahn-Benchmark mit Verkehr (--bench=30 --highway --full) und dazu die
# GPU-Auslastung (ioreg). Aufräumen: git worktree remove ~/Godot-Projekte/.endlose-welt-vergleich-REF
set -u
cd "$(dirname "$0")/.."

GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
REF="${1:-c71aa75}"
ROUNDS="${2:-2}"
QUALITY="${3:-hoch}"
OLD="$HOME/Godot-Projekte/.endlose-welt-vergleich-$REF"

if [ ! -d "$OLD" ]; then
  echo "Lege den Stand $REF an: $OLD"
  git worktree add --detach "$OLD" "$REF" || exit 1
  for model in assets/models/*(/); do
    [ -e "$OLD/$model" ] || ln -s "$PWD/$model" "$OLD/$model"
  done
  echo "Importiere den alten Stand einmal (dauert ein paar Minuten) …"
  "$GODOT" --headless --path "$OLD" --import > /dev/null 2>&1
fi

# 0 Runden: nur vorbereiten (worktree anlegen und importieren)
if [ "$ROUNDS" -lt 1 ]; then
  echo "Vorbereitet: $OLD"
  exit 0
fi

# Ein Benchmark: Ausgabe „FPS 1%-Low GPU%“
bench() {
  local folder="$1" log
  log=$(mktemp)
  "$GODOT" --path "$folder" --always-on-top -- --bench=30 --highway --full --quality="$QUALITY" > "$log" 2>&1 &
  local pid=$! sum=0 n=0 u
  until grep -q "Welt geladen" "$log" 2>/dev/null; do sleep 0.5; kill -0 $pid 2>/dev/null || break; done
  sleep 4
  while kill -0 $pid 2>/dev/null && ! grep -q "BENCH frames" "$log"; do
    u=$(ioreg -r -d 1 -c IOAccelerator | grep -oE '"Device Utilization %"=[0-9]+' | head -1 | cut -d= -f2)
    [ -n "$u" ] && { sum=$((sum + u)); n=$((n + 1)); }
    sleep 1
  done
  wait $pid
  local line
  line=$(grep "BENCH frames" "$log" | sed -E 's/.*fps_avg=([0-9.]+) fps_1pct_low=([0-9.]+).*/\1 \2/')
  echo "$line $((n > 0 ? sum / n : 0))"
  rm -f "$log"
}

echo "Strom: $(pmset -g batt | sed -n 1p)"
printf "%-6s %-10s %8s %8s %6s\n" "Runde" "Stand" "FPS" "1%-Low" "GPU%"
for round in $(seq 1 "$ROUNDS"); do
  for side in alt neu; do
    folder="."
    [ "$side" = "alt" ] && folder="$OLD"
    result=($(bench "$folder"))
    printf "%-6s %-10s %8s %8s %6s\n" "$round" "$side" "${result[1]:--}" "${result[2]:--}" "${result[3]:--}"
  done
done
