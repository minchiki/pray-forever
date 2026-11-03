#!/usr/bin/env bash
# Отправляет анонс (docs/telegram_post.md) с баннером через Telegram Bot API sendPhoto.
# Токен и чат — только из переменных TELEGRAM_BOT_TOKEN и TELEGRAM_CHAT_ID (или из .env в корне);
# скрипт их не печатает.
#
#   bash scripts/post_telegram.sh --dry-run   # показать подпись и её длину, ничего не отправлять
#   bash scripts/post_telegram.sh             # отправить
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
POST="$ROOT/docs/telegram_post.md"
PHOTO="$ROOT/assets/social-preview.png"

if [ -f "$ROOT/.env" ]; then
  while IFS='=' read -r key value; do
    case "$key" in
      TELEGRAM_BOT_TOKEN | TELEGRAM_CHAT_ID) [ -z "${!key:-}" ] && export "$key=$value" ;;
    esac
  done < <(grep -E '^TELEGRAM_(BOT_TOKEN|CHAT_ID)=' "$ROOT/.env" || true)
fi

CAPTION="$(sed -n '/<!-- caption:start -->/,/<!-- caption:end -->/p' "$POST" | sed '1d;$d')"
# Telegram считает длину видимого текста, без HTML-тегов.
VISIBLE="$(printf '%s' "$CAPTION" | sed -E 's/<[^>]+>//g')"
count_chars() {
  local py
  for py in python3 python; do
    if "$py" -c 'import sys' >/dev/null 2>&1; then
      printf '%s' "$1" | "$py" -c 'import sys; print(len(sys.stdin.buffer.read().decode("utf-8")))'
      return
    fi
  done
  printf '%s' "$1" | LC_ALL=C.UTF-8 wc -m | tr -d ' '
}
LENGTH="$(count_chars "$VISIBLE")"

if [ "${1:-}" = "--dry-run" ]; then
  printf '%s\n\n--- %s символов из 1024\n' "$CAPTION" "$LENGTH"
  exit 0
fi

if [ "$LENGTH" -gt 1024 ]; then
  echo "Подпись длиннее 1024 символов ($LENGTH)" >&2
  exit 1
fi
: "${TELEGRAM_BOT_TOKEN:?Задайте TELEGRAM_BOT_TOKEN (переменная окружения или .env)}"
: "${TELEGRAM_CHAT_ID:?Задайте TELEGRAM_CHAT_ID (переменная окружения или .env)}"

RESPONSE="$(curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendPhoto" \
  -F "chat_id=${TELEGRAM_CHAT_ID}" \
  -F "photo=@${PHOTO}" \
  -F "parse_mode=HTML" \
  --form-string "caption=${CAPTION}")"

if printf '%s' "$RESPONSE" | grep -q '"ok":true'; then
  echo "Отправлено: message_id $(printf '%s' "$RESPONSE" | sed -nE 's/.*"message_id":([0-9]+).*/\1/p')"
else
  echo "Ошибка Telegram: $(printf '%s' "$RESPONSE" | sed -nE 's/.*"description":"([^"]*)".*/\1/p')" >&2
  exit 1
fi
