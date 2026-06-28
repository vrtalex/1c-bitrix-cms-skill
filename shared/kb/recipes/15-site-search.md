# 15. Поиск по сайту (модуль search)

## Цель

Включить полнотекстовый поиск по сайту на «1С-Битрикс: Управление сайтом»:
проиндексировать контент (инфоблоки и др.), вывести форму поиска в шапке,
страницу выдачи `/search/`, подсказки и облако тегов. Модуль `search` —
встроенная поисковая система ядра: индексация из произвольных источников,
стемминг (рус/анг/тур), теги, suggest, статистика запросов.

## Когда применять

- Нужен поиск по каталогу, новостям, статическим страницам.
- Нужен живой typeahead (подсказки по заголовкам) в шапке.
- Нужно проиндексировать собственный контент (не из стандартного модуля).
- Нужно настроить, какие источники участвуют в выдаче и в каком порядке.

Поиск API в модуле реализован в едином стиле классов без namespace
(`CSearch`, `CSearchTags`, `CSearchFullText` и т.д.) — D7-обёрток нет,
пишите через `CSearch::Index()` / `CSearch::Search()`.

## Шаги

1. **Подключить модуль.** `CModule::IncludeModule('search')`. При установке
   модуль сам регистрирует обработчики событий и агенты.

2. **Что индексируется.** Каждый модуль-источник регистрирует обработчик
   события `search::OnReindex`. В дистрибутиве это `iblock`
   (`CIBlock::OnSearchReindex` — элементы и разделы инфоблоков с флагом
   `INDEX_ELEMENT='Y'` / `INDEX_SECTION='Y'`), `forum`, `blog`, `learning`.
   Статические `*.php` / `*.html` индексирует модуль `main` по include/exclude-маске.

3. **Включить индексацию инфоблока.** В настройках инфоблока выставить
   «Индексировать для поиска» (элементы и/или разделы). Без этого флага
   `CIBlock::OnSearchReindex` пропустит инфоблок (см. 02-create-iblock.md).

4. **Настроить опции поиска.** Через `COption::SetOptionString('search', ...)`
   или админку (`Настройки → Настройки модулей → Поиск`): стемминг, маски,
   сбор статистики, движок FTS.

5. **Переиндексировать.** Полная переиндексация строит индекс заново.
   Запускается из админки (`Сервис → Поиск → Переиндексация`) или из кода.

6. **Создать страницу выдачи** `/search/index.php` с `bitrix:search.page`.

7. **Добавить форму поиска** в шапку (`bitrix:search.title` для typeahead
   или `bitrix:search.form` для простой формы).

8. **Опционально** — облако тегов (`bitrix:search.tags.cloud`),
   подсказки из истории (`bitrix:search.suggest.input`),
   кастомный ранг источников (`CSearchCustomRank`).

## Рабочий сниппет/конфиг

### Базовая конфигурация (`/local/php_interface/init.php` или установочный скрипт)

```php
CModule::IncludeModule('search');

COption::SetOptionString('search', 'use_stemming', 'Y');
COption::SetOptionString('search', 'stat_phrase', 'Y');   // статистика фраз
COption::SetOptionString('search', 'include_mask', '*.php;*.html;*.htm');
COption::SetOptionString('search', 'exclude_mask', '/bitrix/*;/upload/*;/local/*');
COption::SetOptionString('search', 'full_text_engine', 'bitrix'); // движок по умолчанию
```

### Страница выдачи `/search/index.php`

