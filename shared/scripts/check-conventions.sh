#!/bin/sh
# check-conventions.sh [--strict] <project_dir>
# Best-effort статические проверки конвенций и безопасности 1С-Битрикс.
# [FAIL]   — надёжные нарушения (всегда влияют на exit-код).
# [REVIEW] — эвристика, требует ручного подтверждения. По умолчанию НЕ меняет exit-код.
#
# Покрытие [REVIEW] (помимо базовых конвенций): негейченный установщик в webroot
# (prolog_before.php + мутирующий вызов Add/Update/Delete без IsAdmin()/CLI-гейта),
# хардкод-секреты (password|token|api_key|... = "литерал"), косвенные/опасные sink'и
# (include/require по переменной, system/exec/shell_exec/passthru/proc_open/popen,
# unserialize() на запросе, $DBDebug=true).
#
# STRICT/CI-режим: при CHECK_STRICT=1 (env) или флаге --strict любой [REVIEW] тоже
# делает финальный exit-код ненулевым — чтобы автоматизация не «проезжала» мимо
# неподтверждённых [REVIEW]. По умолчанию (без strict) [REVIEW] не меняет exit-код.
set -eu

STRICT="${CHECK_STRICT:-0}"
if [ "${1:-}" = "--strict" ]; then STRICT=1; shift; fi

DIR="${1:?usage: check-conventions.sh [--strict] <project_dir>}"
rc=0
reviews=0
fail()  { echo "[FAIL] $1"; rc=1; }
review(){ echo "[REVIEW] $1"; reviews=$((reviews + 1)); }

# 1) [REVIEW] файлы в каталогах ядра — кастом должен быть в /local
if find "$DIR/bitrix/modules" "$DIR/bitrix/components/bitrix" -type f 2>/dev/null | grep -q .; then
  review "есть файлы в каталогах ядра (bitrix/modules|components/bitrix) — кастом держать в /local"
fi

# SCOPE: кастомный код проекта = всё под $DIR, КРОМЕ дерева ядра $DIR/bitrix
# (legacy-ядро легально содержит короткие теги и НЕ должно флагаться).
# grep_proj <ERE> — рекурсивный grep по проекту с исключением каталога ядра /bitrix.
grep_proj() {
  grep -rnE --exclude-dir=bitrix "$1" "$DIR" 2>/dev/null
}

# 2) [FAIL] eval(base64(...)) в коде проекта (кроме ядра /bitrix)
if grep_proj 'eval[[:space:]]*\([[:space:]]*base64' | grep -q .; then
  fail "eval(base64(...)) в коде проекта"
fi

# 3) [FAIL] короткий открывающий тег <? в коде проекта (нужен <?php).
#    Ловим настоящий короткий ОТКРЫВАЮЩИЙ тег: '<?' СРАЗУ за которым идёт PHP-токен
#    ($, буква, или пробел) — т.е. '<?$APPLICATION', '<?if', '<? echo', '<?foreach'.
#    Разрешены: '<?php' и '<?=' (короткий echo). Bare '<?' (открытие) — запрещён.
#    ПРИМЕЧАНИЕ: шаблоны сайта Битрикс легально используют стиль '<?$APPLICATION->ShowHead()',
#    но конвенция запрещает короткие теги в кастоме — поэтому чекер их флагает.
#    '<?=' (короткий echo) допускается, голые '<?'-открытия — нет.
#    '<?xml' (литерал XML-декларации в строке/heredoc) исключаем как ложноположительный.
if grep_proj '<\?([[:alpha:]$]|[[:space:]])' | grep -vE '<\?php|<\?=|<\?xml' | grep -q .; then
  fail "короткий тег <? в коде проекта (использовать <?php; разрешён только <?=)"
fi

# 4) [REVIEW] изменяющие действия без видимого check_bitrix_sessid (семантика — не вердикт)
for ff in $(grep -rlE --exclude-dir=bitrix '\$_(REQUEST|POST|GET)\[' "$DIR" 2>/dev/null || true); do
  grep -q 'bitrix_sessid' "$ff" || review "обработка \$_POST/\$_GET без check_bitrix_sessid: $ff — проверить защиту от CSRF вручную"
done

# 5) [REVIEW] прямой SQL с пользовательским вводом (риск SQL-инъекции)
if grep_proj '->(Query|Execute|QueryScalar)\([^)]*\$_(REQUEST|POST|GET|COOKIE)' | grep -q .; then
  review "прямой SQL с пользовательским вводом (->Query/Execute) — использовать ForSql()/PrepareInsert()/PrepareUpdate() или параметры ORM"
fi

# 6) [REVIEW] вывод пользовательского ввода без экранирования (риск XSS)
if grep_proj '(echo|print)[[:space:]]+\$_(REQUEST|POST|GET|COOKIE)\[' | grep -v 'htmlspecialcharsbx' | grep -q .; then
  review "вывод \$_REQUEST/\$_GET без htmlspecialcharsbx() — экранировать против XSS"
fi

