# Рецепт. Создать шаблон сайта в /local/templates/

## Цель
Создать собственный шаблон сайта на «1С-Битрикс: Управление сайтом» (ядро 26.x): папку в `/local/templates/<id>/` с обязательной парой `header.php` (всё до рабочей области) + `footer.php` (всё после), метаданными `description.php`, авто-CSS (`styles.css` / `template_styles.css`), стилями визуального редактора (`.styles.php`) и служебными папками `components/`, `images/`, `page_templates/`. В конце — привязать шаблон к сайту (по умолчанию — стартовый сайт `s1`).

## Когда применять
- Нужен свой дизайн-каркас сайта: своя шапка, подвал, подключение CSS/JS, меню и хлебные крошки.
- Нужно отделить визуальную обёртку от контента страниц (страница рисует только то, что между `bitrix/header.php` и `bitrix/footer.php`).
- Нужна основа, поверх которой кладутся переопределённые шаблоны компонентов под конкретный сайт.

Не применять, если требуется изменить только вывод одного компонента, — это уровень шаблона компонента (см. `../07-customize-component-template.md`), а не шаблона сайта.

## Как ядро собирает страницу (конвейер из 5 стадий)
Страница в Битриксе формируется в строгом порядке, и шаблон сайта встраивается в него на двух стадиях:
1. **Служебный пролог** — `/bitrix/modules/main/include/prolog_before.php`: инициализация ядра, без дизайна.
2. **Визуальный пролог** — `/bitrix/modules/main/include/prolog_after.php`: сам подключает `header.php` активного шаблона сайта.
3. **Рабочая область** — содержимое страницы подставляется на месте маркера `#WORK_AREA#` (граница между `header.php` и `footer.php`).
4. **Визуальный эпилог** — `/bitrix/modules/main/include/epilog_before.php`: сам подключает `footer.php` шаблона.
5. **Служебный эпилог** — `/bitrix/modules/main/include/epilog_after.php`.

В терминологии вендора `header.php` — это «пролог данного шаблона», `footer.php` — «эпилог данного шаблона». Отсюда следствие: `header.php` — не самостоятельный файл, а визуальный пролог; скрипт без дизайна подключает только служебные половины (`prolog_before.php` + `epilog_after.php`), чтобы получить ядро без вёрстки.

## Шаги
1. Создайте папку `/local/templates/<id>/`. Имя папки `<id>` станет константой `SITE_TEMPLATE_ID`. Размещение в `/local` даёт приоритет над `/bitrix/templates/` и переживает обновления ядра: ядро (`CSiteTemplate::GetList()`) сканирует сперва `/local/templates`, затем `/bitrix/templates`.
2. Создайте `header.php` — верхнюю обёртку. Три обязательных вызова ядра и их места: `ShowTitle()` внутри `<title>`, `ShowHead()` в `<head>` (выводит meta и подключает ВСЕ CSS/JS, включая авто-`styles.css`/`template_styles.css`), `ShowPanel()` сразу после открытия `<body>`. Дальше — шапка (логотип/меню/хлебные крошки) и ОТКРЫТЫЙ контейнер контента. Файл заканчивается незакрытыми тегами.
3. Создайте `footer.php` — нижнюю обёртку: закрывает всё, что открыл `header.php`, рисует подвал и `</body></html>`.
4. Создайте `description.php` с массивом `$arTemplate` (`NAME`, `DESCRIPTION`, `SORT`) — по нему шаблон появится в списке выбора в админке.
5. Создайте `styles.css` и `template_styles.css` — два разных файла с разными ролями:
   - `styles.css` — стили **контента и включаемых областей**; это ЕДИНСТВЕННЫЙ файл, который подгружается в `<head>` iframe визуального редактора (контент-менеджер видит WYSIWYG только по этим правилам).
   - `template_styles.css` — основной CSS **дизайна** шаблона (раскладка/структура), внутри iframe редактора намеренно не отрисовывается.
   - Порядок подключения на живой странице: сначала `styles.css`, затем `template_styles.css` (поэтому при равной специфичности дизайн перебивает контентные правила). Оба подключаются ядром автоматически (`Asset::addTemplateCss()`), `<link>` на них в `header.php` не нужен.
6. Создайте `.styles.php` — массив именованных стилей контента для выпадающего списка «Стиль» визуального HTML-редактора. У каждой записи обязательны ключи `tag` (HTML-элемент-обёртка) и `title` (подпись/тултип в списке); опциональны `html` (кастомная разметка превью) и `section` (группировка стиля в категорию). CSS-классы из `.styles.php` должны существовать в `styles.css`, иначе в редакторе они не отрисуются. Если стилей нет — файл возвращает `false`. Это НЕ CSS-файл.
7. Заведите служебные папки: `components/` (переопределённые шаблоны компонентов локально для этого шаблона), `images/` (статика шаблона), `page_templates/` (скелеты новых страниц с реестром `.content.php`).
8. Привяжите шаблон к сайту: «Настройки → Настройки продукта → Сайты → Сайты», откройте сайт (стартовый — `s1`), на вкладке «Шаблон сайта» добавьте шаблон с условием. Условие может быть пустым (применять всегда), либо по GET-параметру `tmpl` (поле «для условия», предпросмотр без смены основного шаблона), либо по папке/иной логике. Шаблоны проверяются сверху вниз — первый подошедший выигрывает.

