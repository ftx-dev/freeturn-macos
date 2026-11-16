#!/bin/bash
# Собирает FreeTurn.app из сборки SwiftPM и Go-бинарников (make engine helper).
#   ARCH=arm64|x86_64 (по умолчанию - архитектура машины), BIN=каталог Go-бинарников (build),
#   OUT=куда положить FreeTurn.app (build).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
ARCH="${ARCH:-$(uname -m)}"
GOBIN="${BIN:-build}"
APP="${OUT:-build}/FreeTurn.app"

for f in "$GOBIN/freeturn-core" "$GOBIN/freeturnd" "$GOBIN/amnezia-box"; do
  [ -x "$f" ] || { echo "bundle-app: нет $f - выполни make engine helper" >&2; exit 1; }
done

swift build -c release --arch "$ARCH" --package-path App --product FreeTurn
BIN="$(swift build -c release --arch "$ARCH" --package-path App --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources/daemon"
cp App/Bundle/Info.plist "$APP/Contents/Info.plist"
cp App/Bundle/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Имя в Finder, Launchpad и Dock - FreeTurnX, хотя папка остаётся FreeTurn.app (на это имя завязано автообновление 0.1-0.2).
cp -R App/Bundle/en.lproj App/Bundle/ru.lproj "$APP/Contents/Resources/"
cp "$BIN/FreeTurn" "$APP/Contents/MacOS/FreeTurn"
cp -R "$BIN/FreeTurn_FreeTurn.bundle" "$APP/Contents/Resources/"
cp "$GOBIN/freeturn-core" "$APP/Contents/Helpers/freeturn-core"
# Служба и движок: приложение отдаёт их установщику, тот копирует в каталог root.
cp "$GOBIN/freeturnd" "$GOBIN/amnezia-box" scripts/install-daemon.sh scripts/uninstall-daemon.sh "$APP/Contents/Resources/daemon/"

# Подпись ad-hoc: сначала вложенный код, потом само приложение.
codesign --force --sign - "$APP/Contents/Helpers/freeturn-core" \
  "$APP/Contents/Resources/daemon/freeturnd" "$APP/Contents/Resources/daemon/amnezia-box"
codesign --force --sign - "$APP"
echo "готово: $ROOT/$APP"
