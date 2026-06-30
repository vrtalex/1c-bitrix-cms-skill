# Компоненты: каталог магазина

Группа `catalog.*` — витрина интернет-магазина: разделы, товары, фильтр. Каталог —
надстройка над инфоблоком (см. `1c-bitrix-cms-content`), плюс модули `catalog`/`sale`.
Базовые рецепты — `../recipes/commerce/01-catalog-setup.md`, фильтр и SEO —
`../recipes/seo/07-smart-filter-seo.md`.

---

## `bitrix:catalog.section`

1. **Назначение.** Выводит список товаров одного раздела каталога (с ценами, SKU,
   корзинными кнопками, пагинацией). Каталожный аналог `news.list`.
2. **Когда брать.** Витрина категории (страница раздела). Для детальной карточки
   товара — `bitrix:catalog.element`; для всего магазина на ЧПУ — комплексный
   `bitrix:catalog`.
3. **Ключевые `arParams`.**
   - `IBLOCK_TYPE`, `IBLOCK_ID` — инфоблок каталога.
   - `SECTION_ID` / `SECTION_CODE` — какой раздел показывать.
   - `ELEMENT_SORT_FIELD` / `ELEMENT_SORT_ORDER` — сортировка товаров.
   - `PAGE_ELEMENT_COUNT` — товаров на странице.
   - `PROPERTY_CODE` — свойства товара для вывода.
   - `PRICE_CODE` — массив кодов типов цен (`["BASE"]`).
   - `USE_PRODUCT_QUANTITY`, `ADD_TO_BASKET_ACTION` — кнопки покупки.
   - `OFFERS_*` (`OFFERS_LIMIT`, `OFFERS_SORT_FIELD`) — торговые предложения (SKU).
   - `SHOW_DISCOUNT_PERCENT`, `CONVERT_CURRENCY` — цены/скидки.
   - `DETAIL_URL`, `SECTION_URL` — шаблоны ссылок.
   - `CACHE_TYPE`, `CACHE_TIME` — кэш по тегам инфоблока.
4. **Типовой вызов.**
   ```php
   $APPLICATION->IncludeComponent("bitrix:catalog.section", ".default", [
       "IBLOCK_TYPE"   => "catalog",
       "IBLOCK_ID"     => 2,
       "SECTION_CODE"  => $_REQUEST["SECTION_CODE"] ?? "",
       "ELEMENT_SORT_FIELD" => "SORT", "ELEMENT_SORT_ORDER" => "ASC",
       "PAGE_ELEMENT_COUNT" => 24,
       "PRICE_CODE"    => ["BASE"],
       "PROPERTY_CODE" => ["BRAND", "COLOR"],
       "DETAIL_URL"    => "/catalog/#SECTION_CODE#/#ELEMENT_CODE#/",
       "CACHE_TYPE"    => "A", "CACHE_TIME" => "36000000",
   ]);
   ```
5. **Что кастомизируют в `/local`.** Шаблон копируют в
   `/local/templates/<tpl>/components/bitrix/catalog.section/<tpl>/`. Карточку
   товара в плитке правят в `template.php`; вычисляемые поля (бейджи, форматы цен)
   — в `result_modifier.php`. Корзинные действия идут AJAX-экшеном — разметку
   кнопок не ломать. Title/крошки раздела — в `component_epilog.php`.
6. **Типовые ошибки.**
   - Пустой `PRICE_CODE` → цены не выведутся.
   - Не подключён модуль `catalog`/`sale` → компонент не найдёт цены/корзину.
   - Несогласованный `DETAIL_URL` ↔ место `catalog.element` → 404 на товаре.
   - SKU не выводятся без `OFFERS_*` и без указания инфоблока торговых предложений.
