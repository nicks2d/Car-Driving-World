#!/bin/zsh
# Baut die Mac-App „Car Driving World“ in einer von zwei Varianten:
#   Vollversion (Vorlage „macOS“) → build/Car Driving World.app, mit allen Autos (teils NC/ND-Lizenz:
#     nur für diesen Mac, nie hochladen). Mit --install danach nach /Applications kopieren.
#   Download-Version (--download, Vorlage „macOS Download“) → build/download/Car Driving World.app, nur Modelle
#     mit CC-BY-Lizenz (E30, E92, M5 F90, M4 CSL, Audi S3, Tankstelle), dazu CREDITS.txt, LICENSE.txt und
#     Inter-LICENSE.txt im App-Paket und ein ZIP für GitHub: build/Car-Driving-World-VERSION-macOS.zip
# Schritte: Export (Godot liefert nur eine Universal-App), nur Apple Silicon behalten (lipo -thin arm64),
# App-Name in der Info.plist setzen (Godot nimmt den Projektnamen „Endlose Welt“; der bleibt, weil danach der
# Speicherordner user:// heißt), ad-hoc signieren (ohne Apple-Zertifikat, nicht notarisiert).
# Voraussetzung: Godot-Exportvorlagen 4.7.2 (macos.zip) installiert.
# Aufruf: tools/build_mac_app.sh [--download] [--install] [Pfad zur Godot-Programmdatei]
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
DOWNLOAD=0
INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --download) DOWNLOAD=1 ;;
    --install) INSTALL=1 ;;
    *) GODOT="$arg" ;;
  esac
done
NAME="Car Driving World"
VERSION=$(sed -n 's/^config\/version="\(.*\)"$/\1/p' project.godot)
# Ordner der Modelle mit NC/ND-Lizenz: dürfen nie in der Download-Version stecken
NC_FOLDERS=(bmw_m2 2025_bmw_m5_sedan 2009_mercedes-benz_sl65_amg_black_series
  2013_mercedes-benz_c63_amg_coupe_black_series verkehr/2005_pontiac_aztek verkehr/2021_honda_accord
  verkehr/2023_volkswagen_id_buzz_gtx verkehr/2017_lexus_lc_500 verkehr/kia_stinger)

if [ $DOWNLOAD -eq 1 ]; then
  if [ $INSTALL -eq 1 ]; then
    echo "--install nur für die Vollversion (beide Apps heißen gleich)"; exit 1
  fi
  PRESET="macOS Download"
  OUT="build/download"
else
  PRESET="macOS"
  OUT="build"
fi
APP="$OUT/$NAME.app"

rm -rf "$APP"
mkdir -p "$OUT"
"$GODOT" --headless --path . --export-release "$PRESET" "$APP"

PLIST="$APP/Contents/Info.plist"
EXE="$APP/Contents/MacOS/$(plutil -extract CFBundleExecutable raw "$PLIST")"
lipo "$EXE" -thin arm64 -output "$EXE.arm64"
mv "$EXE.arm64" "$EXE"
plutil -replace CFBundleName -string "$NAME" "$PLIST"
plutil -replace CFBundleDisplayName -string "$NAME" "$PLIST"

if [ $DOWNLOAD -eq 1 ]; then
  # Sicherheitsprüfung: Im Spiel-Paket (.pck) darf kein Pfad aus einem NC/ND-Ordner stehen
  PCK=$(find "$APP/Contents/Resources" -name "*.pck" | head -1)
  for folder in "${NC_FOLDERS[@]}"; do
    if LC_ALL=C grep -aqF "assets/models/$folder/" "$PCK"; then
      echo "FEHLER: $folder steckt in der Download-Version ($PCK)"; exit 1
    fi
  done
  # Credits und Lizenzen gehören zur App
  cp tools/download/CREDITS.txt "$APP/Contents/Resources/CREDITS.txt"
  cp LICENSE "$APP/Contents/Resources/LICENSE.txt"
  cp assets/fonts/Inter-LICENSE.txt "$APP/Contents/Resources/Inter-LICENSE.txt"
fi

codesign --force --deep --sign - --preserve-metadata=entitlements,flags,runtime "$APP"
codesign --verify --deep --strict "$APP"
echo "Fertig: $APP ($(du -sh "$APP" | cut -f1), $(lipo -archs "$EXE"), Version $VERSION)"

if [ $DOWNLOAD -eq 1 ]; then
  # ZIP für GitHub: Ordner mit App, Lies-mich, Credits und Lizenzen
  STAGE="$OUT/$NAME $VERSION"
  ZIP="build/Car-Driving-World-$VERSION-macOS.zip"
  rm -rf "$STAGE" "$ZIP"
  mkdir -p "$STAGE"
  ditto "$APP" "$STAGE/$NAME.app"
  cp tools/download/README.txt tools/download/CREDITS.txt "$STAGE/"
  cp LICENSE "$STAGE/LICENSE.txt"
  cp assets/fonts/Inter-LICENSE.txt "$STAGE/Inter-LICENSE.txt"
  # ohne macOS-Zusatzdaten (sonst liegen „._“-Dateien im ZIP); die Signatur steckt in der App selbst
  ditto -c -k --norsrc --noextattr --noacl --keepParent "$STAGE" "$ZIP"
  echo "ZIP: $ZIP ($(du -h "$ZIP" | cut -f1))"
fi

if [ $INSTALL -eq 1 ]; then
  rm -rf "/Applications/$NAME.app"
  ditto "$APP" "/Applications/$NAME.app"
  echo "Installiert: /Applications/$NAME.app"
fi