```php
<?php require($_SERVER['DOCUMENT_ROOT'].'/bitrix/header.php');
$APPLICATION->SetTitle('Поиск');
$APPLICATION->IncludeComponent('bitrix:search.page', '', [
    'PAGE_RESULT_COUNT'  => 20,
    'USE_LANGUAGE_GUESS' => 'Y',   // автокоррекция раскладки клавиатуры
    'DEFAULT_SORT'       => 'rank',
    'RESTART'            => 'Y',    // повтор поиска без стемминга, если пусто
    'SHOW_WHERE'         => 'Y',    // дропдаун «где искать»
    'arrWHERE'           => ['iblock_catalog', 'main'],
    'arrFILTER'          => 'no',
    'CHECK_DATES'        => 'N',
    'CACHE_TYPE'         => 'N',
]);
require($_SERVER['DOCUMENT_ROOT'].'/bitrix/footer.php');
```

GET-параметры страницы: `q` (запрос), `tags`, `where`, `how` (`r` — по рейтингу,
`d` — по дате), `from`, `to`.

### Форма поиска в шапке (простая)

```php
$APPLICATION->IncludeComponent('bitrix:search.form', '', [
    'PAGE' => SITE_DIR . 'search/index.php',
]);
```

### Живой typeahead в шапке (подсказки по заголовкам)

```php
$APPLICATION->IncludeComponent('bitrix:search.title', '', [
    'PAGE'               => SITE_DIR . 'search/index.php',
    'NUM_CATEGORIES'     => 2,
    'CATEGORY_0'         => ['iblock_catalog'],
    'CATEGORY_0_TITLE'   => 'Товары',
    'CATEGORY_1'         => ['main'],
    'CATEGORY_1_TITLE'   => 'Страницы',
    'TOP_COUNT'          => 5,
    'SHOW_OTHERS'        => 'Y',
    'USE_LANGUAGE_GUESS' => 'Y',
]);
```

`search.title` ищет только по заголовкам (`b_search_content_title`) через AJAX —
быстро, но без полнотекстового совпадения по телу документа.

### Облако тегов

```php
$APPLICATION->IncludeComponent('bitrix:search.tags.cloud', '', [
    'PAGE_ELEMENTS' => 30,
    'SORT'          => 'CNT',   // по количеству
    'SORT_BY'       => 'DESC',
    'CACHE_TYPE'    => 'A',
    'CACHE_TIME'    => 3600,
]);
```

Подсказки из истории запросов — `bitrix:search.suggest.input` (использует
`CSearchSuggest` и таблицу `b_search_suggest`; на новом сайте история пуста,
подсказки появятся после реальных запросов).

### Индексация собственного контента

```php
CModule::IncludeModule('search');

CSearch::Index('mymodule', 'item_' . $ID, [
    'SITE_ID'     => [SITE_ID => '/custom/item/' . $ID . '/'], // сайт => URL
    'TITLE'       => $title,
    'BODY'        => strip_tags($description),
    'TAGS'        => implode(',', $tags),
    'PERMISSIONS' => [2],          // 2 = «все посетители»
    'DATE_CHANGE' => date('d.m.Y H:i:s'),
    'PARAM1'      => 'custom_type',
    'PARAM2'      => $category_id,
    'URL'         => '/custom/item/' . $ID . '/',
]);

// Удаление из индекса:
CSearch::DeleteIndex('mymodule', 'item_' . $ID);
```

### Программный поиск (CSearch API)

```php
$obSearch = new CSearch();
$obSearch->Search(
    ['QUERY' => $q, 'SITE_ID' => SITE_ID],
    ['RANK' => 'DESC', 'DATE_CHANGE' => 'DESC'],
    [['=MODULE_ID' => 'iblock', 'PARAM1' => 'catalog']] // фильтр источников (OR между элементами)
);
$obSearch->NavStart(20, false);
while ($ar = $obSearch->GetNext()) {
    // $ar['TITLE_FORMATED'], $ar['URL'], $ar['BODY_FORMATED'], $ar['TAGS_FORMATED']
}
```

### Кастомный ранг источника (поднять источник в выдаче)

```php
$oRank = new CSearchCustomRank;
$oRank->Add([
    'SITE_ID' => 's1', 'MODULE_ID' => 'iblock',
    'PARAM1'  => 'catalog', 'PARAM2' => '5', 'RANK' => 10,
]);
$oRank->StartUpdate();
while ($oRank->NextUpdate() !== false) { /* применяем шагами */ }
```

