#!/bin/bash
# Проба вживую (Task 8): ядро + движок без приложения и службы.
# Запуск:  scripts/proof.sh 'freeturn://…' ['https://…ссылка-на-звонок'] [файл.conf]
# Итог пишется в build/proof/result.txt. Нужен пароль администратора (sudo) для движка.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/scripts/proof-lib.sh"
OUT="$ROOT/build/proof"
LINK="${1:?usage: scripts/proof.sh 'freeturn://…' [call-link] [wg.conf]}"
CALL="${2:-}"
WG="${3:-}"
WAIT="${PROOF_WAIT:-180}"
IP_URL="https://api.ipify.org"        # идёт через VPN
DIRECT_URL="https://icanhazip.com"    # правило по домену: напрямую

mkdir -p "$OUT" && chmod 700 "$OUT"
RESULT="$OUT/result.txt"
: > "$RESULT"
say() { echo "$*" | tee -a "$RESULT"; }
check() { # check <имя> <ok|fail> <подробности>
  if [ "$2" = ok ]; then say "PASS  $1 — $3"; else say "FAIL  $1 — $3"; fi
}
ip_of() { "${2:-/usr/bin/curl}" -s --max-time 15 "$1" 2>/dev/null | tr -d '[:space:]'; }

ENGINE_PID=""
cleanup() {
  [ -n "$ENGINE_PID" ] && sudo kill "$ENGINE_PID" 2>/dev/null
  exec 3>&- 2>/dev/null   # закрытый stdin = приложение умерло: ядро обязано выйти само
  sleep 3
  if [ -n "${CORE_PID:-}" ] && kill -0 "$CORE_PID" 2>/dev/null; then
    check "ядро выходит по закрытию stdin" fail "процесс $CORE_PID ещё жив"; kill "$CORE_PID"
  elif [ -n "${CORE_PID:-}" ]; then
    check "ядро выходит по закрытию stdin" ok "процесс завершился"
  fi
  if [ -n "$ENGINE_PID" ]; then
    AFTER="$(ip_of "$IP_URL")"
    [ -n "$AFTER" ] && [ "$AFTER" = "${HOME_IP:-}" ] \
      && check "интернет вернулся после остановки" ok "IP снова $AFTER" \
      || check "интернет вернулся после остановки" fail "IP после остановки: '${AFTER:-нет ответа}', ожидался ${HOME_IP:-?}"
  fi
  rm -f "$OUT/core.in"
  echo; echo "Итог: $RESULT"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

cd "$ROOT"
[ -x build/amnezia-box ] && [ -x build/freeturn-core ] || { say "нет бинарников: выполни make engine helper"; exit 1; }
make ftctl >/dev/null 2>&1 || { say "ftctl не собрался"; exit 1; }

# Копия curl по другому пути - на ней проверяется правило по приложению.
cp /usr/bin/curl "$OUT/curl-direct"

GEN=(App/.build/debug/ftctl gen --link "$LINK" --out "$OUT"
     --rule "app=$OUT/curl-direct=direct" --rule "domainSuffix=icanhazip.com=direct")
[ -n "$CALL" ] && GEN+=(--call-link "$CALL")
[ -n "$WG" ] && GEN+=(--wg "$WG")
"${GEN[@]}" | tee -a "$RESULT" || exit 1

HOME_IP="$(ip_of "$IP_URL")"
[ -n "$HOME_IP" ] || { say "нет интернета до старта"; exit 1; }
say "домашний IP: $HOME_IP"

# PROOF_NO_ENGINE=1 - сухой прогон: только ядро, без sudo и движка.
if [ -z "${PROOF_NO_ENGINE:-}" ]; then
  echo "Нужен пароль администратора для запуска движка:"
  sudo -v || { say "sudo отклонён"; exit 1; }
fi

rm -f "$OUT/core.in" && mkfifo "$OUT/core.in"
build/freeturn-core -state-dir "$OUT/core-state" < "$OUT/core.in" > "$OUT/core.log" 2>&1 &
CORE_PID=$!
exec 3> "$OUT/core.in"
cat "$OUT/core-start.jsonl" >&3

echo "Жду подключения ядра (до $WAIT с)…"
OPENED=""
for _ in $(seq "$WAIT"); do
  grep -q '"state":"connected"' "$OUT/core.log" && break
  grep -q '"ev":"error"' "$OUT/core.log" && break
  # Ручная капча: открываем локальную страницу ядра в браузере.
  URL="$(captcha_url "$OUT/core.log")"
  if [ -n "$URL" ] && [ "$URL" != "$OPENED" ]; then
    echo "Нужна капча — открываю $URL"; open "$URL"; OPENED="$URL"
  fi
  sleep 1
done
if ! grep -q '"state":"connected"' "$OUT/core.log"; then
  WHY="$(grep -E '"ev":"error"|"state":"error"|"level":"error"' "$OUT/core.log" | tail -2 | cut -c1-300)"
  check "ядро подключилось" fail "${WHY:-не подключилось за $WAIT с; последняя строка: $(tail -1 "$OUT/core.log" | cut -c1-300)}"
  exit 1
fi
check "ядро подключилось" ok "$(grep '"state":"connected"' "$OUT/core.log" | head -1 | sed -n 's/.*"streams":\([0-9]*\),"total":\([0-9]*\).*/потоков \1 из \2/p')"

[ -n "${PROOF_NO_ENGINE:-}" ] && exit 0

sudo "$ROOT/build/amnezia-box" run -c "$OUT/engine.json" -D "$OUT" > "$OUT/engine.log" 2>&1 &
ENGINE_PID=$!
for _ in $(seq 20); do grep -q 'sing-box started' "$OUT/engine.log" && break; sleep 1; done
if ! grep -q 'sing-box started' "$OUT/engine.log"; then
  check "движок поднял туннель" fail "$(tail -3 "$OUT/engine.log" | cut -c1-300)"
  exit 1
fi
check "движок поднял туннель" ok "utun поднят"
sleep 5

VPN_IP="$(ip_of "$IP_URL")"
[ -n "$VPN_IP" ] && [ "$VPN_IP" != "$HOME_IP" ] \
  && check "трафик идёт через VPN" ok "IP $VPN_IP" \
  || check "трафик идёт через VPN" fail "IP '${VPN_IP:-нет ответа}', домашний $HOME_IP"

DOMAIN_IP="$(ip_of "$DIRECT_URL")"
[ "$DOMAIN_IP" = "$HOME_IP" ] \
  && check "правило по домену (напрямую)" ok "icanhazip.com видит $DOMAIN_IP" \
  || check "правило по домену (напрямую)" fail "icanhazip.com видит '${DOMAIN_IP:-нет ответа}', ожидался $HOME_IP"

APP_IP="$(ip_of "$IP_URL" "$OUT/curl-direct")"
[ "$APP_IP" = "$HOME_IP" ] \
  && check "правило по приложению (напрямую)" ok "копия curl видит $APP_IP" \
  || check "правило по приложению (напрямую)" fail "копия curl видит '${APP_IP:-нет ответа}', ожидался $HOME_IP"

# Петля проявилась бы как срыв сессии сразу после подъёма туннеля.
BEFORE="$(grep -c '"state":"connecting"' "$OUT/core.log")"
sleep 20
AFTER_N="$(grep -c '"state":"connecting"' "$OUT/core.log")"
STILL="$(ip_of "$IP_URL")"
[ "$AFTER_N" = "$BEFORE" ] && [ "$STILL" = "$VPN_IP" ] \
  && check "сокеты ядра идут мимо туннеля" ok "за 20 с переподключений нет, VPN жив" \
  || check "сокеты ядра идут мимо туннеля" fail "переподключений: $((AFTER_N - BEFORE)), IP '${STILL:-нет ответа}'"

echo; echo "Туннель работает. Можно проверить руками в браузере; Ctrl-C — остановить."
wait "$ENGINE_PID"
