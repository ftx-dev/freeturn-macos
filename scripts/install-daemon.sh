#!/bin/bash
# Ставит службу FreeTurn (launchd, root). Запускается приложением с правами администратора:
#   install-daemon.sh <каталог с freeturnd и amnezia-box> <uid владельца>
#   install-daemon.sh --print-plist <uid>   # только показать plist (для теста)
set -euo pipefail

LABEL=dev.freeturn.daemon
DEST=/Library/PrivilegedHelperTools/dev.freeturn
PLIST=/Library/LaunchDaemons/$LABEL.plist
STATE=/var/db/freeturnd
SOCKET=/var/run/freeturnd.sock

usage() { echo "usage: install-daemon.sh <src-dir> <owner-uid>" >&2; exit 2; }

# uid попадает в plist службы root: принимаем только цифры.
check_uid() {
  case "${1:-}" in
    ''|*[!0-9]*) echo "install-daemon: bad owner uid '${1:-}'" >&2; exit 2 ;;
  esac
}

plist_body() {
  cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$DEST/freeturnd</string>
    <string>-socket</string><string>$SOCKET</string>
    <string>-owner-uid</string><string>$1</string>
    <string>-engine</string><string>$DEST/amnezia-box</string>
    <string>-state-dir</string><string>$STATE</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardErrorPath</key><string>/var/log/freeturnd.log</string>
</dict>
</plist>
PLIST
}

if [ "${1:-}" = "--print-plist" ]; then
  check_uid "${2:-}"
  plist_body "$2"
  exit 0
fi

[ $# -eq 2 ] || usage
SRC="$1"
OWNER_UID="$2"
check_uid "$OWNER_UID"
for f in freeturnd amnezia-box; do
  [ -f "$SRC/$f" ] || { echo "install-daemon: missing $SRC/$f" >&2; exit 2; }
done
[ "$(id -u)" -eq 0 ] || { echo "install-daemon: must run as root" >&2; exit 1; }

launchctl bootout "system/$LABEL" 2>/dev/null || true
# Бинарники уходят в каталог root: из пользовательского каталога служба ничего не запускает.
install -d -o root -g wheel -m 755 "$DEST"
install -o root -g wheel -m 755 "$SRC/freeturnd" "$SRC/amnezia-box" "$DEST/"
install -d -o root -g wheel -m 700 "$STATE"
plist_body "$OWNER_UID" > "$PLIST"
chown root:wheel "$PLIST"
chmod 644 "$PLIST"
launchctl bootstrap system "$PLIST"
