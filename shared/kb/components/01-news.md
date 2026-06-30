# Компоненты: новости / контент инфоблока

Группа `news.*` — вывод элементов инфоблока на публичной странице (новости,
статьи, услуги, FAQ). Базовый рецепт вывода списка — `../recipes/06-output-on-page.md`,
комплексный на ЧПУ — `../recipes/08-complex-component-sef.md`.

---

## `bitrix:news.list`

1. **Назначение.** Выводит список элементов одного инфоблока (с пагинацией,
   сортировкой, кэшем по тегам инфоблока). Эталонный компонент вывода контента.
2. **Когда брать.** Нужен **один** список на странице (лента новостей, блок
   статей, плитка услуг). Для целого раздела (список + детальная + RSS на ЧПУ)
   берут комплексный `bitrix:news`; для детальной карточки — `bitrix:news.detail`.
3. **Ключевые `arParams`.**
   - `IBLOCK_TYPE` — символьный код типа инфоблока (`"news"`).
   - `IBLOCK_ID` — число (ID) или строка (CODE; ветвление `is_numeric`).
   - `NEWS_COUNT` — размер страницы; при `<=0` движок берёт 20.
   - `SORT_BY1` / `SORT_ORDER1` (+ `…2`) — сортировка (`ACTIVE_FROM` `DESC`); к ней
     дописывается `ID DESC` для детерминизма.
   - `FIELD_CODE` — массив полей (`PREVIEW_PICTURE`, `DATE_ACTIVE_FROM`).
   - `PROPERTY_CODE` — массив кодов свойств этого инфоблока (`["AUTHOR"]`).
   - `DETAIL_URL` — шаблон ссылки на детальную (`/news/#ELEMENT_ID#/`); обязан
     совпасть с местом `news.detail`.
   - `CACHE_TYPE` — `"A"` (Авто, по настройкам сайта); `CACHE_TIME` — верхняя
     граница TTL; `CACHE_GROUPS` — учитывать группы в ключе.
   - `SET_TITLE`, `ADD_SECTIONS_CHAIN` — заголовок/крошки (вне кэша, на хите).
   - `DISPLAY_BOTTOM_PAGER`, `PAGER_TITLE` — пагинация.
   - `CHECK_DATES` — показывать только элементы с активной датой.
4. **Типовой вызов.**
   ```php
   $APPLICATION->IncludeComponent("bitrix:news.list", ".default", [
       "IBLOCK_TYPE"   => "news",
       "IBLOCK_ID"     => 1,            // число (ID) или CODE (строка)
       "NEWS_COUNT"    => 12,
       "SORT_BY1"      => "ACTIVE_FROM", "SORT_ORDER1" => "DESC",
       "FIELD_CODE"    => ["PREVIEW_PICTURE", "DATE_ACTIVE_FROM"],
       "PROPERTY_CODE" => ["AUTHOR"],
       "DETAIL_URL"    => "/news/#ELEMENT_ID#/",
       "CACHE_TYPE"    => "A", "CACHE_TIME" => "36000000", "CACHE_GROUPS" => "Y",
       "SET_TITLE"     => "Y", "ADD_SECTIONS_CHAIN" => "Y",
       "DISPLAY_BOTTOM_PAGER" => "Y", "PAGER_TITLE" => "Новости",
       "CHECK_DATES"   => "Y",
   ]);
   ```
5. **Что кастомизируют в `/local`.** Копируют папку шаблона в
   `/local/templates/<site_tpl>/components/bitrix/news.list/<tpl>/` (см.
   `../recipes/template/07-component-templates.md`). Разметка — в `template.php`;
   подготовка/перебор `$arResult['ITEMS']` (вычисляемые поля) — в
   `result_modifier.php` (внутри кэша, 1 раз); `SetTitle`/мета/крошки — в
   `component_epilog.php` (вне кэша). Данные из модификатора в эпилог тащат через
   `SetResultCacheKeys([...])`.
6. **Типовые ошибки.**
   - `SetTitle`/`AddChainItem` в `template.php`/`result_modifier.php` → «застынут»
     под кэшем; их место — эпилог.
   - Несогласованный `DETAIL_URL` ↔ реальное место `news.detail` → ложный 404.
   - Вывод сырого `~CODE`/`~NAME` без `htmlspecialcharsbx()` → XSS.
   - Неверный `IBLOCK_TYPE` / неактивный `IBLOCK_ID` чужого сайта → пустой список.
   - Динамический параметр в `arParams` (текущее время) → кэш отравлен.
