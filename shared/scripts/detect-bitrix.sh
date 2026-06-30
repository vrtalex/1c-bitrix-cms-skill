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
#   install_finalized Y | N | unknown — эвристика «установка доведена до конца».
#                     Требует публичный корневой index.php: завершённый сайт без
#                     него консервативно даёт N. Ключевой для сканера артефакт —
#                     bitrix/install/index.php (его наличие → N). Сигнализирует
#                     только пункты гейта 1 и 4; артефакты публичного слоя
#                     (пункт 3) не проверяет.
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
   && grep -A2 'utf_mode' "$ROOT/bitrix/.settings.php" 2>/dev/null \
      | grep -qiE "'value'[[:space:]]*=>[[:space:]]*true"; then
  # 'utf_mode' => array('value' => true, ...). Битрикс печатает этот массив
  # многострочно, поэтому захватываем 2 строки после ключа (grep -A2).
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

# --- сигнал install_finalized ---------------------------------------------
# Эвристика «установка доведена до конца»: Y / N / unknown.
# unknown — если нет никаких признаков Битрикса в корне (нечего анализировать).
# Это эвристика; ПОЛНЫЙ «гейт завершённости» дополнительно проверяет, что
# визуальный редактор открывается — этого shell не умеет,
# см. recipes/setup/03-installation.
install_finalized="unknown"
if [ "$core_present" = "1" ] || [ -f "$ROOT/index.php" ]; then
  # Условия для Y (все должны выполняться):
  # 1) корневой index.php есть и не содержит маркеров мастера установки
  #    (нет публичного index.php — консервативно N, а не Y).
  # 2) присутствует bitrix/admin/index.php
  # 3) нет установочных скриптов в корне и нет bitrix/install/index.php
  # Это сигнал по пунктам гейта 1 и 4; артефакты публичного слоя
  # (пункт 3 гейта) здесь НЕ инспектируются.
  _idx="$ROOT/index.php"
  _idx_ok=0
  if [ -f "$_idx" ]; then
    if ! grep -qiE 'bitrixsetup|BX_BITRIX_INSTALL|CurrentStepID|wizard' "$_idx" 2>/dev/null; then
      _idx_ok=1
    fi
  fi

  _admin_ok=0
  [ -f "$ROOT/bitrix/admin/index.php" ] && _admin_ok=1

  # restore.php ловим по СУФФИКСУ: распространён префиксный вариант
  # example.com.restore.php (публичный эндпоинт перезаписи сайта); шаблон
  # *[Rr]estore.php покрывает и .Restore.php. Карантинный суффикс *.suspected
  # (модуль «Лечение сайта») — тоже артефакт. Остальные — по точному имени.
  # [ -e ] нужен, т.к. под set -eu несовпавший glob /bin/sh раскрывается в сам
  # шаблон, и [ -f ] на нём дал бы ложный матч.
  _setup_absent=1
  for _s in "$ROOT"/*[Rr]estore.php "$ROOT"/*.suspected "$ROOT"/bitrixsetup.php "$ROOT"/bx_1c_import.php "$ROOT"/bitrix_server_test.php; do
    [ -e "$_s" ] && { _setup_absent=0; break; }
  done
  [ -f "$ROOT/bitrix/install/index.php" ] && _setup_absent=0

  if [ "$_idx_ok" = "1" ] && [ "$_admin_ok" = "1" ] && [ "$_setup_absent" = "1" ]; then
    install_finalized="Y"
  else
    install_finalized="N"
  fi
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
printf '"d7_available": %s, ' "$(emit_bool "$d7_available")"
printf '"install_finalized": "%s"' "$(json_escape "$install_finalized")"
printf '}\n'
