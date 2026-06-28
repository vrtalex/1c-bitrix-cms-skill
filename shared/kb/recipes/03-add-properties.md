# Рецепт 03 — Добавить свойства инфоблока

> Основан на изучении ядра «1С-Битрикс: Управление сайтом» (модуль iblock `25.300.0`, ядро `26.150.0`) и официальной документации вендора.
> Две поддерживаемые версии API: **legacy** (`CIBlockProperty`) и **D7** (`\Bitrix\Iblock\PropertyTable`).

## Цель

Программно создать свойства существующего инфоблока: строки, числа, списки (с вариантами), привязки к элементам/разделам, файлы; одиночные и множественные, обязательные, с символьным кодом (`CODE`). Цель — воспроизводимая структура (миграция/деплой), а не ручная настройка через админку.

## Когда применять

- Готовите контентную модель кодом (после рецепта `02-create-iblock`), чтобы её можно было повторить на dev/stage/prod.
- Нужны свойства, которые потом читаются компонентами (`PROPERTY_CODE`) или D7-ORM (поля `Element<ApiCode>Table`).
- Добавляете поля к уже наполненному инфоблоку (свойство добавляется безопасно — старые элементы получают пустое значение).

Не применяйте этот рецепт для значений в элементах — установка значений свойств у элемента это `CIBlockElement::SetPropertyValuesEx()` (рецепт `04-fill-elements`).

## Шаги

1. Подключить модуль: `Loader::includeModule('iblock')` с проверкой результата.
2. Определить целевой `IBLOCK_ID` (по `CODE`/`API_CODE` инфоблока), а не хардкодить число.
3. Перед созданием проверить, что свойство с таким `CODE` ещё не существует (идемпотентность миграции).
4. Собрать массив полей свойства: `IBLOCK_ID`, `NAME`, `CODE`, `PROPERTY_TYPE`, при необходимости `USER_TYPE`, `MULTIPLE`, `IS_REQUIRED`, `SORT`.
5. Для типа `L` (список) передать варианты в ключе `VALUES` (для legacy `CIBlockProperty::Add`) или добавить их отдельно после создания свойства (для D7).
6. Создать свойство; проверить возвращённый ID, при ошибке прочитать `$prop->LAST_ERROR`.
7. После всех изменений сбросить кэш инфоблочного компонентного кэша (см. «Проверка»).

## Рабочий сниппет

`/local/php_interface/migrations/iblock_add_properties.php` — запускается из-под админа (CLI-скрипт с прологом или одноразовый агент).

```php
<?php
// /local/php_interface/migrations/iblock_add_properties.php
// CLI-only: иначе публичный привилегированный эндпоинт (создание свойств ИБ) для любого посетителя.
if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }

use Bitrix\Main\Loader;
use Bitrix\Iblock\IblockTable;

require $_SERVER['DOCUMENT_ROOT'] . '/bitrix/modules/main/include/prolog_before.php';

if (!Loader::includeModule('iblock')) {
	throw new \RuntimeException('iblock module is not installed');
}

// 1. Найти инфоблок по API_CODE (надёжнее, чем числовой ID)
$iblock = IblockTable::getRow([
	'select' => ['ID'],
	'filter' => ['=API_CODE' => 'news'],
]);
if (!$iblock) {
	throw new \RuntimeException('iblock with API_CODE=news not found');
}
$iblockId = (int)$iblock['ID'];

// 2. Хелпер: создать свойство только если его ещё нет (идемпотентно)
$addProperty = static function (array $fields) use ($iblockId): int {
	$fields['IBLOCK_ID'] = $iblockId;

	$existing = \CIBlockProperty::GetList([], [
		'IBLOCK_ID' => $iblockId,
		'CODE'      => $fields['CODE'],
	])->Fetch();
	if ($existing) {
		return (int)$existing['ID'];
	}

	$obj = new \CIBlockProperty();
	$id  = $obj->Add($fields);          // classes/general/iblockproperty.php
	if (!$id) {
		throw new \RuntimeException("property {$fields['CODE']}: {$obj->LAST_ERROR}");
	}
	return (int)$id;
};

// 3. S — строка
$addProperty([
	'NAME' => 'Автор', 'CODE' => 'AUTHOR', 'PROPERTY_TYPE' => 'S',
	'SORT' => 100, 'MULTIPLE' => 'N', 'IS_REQUIRED' => 'N',
]);

// 4. N — число (обязательное)
$addProperty([
	'NAME' => 'Время чтения, мин', 'CODE' => 'READ_TIME', 'PROPERTY_TYPE' => 'N',
	'SORT' => 200, 'MULTIPLE' => 'N', 'IS_REQUIRED' => 'Y',
]);

// 5. L — список с вариантами (XML_ID — стабильный ключ варианта)
$addProperty([
	'NAME' => 'Рубрика', 'CODE' => 'RUBRIC', 'PROPERTY_TYPE' => 'L',
	'SORT' => 300, 'MULTIPLE' => 'N', 'LIST_TYPE' => 'L', // L = выпадающий, C = чекбоксы
	'VALUES' => [
		['VALUE' => 'Новости', 'XML_ID' => 'news', 'DEF' => 'Y', 'SORT' => 10],
		['VALUE' => 'Аналитика', 'XML_ID' => 'analytics', 'SORT' => 20],
		['VALUE' => 'Интервью', 'XML_ID' => 'interview', 'SORT' => 30],
	],
]);

// 6. E — привязка к элементам (множественная), с указанием инфоблока-источника
$addProperty([
	'NAME' => 'Похожие материалы', 'CODE' => 'RELATED', 'PROPERTY_TYPE' => 'E',
	'SORT' => 400, 'MULTIPLE' => 'Y',
	'LINK_IBLOCK_ID' => $iblockId,   // из какого ИБ выбирать элементы
]);

// 7. F — файл (множественный) = галерея
$addProperty([
	'NAME' => 'Галерея', 'CODE' => 'GALLERY', 'PROPERTY_TYPE' => 'F',
	'SORT' => 500, 'MULTIPLE' => 'Y',
	'FILE_TYPE' => 'jpg, jpeg, png, webp',
]);

// 8. G — привязка к разделам (множественная)
$addProperty([
	'NAME' => 'Доп. разделы', 'CODE' => 'EXTRA_SECTIONS', 'PROPERTY_TYPE' => 'G',
	'SORT' => 600, 'MULTIPLE' => 'Y',
	'LINK_IBLOCK_ID' => $iblockId,
]);

echo "done\n";
```

