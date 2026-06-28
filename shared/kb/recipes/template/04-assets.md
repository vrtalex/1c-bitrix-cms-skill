# Подключение CSS/JS в шаблоне сайта (assets)

## Цель
Правильно подключить стили и скрипты шаблона сайта и его компонентов: что
подключается автоматически, как добавить свои CSS/JS, как подтянуть UI-расширения
Битрикс (`ui.*`, `main.*`) и куда класть ассеты, чтобы вёрстка не дублировалась и
не ломалась при обновлении ядра.

## Когда применять
- Пишешь `header.php`/`footer.php` шаблона и нужно собрать `<head>`.
- В шаблоне компонента (`template.php`) требуется свой стиль/скрипт.
- Нужны готовые UI-кирпичи Битрикс: кнопки, попапы, вкладки, дизайн-токены.
- Подключаешь сторонний CSS/JS (шрифты, библиотеку) и хочешь сделать это так,
  чтобы попадало в правильную зону страницы и участвовало в объединении/минификации.

## Шаги
1. **Корневые CSS подключатся сами.** Файлы `template_styles.css` и `styles.css`
   в корне папки шаблона ядро добавляет автоматически (метод
   `Asset::addTemplateCss()`). Основной CSS шаблона кладём в `template_styles.css`,
   контентный — в `styles.css`. Вручную `<link>` на них не пишем.
2. **В `<head>` выводим всё одним вызовом.** `<?php $APPLICATION->ShowHead();?>` выводит
   meta-теги, canonical, все CSS, head-строки и head-скрипты. Это обязательный
   вызов; без него подключённые ассеты не попадут на страницу.
3. **UI-расширения — через `Extension::load()`.** В `header.php` подключаем
   нужный фронтенд-кит: дизайн-токены, шрифты, библиотеки `ui.*`/`main.*`. Зависимости
   расширения тянутся автоматически.
4. **Свои CSS/JS — через `Asset::getInstance()`.** Для произвольных файлов и
   inline-строк используем менеджер ассетов с указанием зоны (location).
5. **В компоненте подключаем расширения из его кода.** В `template.php`,
   `component.php` или `class.php` вызываем `Extension::load([...])` — стили/скрипты
   станут доступны в шаблоне компонента. Файлы `style.css` и `script.js` рядом с
   `template.php` ядро подключает автоматически.
6. **Объединение/минификация** включается в настройках модуля `main`
   («Оптимизация загрузки CSS/JS») — отдельные файлы собираются в общие бандлы.

## Рабочий сниппет (путь в /local)

`/local/templates/my_template/header.php`
```php
<?php
if (!defined('B_PROLOG_INCLUDED') || B_PROLOG_INCLUDED !== true) die();

use Bitrix\Main\Page\Asset;
use Bitrix\Main\Page\AssetLocation;
use Bitrix\Main\UI\Extension;

IncludeTemplateLangFile(__FILE__);

// Фронтенд-кит Битрикс: дизайн-токены + ядро + попапы (зависимости подтянутся сами)
Extension::load([
    'ui.design-tokens',   // CSS-переменные --ui-*
    'ui.fonts.opensans',  // шрифт (для AIR-шаблона не нужен)
    'main.core',          // глобальный BX
    'main.popup',         // всплывающие окна
]);

// Свои файлы шаблона и inline-строка через менеджер ассетов
$asset = Asset::getInstance();
$asset->addCss(SITE_TEMPLATE_PATH . '/css/layout.css');
$asset->addJs(SITE_TEMPLATE_PATH . '/js/app.js');
$asset->addString(
    '<link rel="preconnect" href="https://fonts.example">',
    true,
    AssetLocation::BEFORE_CSS
);
?>
<!DOCTYPE html>
<html lang="<?= LANGUAGE_ID ?>">
<head>
    <meta charset="<?= LANG_CHARSET ?>">
    <title><?php $APPLICATION->ShowTitle()?></title>
    <?php $APPLICATION->ShowHead();?>
</head>
<body>
<?php $APPLICATION->ShowPanel();?>
<div class="workarea"><!-- закроется в footer.php -->
```

`/local/templates/my_template/template_styles.css` — основной CSS (подключается
ядром автоматически, дублировать `<link>` не нужно).

В шаблоне компонента (`.../components/bitrix/menu/my_tpl/template.php`):
```php
<?php
use Bitrix\Main\UI\Extension;
Extension::load(['ui.buttons', 'ui.tabs']); // станут доступны в этом шаблоне
// style.css и script.js рядом с этим файлом подключатся автоматически
```

