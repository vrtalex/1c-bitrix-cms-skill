# Рецепт 08. Комплексный компонент bitrix:news с ЧПУ (SEF)

## Цель

Развернуть готовый раздел «Новости» (список → раздел → детальная → поиск → RSS) одним
комплексным компонентом `bitrix:news` в режиме человекопонятных URL (SEF). Компонент сам
маршрутизирует запрос между вложенными `news.list` / `news.list` (для раздела) / `news.detail`
по шаблонам URL и подставляет ЧПУ-ссылки во все дочерние компоненты, без отдельных физических
файлов под каждую страницу.

## Когда применять

- Нужен целый раздел контента с подстраницами, а не одиночный список. Для одного списка берите
  вложенный `bitrix:news.list` напрямую — комплексный роутер избыточен (см. рецепт 06).
- Требуются ЧПУ вида `/news/`, `/news/<section>/`, `/news/<id>/`, `/news/search/`, `/news/rss/`
  вместо `?ELEMENT_ID=...&SECTION_ID=...`.
- Один публичный URL-узел отвечает за всё дерево подстраниц.

Комплексный компонент помечен `"COMPLEX" => "Y"` в `.description.php`; сам он ничего не выбирает
из БД — это роутер поверх `CComponentEngine`, реальную выборку делают вложенные компоненты.

## Шаги

1. **Создать единый публичный файл** `/news/index.php` — он будет точкой входа для всего дерева
   подстраниц. SEF-роутинг ловит подпути (`/news/<section>/`, `/news/<id>/` и т.д.) именно через
   этот файл.

2. **Вызвать `bitrix:news` с `SEF_MODE=Y`**, задав `SEF_FOLDER` (физический префикс пути) и
   `SEF_URL_TEMPLATES` для каждой именованной страницы: `news`, `section`, `detail`, `search`,
   `rss`, `rss_section`. Шаблоны — это хвост URL относительно `SEF_FOLDER` с плейсхолдерами
   `#SECTION_ID#` / `#ELEMENT_ID#` (либо `#SECTION_CODE_PATH#` / `#ELEMENT_CODE#` для ЧПУ по
   символьным кодам).

3. **Согласовать три значения:** `SEF_FOLDER`, ключи `SEF_URL_TEMPLATES` и реальное расположение
   `index.php`. Рассогласование приводит к ложным 404 (`process404`).

4. **Сохранить настройки в публичном редакторе или в коде вызова.** При первом сохранении из
   визуального редактора Битрикс предложит автоматически добавить правила в `urlrewrite.php` —
   согласиться. Битрикс генерирует правила сам через `CComponentEngine::makeComponentUrlTemplates`
   и `makeComponentVariableAliases` (см. блок «Выбор API»).

5. **Проверить детальные и разделные ссылки** в выводе списка — они должны строиться от
   `SEF_FOLDER` + шаблон, без дублирования сегментов пути.

## Рабочий сниппет

Файл: `/local/templates/.default/components/bitrix/news/.default/template.php` для кастома, но сам
вызов размещается в публичном файле — `/news/index.php`:

```php
<?php
require($_SERVER["DOCUMENT_ROOT"] . "/bitrix/header.php");

$APPLICATION->IncludeComponent("bitrix:news", ".default", [
    "IBLOCK_TYPE" => "news",
    "IBLOCK_ID"   => 1,                 // ID активного инфоблока (или CODE, привязанный к сайту)

    "SEF_MODE"   => "Y",
    "SEF_FOLDER" => "/news/",           // совпадает с расположением этого index.php
    "SEF_URL_TEMPLATES" => [
        "news"        => "",                       // /news/
        "section"     => "#SECTION_ID#/",          // /news/<section>/
        "detail"      => "#ELEMENT_ID#/",          // /news/<id>/
        "search"      => "search/",                // /news/search/
        "rss"         => "rss/",                   // /news/rss/
        "rss_section" => "#SECTION_ID#/rss/",      // /news/<section>/rss/
    ],

    // параметры подстраниц (роутер раздаёт их вложенным компонентам)
    "NEWS_COUNT"          => 12,
    "SORT_BY1"            => "ACTIVE_FROM",
    "SORT_ORDER1"         => "DESC",
    "LIST_PROPERTY_CODE"   => ["AUTHOR"],
    "DETAIL_PROPERTY_CODE" => ["AUTHOR"],
    "USE_SEARCH" => "Y",
    "USE_RSS"    => "Y",

    // кэш и заголовки
    "CACHE_TYPE"  => "A",
    "CACHE_TIME"  => "36000000",
    "CACHE_GROUPS" => "Y",
    "SET_TITLE"   => "Y",
    "ADD_SECTIONS_CHAIN" => "Y",
]);

require($_SERVER["DOCUMENT_ROOT"] . "/bitrix/footer.php");
```

Внутри роутер вычисляет текущую страницу через `CComponentEngine` и подключает соответствующий
шаблон-подстраницу:

```php
// news/component.php (логика роутера, для понимания — не править)
$engine = new CComponentEngine($this);
$engine->addGreedyPart("#SECTION_CODE_PATH#");                 // ЧПУ по дереву разделов
$engine->setResolveCallback(["CIBlockFindTools", "resolveComponentEngine"]);
$componentPage = $engine->guessComponentPath($arParams["SEF_FOLDER"], $arUrlTemplates, $arVariables);
// ...
$this->includeComponentTemplate($componentPage);              // templates/<тема>/{news,section,detail,search,rss}.php
```

Каждая подстраница (`templates/.default/news.php`, `section.php`, `detail.php`) вызывает вложенный
компонент и передаёт ему собранные из шаблонов URL ссылки:

```php
// templates/.default/news.php — список
$APPLICATION->IncludeComponent("bitrix:news.list", "", [
    "IBLOCK_TYPE" => $arParams["IBLOCK_TYPE"],
    "IBLOCK_ID"   => $arParams["IBLOCK_ID"],
    "NEWS_COUNT"  => $arParams["NEWS_COUNT"],
    "PROPERTY_CODE" => $arParams["LIST_PROPERTY_CODE"],
    "DETAIL_URL"  => $arResult["FOLDER"] . $arResult["URL_TEMPLATES"]["detail"],
    "SECTION_URL" => $arResult["FOLDER"] . $arResult["URL_TEMPLATES"]["section"],
    "IBLOCK_URL"  => $arResult["FOLDER"] . $arResult["URL_TEMPLATES"]["news"],
    // + пейджер, кэш, флаги 404
], $component);
```

## Выбор API (что рекомендовано для ЭТОЙ задачи и почему)

- **Маршрутизация — `CComponentEngine`** (`guessComponentPath`, `addGreedyPart`,
  `setResolveCallback`, `makeComponentUrlTemplates`, `makeComponentVariableAliases`). Это
  встроенный механизм SEF для комплексных компонентов; именно он сопоставляет текущий URL с
  `SEF_URL_TEMPLATES` и обратно собирает правила для `urlrewrite.php`. Своя маршрутизация не нужна
  и будет конфликтовать с авто-генерацией правил.
- **ЧПУ по дереву разделов — greedy-часть `#SECTION_CODE_PATH#`** + резолвер
  `CIBlockFindTools::resolveComponentEngine`. Превращает многосегментный путь раздела в
  `SECTION_ID`. Для простых числовых ЧПУ достаточно `#SECTION_ID#` / `#ELEMENT_ID#`.
- **404 — `\Bitrix\Iblock\Component\Tools::process404(...)`** (D7). Вызывается роутером, когда путь
  не распознан; не изобретайте ручную отдачу 404.
