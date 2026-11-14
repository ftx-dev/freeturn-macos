#!/bin/bash
# Тест scripts/proof-lib.sh. Запуск: make test-sh
set -uo pipefail
cd "$(dirname "$0")"
. ./proof-lib.sh

LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT
fails=0
expect() { # expect <имя> <ожидалось> <получено>
  if [ "$2" = "$3" ]; then echo "ok    $1"; else echo "FAIL  $1: ожидалось '$2', получено '$3'"; fails=$((fails + 1)); fi
}

# Go пишет амперсанд в JSON escape-последовательностью: адрес обязан прийти в браузер раскодированным.
# \134 в printf - обратная косая: в логе амперсанд записан шестью символами.
printf '%s\n' '{"ev":"log","level":"info","msg":"x","url":"","manual":false}' > "$LOG"
printf '{"ev":"captcha","streams":0,"total":0,"url":"http://localhost:8765/not_robot_captcha?domain=vk.com\134u0026session_token=a.b-c_d\134u0026variant=popup","manual":true,"tx":0}\n' >> "$LOG"
grep -q 'vk.com.u0026session' "$LOG" || { echo 'FAIL  сам тест: в логе нет экранированного амперсанда'; exit 1; }
expect "адрес раскодирован из JSON" \
  "http://localhost:8765/not_robot_captcha?domain=vk.com&session_token=a.b-c_d&variant=popup" "$(captcha_url "$LOG")"

# Пустой адрес после показа - ядро просит убрать капчу.
echo '{"ev":"captcha","url":"","manual":false}' >> "$LOG"
expect "капча снята - адреса нет" "" "$(captcha_url "$LOG")"

echo '{"ev":"captcha","url":"http://localhost:8765/auto","manual":false}' > "$LOG"
expect "автоматическая капча не открывается в браузере" "" "$(captcha_url "$LOG")"

: > "$LOG"
expect "нет событий - адреса нет" "" "$(captcha_url "$LOG")"

exit "$fails"
