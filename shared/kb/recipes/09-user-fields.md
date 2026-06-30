# 09. Пользовательские поля (UF)

## Цель

Добавить произвольные поля к сущности, у которой есть строковый `ENTITY_ID` (раздел инфоблока, запись HL-блока, заказ, пользователь), и научиться читать/писать значения. UF — сквозной механизм модуля `main`: метаданные поля живут в `b_user_field`, значения — в служебных таблицах `b_uts_*` (немножественные) и `b_utm_*` (множественные).

## Когда применять

- **Корп-сайт:** доп. свойства РАЗДЕЛОВ инфоблока (баннер раздела, SEO-текст, иконка категории) — у разделов нет «свойств инфоблока», только UF. Доп. поля профиля пользователя (entity `USER`).
- **Магазин:** доп. поля ЗАКАЗА (entity `ORDER`) — источник заказа, трек-номер, комментарий менеджера; доп. поля разделов каталога; справочники на HL-блоках (бренды, цвета, размеры — entity `HLBLOCK_{ID}`).
- НЕ применять к **элементам инфоблока**: их доп. данные делаются через «свойства инфоблока» (`CIBlockProperty`), отдельный механизм. UF разделов — да: entity `IBLOCK_{ID}_SECTION`.

| Сущность | ENTITY_ID |
|----------|-----------|
| Раздел инфоблока | `IBLOCK_{ID}_SECTION` |
| Пользователь | `USER` |
| Заказ магазина | `ORDER` |
| Запись HL-блока | `HLBLOCK_{ID}` |

## Шаги

1. Подключить ядро (`prolog_before.php`) и при необходимости модуль сущности (`iblock`, `sale`, `highloadblock`).
2. Метаданные поля создать через `CUserTypeEntity::Add($arFields)`. Имя обязано начинаться с `UF_`, символы `[0-9A-Z_]`, длина 4–50.
3. Для типа `enum` варианты задать отдельно через `CUserFieldEnum::SetEnumValues($fieldId, $values)`.
4. Значения читать/писать через `$USER_FIELD_MANAGER->GetUserFields()` / `->Update()`.
5. После прямых правок БД сбросить кэш метаданных: `CUserTypeEntity::cleanCache()`.

Типы `USER_TYPE_ID`: `string`, `integer`, `double`, `datetime`, `date`, `boolean`, `url`, `enum`, `file`, `iblock_element`, `iblock_section`.

## Рабочий сниппет

Файл: `/local/php_interface/migrations/add_uf_fields.php` (одноразовый CLI-скрипт миграции).

