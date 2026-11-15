#!/bin/bash
# Установщик DMG под одну архитектуру: scripts/make-dmg.sh arm64|x86_64
# Результат: build/FreeTurn-<версия>-<arch>.dmg (приложение + ярлык «Программы»).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
ARCH="${1:?usage: make-dmg.sh arm64|x86_64}"
case "$ARCH" in
  arm64) GOARCH=arm64 ;;
  x86_64) GOARCH=amd64 ;;
  *) echo "make-dmg: неизвестная архитектура $ARCH" >&2; exit 2 ;;
esac
VERSION="$(plutil -extract CFBundleShortVersionString raw App/Bundle/Info.plist)"
WORK="build/$ARCH"
DMG="build/FreeTurn-$VERSION-$ARCH.dmg"

make engine helper GOARCH="$GOARCH" GOOUT="$WORK"
ARCH="$ARCH" BIN="$WORK" OUT="$WORK" scripts/bundle-app.sh

# Всё в бандле - под нужную архитектуру: иначе служба не запустится на чужом процессоре.
for f in "$WORK/FreeTurn.app/Contents/MacOS/FreeTurn" "$WORK/FreeTurn.app/Contents/Helpers/freeturn-core" \
         "$WORK/FreeTurn.app/Contents/Resources/daemon/freeturnd" "$WORK/FreeTurn.app/Contents/Resources/daemon/amnezia-box"; do
  got="$(lipo -archs "$f")"
  [ "$got" = "$ARCH" ] || { echo "make-dmg: $f собран под '$got', нужен $ARCH" >&2; exit 1; }
done

STAGE="$WORK/dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$WORK/FreeTurn.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "FreeTurn" -srcfolder "$STAGE" -fs HFS+ -format UDZO "$DMG"
rm -rf "$STAGE"
echo "готово: $ROOT/$DMG"