### Переиндексация из кода (пошагово, для cron/агента)

```php
$NS = CSearch::ReIndexAll(false, 20, $NS); // 20 сек на шаг; $NS — состояние
// is_array($NS) — продолжить со следующим $NS; иначе — готово
```

## Проверка

**Режим «только файлы»:**
- `/search/index.php` существует и вызывает `bitrix:search.page`.
- В шапке шаблона есть вызов `bitrix:search.form` или `bitrix:search.title`
  с `PAGE => SITE_DIR.'search/index.php'`.
- Параметры компонентов соответствуют сигнатурам выше (имена ключей,
  `arrWHERE` как массив источников).
- В установочном скрипте/`init.php` заданы опции `use_stemming`,
  `include_mask`, `exclude_mask`.

**Режим «живой Битрикс»:**
- `CModule::IncludeModule('search')` возвращает `true`.
- У целевого инфоблока включён флаг индексации (элементы/разделы).
- Запущена переиндексация (`Сервис → Поиск → Переиндексация`), счётчик
  обработанных записей > 0; таблица `b_search_content` непустая.
- Запрос на `/search/?q=...` возвращает результаты; в `arResult['SEARCH']`
  есть элементы, `arResult['ERROR_CODE']` пуст.
- Typeahead в шапке отдаёт подсказки на ввод (AJAX-ответ `search.title`).
- Облако тегов выводит теги, если у проиндексированных элементов они есть.

## ⚠️ Риски

- ⚠️ **Индекс надо переиндексировать.** Новый контент не появляется в выдаче
  сам по себе — нужна переиндексация (полная или по событию). Полная
  переиндексация с `$bFull = true` делает `TRUNCATE` всех поисковых таблиц:
  на продакшене выполняйте в окно обслуживания или пошагово через агент.
- ⚠️ **Права на видимость (`PERMISSIONS`).** Это список номеров групп; группа
  `2` — «все посетители». Если `PERMISSIONS` не указать, документ увидят
  только администраторы. Проверяйте права при индексации собственного контента.
- **`ITEM_ID` ≤ 255 символов** (`VARCHAR(255)`); идентификатор документа
  уникален в паре `(MODULE_ID, ITEM_ID)`.
- **URL с `=` в начале** — служебный формат (разворачивается событием
  `search::OnSearchGetURL`, используется iblock). Для своей индексации
  передавайте обычный URL без `=`.
- **Лимит 500 результатов** (`max_result_size`) — пагинация работает только
  в пределах этого числа документов.
- **Стоп-слова и короткие слова** могут не индексироваться; если запрос
  состоит только из них — пустая выдача. Параметр `RESTART='Y'` повторяет
  поиск без стемминга.
- **OpenSearch** требует отдельной настройки пароля (`CPasswordStorage`),
  иначе подключение не устанавливается.

### Движки полнотекстового поиска (кратко)

`CSearchFullText::getInstance()` выбирает движок по опции
`search.full_text_engine`:

- `bitrix` (по умолчанию) — стемминг-таблицы в БД, без внешних зависимостей.
- `mysql` — нативный MySQL `FULLTEXT`.
- `sphinx` — внешний Sphinx (`sphinx_connection`, `sphinx_index_name`).
- `opensearch` — внешний OpenSearch (нужен пароль через `CPasswordStorage`).
- `pgsql` — PostgreSQL FTS.

Внешние движки имеют смысл при больших объёмах индекса; для типового сайта
достаточно встроенного `bitrix`.

## Связано

- [Карта API модулей](../api-map.md)
- [02-create-iblock.md](02-create-iblock.md) — создание инфоблока и флаг индексации
- [06-output-on-page.md](06-output-on-page.md) — подключение компонентов на странице
