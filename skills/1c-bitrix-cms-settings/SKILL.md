---
name: 1c-bitrix-cms-settings
description: "Настройки и расширение «1С-Битрикс: Управление сайтом» — .settings.php и Option, обработчики событий (init.php), агенты и cron, кэширование (управляемый/тегированный/композит), SMTP и почта. Используй для конфигурации, событий, агентов, кэша на сайте Битрикс (не Битрикс24)."
---
# 1c-bitrix-cms-settings

Конфигурация и расширение поведения сайта на Битрикс. Гейты оркестратора: код в `/local` (обработчики — в `/local/php_interface/init.php`), ядро не трогать.

## Среда
- «только файлы» → создавай `init.php`/конфиг + инструкцию; «живой Битрикс» → можно применить Option/событие/агент и проверить.

## Задача → рецепт (`../../shared/kb/recipes/settings/`)
- конфиг: `.settings.php` (Configuration) vs Option (настройки модулей в БД) → `settings/01-config-settings.md`
- обработчики событий (init.php, D7 EventManager / legacy AddEventHandler) → `settings/02-events.md`
- агенты и cron (периодические задачи) → `settings/03-agents-cron.md`
- кэширование (управляемый/тегированный/HTML/композит) → `settings/04-caching.md`
- почта и SMTP (доставка писем, очередь) → `settings/05-mail-smtp.md`

## База знаний
Ядро/Configuration/события/кэш — `../../shared/kb/00-overview.md`; «задача → класс» — `../../shared/kb/api-map.md`; правила — `../../shared/kb/conventions.md`. Транзакционные письма (тип события + шаблон) — в `1c-bitrix-cms-content` (`13-email-events.md`).

## Завершение
`../../shared/scripts/check-conventions.sh <каталог_проекта>`