- **Выборка во вложенных компонентах — `bitrix:news.list`** (две поддерживаемые версии API: внутри
  list процедурный `CIBlockElement::GetList`, а соседний `bitrix:catalog.section` — ООП
  `\Bitrix\Iblock\Component\ElementList`). Для раздела «Новости» штатная связка news → news.list
  закрывает все подстраницы без дополнительного кода.

Итог: для готового SEF-раздела рекомендуется комплексный `bitrix:news` «как есть» — он использует
`CComponentEngine` и сам раздаёт ЧПУ-ссылки вложенным компонентам через `$arResult["FOLDER"]` +
`$arResult["URL_TEMPLATES"]`.

## Проверка

**Режим «только файлы» (без живого Битрикса):**
- В вызове присутствуют `SEF_MODE => "Y"`, `SEF_FOLDER` и все ключи `SEF_URL_TEMPLATES`
  (`news`, `section`, `detail` минимум; `search`/`rss` при `USE_SEARCH`/`USE_RSS`).
- `SEF_FOLDER` совпадает с каталогом, где лежит `index.php` с вызовом (оба `/news/`).
- Шаблоны URL не начинаются со слэша (хвост относительно `SEF_FOLDER`) и содержат корректные
  плейсхолдеры `#SECTION_ID#` / `#ELEMENT_ID#`.
- В подстраницах (`news.php`/`section.php`/`detail.php`) ссылки строятся как
  `$arResult["FOLDER"] . $arResult["URL_TEMPLATES"][...]`, без хардкода путей.

**Режим «живой Битрикс»:**
- Открыть `/news/` → отдаётся список; перейти в раздел → URL вида `/news/<section>/`; в элемент →
  `/news/<id>/`. Все три страницы возвращают HTTP 200.
- Несуществующий путь `/news/zzz/` → корректный 404 (`process404`), а не пустая страница.
- В сгенерированном корневом `urlrewrite.php` появилось правило, ведущее на `/news/index.php` с
  условием по `SEF_FOLDER` (проверить, что Битрикс добавил его сам при сохранении настроек).
- Ссылки в списке (`DETAIL_PAGE_URL`, `SECTION_PAGE_URL`) указывают на ЧПУ, а не на `?ELEMENT_ID=`.

## ⚠️ Риски

- ⚠️ **Не редактировать корневой `urlrewrite.php` вручную для этих правил.** Правила SEF для
  комплексного компонента генерируются автоматически (`CComponentEngine::makeComponentUrlTemplates`
  / `makeComponentVariableAliases`) при сохранении настроек компонента и **перетираются** при
  следующем пересохранении. Меняйте `SEF_FOLDER` / `SEF_URL_TEMPLATES` в параметрах компонента и
  пересохраняйте — правило обновится корректно. Ручные правки в этом диапазоне пропадут.
- ⚠️ **Рассогласование `SEF_FOLDER` ↔ размещение `index.php` ↔ `SEF_URL_TEMPLATES`** даёт ложные
  404: `guessComponentPath()` не сопоставит URL с шаблонами. Все три значения должны быть
  согласованы.
- При `IBLOCK_ID` строкой-CODE инфоблок обязан быть привязан к текущему сайту, иначе вложенный
  `news.list` уйдёт в 404 поиска инфоблока.
- Заголовок страницы, мета и хлебные крошки вложенные компоненты ставят **вне кэша** (зависят от
  прав пользователя) — не пытаться кэшировать их в составе `$arResult`.

## Связано

- Рецепт 06 (recipes/06-output-on-page.md) — одиночный список через `bitrix:news.list` напрямую (когда комплексный роутер не
  нужен).
- Под-скилл `1c-bitrix-cms-seo` — канонические URL, мета-шаблоны (inherited properties
  `\Bitrix\Iblock\InheritedProperty\ElementValues`) и sitemap для SEF-раздела.
- База знаний: `recipes/06-output-on-page.md` — разбор `news` / `news.list` / `catalog` и
  цепочки «параметры → выборка → шаблон».