## Выбор API
Обе версии API поддерживаются; для нового кода предпочтителен D7.

| Задача | D7 (рекомендуется) | Legacy ($APPLICATION / CJSCore) |
|---|---|---|
| Добавить CSS-файл | `Asset::getInstance()->addCss($path)` | `$APPLICATION->SetAdditionalCSS($path)` |
| Добавить JS-файл | `Asset::getInstance()->addJs($path)` | `$APPLICATION->AddHeadScript($path)` |
| Inline в `<head>` | `Asset::getInstance()->addString($html, true, $location)` | `$APPLICATION->AddHeadString($html)` |
| UI-расширение | `\Bitrix\Main\UI\Extension::load(['ui.buttons'])` | `\CJSCore::Init(['popup', 'ajax'])` |
| Вывод в шаблоне | `$APPLICATION->ShowHead()` (всё разом) | `ShowCSS()` / `ShowHeadScripts()` / `ShowHeadStrings()` |

Зоны вставки (`AssetLocation`): `BEFORE_CSS`, `AFTER_CSS`, `AFTER_JS_KERNEL`
(по умолчанию), `AFTER_JS`. Для composite-режима оборачивай ручные ассеты в
`startTarget('NAME')` … `stopTarget()`.

Когда что брать:
- `Extension::load()` — имя расширения из ≥2 частей (`ui.buttons`, `main.popup`):
  ядро находит `config.php` по `/local/js/...` затем `/bitrix/js/...` и тянет зависимости.
- `CJSCore::Init()` — для legacy-расширений из одной части (`popup`, `ajax`, `fx`):
  `Extension::load('popup')` их не найдёт.
- AIR-тема (Битрикс24-стиль): подключай `ui.design-tokens.air` вместо
  `ui.design-tokens` и определи `AIR_SITE_TEMPLATE` до загрузки UI; смешивать два
  поколения токенов без адаптации не следует.

## Проверка
Режим «только файлы» (без запущенного Битрикс):
- Корневые `template_styles.css` / `styles.css` существуют; ручного `<link>` на
  них в `header.php` нет (иначе двойная загрузка).
- В `<head>` ровно один `<?php $APPLICATION->ShowHead();?>`.
- Имена расширений в `Extension::load()` — из ≥2 частей; legacy-имена идут через
  `CJSCore::Init()`.
- Пути ассетов абсолютные от корня сайта (`SITE_TEMPLATE_PATH . '/...'`), без
  `dist`/локальных путей разработчика.

Режим «живой Битрикс»:
- Открыть страницу, в DevTools → Network убедиться, что CSS/JS грузятся один раз
  и в нужном порядке (токены до пользовательских стилей).
- Включить объединение CSS/JS в настройках модуля `main` и проверить, что вёрстка
  не поехала, в консоли нет ошибок отсутствующих расширений.
- В исходнике страницы проверить, что inline-строки попали в заданную зону.

## ⚠️ Риски
- ⚠️ Ручной `<link>` на `template_styles.css`/`styles.css` даёт двойную загрузку
  стилей и может перебить каскад — вёрстка визуально «прыгает».
- ⚠️ Отсутствие `$APPLICATION->ShowHead()` в `<head>`: подключённые CSS/JS и
  расширения не выводятся, страница и визуальный редактор остаются без стилей.
- ⚠️ Смешивание двух поколений дизайн-токенов (`ui.design-tokens` и
  `.air`) без адаптации ломает цвета/отступы UI-компонентов.
- ⚠️ Загрузка dev-сборок в продакшене (`VUEJS_DEBUG`/`VUEJS_DEBUG=true`) утяжеляет
  страницу; в проде константа должна быть `false` или не определена.
- Включение объединения/минификации после ручной вставки `<script>`/`<style>`
  в разметку: такие inline-блоки в бандл не попадут — выноси их через `addString`.

## Связано
- [../../api-map.md](../../api-map.md) — карта классов `Asset`, `Extension`, `CJSCore`.
- [../../00-overview.md](../../00-overview.md) — общая структура шаблона сайта.
- [../06-output-on-page.md](../06-output-on-page.md) — вывод заголовка/мета/областей.
- [../07-customize-component-template.md](../07-customize-component-template.md) —
  ассеты внутри шаблона компонента (`style.css`/`script.js`).
