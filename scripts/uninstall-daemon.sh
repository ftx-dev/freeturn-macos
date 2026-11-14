#!/bin/bash
# Удаляет службу FreeTurn и всё, что она положила в систему.
set -euo pipefail

LABEL=dev.freeturn.daemon
[ "$(id -u)" -eq 0 ] || { echo "uninstall-daemon: must run as root" >&2; exit 1; }

launchctl bootout "system/$LABEL" 2>/dev/null || true
rm -f "/Library/LaunchDaemons/$LABEL.plist" /var/run/freeturnd.sock /var/log/freeturnd.log
rm -rf /Library/PrivilegedHelperTools/dev.freeturn /var/db/freeturnd