# 7) [REVIEW] NOT_CHECK_PERMISSIONS — привилегированный установщик в webroot
if grep -rlE --exclude-dir=bitrix "define\([\"']NOT_CHECK_PERMISSIONS" "$DIR" 2>/dev/null | grep -q .; then
  for ff in $(grep -rlE --exclude-dir=bitrix "define\([\"']NOT_CHECK_PERMISSIONS" "$DIR" 2>/dev/null); do
    review "NOT_CHECK_PERMISSIONS в $ff — привилегированный скрипт в webroot: удалить/вынести из корня/закрыть по HTTP после использования"
  done
fi

# 8) [REVIEW] целостность ядра — только при наличии эталона контрольных сумм
if [ -f "$DIR/.bitrix-core-checksums" ]; then
  review "найден эталон контрольных сумм — сверку целостности ядра выполнить отдельным шагом"
fi

# 9) [REVIEW] НЕГЕЙЧЕНЫЙ УСТАНОВЩИК: файл подключает prolog_before.php И вызывает
#    мутирующий метод (CIBlock*::Add | CUserTypeEntity::Add | CAgent::AddAgent |
#    ->Add( | ->Update( | ->Delete()), НО не содержит ни IsAdmin(), ни CLI-гейта
#    (PHP_SAPI / php_sapi_name 'cli'). Это рецепт-02/03 установщики, мимо которых
#    проходит правило NOT_CHECK_PERMISSIONS. Каталог ядра /bitrix исключаем.
for ff in $(grep -rlE --exclude-dir=bitrix 'prolog_before\.php' "$DIR" 2>/dev/null || true); do
  grep -qE 'CIBlock[[:alnum:]_]*::Add|CUserTypeEntity::Add|CAgent::AddAgent|->Add\(|->Update\(|->Delete\(\)' "$ff" || continue
  if grep -qE 'IsAdmin\(|PHP_SAPI|php_sapi_name' "$ff"; then continue; fi
  review "негейченый установщик: $ff подключает prolog_before.php и мутирует данные (Add/Update/Delete) без IsAdmin()/CLI-гейта — закрыть проверкой прав или ограничить запуском из CLI"
done

# 10) [REVIEW] ХАРДКОД-СЕКРЕТЫ: ключ (password|token|api_key|secret|client_secret)
#     с присваиванием = или : и закавыченным литералом длиной >=6. Очевидные
#     плейсхолдеры исключаем, чтобы не флагать примеры из рецептов.
# Между ключом и литералом допускаем кавычки/пробелы/стрелку (`'api_key' => '...'`,
# `password: "..."`, `token="..."`). Литерал — закавыченная строка длиной >=6.
if grep_proj '(password|passwd|secret|token|api[_-]?key|client[_-]?secret)[[:alnum:]_'"'"'"]*[[:space:]]*[=:][>[:space:]]*["'"'"'][^"'"'"']{6,}["'"'"']' \
   | grep -viE 'CHANGE_ME|\*\*\*|XXX|your_|<|example|описан|placeholder' | grep -q .; then
  review "похоже на хардкод-секрет (password/token/api_key/... = \"литерал\") — вынести в .settings.php/ENV, не коммитить в репозиторий"
fi

# 11) [REVIEW] КОСВЕННЫЕ/ОПАСНЫЕ SINK'И:
#     include/require с непостоянным ($) аргументом — LFI/RFI-риск.
if grep_proj '(include|include_once|require|require_once)[[:space:]]*\(?[[:space:]]*\$' | grep -q .; then
  review "include/require с переменной (\$...) — риск LFI/RFI: подключать только из белого списка/констант"
fi
#     запуск процессов ОС.
if grep_proj '(system|exec|shell_exec|passthru|proc_open|popen)[[:space:]]*\(' | grep -q .; then
  review "вызов system/exec/shell_exec/passthru/proc_open/popen — командная инъекция: избегать или строго экранировать (escapeshellarg)"
fi
#     unserialize() на данных запроса — object injection.
if grep_proj 'unserialize[[:space:]]*\([^)]*\$_(REQUEST|POST|GET|COOKIE)' | grep -q .; then
  review "unserialize() на данных запроса — PHP object injection: не десериализовать пользовательский ввод (использовать json_decode)"
fi
#     режим отладки БД в коде.
if grep_proj '\$DBDebug[[:space:]]*=[[:space:]]*true' | grep -q .; then
  review "\$DBDebug = true — отладка БД раскрывает SQL/структуру: не оставлять в продакшене"
fi

if [ $rc -eq 0 ]; then
  echo "check-conventions: OK (структурные правила + эвристики безопасности: установщики/секреты/sink'и); это НЕ гарантия безопасности — проверьте все [REVIEW] вручную перед сдачей."
else
  echo "check-conventions: НАРУШЕНИЯ найдены — это НЕ гарантия безопасности, проверьте все [REVIEW] вручную перед сдачей."
fi
if [ "$reviews" -gt 0 ]; then
  echo "check-conventions: [REVIEW]-пунктов: $reviews — каждый требует ручного подтверждения (manual sign-off) перед сдачей."
  if [ "$STRICT" = "1" ]; then
    echo "check-conventions: STRICT-режим (CHECK_STRICT=1/--strict) — неподтверждённые [REVIEW] делают exit ненулевым."
    rc=1
  fi
fi
exit $rc
