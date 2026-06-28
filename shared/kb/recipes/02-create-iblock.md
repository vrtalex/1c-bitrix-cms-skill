# Рецепт 02: Создать тип инфоблока и инфоблок

Под-скилл: `1c-bitrix-cms-content` • Платформа: «1С-Битрикс: Управление сайтом», ядро 26.x, модуль `iblock` 25.x.

## Цель
Создать **тип инфоблока** (контейнер-категория, таблица `b_iblock_type`) и внутри него **инфоблок** (сущность контента, таблица `b_iblock`), привязать инфоблок к сайту (`LID` → `b_iblock_site`), задать `API_CODE` и `VERSION=2`, корректно обработать ошибки. Результат — готовая к наполнению контентная сущность (новости, услуги, команда, каталог).

## Когда применять
- Проектируете контентную модель сайта: один инфоблок = одна сущность.
- Нужна **воспроизводимая** установка структуры (миграция, перенос между стендами, CI), а не ручное создание в админке.
- Готовите почву для рецептов наполнения и вывода (свойства, элементы, компоненты).

Если структура уже есть в админке и нужно только наполнять/выводить — этот рецепт не нужен, переходите к рецептам по элементам.

## Шаги
1. **Спроектируйте идентификаторы.** Для типа — `ID` (латиница, напр. `content`). Для инфоблока — `CODE` (символьный код, для ЧПУ) и `API_CODE` (латиница, нужен для D7-ORM `Elements\Element<ApiCode>Table` и REST).
2. **Создайте тип** (`CIBlockType::Add` или `TypeTable::add`) с локализацией (`LANG` / `TypeLanguageTable`). Тип создаётся один раз и переиспользуется.
3. **Создайте инфоблок** с обязательными полями: `IBLOCK_TYPE_ID`, `NAME`, `SITE_ID`/`LID`, `API_CODE`, `VERSION=2`, права `GROUP_ID`, шаблоны URL.
4. **Проверьте результат ошибок** до выхода из скрипта (`$ib->LAST_ERROR` / `Result::isSuccess()`), верните созданный `IBLOCK_ID`.
5. Запустите скрипт **один раз из CLI** (`php local/install/02_create_iblock.php`), затем удалите/переместите его из публичной зоны.

## Рабочий сниппет
Разовый установочный скрипт. Положите в `/local/` (не в `bitrix/`), запустите из CLI (`php ...`) один раз, затем удалите.

Файл: `/local/install/02_create_iblock.php`

```php
<?php
// Разовый установочный скрипт. ЗАПУСТИТЬ ОДИН РАЗ ИЗ CLI, затем УДАЛИТЬ.
// CLI-only: иначе публичный привилегированный эндпоинт (создание ИБ) для любого посетителя.
if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }

require($_SERVER['DOCUMENT_ROOT'] . '/bitrix/modules/main/include/prolog_before.php');

use Bitrix\Main\Loader;

if (!Loader::includeModule('iblock')) {
    die('Module iblock is not installed');
}

$report = [];

// ---------------------------------------------------------------------------
// 1. ТИП ИНФОБЛОКА — путь legacy (CIBlockType::Add)
//    Реальная сигнатура: classes/general/iblocktype.php
// ---------------------------------------------------------------------------
$typeId = 'content';

$exists = CIBlockType::GetByID($typeId)->Fetch();
if (!$exists) {
    $ibType = new CIBlockType;
    $ok = $ibType->Add([
        'ID'       => $typeId,
        'SECTIONS' => 'Y',   // разрешить разделы (дерево категорий)
        'IN_RSS'   => 'N',
        'SORT'     => 100,
        'LANG'     => [
            'ru' => [
                'NAME'         => 'Контент',
                'SECTION_NAME' => 'Разделы',
                'ELEMENT_NAME' => 'Элементы',
            ],
            'en' => [
                'NAME'         => 'Content',
                'SECTION_NAME' => 'Sections',
                'ELEMENT_NAME' => 'Elements',
            ],
        ],
    ]);
    if (!$ok) {
        die('IBlockType add error: ' . $ibType->LAST_ERROR);
    }
    $report[] = "Тип инфоблока '{$typeId}' создан.";
} else {
    $report[] = "Тип инфоблока '{$typeId}' уже существует.";
}

// ---------------------------------------------------------------------------
// 2. ИНФОБЛОК — путь legacy (new CIBlock; $ib->Add)
//    Реальная сигнатура: classes/general/iblock.php
// ---------------------------------------------------------------------------
$ib = new CIBlock;
$iblockId = $ib->Add([
    'ACTIVE'          => 'Y',
    'NAME'            => 'Новости',
    'CODE'            => 'news',            // символьный код (ЧПУ)
    'API_CODE'        => 'news',            // нужен для D7-ORM и REST
    'IBLOCK_TYPE_ID'  => $typeId,
    'SITE_ID'         => ['s1'],            // привязка к сайту (LID) -> b_iblock_site
    'SORT'            => 100,
    'VERSION'         => 2,                 // 2 = отдельные таблицы значений свойств
    'GROUP_ID'        => ['2' => 'R'],      // права: группа «Все пользователи» -> чтение
    'LIST_PAGE_URL'   => '/news/',
    'SECTION_PAGE_URL'=> '/news/#SECTION_CODE#/',
    'DETAIL_PAGE_URL' => '/news/#SECTION_CODE#/#ELEMENT_CODE#/',
    'INDEX_ELEMENT'   => 'Y',               // индексировать для поиска
]);

if ((int)$iblockId <= 0) {
    die('IBlock add error: ' . $ib->LAST_ERROR);
}

$report[] = "Инфоблок 'news' создан, IBLOCK_ID = {$iblockId}.";

require($_SERVER['DOCUMENT_ROOT'] . '/bitrix/modules/main/include/epilog_after.php');
echo '<pre>' . implode("\n", $report) . '</pre>';
```