### Вариант D7 (`PropertyTable::add`) + варианты списка отдельно

`PropertyTable::add` создаёт строку свойства, но **не** принимает встроенный массив `VALUES` — варианты списка добавляются отдельно через `PropertyEnumerationTable::add`.

```php
use Bitrix\Iblock\PropertyTable;
use Bitrix\Iblock\PropertyEnumerationTable;

// Строковое свойство
$res = PropertyTable::add([
	'IBLOCK_ID' => $iblockId, 'NAME' => 'Подзаголовок', 'CODE' => 'SUBTITLE',
	'PROPERTY_TYPE' => PropertyTable::TYPE_STRING, // 'S'
	'MULTIPLE' => 'N', 'IS_REQUIRED' => 'N', 'SORT' => 700,
]);
if (!$res->isSuccess()) {
	throw new \RuntimeException(implode('; ', $res->getErrorMessages()));
}

// Список + варианты
$listRes = PropertyTable::add([
	'IBLOCK_ID' => $iblockId, 'NAME' => 'Статус', 'CODE' => 'STATUS',
	'PROPERTY_TYPE' => PropertyTable::TYPE_LIST, // 'L'
	'MULTIPLE' => 'N', 'SORT' => 800,
]);
$propId = $listRes->getId();
foreach ([['draft', 'Черновик'], ['published', 'Опубликовано']] as $i => [$xml, $label]) {
	PropertyEnumerationTable::add([
		'PROPERTY_ID' => $propId, 'VALUE' => $label,
		'XML_ID' => $xml, 'SORT' => ($i + 1) * 10,
		'DEF' => $i === 0 ? 'Y' : 'N',
	]);
}
```

Константы типов (`lib/propertytable.php`): `TYPE_STRING='S'`, `TYPE_NUMBER='N'`, `TYPE_FILE='F'`, `TYPE_LIST='L'`, `TYPE_ELEMENT='E'`, `TYPE_SECTION='G'`.

## Выбор API (что рекомендовано для ЭТОЙ задачи)

**Для создания свойств рекомендуется legacy `CIBlockProperty::Add`.** Причины именно для этой задачи:

- один вызов делает всё: для типа `L` варианты передаются прямо в `VALUES`, не нужен отдельный проход по `PropertyEnumerationTable`;
- это тот же путь, что выполняет мастер и XML-импорт, — структура получается такой, какую ожидают штатные компоненты;
- `LINK_IBLOCK_ID`, `FILE_TYPE`, `LIST_TYPE`, `DEFAULT_VALUE` принимаются единым массивом.

**`PropertyTable::add` (D7)** уместен, когда создание свойств — часть более крупного ORM-кода (транзакции, `Result`-объекты, единый стиль модуля). Учитывайте, что варианты списка добавляются вторым вызовом, а после изменения набора свойств у инфоблока с заполненным `API_CODE` нужно учитывать перекомпиляцию ORM-сущности `Element<ApiCode>Table` (см. рецепт `01-d7-orm-elements`).

