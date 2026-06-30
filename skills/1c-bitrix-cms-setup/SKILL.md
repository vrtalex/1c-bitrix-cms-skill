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
- установка: оркестрация (3 режима базы, гейт завершённости, дерево решений) → `setup/03-installation.md`
- установка с нуля мастером (карта полей, браузер-хэндофф, Режим 2) → `setup/06-install-wizard.md`
- CLI и composer (консольные команды для уже установленного сайта, ORM Make) → `setup/04-cli-console.md`
- настройка dev-среды (режим разработки, отключение автообновлений, кэш на деве) → `setup/05-dev-setup.md`
- локальный контейнерный dev-стенд (env-docker, docker compose, PHP 8.2–8.4, БД, кэш) → `setup/05-dev-setup.md`

## База знаний
Структура и bootstrap — `../../shared/kb/00-overview.md`; эксплуатация — `../../shared/kb/operations.md`; правила — `../../shared/kb/conventions.md`. Деплой/CI — под-скилл `1c-bitrix-cms-deploy`.

## Завершение
`../../shared/scripts/check-conventions.sh <каталог_проекта>`
