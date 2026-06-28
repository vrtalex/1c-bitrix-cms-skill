# Рецепт: меню сайта (файлы меню + компонент bitrix:menu)

## Цель
Собрать рабочее меню сайта на «1С-Битрикс: Управление сайтом» (ядро 26.x): данные пунктов хранятся в файлах `.<type>.menu.php` (статика) и `.<type>.menu_ext.php` (динамика), а выводит их компонент `bitrix:menu` (или `bitrix:menu.sections` для меню из разделов инфоблока). Покрываем многоуровневое меню, подсветку активного пункта и подключение шаблона меню из шаблона сайта.

## Когда применять
- В шапке/сайдбаре сайта нужно горизонтальное (top) или вертикальное (left) меню.
- Меню должно быть многоуровневым (выпадающее/дерево) с подсветкой текущего раздела.
- Часть пунктов формируется динамически из разделов инфоблока (каталог/новости).
- Нужно переопределить вёрстку меню под дизайн, не трогая файлы компонента в `/bitrix/components`.

Меню — это подсистема модуля `main` (классы `CMenu`, компонент `bitrix:menu`). Модуль fileman даёт лишь редактор пунктов в админке (`fileman_menu_edit.php`); формат файлов от этого не меняется.

## Шаги
1. **Данные пунктов.** В каталоге раздела (или в корне сайта) положить `.<type>.menu.php` с массивом `$aMenuLinks`. Тип (`top`, `left`, `bottom` и произвольные) задаётся в настройках сайта и должен совпасть с `ROOT_MENU_TYPE`/`CHILD_MENU_TYPE` компонента.
2. **Формат пункта — позиционный массив из 5 элементов** (порядок важен):
   ```php
   [TEXT, LINK, ADDITIONAL_LINKS[], PARAMS[], CONDITION]
   ```
   - `[0] TEXT` — подпись;
   - `[1] LINK` — ссылка;
   - `[2] ADDITIONAL_LINKS` — доп. URL для подсветки активного пункта;
   - `[3] PARAMS` — доп. параметры (`IMAGE`, `ARTICLE_ID`…);
   - `[4] CONDITION` — строка с PHP-условием показа (например `$USER->IsAuthorized()`), вычисляется при рендере.
3. **Многоуровневость.** Подменю раздела — отдельный файл `.<type>.menu.php` в подкаталоге. `CMenu::Init()` поднимается по дереву каталогов от текущей страницы и собирает уровни; глубину ограничивает `MAX_LEVEL` компонента (1..4).
4. **Динамические пункты (опц.).** Рядом положить `.<type>.menu_ext.php` — это PHP, который ДОЗАПОЛНЯЕТ `$aMenuLinks` (обычно через `bitrix:menu.sections`). Работает только при `USE_EXT => "Y"` в компоненте.
5. **Вывод.** В `header.php` шаблона сайта вызвать `bitrix:menu` с нужным шаблоном меню (`horizontal_multilevel` / `vertical_multilevel` / свой).
6. **Кастомная вёрстка (опц.).** Положить шаблон меню в `templates/<site_tpl>/components/bitrix/menu/<tpl_name>/template.php` — он перекроет дефолт компонента (приоритет `/local` → `/bitrix`).

## Рабочий сниппет (путь в /local)
Данные верхнего меню — `/local/.top.menu.php` (или в корне сайта):
```php
<?php
if (!defined("B_PROLOG_INCLUDED") || B_PROLOG_INCLUDED !== true) die();

$aMenuLinks = [
    ["Главная",   "/",               [], [], ""],
    ["О компании","/about/",         ["/about/contacts/"], [], ""],
    ["Каталог",   "/catalog/",       [], [], ""],
    ["Кабинет",   "/personal/",      [], [], '$USER->IsAuthorized()'], // только авторизованным
];
```
Подменю раздела «О компании» — `/local/about/.top.menu.php`:
```php
<?php
if (!defined("B_PROLOG_INCLUDED") || B_PROLOG_INCLUDED !== true) die();

$aMenuLinks = [
    ["История",  "/about/history/",  [], [], ""],
    ["Контакты", "/about/contacts/", [], [], ""],
];
```
Вывод в `header.php` шаблона (`/local/templates/<site_tpl>/header.php`):
```php
<?php $APPLICATION->IncludeComponent("bitrix:menu", "horizontal_multilevel", [
    "ROOT_MENU_TYPE"   => "top",
    "CHILD_MENU_TYPE"  => "top",
    "MAX_LEVEL"        => 2,
    "USE_EXT"          => "Y",       // подключать .top.menu_ext.php
    "DELAY"            => "N",
    "ALLOW_MULTI_SELECT" => "N",
    "MENU_CACHE_TYPE"  => "A",       // кэш меню
    "MENU_CACHE_TIME"  => "3600",
    "MENU_CACHE_USE_GROUPS" => "Y",
], false); ?>
```
Динамические пункты из инфоблока — `/local/catalog/.top.menu_ext.php`:
```php
<?php
if (!defined("B_PROLOG_INCLUDED") || B_PROLOG_INCLUDED !== true) die();

$aMenuLinksExt = $APPLICATION->IncludeComponent("bitrix:menu.sections", "", [
    "IBLOCK_TYPE" => "catalog",
    "IBLOCK_ID"   => 1,
    "SECTION_URL" => "/catalog/#SECTION_CODE#/",
    "DEPTH_LEVEL" => 2,
    "CACHE_TYPE"  => "A",
    "CACHE_TIME"  => "3600",
], false);
$aMenuLinks = array_merge($aMenuLinks, $aMenuLinksExt);
```

