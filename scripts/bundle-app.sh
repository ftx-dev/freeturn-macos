#!/bin/bash
# Собирает build/FreeTurn.app из сборки SwiftPM и бинарников build/ (make engine helper).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
APP=build/FreeTurn.app

for f in build/freeturn-core build/freeturnd build/amnezia-box; do
  [ -x "$f" ] || { echo "bundle-app: нет $f - выполни make engine helper" >&2; exit 1; }
done

swift build -c release --package-path App --product FreeTurn
BIN="$(swift build -c release --package-path App --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources/daemon"
cp App/Bundle/Info.plist "$APP/Contents/Info.plist"
cp App/Bundle/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp "$BIN/FreeTurn" "$APP/Contents/MacOS/FreeTurn"
cp -R "$BIN/FreeTurn_FreeTurn.bundle" "$APP/Contents/Resources/"
cp build/freeturn-core "$APP/Contents/Helpers/freeturn-core"
# Служба и движок: приложение отдаёт их установщику, тот копирует в каталог root.
cp build/freeturnd build/amnezia-box scripts/install-daemon.sh scripts/uninstall-daemon.sh "$APP/Contents/Resources/daemon/"

# Подпись ad-hoc: сначала вложенный код, потом само приложение.
codesign --force --sign - "$APP/Contents/Helpers/freeturn-core" \
  "$APP/Contents/Resources/daemon/freeturnd" "$APP/Contents/Resources/daemon/amnezia-box"
codesign --force --sign - "$APP"
echo "готово: $ROOT/$APP"
