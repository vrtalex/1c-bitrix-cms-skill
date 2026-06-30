# Компоненты: навигация (меню, крошки)

Группа навигации шаблона: меню из позиционных файлов `.<type>.menu.php`,
динамическое меню из разделов инфоблока, хлебные крошки. Базовый рецепт меню —
`../recipes/template/02-menu.md`; крошки в шаблоне — `../api-map.md` (§2).

---

## `bitrix:menu`

1. **Назначение.** Выводит меню заданного типа из позиционного файла
   `.<type>.menu.php` (массив `$aMenuLinks`), с подсветкой активного пункта.
2. **Когда брать.** Статическое верхнее/левое меню сайта. Когда пункты должны
   тянуться из разделов инфоблока — `bitrix:menu.sections` (или `USE_EXT=Y` +
   `.<type>.menu_ext.php`).
3. **Ключевые `arParams`.**
   - `ROOT_MENU_TYPE` — тип меню (`"top"`, `"left"`); ищет `.top.menu.php`.
   - `MAX_LEVEL` — глубина (1 — плоское, 2+ — со вложенностью).
   - `USE_EXT` — `"Y"` подключает `.<type>.menu_ext.php` (динамические пункты).
   - `MENU_CACHE_TYPE` — `"A"`; `MENU_CACHE_TIME` — TTL.
   - `MENU_CACHE_USE_GROUPS` — учитывать группы (права на пункты).
   - `MENU_CACHE_GET_VARS` — GET-переменные, влияющие на активный пункт.
   - `DELAY` — отложенный вывод (для меню в `header`, зависящего от страницы).
4. **Типовой вызов.**
   ```php
   $APPLICATION->IncludeComponent("bitrix:menu", "horizontal_multilevel", [
       "ROOT_MENU_TYPE"   => "top",
       "MAX_LEVEL"        => 2,
       "USE_EXT"          => "N",
       "MENU_CACHE_TYPE"  => "A",
       "MENU_CACHE_TIME"  => 3600,
       "MENU_CACHE_USE_GROUPS" => "Y",
       "DELAY"            => "N",
   ]);
   ```
5. **Что кастомизируют в `/local`.** Шаблон меню копируют в
   `/local/templates/<tpl>/components/bitrix/menu/<tpl>/`; правят `template.php`
   (разметка `<ul>`/`<li>`, классы активного пункта по `$arItem["SELECTED"]`). Сами
   пункты редактируют в `.<type>.menu.php` шаблона сайта, не в компоненте.
6. **Типовые ошибки.**
   - `ROOT_MENU_TYPE` не совпал с именем файла (`.top.menu.php`) → пустое меню.
   - `MAX_LEVEL=1` при многоуровневой структуре → подпункты не покажутся.
   - Активный пункт «не подсвечивается» — проверять `$arItem["SELECTED"]` в шаблоне.
7. **Источник.** [src](https://dev.1c-bitrix.ru/user_help/components/sluzhebnie/navigation/menu.php)

---

## `bitrix:menu.sections`

1. **Назначение.** Дополняет статическое меню пунктами из разделов инфоблока —
   гибрид ручных и динамических ссылок.
2. **Когда брать.** Меню каталога/новостей, где категории должны появляться
   автоматически из разделов ИБ. Чисто статическое меню — `bitrix:menu`.
3. **Ключевые `arParams`.**
   - `IBLOCK_TYPE`, `IBLOCK_ID` — инфоблок, чьи разделы добавляются.
   - `ROOT_MENU_TYPE` — базовый тип меню.
   - `MENU_THEME`, `MAX_LEVEL` — оформление/глубина.
   - `SECTION_URL` — шаблон ссылки на раздел.
   - `CACHE_TYPE`, `CACHE_TIME` — кэш.
4. **Типовой вызов.**
   ```php
   $APPLICATION->IncludeComponent("bitrix:menu.sections", ".default", [
       "IBLOCK_TYPE"    => "catalog",
       "IBLOCK_ID"      => 2,
       "ROOT_MENU_TYPE" => "left",
       "MAX_LEVEL"      => 2,
       "SECTION_URL"    => "/catalog/#SECTION_CODE#/",
       "CACHE_TYPE"     => "A", "CACHE_TIME" => 3600,
   ]);
   ```
5. **Что кастомизируют в `/local`.** Как у `bitrix:menu` — копия шаблона в
   `…/menu.sections/<tpl>/`, разметка в `template.php`. Точку соединения статики и
   динамики настраивают через `USE_EXT=Y` и `.<type>.menu_ext.php`.
6. **Типовые ошибки.**
   - Неверный `IBLOCK_ID` → динамические пункты не появятся.
   - Рассинхрон `SECTION_URL` с реальными путями разделов → битые ссылки.
   - Тяжёлое дерево разделов без кэша → лишняя нагрузка на каждый хит.
7. **Источник.** [src](https://dev.1c-bitrix.ru/user_help/components/sluzhebnie/navigation/menu_section.php)

---

## `bitrix:breadcrumb`

1. **Назначение.** Выводит хлебные крошки (навигационную цепочку) из элементов,
   накопленных `$APPLICATION->AddChainItem()` за хит.
2. **Когда брать.** Почти всегда — один раз в шаблоне сайта (между header и
   контентом). Сами звенья добавляют компоненты (`ADD_SECTIONS_CHAIN`/
   `ADD_ELEMENT_CHAIN`) и страницы (`AddChainItem`).
3. **Ключевые `arParams`.**
   - `START_FROM` — с какого уровня начинать (обычно `0`).
   - `PATH` — переопределить путь (по умолчанию текущий).
   - `SITE_ID` — для мультисайта.
   Параметров мало: компонент простой, основное — шаблон вывода.
4. **Типовой вызов.**
   ```php
   $APPLICATION->IncludeComponent("bitrix:breadcrumb", "", [
       "START_FROM" => "0",
       "PATH"       => "",
       "SITE_ID"    => SITE_ID,
   ]);
   ```
   Вызывается без имени шаблона (`""`) — берётся шаблон сайта по умолчанию.
5. **Что кастомизируют в `/local`.** Шаблон крошек копируют в
   `/local/templates/<tpl>/components/bitrix/breadcrumb/<tpl>/template.php`. Часто
   добавляют микроразметку `BreadcrumbList` (JSON-LD/Microdata) прямо в `template.php`
   — это разметка, не логика.
6. **Типовые ошибки.**
   - Крошки пустые — звенья не добавлены: проверить `ADD_*_CHAIN` у компонентов и
     `AddChainItem` на странице.
   - `AddChainItem` внутри `result_modifier.php`/кэша «застынет» — добавлять на
     странице или в `component_epilog.php`.
   - Дубль домашней ссылки — компонент часто добавляет «Главная» сам.
7. **Источник.** [src](https://dev.1c-bitrix.ru/user_help/components/sluzhebnie/navigation/breadcrumb.php)

---

## Связано

- [`00-index.md`](./00-index.md) — индекс каталога.
- [`../recipes/template/02-menu.md`](../recipes/template/02-menu.md) — типы меню, файлы `.<type>.menu.php`.
- [`../api-map.md`](../api-map.md) — меню/крошки (§2): `CMenu`, `AddChainItem`.
