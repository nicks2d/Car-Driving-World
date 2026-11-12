#!/bin/zsh
# Baut die Mac-App „Car Driving World“ nach build/Car Driving World.app:
#   1. Export mit der Vorlage „macOS“ aus export_presets.cfg (Godot liefert nur eine Universal-App)
#   2. nur Apple Silicon behalten (lipo -thin arm64)
#   3. App-Name in der Info.plist setzen (Godot nimmt den Projektnamen „Endlose Welt“; der bleibt,
#      weil danach der Speicherordner user:// heißt, den Editor und App teilen)
#   4. ad-hoc neu signieren (ohne Apple-Zertifikat, läuft nur auf diesem Mac ohne Rückfrage)
# Voraussetzung: Godot-Exportvorlagen 4.7.2 (macos.zip) installiert.
# Aufruf: tools/build_mac_app.sh [Pfad zur Godot-Programmdatei]
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT="${1:-/Applications/Godot.app/Contents/MacOS/Godot}"
NAME="Car Driving World"
APP="build/$NAME.app"

rm -rf "$APP"
mkdir -p build
"$GODOT" --headless --path . --export-release "macOS" "$APP"

PLIST="$APP/Contents/Info.plist"
EXE="$APP/Contents/MacOS/$(plutil -extract CFBundleExecutable raw "$PLIST")"
lipo "$EXE" -thin arm64 -output "$EXE.arm64"
mv "$EXE.arm64" "$EXE"
plutil -replace CFBundleName -string "$NAME" "$PLIST"
plutil -replace CFBundleDisplayName -string "$NAME" "$PLIST"
codesign --force --deep --sign - --preserve-metadata=entitlements,flags,runtime "$APP"
codesign --verify --deep --strict "$APP"

echo "Fertig: $APP ($(du -sh "$APP" | cut -f1), $(lipo -archs "$EXE"))"
