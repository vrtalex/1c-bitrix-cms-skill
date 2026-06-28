#!/bin/sh
# refresh-version-baseline.sh — BEST-EFFORT помощник по сверке version-baseline.json.
#
# ЧЕСТНО: у 1С-Битрикс НЕТ чистого публичного version-API (как api.wordpress.org
# у WordPress). Состав версий и снятых API публикуется в человекочитаемых
# страницах (reqintro.php, docs/versions.php), форма которых меняется. Поэтому
# этот скрипт — ЛЕСА/ПОДСПОРЬЕ, а НЕ авторитетный авто-обновлятель:
#   (a) пытается скачать вендорские страницы требований/версий (если есть сеть);
#   (b) печатает, что удалось получить (намёки на упоминания PHP/MySQL/версий);
#   (c) считает контент-хэш version-baseline.json и сигналит флагом «изменилось»;
#   (d) НИКОГДА не переписывает проверенные факты молча — он лишь помечает файл
#       к ручному ревью (human review).
#
# Сеть опциональна: офлайн скрипт отрабатывает без ошибок (network-шаги skip'аются).
# Exit 0 во всех штатных случаях. Флаг изменения — в stdout (CHANGED=...), не в коде
# возврата, чтобы CI-обёртка решала, открывать ли PR.
set -eu

# --- Пути -------------------------------------------------------------------
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
BASELINE="$REPO_ROOT/shared/kb/version-baseline.json"
HASH_FILE="$REPO_ROOT/shared/kb/.version-baseline.sha256"

# Вендорские страницы (человекочитаемые, не API).
REQ_URL="https://dev.1c-bitrix.ru/user_help/reqintro.php"
VERSIONS_URL="https://dev.1c-bitrix.ru/docs/versions.php"

CHANGED=0

log() { echo "[refresh-version-baseline] $1"; }

# --- 0. Базовая проверка наличия baseline -----------------------------------
if [ ! -f "$BASELINE" ]; then
  log "НЕ НАЙДЕН $BASELINE — нечего сверять. Создайте файл вручную."
  echo "CHANGED=0"
  exit 0
fi

# --- 1. Контент-хэш: детект ручных правок baseline между прогонами -----------
compute_hash() {
  # POSIX-устойчивый хэш: предпочитаем sha256sum, иначе shasum -a 256.
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    echo "no-sha-tool"
  fi
}

CUR_HASH=$(compute_hash "$BASELINE")
log "текущий хэш baseline: $CUR_HASH"

if [ -f "$HASH_FILE" ]; then
  PREV_HASH=$(cat "$HASH_FILE" 2>/dev/null || echo "")
  if [ "$CUR_HASH" != "$PREV_HASH" ]; then
    log "baseline изменился с прошлого прогона (был: ${PREV_HASH:-нет}) — флаг к ревью."
    CHANGED=1
  else
    log "baseline без изменений с прошлого прогона."
  fi
else
  log "снимок хэша отсутствует — первый прогон, сохраняю эталон."
fi

# --- 2. Сетевая часть (best-effort, опциональна) ----------------------------
# Если curl недоступен или сети нет — graceful skip, БЕЗ ошибки.
fetch() {
  # fetch <url> -> печатает тело в stdout, пусто при неудаче. Не валит set -e.
  _url="$1"
  if ! command -v curl >/dev/null 2>&1; then
    return 1
  fi
  curl -fsSL --max-time 15 -A "bitrix-skill-version-refresh/0.1" "$_url" 2>/dev/null || return 1
}

scan_page() {
  # scan_page <label> <url> — печатает строки с упоминанием PHP/MySQL/версий.
  _label="$1"; _url="$2"
  log "сверяю $_label: $_url"
  _body=$(fetch "$_url") || {
    log "  сеть недоступна или страница не получена — пропускаю (offline-safe)."
    return 0
  }
  _hits=$(printf '%s\n' "$_body" \
    | tr '<>' '\n\n' \
    | grep -iE 'PHP[[:space:]]*[0-9]|MySQL[[:space:]]*[0-9]|MariaDB|utf8mb4|26\.[0-9]|25\.[0-9]' \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
    | grep -vE '^$' \
    | head -n 12 || true)
  if [ -n "$_hits" ]; then
    log "  упоминания (СВЕРИТЬ ВРУЧНУЮ с baseline, НЕ автоприменяется):"
    printf '%s\n' "$_hits" | sed 's/^/    | /'
  else
    log "  явных упоминаний версий не извлечено (форма страницы могла измениться)."
  fi
}

scan_page "требования (reqintro)" "$REQ_URL"
scan_page "история версий (docs/versions)" "$VERSIONS_URL"

# --- 3. Сохранить снимок хэша и отчитаться -----------------------------------
# Сохраняем текущий хэш как эталон для следующего прогона.
printf '%s\n' "$CUR_HASH" > "$HASH_FILE" 2>/dev/null || \
  log "не удалось записать $HASH_FILE (только чтение?) — продолжаю."

log "ИТОГ: скрипт не меняет проверенные факты. Любые расхождения с вендором"
log "      выше — повод обновить shared/kb/version-baseline.json ВРУЧНУЮ."
echo "CHANGED=$CHANGED"
exit 0