### Вариант D7 (тот же результат через ORM)
Используйте, когда команда стандартизирована на D7-ORM. Создаёт ту же структуру, но управление сайтами и правами делается отдельными шагами (legacy-метод `CIBlock::Add` берёт `SITE_ID`/`GROUP_ID` сразу).

```php
use Bitrix\Iblock\TypeTable;
use Bitrix\Iblock\TypeLanguageTable;
use Bitrix\Iblock\IblockTable;
use Bitrix\Iblock\IblockSiteTable;

// 2.1. Тип инфоблока
$typeResult = TypeTable::add([
    'ID'       => 'content',
    'SECTIONS' => 'Y',
    'IN_RSS'   => 'N',
    'SORT'     => 100,
]);
if (!$typeResult->isSuccess()) {
    die('TypeTable: ' . implode(', ', $typeResult->getErrorMessages()));
}
// Локализация типа — отдельной записью:
TypeLanguageTable::add([
    'IBLOCK_TYPE_ID' => 'content',
    'LANGUAGE_ID'    => 'ru',
    'NAME'           => 'Контент',
    'SECTION_NAME'   => 'Разделы',
    'ELEMENT_NAME'   => 'Элементы',
]);

// 2.2. Инфоблок (API_CODE и VERSION=2 — обязательны для D7-сценариев)
$iblockResult = IblockTable::add([
    'IBLOCK_TYPE_ID' => 'content',
    'LID'            => 's1',     // первичный сайт инфоблока
    'NAME'           => 'Новости',
    'CODE'           => 'news',
    'API_CODE'       => 'news',
    'ACTIVE'         => 'Y',
    'SORT'           => 100,
    'VERSION'        => 2,
    'LIST_PAGE_URL'  => '/news/',
    'DETAIL_PAGE_URL'=> '/news/#SECTION_CODE#/#ELEMENT_CODE#/',
]);
if (!$iblockResult->isSuccess()) {
    die('IblockTable: ' . implode(', ', $iblockResult->getErrorMessages()));
}
$iblockId = $iblockResult->getId();

// 2.3. Привязка к сайту (b_iblock_site) — отдельная сущность в D7
IblockSiteTable::add(['IBLOCK_ID' => $iblockId, 'SITE_ID' => 's1']);
```