## Рабочий сниппет
Минимально достаточный комплект (контент рисуется между этими файлами).

Файл: `/local/templates/<id>/header.php`
```php
<?php
if (!defined("B_PROLOG_INCLUDED") || B_PROLOG_INCLUDED !== true) die();
use Bitrix\Main\Page\Asset; // на случай ручного addCss/addString
IncludeTemplateLangFile(__FILE__); // или \Bitrix\Main\Localization\Loc::loadMessages(__FILE__)
?><!DOCTYPE html>
<html lang="<?= LANGUAGE_ID ?>">
<head>
    <meta charset="<?= LANG_CHARSET ?>">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title><?php $APPLICATION->ShowTitle() ?></title>
    <?php $APPLICATION->ShowHead() // meta, canonical, ВСЕ CSS (вкл. авто styles.css/template_styles.css) ?>
    <link rel="icon" href="<?= SITE_TEMPLATE_PATH ?>/images/favicon.ico">
</head>
<body>
<?php $APPLICATION->ShowPanel() // админ-панель для авторизованных, сразу после <body> ?>
<header class="site-header">
    <a class="logo" href="<?= SITE_DIR ?>">
        <img src="<?= SITE_TEMPLATE_PATH ?>/images/logo.png" alt="">
    </a>
    <?php $APPLICATION->IncludeComponent("bitrix:menu", ".default", array(
        "ROOT_MENU_TYPE" => "top",        // читает top.menu.php в папках сайта
        "MENU_CACHE_TYPE" => "A",
        "USE_EXT" => "N",
    ), false) ?>
</header>

<?php $APPLICATION->IncludeComponent("bitrix:breadcrumb", ".default", array(
    "START_FROM" => "0",
    "PATH" => "",
    "SITE_ID" => SITE_ID,
), false) ?>

<main class="workarea">
    <h1><?php $APPLICATION->ShowTitle(false) // H1 без strip_tags ?></h1>
    <?php // ниже ядро вставит содержимое страницы (work area) ?>
```

Файл: `/local/templates/<id>/footer.php`
```php
<?php
if (!defined("B_PROLOG_INCLUDED") || B_PROLOG_INCLUDED !== true) die();
?>
</main><!-- /.workarea, открыт в header.php -->

<footer class="site-footer">
    <?php $APPLICATION->IncludeComponent("bitrix:main.include", "", array(
        "AREA_FILE_SHOW" => "file",
        "PATH" => SITE_DIR . "include/footer_copyright.php", // правится из публички
        "EDIT_TEMPLATE" => "",
    ), false) ?>
</footer>
</body>
</html>
```

Файл: `/local/templates/<id>/description.php`
```php
<?php
if (!defined("B_PROLOG_INCLUDED") || B_PROLOG_INCLUDED !== true) die();
$arTemplate = array(
    "NAME"        => "Мой шаблон сайта",
    "DESCRIPTION" => "Базовый каркас: шапка, меню, хлебные крошки, подвал.",
    "SORT"        => 1,
);
```

Файл: `/local/templates/<id>/.styles.php` (стили визредактора; `false`, если их нет)
```php
<?php
if (!defined("B_PROLOG_INCLUDED") || B_PROLOG_INCLUDED !== true) die();
IncludeTemplateLangFile(__FILE__);
return array(
    "lead" => array(
        "tag"     => "p",
        "title"   => GetMessage("MY_STYLE_LEAD"), // подпись из lang/<lang>/.styles.php
        "section" => "text",
    ),
);
// return false; // если стилей для редактора не нужно
```

Файл: `/local/templates/<id>/page_templates/.content.php` (+ рядом `standard.php`)
```php
<?php
if (!defined("B_PROLOG_INCLUDED") || B_PROLOG_INCLUDED !== true) die();
$TEMPLATE["standard.php"] = array("name" => "Обычная страница", "sort" => 1);
```

`template_styles.css` и `styles.css` создайте даже пустыми — ядро ждёт их по именам и подключает само.

