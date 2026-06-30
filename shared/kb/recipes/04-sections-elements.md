# Рецепт 04 — Разделы и элементы инфоблока (создание и наполнение)

> Подсистема: `iblock` (модуль `25.300.0`, ядро `main 26.150.0`).
> Две поддерживаемые версии API. Для записи разделов/элементов со свойствами и привязками рекомендуется legacy-слой `CIBlockSection` / `CIBlockElement`; D7-опция через ORM-сущность инфоблока упомянута ниже.

## Цель

Программно создать разделы (`CIBlockSection::Add`) и элементы (`CIBlockElement::Add`) в существующем инфоблоке: заполнить базовые поля и свойства (`PROPERTY_VALUES`), прикрепить картинки (`PREVIEW_PICTURE` / `DETAIL_PICTURE` через `CFile::MakeFileArray`) и привязать элемент к разделу (`IBLOCK_SECTION`).

## Когда применять

- Сидирование/наполнение контента кодом (миграции, импорт фидов, демо-данные) — воспроизводимо и совпадает с тем, что делает мастер импорта.
- Нужны побочные эффекты записи: авто-ресайз картинок, события `OnAfterIBlockElementAdd`, обновление поискового индекса, сброс кэша, пересчёт nested-set разделов. Их даёт legacy `Add`; при записи через ORM-сущность инфоблока они НЕ выполняются (см. ## Выбор API).
- Инфоблок уже создан (есть `IBLOCK_ID`, заданы свойства). Создание самого инфоблока — отдельный рецепт (см. ## Связано).

## Шаги

1. Подключить модуль: `\Bitrix\Main\Loader::includeModule('iblock')` с проверкой результата.
2. Создать раздел через `CIBlockSection::Add($arFields)`. Обязательны `IBLOCK_ID`, `NAME`, `ACTIVE`. Вложенность — через `IBLOCK_SECTION_ID` (ID родителя).
3. ⚠️ Проверить результат: метод возвращает ID нового раздела или `false`. При `false` читать `$section->LAST_ERROR`.
4. Подготовить картинки: локальный путь или URL → `CFile::MakeFileArray($pathOrUrl)` → массив `$_FILES`-формата. В `PREVIEW_PICTURE`/`DETAIL_PICTURE` передаётся именно этот массив — модуль iblock сам сохранит файл в `b_file` через `CFile::SaveFile`.
5. Создать элемент через `CIBlockElement::Add($arFields)`. Обязательны `IBLOCK_ID`, `NAME`, `ACTIVE`. Свойства — в `PROPERTY_VALUES` (ключ = `CODE` или `ID` свойства). Привязка к разделам — `IBLOCK_SECTION` массивом ID.
6. ⚠️ Проверить результат `Add`: при пустом/`false` ID читать `$element->LAST_ERROR`.
7. (Опционально) Множественные свойства/картинки после создания — `CIBlockElement::SetPropertyValuesEx($id, $iblockId, [...])`.

## Рабочий сниппет

Файл: `/local/php_interface/migrations/seed_catalog.php` (запуск из CLI/агента; точку входа защитить от прямого вызова при подключении в публичном контексте).

```php
<?php
use Bitrix\Main\Loader;

if (!Loader::includeModule('iblock')) {
	throw new \RuntimeException('Module iblock is not installed');
}

$iblockId = 5; // существующий инфоблок

// 1. Раздел (NAME, IBLOCK_ID, ACTIVE — обязательны)
$section = new CIBlockSection();
$sectionId = $section->Add([
	'IBLOCK_ID'         => $iblockId,
	'NAME'              => 'Смартфоны',
	'CODE'             => 'smartfony',     // символьный код для ЧПУ
	'ACTIVE'           => 'Y',
	'SORT'             => 100,
	'IBLOCK_SECTION_ID' => false,         // false = корень; ID родителя для вложенности
	'DESCRIPTION'       => 'Каталог смартфонов',
	'DESCRIPTION_TYPE'  => 'text',
]);
if (!$sectionId) {
	throw new \RuntimeException('Section add failed: ' . $section->LAST_ERROR);
}

// 2. Картинки: локальный файл или URL -> массив для записи в поле картинки
$preview = CFile::MakeFileArray($_SERVER['DOCUMENT_ROOT'] . '/local/seed/iphone.jpg');
// из URL: $preview = CFile::MakeFileArray('https://example.com/img/iphone.jpg');

// 3. Элемент (NAME, IBLOCK_ID, ACTIVE — обязательны)
$element = new CIBlockElement();
$elementId = $element->Add([
	'IBLOCK_ID'       => $iblockId,
	'NAME'            => 'iPhone 16',
	'CODE'           => 'iphone-16',
	'ACTIVE'         => 'Y',
	'SORT'           => 500,
	'IBLOCK_SECTION' => [$sectionId],      // привязка к разделу(ам) массивом ID
	'PREVIEW_PICTURE' => $preview ?: false, // массив MakeFileArray; iblock сам вызовет SaveFile
	'PREVIEW_TEXT'    => 'Флагман 2024 года',
	'PREVIEW_TEXT_TYPE' => 'text',
	'PROPERTY_VALUES' => [
		'ARTICLE' => 'IP16-128',          // одиночное свойство по CODE
		'COLOR'   => ['red', 'black'],    // множественное свойство (массив значений)
		'MANUAL'  => $preview,             // свойство типа F (файл) — тоже MakeFileArray
	],
]);
if (!$elementId) {
	throw new \RuntimeException('Element add failed: ' . $element->LAST_ERROR);
}

// 4. (опц.) дозаполнить свойства после создания — по CODE
CIBlockElement::SetPropertyValuesEx($elementId, $iblockId, [
	'AUTHOR' => 'Редакция',
]);
```

Формат множественного свойства типа F (несколько картинок «MORE_PHOTO») при создании элемента:
```php
'PROPERTY_VALUES' => [
	'MORE_PHOTO' => [
		'n0' => ['VALUE' => CFile::MakeFileArray($path1), 'DESCRIPTION' => ''],
		'n1' => ['VALUE' => CFile::MakeFileArray($path2), 'DESCRIPTION' => ''],
	],
],
```

## Выбор API (что рекомендовано для ЭТОЙ задачи и почему)

- **Рекомендация: legacy `CIBlockSection::Add` / `CIBlockElement::Add`.** Это путь, на котором написаны все штатные компоненты и мастер импорта. Запись через `Add` запускает полный цикл побочных эффектов: события (`OnAfterIBlockElementAdd` и др.), авто-ресайз и сохранение картинок, обновление поискового индекса, сброс кэша по тегам, пересчёт `LEFT_MARGIN/RIGHT_MARGIN/DEPTH_LEVEL` для разделов, права. Работает и без заполненного `API_CODE` у инфоблока.
- **D7-опция (ORM-сущность инфоблока).** Если у инфоблока задан `API_CODE`, можно писать через скомпилированную сущность: `IblockTable::compileEntity('news')->getDataClass()::add([...])`, свойства как обычные ORM-поля. Подходит для нового backend-кода с объектами и при работе через коллекции.
  - ⚠️ При записи через ORM-сущность НЕ выполняются: события, авто-ресайз картинок, обновление фасетного индекса/SEO, сброс кэша, права, бизнес-процессы, индексация поиска, пересчёт nested-set разделов — реализовывать вручную или использовать legacy `Add`.
- **`PROPERTY_VALUES` vs `SetPropertyValuesEx`.** Передавать свойства прямо в `Add` удобнее одним вызовом. `CIBlockElement::SetPropertyValuesEx($id, $iblockId, [...])` — для дозаполнения/обновления свойств уже созданного элемента по `CODE`.
- **Картинки только через `CFile`.** В поля картинок и свойства типа `F` передаётся массив `CFile::MakeFileArray()` (локальный путь или URL); прямой записи в `b_file` через ORM нет — `\Bitrix\Main\FileTable` доступна только на чтение. Удалять файлы — `CFile::Delete($id)`, не `unlink`.

## Проверка

Проверка рендера и структуры — по общему паттерну: [verification](../operations.md) (CLI для структуры, браузер/preview для рендера; на dev-стенде).

**Режим «только файлы» (без живого Битрикс):**
- Линт PHP: `php -l /local/php_interface/migrations/seed_catalog.php`.
- Статически убедиться, что в каждом `Add` присутствуют `IBLOCK_ID`, `NAME`, `ACTIVE`, а результат вызова проверяется (`if (!$id) ... LAST_ERROR`).
- `IBLOCK_SECTION` — массив ID; `PROPERTY_VALUES` — ключи совпадают с `CODE`/`ID` существующих свойств инфоблока.
- Картинки задаются через `CFile::MakeFileArray`, а не строкой пути.

**Живой Битрикс:**
- Запустить скрипт (CLI `php seed_catalog.php` при настроенном bootstrap, или через консольную команду/агент) и убедиться, что вернулись числовые ID.
- В админке: «Контент → инфоблок → Разделы и элементы» — раздел и элемент присутствуют, активны, привязка к разделу видна, картинка прогрузилась (есть `b_file.ID` в `PREVIEW_PICTURE`).
- Свойства: открыть элемент — значения `PROPERTY_VALUES` заполнены; для множественных видны все значения.
- На публичной странице (компонент `bitrix:news.list` / `catalog.section`) элемент появляется в нужном разделе; миниатюра рендерится через `CFile::ResizeImageGet`.

## ⚠️ Риски

- ⚠️ **Обязательные поля.** Без `NAME`, `IBLOCK_ID` (и практически всегда `ACTIVE='Y'`, иначе элемент скрыт от публички) запись отклоняется или контент не виден. Всегда задавать явно.
- ⚠️ **Молчаливый провал без проверки результата.** `Add` возвращает `false`/пустой ID при ошибке валидации и НЕ бросает исключение. Обязательно проверять результат и читать `$obj->LAST_ERROR`, иначе данные «теряются» без следов.
- ⚠️ **ORM-запись минует побочные эффекты** (события, ресайз, индекс, кэш, nested-set, права) — для наполнения с полным циклом использовать legacy `Add`.
- ⚠️ **Картинки — только через `CFile`.** Прямая запись в `b_file` через `FileTable` запрещена by design; чужие файлы не удалять `unlink` (останутся записи и `resize_cache`) — только `CFile::Delete`.
- При импорте из внешних URL `MakeFileArray` скачивает файл (с отключением приватных IP); проверять, что массив не `false`, перед записью.
- Включить настройку `main.control_file_duplicates = Y`, чтобы одинаковые картинки (например, SKU) не плодили файлы в `b_file`.

## Связано

- `recipes/02-create-iblock.md` — создание типа инфоблока, инфоблока (`API_CODE`, `VERSION=2`) и свойств (предшествует наполнению).
- `recipes/05-query-elements.md` — чтение элементов (`CIBlockElement::GetList`, два прохода; D7 `compileEntity`).
- `../api-map.md` — работа с файлами и ресайз (`CFile::ResizeImageGet`, `PROPORTIONAL`/`EXACT`).
- `kb/api-map.md` §3 «Инфоблоки», §8 «Файлы и медиа (CFile)» — выбор версии API по задаче.
- `kb/conventions.md` §5 — инвариант: при ORM-записи элементов побочные эффекты не выполняются; проверять `isSuccess()` для ORM.