```php
<?php
// /local/php_interface/migrations/add_uf_fields.php
// Запуск: php -d display_errors=1 add_uf_fields.php  (из DOCUMENT_ROOT, при подключённом ядре)
// CLI-only: иначе публичный привилегированный эндпоинт (мутация схемы БД в обход прав) для любого посетителя.
if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }

use Bitrix\Main\Loader;

$_SERVER['DOCUMENT_ROOT'] = realpath(__DIR__ . '/../../..');
define('NO_KEEP_STATISTIC', true);
define('NOT_CHECK_PERMISSIONS', true);
require $_SERVER['DOCUMENT_ROOT'] . '/bitrix/modules/main/include/prolog_before.php';

Loader::includeModule('iblock');
Loader::includeModule('sale');

$iblockId = 5; // ID каталога/раздела — подставить реальный

// --- Пример 1: файл-баннер у разделов инфоблока (корп-сайт) ---
$obUF = new CUserTypeEntity();
$bannerId = $obUF->Add([
    'ENTITY_ID'         => 'IBLOCK_' . $iblockId . '_SECTION',
    'FIELD_NAME'        => 'UF_SECTION_BANNER', // неизменяемо после создания
    'USER_TYPE_ID'      => 'file',
    'MULTIPLE'          => 'N',
    'MANDATORY'         => 'N',
    'SHOW_IN_LIST'      => 'Y',
    'EDIT_IN_LIST'      => 'Y',
    'SETTINGS'          => [], // зависит от типа
    'EDIT_FORM_LABEL'   => ['ru' => 'Баннер раздела', 'en' => 'Section banner'],
    'LIST_COLUMN_LABEL' => ['ru' => 'Баннер', 'en' => 'Banner'],
]);
echo $bannerId ? "UF_SECTION_BANNER id={$bannerId}\n" : "FAIL banner\n";
// ALTER TABLE b_uts_iblock_{ID}_section ADD UF_SECTION_BANNER ... делается внутри Add()

// --- Пример 2: список-справочник (enum) для заказа (магазин) ---
$sourceId = $obUF->Add([
    'ENTITY_ID'       => 'ORDER',
    'FIELD_NAME'      => 'UF_SOURCE',
    'USER_TYPE_ID'    => 'enum',
    'MULTIPLE'        => 'N',
    'MANDATORY'       => 'N',
    'EDIT_FORM_LABEL' => ['ru' => 'Источник заказа', 'en' => 'Order source'],
]);
if ($sourceId) {
    $obEnum = new CUserFieldEnum();
    $obEnum->SetEnumValues($sourceId, [
        'n0' => ['VALUE' => 'Сайт',       'DEF' => 'Y', 'SORT' => 100, 'XML_ID' => 'site'],
        'n1' => ['VALUE' => 'Телефон',    'DEF' => 'N', 'SORT' => 200, 'XML_ID' => 'phone'],
        'n2' => ['VALUE' => 'Мессенджер', 'DEF' => 'N', 'SORT' => 300, 'XML_ID' => 'messenger'],
    ]);
    echo "UF_SOURCE id={$sourceId} + enum values set\n";
}

// --- Чтение/запись значений раздела ---
global $USER_FIELD_MANAGER;
$entity    = 'IBLOCK_' . $iblockId . '_SECTION';
$sectionId = 12; // ID раздела

$uf = $USER_FIELD_MANAGER->GetUserFields($entity, $sectionId, LANGUAGE_ID);
$currentBanner = $uf['UF_SECTION_BANNER']['VALUE'] ?? null;

$USER_FIELD_MANAGER->Update($entity, $sectionId, ['UF_SECTION_BANNER' => $newFileId]);
```

HL-блок как словарь (после `compileEntity` поля `UF_*` — обычные ORM-поля):

```php
$entity    = \Bitrix\Highloadblock\HighloadBlockTable::compileEntity($hlId);
$dataClass = $entity->getDataClass();
$dataClass::add(['UF_NAME' => 'Красный', 'UF_XML_ID' => 'red', 'UF_FILE' => $fileId]);
$rows = $dataClass::getList(['select' => ['UF_NAME', 'UF_FILE']])->fetchAll();
```

## Выбор API

В платформе сосуществуют две поддерживаемые версии API.

- **Метаданные поля (CRUD описаний):** `CUserTypeEntity` (он же `CAllUserTypeEntity`) — это рабочий, не deprecated API; единого аналога «всё-в-одном» в `\Bitrix\Main\` нет. Методы: `Add`, `Update` (только SORT/MANDATORY/SHOW_*/EDIT_IN_LIST/IS_SEARCHABLE/SETTINGS/метки), `Delete`, `DropEntity`, `GetList`.
- **Значения (чтение/запись):** `$USER_FIELD_MANAGER` (`CUserTypeManager`). `GetUserFields($entity_id, $value_id, $LANG)` — чтение, `Update($entity_id, $value_id, $arFields)` — запись, `CheckFields(...)` — валидация, `GetPublicView($field)` — готовый HTML для публички.
- **ORM-доступ:** `UserFieldTable` динамически подмешивает `UF_*` в ORM-сущность владельца, поэтому в заказах (`\Bitrix\Sale\Order`) и HL-записях поля `UF_*` доступны в `getList(['select' => ['UF_*']])`.
- **Типы:** трактуйте как D7-классы `\Bitrix\Main\UserField\Types\*` (`StringType`, `EnumType`, `FileType`...). Легаси-обёртки `C*UserType*` (deprecated since main 20.0.700) проксируют в них; именно эти `C*`-классы регистрируют встроенные типы через событие `OnUserTypeBuildList` — не удаляйте их, но в своём коде наследуйте `BaseType`.

Памятка по именам `Update`: у менеджера `Update($entity_id, $value_id, $arFields)` пишет значения; у `CUserTypeEntity::Update($field_id, $arFields)` меняет метаданные. Сигнатуры легко перепутать.

## Проверка

**Режим «только файлы»** (без живого Битрикса):

```bash
# имя UF корректно: UF_, символы [0-9A-Z_], длина 4..50
grep -REn "FIELD_NAME\s*=>\s*'UF_[0-9A-Z_]{1,47}'" /local/php_interface/migrations/
# не перепутаны сигнатуры Update менеджера и сущности
grep -REn 'USER_FIELD_MANAGER->Update' /local/   # ожидаем 3 аргумента: entity_id, value_id, arFields
# PHP-синтаксис скрипта миграции
php -l /local/php_interface/migrations/add_uf_fields.php
```

**Режим «живой Битрикс»:**

```bash
# выполнить миграцию
php -d display_errors=1 /path/to/DOCUMENT_ROOT/local/php_interface/migrations/add_uf_fields.php
# проверить, что метаданные созданы (через CLI с подключённым ядром)
php -r 'require "/path/DOCUMENT_ROOT/bitrix/modules/main/include/prolog_before.php";
  $r = CUserTypeEntity::GetList([], ["ENTITY_ID" => "ORDER", "FIELD_NAME" => "UF_SOURCE"]);
  var_dump($r->Fetch());'