## Выбор API
- Вёрстка шапки/подвала: глобальный `$APPLICATION` (класс `CMain`) — `ShowHead()`, `ShowTitle()`, `ShowPanel()`, `IncludeComponent()`. Это базовый и обязательный слой для шаблонов в обеих поддерживаемых версиях API; без него шаблон не собрать.
- Подключение CSS/JS: основной путь — авто-подключение `styles.css` / `template_styles.css` ядром; UI-библиотеки (Bootstrap, шрифты, ui.*) — через `\Bitrix\Main\UI\Extension::load([...])`; точечные ресурсы — `Asset::getInstance()->addCss()/addString()`.
- Локализация: `\Bitrix\Main\Localization\Loc::loadMessages(__FILE__)` (актуальный путь) или `IncludeTemplateLangFile(__FILE__)` + `GetMessage()` (исторический путь, по-прежнему рабочий).
- Хранение настроек шаблона (например выбранной темы): `\Bitrix\Main\Config\Option::get/set` для нового кода; `COption` — рабочая обёртка над тем же механизмом, исторически частая в шаблонах.
- Редактируемые из публички области (логотип, телефон, копирайт): `bitrix:main.include` с `AREA_FILE_SHOW="file"` (поддерживает режимы `file`/`sect`/`page`, кэш и правку из публичной части).

## Проверка
Режим «только файлы» (без запущенного Битрикса):
- В `/local/templates/<id>/` присутствуют `header.php`, `footer.php`, `description.php`, `styles.css`, `template_styles.css`, `.styles.php`.
- В начале `header.php`, `footer.php`, `description.php`, `.styles.php` есть guard `if (!defined("B_PROLOG_INCLUDED")...) die();`.
- В `<head>` ровно один `ShowHead()` и один `ShowTitle()`; сразу после `<body>` — `ShowPanel()`.
- Теги, открытые в `header.php` (`<body>`, контейнеры контента), закрыты именно в `footer.php` (по отдельности файлы валидным HTML не являются — это нормально).
- На `styles.css`/`template_styles.css` нет ручного `<link>` (иначе двойная загрузка).
- `.styles.php` возвращает массив или `false`, но не CSS-текст.

Режим «живой Битрикс»:
- Шаблон виден в списке выбора (Сайты → вкладка «Шаблон сайта») под именем из `description.php`.
- После привязки к `s1` публичная страница (`/index.php`) рендерится в новой обёртке; в `<head>` присутствуют `styles.css` и `template_styles.css` (видно в исходнике страницы).
- Для авторизованного администратора отображается верхняя админ-панель (работает `ShowPanel()`).
- Предпросмотр без смены основного шаблона: добавьте `?tmpl=<id>` к URL (если для шаблона задано условие по GET `tmpl`).
- Заголовок вкладки браузера и `<h1>` соответствуют `SetTitle()` страницы.

## ⚠️ Риски
- ⚠️ `header.php`/`footer.php` — это «бутерброд» с незакрытым HTML: `header.php` открывает теги, `footer.php` их закрывает. Если сделать каждый файл валидным по отдельности (закрыть `<body>`/контейнеры в `header.php`), вёрстка страницы поедет.
- ⚠️ Пропуск `ShowHead()` ломает подключение CSS/JS и meta всей страницы; пропуск `ShowPanel()` убирает админ-панель и режим визуального редактирования из публички.
- ⚠️ Папку шаблона с именем `.default` ядро не показывает в выборе (`CSiteTemplate::GetList()` её пропускает) — это системный fallback, своему шаблону давайте другое имя.
- ⚠️ `.styles.php` — это PHP-массив для редактора, а не CSS. Если положить туда CSS-текст, выпадающий список стилей визредактора сломается.
- Дубль `<link>` на `styles.css`/`template_styles.css` приводит к их двойной загрузке — ядро уже подключает оба файла само.
- ⚠️ Папка `/local` должна существовать на момент загрузки ядра: `getLocalPath()` кэширует `is_dir('/local')` в начале запроса, поэтому созданную «на лету» `/local` ядро в этом же запросе не увидит. На чистом проекте создайте каталог `/local` заранее (в деплое), затем размещайте в нём шаблон — проверено на 26.x.
- `SITE_TEMPLATE_PATH` (папка шаблона: favicon, картинки, статика) и `SITE_DIR` (корень сайта: контент, include-области) — разные пути; их путаница ломает ссылки, особенно при многосайтовости.
- Опечатка в имени шаблона компонента во втором аргументе `IncludeComponent` приводит к тихому откату на `.default` компонента вместо вашего шаблона.

## Связано
- `../06-output-on-page.md` — вставка компонентов и вывод данных в рабочей области страницы.
- `../07-customize-component-template.md` — переопределение шаблонов компонентов внутри `templates/<id>/components/`.
- `../../00-overview.md` — жизненный цикл запроса (prolog/epilog), где ядро подключает `header.php`/`footer.php` шаблона.
- `../../api-map.md` — карта API: `$APPLICATION`/`CMain`, `Asset`, `SITE_TEMPLATE_ID`/`SITE_TEMPLATE_PATH`, приоритет `/local`.
- Шаблоны сайта (структура, `#WORK_AREA#`, styles.css/template_styles.css): https://dev.1c-bitrix.ru/api_help/main/general/template.php
- Конвейер вывода страницы (prolog/epilog): https://training.bitrix24.com/support/training/course/?COURSE_ID=68&LESSON_ID=5950
- Формат `.styles.php` (ключи `tag`/`title`/`html`/`section`): https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&LESSON_ID=3437
