---
name: 1c-bitrix-cms-template
description: Шаблоны сайта на «1С-Битрикс: Управление сайтом» — создание шаблона (header/footer/styles), меню, включаемые области, подключение CSS/JS (Asset, UI-расширения), требования к вёрстке и работе визуального редактора. Используй для оформления/вёрстки сайта Битрикс (не Битрикс24).
---
# 1c-bitrix-cms-template

Оформление сайта на Битрикс. Гейты оркестратора: всё в `/local` (`/local/templates/<id>/`), ядро не трогать, перед сдачей — `check-conventions`.

## Среда
- «только файлы» → создавай файлы шаблона + инструкцию привязки к сайту; «живой Битрикс» → можно привязать и проверить рендер.

## Задача → рецепт (`../../shared/kb/recipes/template/`)
- создать шаблон сайта (header/footer/styles/.styles.php/description) → `template/01-create-template.md`
- меню (верхнее/левое, типы, шаблон меню) → `template/02-menu.md`
- включаемые области (редактируемые блоки) → `template/03-include-areas.md`
- подключение CSS/JS (Asset, UI-расширения) → `template/04-assets.md`
- требования к вёрстке (styles.css vs template_styles.css, H1, адаптив, визредактор) → `template/05-verstka-requirements.md`
- встроить готовую HTML-вёрстку (прототип/макет) в шаблон → `template/06-integrate-prototype.md`

## База знаний
Жизненный цикл страницы и шаблона — `../../shared/kb/00-overview.md`; «задача → класс» — `../../shared/kb/api-map.md`. Вывод контента внутри шаблона — под-скилл `1c-bitrix-cms-content`.

## Завершение
`../../shared/scripts/check-conventions.sh <каталог_проекта>`
