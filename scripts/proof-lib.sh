#!/bin/bash
# Функции scripts/proof.sh, вынесенные ради теста.

# captcha_url <core.log> - адрес ручной капчи из последнего события ядра; пусто, если капча не нужна.
# Строку разбирает plutil, а не sed: в JSON амперсанд записан escape-последовательностью,
# и вырезанный "как есть" адрес приходил в браузер без параметров.
captcha_url() {
  local line
  line="$(grep '"ev":"captcha"' "$1" | tail -1)"
  [ -n "$line" ] || return 0
  [ "$(printf '%s' "$line" | plutil -extract manual raw -o - - 2>/dev/null)" = true ] || return 0
  printf '%s' "$line" | plutil -extract url raw -o - - 2>/dev/null
}