Тип свойства выбирайте по смыслу данных: текст без разметки → `S`; число для сортировки/фильтра → `N`; фиксированный набор значений → `L`; ссылка на другой элемент каталога/новостей → `E`; набор картинок/документов → `F`; связь с разделами → `G`. Для богатого текста, дат, привязки к HL-справочнику используйте user-type (`USER_TYPE` = `HTML`, `Date`, `DateTime`, `directory`) — см. рецепт `05-user-type-properties`.

## Проверка

**Режим «только файлы» (без живого Битрикс):**

- статический разбор сниппета: `php -l /local/php_interface/migrations/iblock_add_properties.php`;
- по чек-листу: у каждого свойства задан `CODE` (латиница, верхний регистр), `PROPERTY_TYPE` из набора `S/N/L/E/F/G`, для `E`/`G` указан `LINK_IBLOCK_ID`, для `L` есть непустой `VALUES`/`PropertyEnumerationTable::add`, множественные помечены `MULTIPLE => 'Y'`, обязательные — `IS_REQUIRED => 'Y'`.

**Живой Битрикс:**

1. Запустить миграцию (CLI с прологом или одноразовый агент), убедиться, что в выводе нет `LAST_ERROR`.
2. Проверить наличие свойств кодом:
   ```php
   $rs = \CIBlockProperty::GetList([], ['IBLOCK_ID' => $iblockId]);
   while ($p = $rs->Fetch()) { echo "{$p['CODE']} / {$p['PROPERTY_TYPE']} / mult={$p['MULTIPLE']}\n"; }
   ```
3. Для списков сверить варианты: `\CIBlockPropertyEnum::GetList([], ['IBLOCK_ID' => $iblockId, 'CODE' => 'RUBRIC'])`.
4. В админке: «Контент → инфоблок → Настройки → Свойства» — свойство видно, тип/множественность/обязательность совпадают.
5. Повторно запустить миграцию — благодаря проверке существования она не создаёт дубль (идемпотентность).
6. Сбросить кэш: «Настройки → Highload-кэш / Очистка кэша» либо `BXClearCache(true)` — чтобы компоненты увидели новое свойство.

## ⚠️ Риски

- ⚠️ `CODE` — основной стабильный идентификатор свойства в коде компонентов и в D7-ORM. Переименование `CODE` у заполненного свойства ломает выборки `PROPERTY_<CODE>` и поля ORM-сущности. Меняйте `NAME`, но не `CODE`.
- ⚠️ Запуск без проверки существования создаёт **дубли свойств** с одинаковым `CODE` — выборки становятся неоднозначными. Всегда проверяйте наличие перед `Add` (как в сниппете).
- ⚠️ Удаление свойства (`CIBlockProperty::Delete`) удаляет все значения этого свойства у всех элементов без возможности отката — выполняйте только на тестовой копии и после бэкапа.
- Для `L` ключ `XML_ID` варианта — стабильная привязка значения. Без явного `XML_ID` система генерирует свой; при повторном импорте варианты могут задвоиться. Задавайте `XML_ID` явно.
- Для `E`/`G` без `LINK_IBLOCK_ID` свойство создастся, но в форме элемента выбор будет вестись по всем инфоблокам — ограничивайте источник явно.
- Выполняйте миграции структуры на тестовой копии в режиме разработки, с актуальным бэкапом (общий инвариант конвенций).
- ⚠️ Скрипт миграции `/local/php_interface/migrations/iblock_add_properties.php` мутирует структуру инфоблока — оставленный в дереве проекта, он становится публичным эндпоинтом, создающим свойства при каждом обращении. Запускайте только из CLI ИЛИ закройте проверкой `IsAdmin()`/CLI-режима в начале файла; держите вне document root (или закройте HTTP-доступ к каталогу `migrations/`); удалите скрипт сразу после успешного прогона.

## Связано

- `02-create-iblock` — создание типа инфоблока и самого инфоблока (`CIBlockType::Add` / `CIBlock::Add`), задание `API_CODE` и `VERSION`.
- `04-fill-elements` — запись значений созданных свойств у элементов (`SetPropertyValuesEx`, `PROPERTY_VALUES`).
- `05-user-type-properties` — свойства user-type (`HTML`, `Date`, `directory`/HL-справочник).
- `01-d7-orm-elements` — чтение свойств через скомпилированную ORM-сущность `Element<ApiCode>Table`.
- kb: `api-map.md` (строка про `PropertyTable::add` / `CIBlockProperty::Add`), `conventions.md` (раздел про /local, бэкап, режим разработки), `../api-map.md` (типы свойств, схема `b_iblock_property`/`b_iblock_property_enum`).
