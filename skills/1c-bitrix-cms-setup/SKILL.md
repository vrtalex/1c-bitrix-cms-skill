---
name: 1c-bitrix-cms-setup
description: "Окружение и установка «1С-Битрикс: Управление сайтом» — системные требования, структура проекта (/local, /bitrix, document root), установка/восстановление, CLI и composer, настройка dev-среды. Используй для разворачивания/инициализации проекта на Битрикс (не Битрикс24)."
---
# 1c-bitrix-cms-setup

Подготовка окружения и проекта на Битрикс. Гейты оркестратора: код в `/local`, ядро не трогать.

## Среда
- «чистый старт» → развернуть окружение + установить; «существующий проект» → интроспекция (см. `1c-bitrix-cms-content` рецепт `01-introspect-project.md`).

## Задача → рецепт (`../../shared/kb/recipes/setup/`)
- системные требования и окружение (PHP/СУБД/расширения, BitrixEnv/Docker, bitrix_server_test) → `setup/01-environment-requirements.md`
- структура проекта (document root, /bitrix vs /local, init.php, .settings) → `setup/02-project-structure.md`
- установка / восстановление (мастер, headless-прогон по HTTP, restore.php) → `setup/03-installation.md`
- CLI и composer (консольные команды, ORM Make) → `setup/04-cli-console.md`
- настройка dev-среды (режим разработки, отключение автообновлений, кэш на деве) → `setup/05-dev-setup.md`

## База знаний
Структура и bootstrap — `../../shared/kb/00-overview.md`; эксплуатация — `../../shared/kb/operations.md`; правила — `../../shared/kb/conventions.md`. Деплой/CI — под-скилл `1c-bitrix-cms-deploy`.

## Завершение
`../../shared/scripts/check-conventions.sh <каталог_проекта>`