7. **Источник.** [src](https://dev.1c-bitrix.ru/user_help/components/content/catalog/catalog_section.php)

---

## `bitrix:catalog.element`

1. **Назначение.** Детальная карточка товара: фото, описание, цена, SKU-выбор,
   кнопка «в корзину».
2. **Когда брать.** Страница одного товара. Парный к `catalog.section`. В составе
   комплексного `bitrix:catalog` подключается автоматически.
3. **Ключевые `arParams`.**
   - `IBLOCK_TYPE`, `IBLOCK_ID` — инфоблок каталога.
   - `ELEMENT_ID` / `ELEMENT_CODE` — товар.
   - `PRICE_CODE`, `SHOW_PRICE_COUNT` — цены и их количество.
   - `PROPERTY_CODE`, `OFFERS_PROPERTY_CODE` — свойства товара и SKU.
   - `USE_PRODUCT_QUANTITY`, `ADD_TO_BASKET_ACTION` — покупка.
   - `OFFERS_CART_PROPERTIES` — свойства SKU, попадающие в корзину.
   - `SET_TITLE`, `ADD_ELEMENT_CHAIN`, `SET_CANONICAL_URL`.
   - `CACHE_TYPE`, `CACHE_TIME`.
4. **Типовой вызов.**
   ```php
   $APPLICATION->IncludeComponent("bitrix:catalog.element", ".default", [
       "IBLOCK_TYPE"   => "catalog",
       "IBLOCK_ID"     => 2,
       "ELEMENT_CODE"  => $_REQUEST["ELEMENT_CODE"] ?? "",
       "PRICE_CODE"    => ["BASE"],
       "PROPERTY_CODE" => ["BRAND", "MATERIAL"],
       "OFFERS_PROPERTY_CODE" => ["SIZE", "COLOR"],
       "SET_TITLE"     => "Y", "ADD_ELEMENT_CHAIN" => "Y",
       "CACHE_TYPE"    => "A", "CACHE_TIME" => "36000000",
   ]);
   ```
5. **Что кастомизируют в `/local`.** Шаблон — в
   `/local/templates/<tpl>/components/bitrix/catalog.element/<tpl>/`. Галерея,
   блок цены и SKU-селектор правят в `template.php`; SEO-мета/крошку — в
   `component_epilog.php`. JS выбора SKU — штатный, разметку селектора не ломать.
6. **Типовые ошибки.**
   - Свойства SKU не попадают в корзину без `OFFERS_CART_PROPERTIES`.
   - Title под кэшем в `template.php` «пропадёт» — ставить в эпилоге.
   - Нет канонического URL при доступе к товару из разных разделов.
7. **Источник.** [src](https://dev.1c-bitrix.ru/user_help/components/content/catalog/catalog_element.php)

---

## `bitrix:catalog.smart.filter`

1. **Назначение.** Готовит и выводит форму умного фильтра по свойствам/цене
   инфоблока; результат фильтрации показывает `catalog.section` через общую
   переменную фильтра.
2. **Когда брать.** Нужна фильтрация витрины (цена, бренд, цвет). Работает в паре с
   `catalog.section`: фильтр пишет в `FILTER_NAME`, секция читает.
3. **Ключевые `arParams`.**
   - `IBLOCK_TYPE`, `IBLOCK_ID` — инфоблок каталога.
   - `SECTION_ID` / `SECTION_CODE` — раздел фильтрации.
   - `FILTER_NAME` — **имя** глобальной переменной фильтра (не сам массив).
   - `PRICE_CODE` — типы цен в фильтре.
   - `SEF_MODE`, `SEF_RULE` — ЧПУ умного фильтра (SEO).
   - `SAVE_IN_SESSION`, `XML_EXPORT` — поведение/выгрузка.
   - `CACHE_TYPE`, `CACHE_TIME`.
4. **Типовой вызов.**
   ```php
   $APPLICATION->IncludeComponent("bitrix:catalog.smart.filter", ".default", [
       "IBLOCK_TYPE" => "catalog",
       "IBLOCK_ID"   => 2,
       "SECTION_CODE"=> $_REQUEST["SECTION_CODE"] ?? "",
       "FILTER_NAME" => "arrFilter",   // одноимённую переменную читает catalog.section
       "PRICE_CODE"  => ["BASE"],
       "CACHE_TYPE"  => "A", "CACHE_TIME" => "36000000",
   ]);
   ```
5. **Что кастомизируют в `/local`.** Шаблон формы — в
   `/local/templates/<tpl>/components/bitrix/catalog.smart.filter/<tpl>/`. Правят
   разметку чекбоксов/слайдера цены в `template.php`. ЧПУ и SEO-теги фильтра —
   отдельная тема, см. `../recipes/seo/07-smart-filter-seo.md`.
6. **Типовые ошибки.**
   - `FILTER_NAME` — имя переменной, маска `^[A-Za-z_][A-Za-z0-9_]*$`; в
     `catalog.section` указать то же имя, иначе фильтр не применится.
   - Умный фильтр конфликтует с композитом — динамику оборачивать в `createFrame()`.
   - ЧПУ-страницы фильтра без SEO-настройки плодят дубли в индексе.
7. **Источник.** [src](https://dev.1c-bitrix.ru/user_help/components/content/catalog/smart_filter.php)

---

## `bitrix:catalog.section.list` (кратко)

1. **Назначение.** Выводит список/дерево разделов каталога для навигации по
   категориям.
2. **Когда брать.** Блок «категории» в сайдбаре/на главной. Не путать с
   `catalog.section` (товары раздела) — здесь именно разделы.
3. **Ключевые `arParams`.** `IBLOCK_TYPE`, `IBLOCK_ID`, `SECTION_ID`
   (родитель), `VIEW_MODE` (`LINE`/`TILE`/`TEXT`), `SHOW_PARENT_NAME`,
   `SECTION_URL`, `CACHE_TYPE`.
4. **Типовой вызов.**
   ```php
   $APPLICATION->IncludeComponent("bitrix:catalog.section.list", ".default", [
       "IBLOCK_TYPE" => "catalog", "IBLOCK_ID" => 2,
       "SECTION_ID"  => 0,            // 0 — от корня
       "VIEW_MODE"   => "LINE",
       "SECTION_URL" => "/catalog/#SECTION_CODE#/",
       "CACHE_TYPE"  => "A", "CACHE_TIME" => "36000000",
   ]);
   ```
5. **Что кастомизируют в `/local`.** Разметку плиток разделов — в `template.php`
   копии шаблона по пути `…/catalog.section.list/<tpl>/`.
6. **Типовые ошибки.** Неверный `SECTION_ID` родителя → пустое дерево; забыть
   `SECTION_URL` → битые ссылки на категории.
7. **Источник.** [src](https://dev.1c-bitrix.ru/user_help/components/content/catalog/catalog_section_list.php)

---

## `bitrix:catalog` (комплексный, кратко)

1. **Назначение.** Комплексный компонент всей витрины: разделы, список товаров,
   детальная, сравнение, фильтр — на ЧПУ одной точкой входа.
2. **Когда брать.** Весь магазин-витрина одним компонентом в SEF-режиме. Когда
   нужен тонкий контроль над отдельными страницами — раскладывают `catalog.section`
   + `catalog.element` + `catalog.smart.filter` по файлам.
3. **Ключевые `arParams`.** `IBLOCK_TYPE`, `IBLOCK_ID`, `SEF_MODE=Y`, `SEF_FOLDER`
   (`/catalog/`), `SEF_URL_TEMPLATES` (`section`/`element`/`compare`), `PRICE_CODE`,
   `USE_FILTER`, `CACHE_TYPE`.
4. **Типовой вызов.**
   ```php
   $APPLICATION->IncludeComponent("bitrix:catalog", ".default", [
       "IBLOCK_TYPE" => "catalog", "IBLOCK_ID" => 2,
       "SEF_MODE"    => "Y", "SEF_FOLDER" => "/catalog/",
       "PRICE_CODE"  => ["BASE"], "USE_FILTER" => "Y",
       "CACHE_TYPE"  => "A", "CACHE_TIME" => "36000000",
   ]);
   ```
   ⚠️ `SEF_FOLDER` обязан совпасть с реальным путём страницы.
5. **Что кастомизируют в `/local`.** Шаблоны вложенных подкомпонентов
   переопределяют по их собственным путям (`…/catalog/<tpl>/...`), как у `news`.
6. **Типовые ошибки.** `SEF_FOLDER` ≠ путь → подстраницы не отрисуются; смешение
   ручного `urlrewrite.php` с реиндексацией ЧПУ.
7. **Источник.** [src](https://dev.1c-bitrix.ru/user_help/components/content/catalog/catalog.php)

---

## Связано

- [`00-index.md`](./00-index.md) — индекс каталога.
- [`../recipes/seo/07-smart-filter-seo.md`](../recipes/seo/07-smart-filter-seo.md) — ЧПУ и SEO умного фильтра.
- [`../api-map.md`](../api-map.md) — `bitrix:catalog.*` и кэш по тегам инфоблока (§5–§6).
- [`03-basket.md`](./03-basket.md) — корзина, куда уходят кнопки покупки.
