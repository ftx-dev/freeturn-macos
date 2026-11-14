#!/bin/bash
# Тест scripts/install-daemon.sh без прав root: проверки аргументов и вид plist.
set -uo pipefail
cd "$(dirname "$0")"

SRC="$(mktemp -d)"
trap 'rm -rf "$SRC"' EXIT
fails=0
expect_fail() { # expect_fail <имя> <подстрока в ошибке> <команда…>
  local name="$1" want="$2"; shift 2
  local out; out="$("$@" 2>&1)"; local rc=$?
  if [ $rc -ne 0 ] && echo "$out" | grep -q "$want"; then echo "ok    $name"
  else echo "FAIL  $name: код $rc, вывод '$out'"; fails=$((fails + 1)); fi
}

expect_fail "без аргументов" "usage" ./install-daemon.sh
expect_fail "uid не число" "uid" ./install-daemon.sh "$SRC" "501; rm -rf /"
expect_fail "uid пустой" "uid" ./install-daemon.sh "$SRC" ""
expect_fail "нет бинарников" "freeturnd" ./install-daemon.sh "$SRC" 501
touch "$SRC/freeturnd" "$SRC/amnezia-box"
expect_fail "не root" "root" ./install-daemon.sh "$SRC" 501

PLIST="$(./install-daemon.sh --print-plist 501)"
if echo "$PLIST" | plutil -lint - >/dev/null 2>&1; then echo "ok    plist валиден"
else echo "FAIL  plist не проходит plutil -lint"; fails=$((fails + 1)); fi
ARGS="$(echo "$PLIST" | plutil -extract ProgramArguments json -o - - 2>/dev/null)"
WANT='["\/Library\/PrivilegedHelperTools\/dev.freeturn\/freeturnd","-socket","\/var\/run\/freeturnd.sock","-owner-uid","501","-engine","\/Library\/PrivilegedHelperTools\/dev.freeturn\/amnezia-box","-state-dir","\/var\/db\/freeturnd"]'
if [ "$ARGS" = "$WANT" ]; then echo "ok    аргументы службы"
else echo "FAIL  аргументы службы: $ARGS"; fails=$((fails + 1)); fi
LABEL="$(echo "$PLIST" | plutil -extract Label raw -o - - 2>/dev/null)"
if [ "$LABEL" = "dev.freeturn.daemon" ]; then echo "ok    метка службы"
else echo "FAIL  метка службы: $LABEL"; fails=$((fails + 1)); fi

expect_fail "удаление не от root" "root" ./uninstall-daemon.sh

exit "$fails"