7. **Источник.** [src](https://dev.1c-bitrix.ru/user_help/components/content/articles_and_news/news_list.php)

---

## `bitrix:news.detail`

1. **Назначение.** Выводит детальную карточку одного элемента инфоблока
   (`DETAIL_TEXT`, `DETAIL_PICTURE`, свойства) по его `ID`/`CODE`.
2. **Когда брать.** Парный к `news.list`: ссылки списка ведут на страницу деталки.
   Если нужен весь раздел на ЧПУ — берут комплексный `bitrix:news`, он сам
   разрулит список и детальную.
3. **Ключевые `arParams`.**
   - `IBLOCK_TYPE`, `IBLOCK_ID` — как у списка.
   - `ELEMENT_ID` / `ELEMENT_CODE` — что показывать (из GET; при ЧПУ — `CODE`).
   - `FIELD_CODE` — поля деталки (`DETAIL_TEXT`, `DETAIL_PICTURE`).
   - `PROPERTY_CODE` — свойства для вывода.
   - `SET_TITLE`, `ADD_ELEMENT_CHAIN` — заголовок/крошка по элементу.
   - `SET_CANONICAL_URL` — канонический URL карточки.
   - `CACHE_TYPE`, `CACHE_TIME`, `CACHE_GROUPS` — кэш.
4. **Типовой вызов.**
   ```php
   $APPLICATION->IncludeComponent("bitrix:news.detail", ".default", [
       "IBLOCK_TYPE"  => "news",
       "IBLOCK_ID"    => 1,
       "ELEMENT_ID"   => (int)($_REQUEST["ELEMENT_ID"] ?? 0),
       "FIELD_CODE"   => ["DETAIL_TEXT", "DETAIL_PICTURE"],
       "PROPERTY_CODE"=> ["AUTHOR"],
       "SET_TITLE"    => "Y", "ADD_ELEMENT_CHAIN" => "Y",
       "CACHE_TYPE"   => "A", "CACHE_TIME" => "36000000", "CACHE_GROUPS" => "Y",
   ]);
   ```
5. **Что кастомизируют в `/local`.** Шаблон копируют в
   `/local/templates/<tpl>/components/bitrix/news.detail/<tpl>/`. Title/крошку
   карточки ставят в `component_epilog.php` (или оставляют `SET_TITLE=>"Y"`);
   разметку деталки — в `template.php`.
6. **Типовые ошибки.**
   - Несуществующий `ELEMENT_ID` без `AbortResultCache()` → пустой результат осядет
     в кэше (для штатного компонента уже обработано; важно при своей логике).
   - Title в `template.php` под кэшем «пропадёт» — ставить в эпилоге.
   - Забыть `SET_CANONICAL_URL` при доступе к карточке по нескольким URL.
7. **Источник.** [src](https://dev.1c-bitrix.ru/user_help/components/content/articles_and_news/news_detail.php)

---

## `bitrix:news` (комплексный)

1. **Назначение.** Комплексный компонент: внутри себя подключает список,
   детальную, поиск и RSS, разруливая подстраницы по SEF-режиму (ЧПУ).
2. **Когда брать.** Нужен **целый раздел** (новости/блог) на ЧПУ одной точкой
   входа, без раскладки `news.list`+`news.detail` по отдельным файлам. Один список
   на лендинге — наоборот, проще `news.list`.
3. **Ключевые `arParams`.**
   - `IBLOCK_TYPE`, `IBLOCK_ID` — инфоблок раздела.
   - `SEF_MODE` — `"Y"` (ЧПУ); `SEF_FOLDER` — корневой путь раздела (`/news/`).
   - `SEF_URL_TEMPLATES` — шаблоны подпутей (`list`, `section`, `detail`, `rss`).
   - `NEWS_COUNT`, `SORT_BY1`/`SORT_ORDER1` — как у списка.
   - `SET_TITLE`, `ADD_SECTIONS_CHAIN`, `ADD_ELEMENT_CHAIN` — заголовки/крошки.
   - `USE_SEARCH`, `USE_RSS` — включить поиск/RSS-подстраницы.
   - `CACHE_TYPE`, `CACHE_TIME` — кэш.
4. **Типовой вызов.**
   ```php
   $APPLICATION->IncludeComponent("bitrix:news", ".default", [
       "IBLOCK_TYPE" => "news",
       "IBLOCK_ID"   => 1,
       "SEF_MODE"    => "Y",
       "SEF_FOLDER"  => "/news/",
       "NEWS_COUNT"  => 20,
       "SET_TITLE"   => "Y", "ADD_SECTIONS_CHAIN" => "Y",
       "CACHE_TYPE"  => "A", "CACHE_TIME" => "36000000",
   ]);
   ```
   ⚠️ `SEF_FOLDER` должен совпасть с реальным путём страницы, иначе деталка молча
   не отрисуется (`guessComponentPath()` → `false`). Подробнее о SEF/ЧПУ —
   `../recipes/08-complex-component-sef.md`.
5. **Что кастомизируют в `/local`.** У комплексного компонента шаблоны вложенных
   подкомпонентов переопределяют по тем же путям, что для `news.list`/`news.detail`
   (`/local/templates/<tpl>/components/bitrix/news/<tpl>/...`). Логику — в
   `result_modifier.php` соответствующей подстраницы.
6. **Типовые ошибки.**
   - `SEF_FOLDER` ≠ реальный путь страницы → деталка/раздел не отрисуются.
   - Ручная правка `/urlrewrite.php` затрётся реиндексацией ЧПУ; правило ставить
     включением компонента + `UrlRewriter::reindexAll()`.
   - Дубли title между списком и детальной при невыставленных `SET_TITLE`.
7. **Источник.** [src](https://dev.1c-bitrix.ru/user_help/components/content/articles_and_news/news.php)

---

## Связано

- [`00-index.md`](./00-index.md) — индекс каталога.
- [`../recipes/06-output-on-page.md`](../recipes/06-output-on-page.md) — эталон вывода `news.list`.
- [`../recipes/08-complex-component-sef.md`](../recipes/08-complex-component-sef.md) — `bitrix:news` + ЧПУ.
- [`../recipes/template/07-component-templates.md`](../recipes/template/07-component-templates.md) — копия шаблона в `/local`.