## Выбор API (что рекомендовано для ЭТОЙ задачи)
Для **создания структуры** рекомендуется **legacy-путь** (`CIBlockType::Add` → `new CIBlock; ->Add()`):
- Один вызов `CIBlock::Add` принимает `SITE_ID` (массив сайтов) и `GROUP_ID` (права) сразу — записи в `b_iblock_site` и группы прав ставятся атомарно. В D7 это отдельные таблицы (`IblockSiteTable`, права) и дополнительные вызовы.
- Это путь, которым создаёт структуру штатный мастер, и он совпадает с тем, что ожидают штатные компоненты вывода.
- `LANG` (локализация типа) задаётся прямо в `CIBlockType::Add`; в D7 нужна отдельная вставка в `TypeLanguageTable`.

D7-путь (`TypeTable::add` / `IblockTable::add`) уместен, когда проект уже стандартизирован на ORM и нужна типобезопасность/единый стиль. Это две поддерживаемые версии API — обе валидны; различие в том, что legacy здесь короче и атомарнее для этой конкретной задачи.

Независимо от пути: **всегда задавайте `API_CODE`** (без него не работают `Elements\Element<ApiCode>Table` и REST `\Bitrix\Iblock\Controller\Element`) и **`VERSION=2`** (раздельное хранилище значений свойств).

## Проверка
**Режим «только файлы» (без живого Битрикса):**
- Скрипт лежит в `/local/install/`, а не в `bitrix/` (не перетрётся обновлением).
- В коде есть: `Loader::includeModule('iblock')`, задан `API_CODE`, `VERSION => 2`, привязка к сайту (`SITE_ID`/`LID`), обработка ошибок (`LAST_ERROR` / `isSuccess()`), и `(int)$iblockId > 0`.
- Идентификаторы `ID`/`CODE`/`API_CODE` — латиница, `SITE_ID` совпадает с существующим сайтом (по умолчанию `s1`).

**Режим «живой Битрикс»:**
- Запустите скрипт один раз из CLI (`php local/install/02_create_iblock.php`) — он должен напечатать `IBLOCK_ID = N`.
- Админка: «Контент → Информ. блоки → Типы информблоков» — виден тип; внутри — инфоблок.
- Вкладка «Доступ» инфоблока — есть привязка к сайту; вкладка «Подписи и заголовки» / SEO — заданы URL.
- Контроль кодом:
  ```php
  $rs = CIBlock::GetByID($iblockId)->Fetch();   // NAME, API_CODE, VERSION
  $sites = CIBlock::GetSite($iblockId);          // привязанные LID
  ```
- Проверка D7-доступности: `\Bitrix\Iblock\IblockTable::compileEntity('news')` не выдаёт предупреждения (значит `API_CODE` корректен).

## ⚠️ Риски
- ⚠️ **Скрипт-инсталлятор в публичной зоне — риск безопасности и повторного запуска.** Удалите файл сразу после успешного прогона или закройте доступ. Перед `Add` проверяйте существование (`CIBlockType::GetByID` / фильтр по `CODE`), чтобы повторный запуск не создал дубль инфоблока.
- ⚠️ **Смена `VERSION` у уже заполненного инфоблока — отдельная операция конвертации** (поле `LAST_CONV_ELEMENT`), не делается простым `Update`. Выбирайте `VERSION=2` сразу при создании.
- **Без `API_CODE`** инфоблок создастся, но D7-ORM элементов и REST будут недоступны (`getEntityDataClass()` выдаст предупреждение `API_CODE required`). Legacy-API при этом работает.
- **Реальные классы — `CAllIBlock*`**, а `CIBlock`/`CIBlockType` подмешиваются из DB-специфичной части (mysql/pgsql). На вызовы в коде это не влияет — используйте `CIBlock` / `CIBlockType` как обычно.

## Связано
- Рецепт 01 (подключение модуля `iblock`, `Loader::includeModule`) — предусловие этого рецепта.
- Рецепт по добавлению свойств (`CIBlockProperty::Add` / `PropertyTable::add`).
- Рецепт по наполнению (`CIBlockElement::Add`, `SetPropertyValuesEx`) и выводу (`bitrix:news.list`, `bitrix:news.detail`).
- База знаний: `../api-map.md` (модель iblock, две версии API, `compileEntity`, права), `../api-map.md` (привязка к сайту через `b_iblock_site`, мультисайт `SITE_ID`/`LID`).
- Документация вендора: https://dev.1c-bitrix.ru/ , https://docs.1c-bitrix.ru/
```