## Выбор API
В ядре 26.x для меню две поддерживаемые версии API; для построения сайта применяют такой порядок.
- **Компонент `bitrix:menu` (рекомендуемый путь).** Декларативный вызов в шаблоне; внутри сам создаёт `CMenu`, выполняет `Init/RecalcMenu`, отдаёт пункты в `$arResult` шаблона меню (ключи `TEXT`, `LINK`, `SELECTED`, `DEPTH_LEVEL`, `IS_PARENT`, `PARAMS`, `ADDITIONAL_LINKS`). Поддерживает кэширование и `USE_EXT`.
- **Компонент `bitrix:menu.sections`.** Строит массив пунктов из разделов инфоблока; вызывается ВНУТРИ `.menu_ext.php` и возвращает массив для `array_merge` с `$aMenuLinks`. Отдельно в шаблоне как самостоятельное меню обычно не выводят.
- **Класс `CMenu` (низкоуровневое API).** `new CMenu($type)` → `Init($InitDir, $bMenuExt, $template, $onlyCurrentDir)` → `RecalcMenu()` → `GetMenuHtmlEx()`/`GetMenuHtml()`. Нужен в редких случаях, когда меню собирают вне компонентной модели. В обычных шаблонах сайта прямой вызов не требуется — его покрывает `bitrix:menu`.

Подсветка активного пункта: значение `SELECTED` для пункта вычисляет ядро по совпадению `LINK`/`ADDITIONAL_LINKS` с текущим URL. В шаблоне меню оно приходит в `$arItem["SELECTED"]` — достаточно повесить CSS-класс:
```php
<?php foreach ($arResult as $arItem):
    if ($arParams["MAX_LEVEL"] == 1 && $arItem["DEPTH_LEVEL"] > 1) continue; ?>
    <li><a href="<?=$arItem["LINK"]?>"<?=$arItem["SELECTED"] ? ' class="active"' : ''?>><?=$arItem["TEXT"]?></a></li>
<?php endforeach; ?>
```

## Проверка
**Режим «только файлы» (без запущенного Битрикса):**
- `php -l` на каждом `.menu.php` / `.menu_ext.php` / `header.php` — синтаксис без ошибок.
- В каждом пункте `$aMenuLinks` ровно 5 элементов в правильном порядке (`TEXT, LINK, ADD_LINKS[], PARAMS[], CONDITION`); `[2]` и `[3]` — массивы, `[4]` — строка.
- Тип меню в файлах (`.top.menu.php`) совпадает с `ROOT_MENU_TYPE`/`CHILD_MENU_TYPE` в вызове компонента.
- Имя шаблона меню (2-й аргумент `IncludeComponent`) существует в одном из путей резолва (`templates/<site_tpl>/components/bitrix/menu/<tpl>/` или дефолт компонента).
- `.menu_ext.php` присутствует только если в компоненте `USE_EXT => "Y"`.

**Режим «живой Битрикс»:**
- Открыть страницу: меню рендерится, уровни раскрываются до `MAX_LEVEL`, активный пункт подсвечен на текущем разделе.
- Перейти в подраздел — подсветка переезжает на нужный пункт (проверка `SELECTED`/`ADDITIONAL_LINKS`).
- Динамические пункты появляются из инфоблока (если используется `menu_ext` + `USE_EXT`).
- После правки файлов меню сбросить кэш компонента (админка → «Очистить кэш» или удалить кэш меню), иначе виден старый состав.

## ⚠️ Риски
- ⚠️ **Порядок элементов пункта.** Пункт — позиционный, а не ассоциативный массив. Перепутанные `LINK`/`ADDITIONAL_LINKS`/`CONDITION` молча ломают вёрстку и подсветку меню; лишний/недостающий элемент сдвигает все следующие.
- ⚠️ **`CONDITION` — это исполняемый PHP.** Строка `[4]` выполняется при каждом рендере меню. Любая динамика/ввод в ней — потенциальная инъекция; держите там только проверки прав (`$USER->IsAuthorized()` и т.п.).
- ⚠️ **`USE_EXT` и `.menu_ext.php`.** Без `USE_EXT => "Y"` динамические пункты не подключатся; при ошибке в `.menu_ext.php` (или забытом `array_merge`) меню может вывестись пустым.
- **Несовпадение типа меню.** Если тип в файле (`top`/`left`) не равен `ROOT_MENU_TYPE`, компонент не найдёт пунктов и покажет пустое меню.
- **Кэш.** При `MENU_CACHE_TYPE => "A"` изменения в `.menu.php` видны только после сброса кэша.
- **Опечатка в имени шаблона меню** во 2-м аргументе `IncludeComponent` → подхватится `.default` компонента вместо вашей вёрстки.
- **Меню — это `main`, не fileman.** Программно правят сами файлы `.menu.php`; редактор пунктов в админке (`fileman_menu_edit.php`) пишет в тот же формат.

## Связано
- [../../00-overview.md](../../00-overview.md) — обзор под-скиллов и устройства сайта на Битрикс.
- [../../api-map.md](../../api-map.md) — карта API (где `CMenu`, `bitrix:menu`, классы main/fileman).
- [../06-output-on-page.md](../06-output-on-page.md) — вывод данных на странице (`IncludeComponent`, свойства страницы, цепочка навигации).
- [../07-customize-component-template.md](../07-customize-component-template.md) — переопределение шаблона компонента (в т.ч. меню) внутри шаблона сайта.
