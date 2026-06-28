# Рецепт 01 — introspect-project: снять состояние существующего проекта

> Подсистема: 1c-bitrix-cms-content. Ядро БУС 26.x. Две поддерживаемые версии API (D7 и legacy) — обе официальны.
> Основан на изучении ядра «1С-Битрикс: Управление сайтом» (SM_VERSION 26.x) и официальной документации вендора.

## Цель

Перед любой правкой получить точную картину проекта: версию ядра, набор установленных модулей, контентную модель (типы инфоблоков, инфоблоки с ID/CODE/API_CODE/VERSION), сайты и активный шаблон, структуру `/local`. Итог — короткая сводка, на которую опираются следующие рецепты (выбор API, точки расширения, риски).

## Когда применять

- Достался незнакомый сайт (передача от другой команды, аудит, доработка).
- Перед добавлением инфоблока/компонента/модуля — чтобы не дублировать существующее и взять верные `IBLOCK_ID`/`SITE_ID`.
- В режиме «только файлы» (есть доступ к коду, нет живого ядра/БД) — собрать максимум из файловой системы.
- Перед миграцией/обновлением — зафиксировать baseline (версии модулей, список инфоблоков).

## Шаги

1. **Версия ядра.** Живой Битрикс: `\Bitrix\Main\ModuleManager::getVersion('main')` (возвращает `SM_VERSION`). Режим «только файлы»: прочитать `/bitrix/modules/main/classes/general/version.php` — там `define("SM_VERSION", "...")` и `SM_VERSION_DATE`. Версии отдельных модулей: `ModuleManager::getVersion('iblock')` либо файл `/bitrix/modules/<m>/install/version.php` (массив `$arModuleVersion['VERSION']`).
2. **Установленные модули.** Живой: `\Bitrix\Main\ModuleManager::getInstalledModules()` (по таблице `b_module`, ключ — id модуля) и точечно `ModuleManager::isModuleInstalled('catalog')`. Файлы: перечислить каталоги в `/bitrix/modules` и `/local/modules` (наличие папки ≠ модуль установлен в БД — это кандидаты).
3. **Инфоблоки и типы.** Подключить модуль: `Loader::includeModule('iblock')`. Типы — `\Bitrix\Iblock\TypeTable::getList()` (D7) или `CIBlockType::GetList()` (legacy). Инфоблоки — `\Bitrix\Iblock\IblockTable::getList()` (поля `ID/IBLOCK_TYPE_ID/CODE/API_CODE/NAME/ACTIVE/VERSION`) или `CIBlock::GetList()`. Зафиксировать, у каких инфоблоков заполнен `API_CODE` (нужен для D7-ORM элементов) и `VERSION` (1 или 2 — физика хранения свойств).
4. **Сайты и шаблон.** Сайты — `\Bitrix\Main\SiteTable::getList()` (поля `LID/DEF/ACTIVE/NAME/DIR/SERVER_NAME/LANGUAGE_ID/CULTURE_ID`) или `CSite::GetList()`. Активный шаблон сайта читается из условий шаблонов сайта (`CSite::GetList()` отдаёт привязку), физически — папки в `/local/templates/<id>` и `/bitrix/templates/<id>`.
5. **Структура `/local`.** Перечислить `components`, `templates`, `modules`, `php_interface` (есть ли `init.php`), `routes`, `.settings.php` — это карта кастомизаций проекта. `/local` приоритетнее `/bitrix` при резолве модулей, шаблонов, компонентов, конфига.
6. **Собрать сводку** в один блок: версия ядра → ключевые модули → таблица инфоблоков (ID/CODE/API_CODE/VERSION/тип) → сайты → активный шаблон → состав `/local`.

## Рабочий сниппет

Файл `/local/php_interface/tools/introspect.php` (запуск через CLI-бутстрап ядра либо из служебной страницы под админом). Кладём в `/local`, ядро не трогаем.

```php
<?php
// /local/php_interface/tools/introspect.php
// Снимок состояния проекта. Запускать под админом / через CLI с поднятым ядром.
use Bitrix\Main\Loader;
use Bitrix\Main\ModuleManager;
use Bitrix\Main\SiteTable;
use Bitrix\Iblock\IblockTable;
use Bitrix\Iblock\TypeTable;

if (!defined('B_PROLOG_INCLUDED') || B_PROLOG_INCLUDED !== true) {
    die();
}

$report = [];

// 1. Версия ядра и ключевых модулей
$report['core'] = [
    'SM_VERSION' => ModuleManager::getVersion('main'),
    'iblock'     => ModuleManager::getVersion('iblock'),
    'catalog'    => ModuleManager::getVersion('catalog'),
    'sale'       => ModuleManager::getVersion('sale'),
];

// 2. Установленные модули (ключи массива = id модулей из b_module)
$report['modules'] = array_keys(ModuleManager::getInstalledModules());

// 3. Сайты
$report['sites'] = SiteTable::getList([
    'select' => ['LID', 'DEF', 'ACTIVE', 'NAME', 'DIR', 'SERVER_NAME', 'LANGUAGE_ID', 'CULTURE_ID'],
    'order'  => ['DEF' => 'DESC', 'SORT' => 'ASC'],
])->fetchAll();

// 4. Инфоблоки и их типы
if (Loader::includeModule('iblock')) {
    $report['iblock_types'] = TypeTable::getList([
        'select' => ['ID'],
        'order'  => ['SORT' => 'ASC'],
    ])->fetchAll();

    $report['iblocks'] = IblockTable::getList([
        'select' => ['ID', 'IBLOCK_TYPE_ID', 'CODE', 'API_CODE', 'NAME', 'ACTIVE', 'VERSION'],
        'order'  => ['IBLOCK_TYPE_ID' => 'ASC', 'SORT' => 'ASC'],
    ])->fetchAll();

    // Инфоблоки без API_CODE — недоступны через D7-ORM элементов
    $report['iblocks_without_api_code'] = array_values(array_filter(
        $report['iblocks'],
        static fn(array $ib): bool => (string)$ib['API_CODE'] === ''
    ));
}

echo json_encode($report, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
```

