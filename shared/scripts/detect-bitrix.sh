#!/bin/sh
# detect-bitrix.sh [project-root]
#
# Детерминированный детектор окружения «1С-Битрикс: Управление сайтом».
# Best-effort, READ-ONLY: только читает файлы, ничего не создаёт и не меняет.
# Эмитит JSON-объект в stdout. Запускается где угодно без ошибки: если сигналов нет,
# деградирует до mode "clean" и unknown-полей.
#
# Это детерминированная версия шага оркестратора «1. Определи среду»: агент всё равно
# рассуждает, но получает структурированную ground-truth картину.
#
# Поля JSON:
#   mode              live | files-only | remote | clean
#   core_present      есть ли каталог ядра bitrix/
#   core_version      SM_VERSION из version.php, если читается; иначе ""
#   local_present     есть ли каталог /local
#   settings_location путь к .settings.php (или bitrix/php_interface/dbconn.php), если есть
#   db_reachable      всегда "unknown" (детектор не подключается к БД)
#   php_available     доступен ли интерпретатор php в PATH
#   encoding          utf-8 | unknown (эвристика по .settings.php/.encoding)
#   d7_available      доступно ли ядро D7 (vendor/autoload.php либо bitrix/modules/main/lib)
set -eu

ROOT="${1:-.}"

# --- утилиты --------------------------------------------------------------

# JSON-экранирование строкового значения (минимально достаточное: \ и ").
json_escape() {
  # читает $1, печатает экранированную строку без кавычек
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

emit_bool() { [ "$1" = "1" ] && printf 'true' || printf 'false'; }

# --- ядро присутствует? ---------------------------------------------------

core_present=0
[ -d "$ROOT/bitrix" ] && core_present=1

local_present=0
[ -d "$ROOT/local" ] && local_present=1

# --- расположение настроек ------------------------------------------------

settings_location=""
for cand in \
  "$ROOT/bitrix/.settings.php" \
  "$ROOT/.settings.php" \
  "$ROOT/bitrix/php_interface/dbconn.php"
do
  if [ -f "$cand" ]; then
    settings_location="$cand"
    break
  fi
done

# --- версия ядра (SM_VERSION) ---------------------------------------------
# Источники по приоритету:
#   1) bitrix/modules/main/classes/general/version.php  (define("SM_VERSION", "..."))
#   2) bitrix/.settings.php / .settings.php             (на случай выноса версии)
core_version=""
vfile="$ROOT/bitrix/modules/main/classes/general/version.php"
if [ -f "$vfile" ]; then
  # Вытаскиваем литерал из define("SM_VERSION","26.150.0") в любом стиле кавычек.
  core_version="$(
    grep -i 'SM_VERSION' "$vfile" 2>/dev/null \
      | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' \
      | head -n1 || true
  )"
fi

# --- php доступен? --------------------------------------------------------

php_available=0
if command -v php >/dev/null 2>&1; then
  php_available=1
fi

# --- кодировка (эвристика) ------------------------------------------------
# Битрикс хранит признак UTF в bitrix/.settings.php (utf_mode) или в /bitrix/.encoding.
encoding="unknown"
if [ -f "$ROOT/bitrix/.encoding" ] \
   && grep -qiE 'utf-?8' "$ROOT/bitrix/.encoding" 2>/dev/null; then
  encoding="utf-8"
elif [ -f "$ROOT/bitrix/.settings.php" ] \
   && grep -iE 'utf_mode' "$ROOT/bitrix/.settings.php" 2>/dev/null \
      | grep -qiE 'true|utf-?8'; then
  # 'utf_mode' => array('value' => true, ...) на одной строке — типичный случай.
  encoding="utf-8"
fi

# --- доступно ли D7 -------------------------------------------------------

d7_available=0
if [ -d "$ROOT/bitrix/modules/main/lib" ] \
   || [ -f "$ROOT/bitrix/modules/main/vendor/autoload.php" ] \
   || [ -f "$ROOT/vendor/autoload.php" ]; then
  d7_available=1
fi

# --- режим ----------------------------------------------------------------
# live      — ядро есть И php доступен (можно исполнять код; БД не проверяем).
# files-only— ядро или /local есть, но php недоступен (только файлы/инструкции).
# remote    — здесь не определяется (нужны явные доступы FTP/SSH/REST); резерв.
# clean     — никаких сигналов Битрикса (чистый старт).
if [ "$core_present" = "1" ] && [ "$php_available" = "1" ]; then
  mode="live"
elif [ "$core_present" = "1" ] || [ "$local_present" = "1" ]; then
  mode="files-only"
else
  mode="clean"
fi

# --- вывод JSON -----------------------------------------------------------

printf '{'
printf '"mode": "%s", ' "$(json_escape "$mode")"
printf '"core_present": %s, ' "$(emit_bool "$core_present")"
printf '"core_version": "%s", ' "$(json_escape "$core_version")"
printf '"local_present": %s, ' "$(emit_bool "$local_present")"
printf '"settings_location": "%s", ' "$(json_escape "$settings_location")"
printf '"db_reachable": "unknown", '
printf '"php_available": %s, ' "$(emit_bool "$php_available")"
printf '"encoding": "%s", ' "$(json_escape "$encoding")"
printf '"d7_available": %s' "$(emit_bool "$d7_available")"
printf '}\n'