# проверить служебную колонку (значения немножественных полей раздела)
mysql -e "SHOW COLUMNS FROM b_uts_iblock_5_section LIKE 'UF_SECTION_BANNER';" bitrix_db
```

В админке UF разделов рисуются автоматически на вкладке инфоблока; UF заказа — на форме заказа; значение через публичный рендер: `$USER_FIELD_MANAGER->GetPublicView($fields['UF_SECTION_BANNER'])`.

## ⚠️ Риски

- ⚠️ **`FIELD_NAME`, `ENTITY_ID`, `USER_TYPE_ID`, `MULTIPLE` неизменяемы после создания.** `Update` метаданных молча отбрасывает эти ключи. Сменить тип или множественность можно только удалением и пересозданием поля — с потерей всех значений. Проверяйте имя и тип до `Add`.
- ⚠️ **`Delete()` поля удаляет значения, а для `file` — физические файлы на диске, для `enum` — варианты из `b_user_field_enum`.** Операция необратима; делайте бэкап перед массовым удалением.
- **Удаление колонки отложено:** `Delete()` не дропает колонку `b_uts_*` сразу, а ставит агент `syncColumnsAgent` на +30 сек. При немедленном пересоздании поля с тем же именем `Add()` инициирует синхронизацию сам, но в скриптах массового пересоздания учитывайте лаг.
- **Кэш метаданных:** список UF кэшируется. После прямых правок БД зовите `CUserTypeEntity::cleanCache()` / `$USER_FIELD_MANAGER->CleanCache()`, иначе новые поля «не видны».
- **`SETTINGS` сериализуются и чистятся** методом `prepareSettings` типа: произвольные ключи отбрасываются, если тип их не пропускает.
- **Множественные значения хранятся смешанно:** «короткий» кэш в `b_uts_*`, сами значения построчно в `b_utm_*`. Не редактируйте `b_utm_*` напрямую без понимания связки — пишите через менеджер.
- **Элементы инфоблока не используют UF** для доп.данных (это `CIBlockProperty`). UF применимы к разделам, пользователям, заказам, HL-записям.
- ⚠️ **Скрипт миграции — только из CLI и удалить сразу после прогона.** Файл `/local/php_interface/migrations/add_uf_fields.php` мутирует схему БД и определяет `NOT_CHECK_PERMISSIONS=true` — оставленный в дереве проекта, он становится публичным эндпоинтом, дёргающим `CUserTypeEntity::Add()` в обход прав. Запускайте только из CLI ИЛИ закройте проверкой `IsAdmin()`/CLI-режима в начале файла; держите вне document root (или закройте HTTP-доступ к каталогу `migrations/`); удалите скрипт сразу после успешного прогона.

## Связано

- `04-sections-elements.md` — инфоблоки, разделы и свойства элементов (`CIBlockProperty`).
- `../api-map.md` — HL-блоки (UF — основные поля структуры); заказы магазина и доступ к `UF_*` через ORM `\Bitrix\Sale\Order`.