Подключение через служебную страницу (под админом): создать `/local/public/_introspect.php`:

```php
<?php
require($_SERVER['DOCUMENT_ROOT'] . '/bitrix/modules/main/include/prolog_before.php');
global $USER;
if (!$USER->IsAdmin()) {
    require($_SERVER['DOCUMENT_ROOT'] . '/bitrix/modules/main/include/prolog_after.php');
    die();
}
header('Content-Type: application/json; charset=utf-8');
require($_SERVER['DOCUMENT_ROOT'] . '/local/php_interface/tools/introspect.php');
```

⚠️ Удалить служебную страницу после снятия снимка — она отдаёт структуру проекта.

## Выбор API (для этой задачи)

- **Версия ядра/модулей — `ModuleManager`.** Один класс закрывает и живой режим (`getVersion('main')` → `SM_VERSION`), и не требует ручного include version.php. В режиме «только файлы» читаем те же файлы, что использует сам `ModuleManager::getVersion()`: для `main` — `classes/general/version.php`, для остальных — `install/version.php`.
- **Модули — `ModuleManager::getInstalledModules()` (D7).** Возвращает реально установленные (по `b_module`), а не просто наличие папок. `getModulesFromDisk()` — отдельный метод для «что лежит на диске», полезен для сверки папка↔установка.
- **Инфоблоки/сайты — D7 Table-классы для чтения.** `IblockTable`/`TypeTable`/`SiteTable::getList()` дают плоский предсказуемый массив без двойного прохода и HTML-конвертации. Это задача чтения метаданных — D7 здесь точнее и короче legacy. `CIBlock::GetList()`/`CSite::GetList()` остаются рабочей альтернативой для старого кода. Для чтения самих элементов инфоблока (значения, URL) выбор API другой — см. рецепт по выводу контента.

## Проверка

**Режим «только файлы»** (без живого ядра):

```sh
# Версия ядра
grep -E 'define\("SM_VERSION' <DOCROOT>/bitrix/modules/main/classes/general/version.php

# Кандидаты-модули (наличие папок; установку в БД так не подтвердить)
ls -1 <DOCROOT>/bitrix/modules <DOCROOT>/local/modules 2>/dev/null

# Версия конкретного модуля
grep -E "'VERSION'" <DOCROOT>/bitrix/modules/iblock/install/version.php

# Карта кастомизаций
ls -1 <DOCROOT>/local 2>/dev/null
ls -1 <DOCROOT>/local/php_interface 2>/dev/null   # есть ли init.php
```

**Живой Битрикс:**

- Открыть `/local/public/_introspect.php` под админом → JSON со всеми блоками.
- Либо в админке: «Marketplace → Установленные решения/Модули» (список модулей), «Контент → Инфоблоки» (типы и инфоблоки с их ID), «Настройки → Сайты» (список сайтов и шаблоны).
- Проверка корректности: число инфоблоков из JSON совпадает с числом в админке; у инфоблоков, предназначенных для D7-ORM, `API_CODE` непустой; `DEF=Y` ровно у одного сайта.

## ⚠️ Риски

- ⚠️ Служебную страницу `_introspect.php` обязательно закрыть проверкой `$USER->IsAdmin()` и удалить после использования — она раскрывает структуру (модули, инфоблоки, домены).
- Наличие папки в `/bitrix/modules` или `/local/modules` ≠ модуль установлен. Установку подтверждает только `b_module` (`ModuleManager::getInstalledModules()`); по файлам это лишь кандидаты.
- `getInstalledModules()` кэширует результат (`cache ttl 86400`) и статически в рамках процесса — для абсолютно свежих данных после установки модуля сбросить кэш/перезапросить.
- Инфоблок без `API_CODE` доступен только через legacy `CIBlockElement`; D7-ORM элементов (`compileEntity`) для него не поднимется. Это влияет на выбор API в последующих рецептах.
- `VERSION` инфоблока (1 vs 2) определяет физику хранения свойств — учитывать при планировании выборок и миграций.
- `SITE_ID` ≠ `LANGUAGE_ID` ≠ `CULTURE_ID`. Мультиязычность реализуется несколькими сайтами; не выводить язык из идентификатора сайта.

## Связано

- Конвенции структуры `/local` и неприкосновенность ядра — `shared/kb/conventions.md` (раздел 1).
- Карта «задача → API» (модули, сайты, инфоблоки) — `shared/kb/api-map.md` (разделы 1–3).
- Подключение модуля: [Loader::includeModule](https://dev.1c-bitrix.ru/api_d7/bitrix/main/loader/includemodule.php).
- ORM-выборки (`getList`, фильтры) — [ORM: запрос данных](https://docs.1c-bitrix.ru/pages/orm/querying-data.html).
