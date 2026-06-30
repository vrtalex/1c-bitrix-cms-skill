# Рецепт 01 (commerce): Подключить каталог над инфоблоком (товары, SKU, единицы)

Под-скилл: `1c-bitrix-cms-commerce` • Платформа: «1С-Битрикс: Управление сайтом», ядро 26.x, модуль `catalog` 25.x (+ `iblock`, `currency`, для продаж — `sale`).

## Цель
Сделать из обычного инфоблока **товарный каталог**: зарегистрировать инфоблок как каталог (`b_catalog_iblock`), превратить элемент в товар (строка `b_catalog_product`: количество, единица измерения, доступность, тип), при необходимости добавить **торговые предложения (SKU)** через отдельный инфоблок-предложений. Результат — структура, на которой работают витринные компоненты цен и провайдер заказа для модуля `sale`.

## Когда применять
- Строите интернет-магазин или каталог с ценами: инфоблок уже создан, нужно «надеть» на него каталог.
- Нужна **воспроизводимая** установка каталога (миграция, перенос стендов, CI), а не ручная отметка «инфоблок является торговым каталогом» в админке.
- Заводите товары с вариациями (цвет/размер) — нужен слой SKU/offers.

Если каталог уже зарегистрирован и нужно только наполнять/выводить — переходите к рецептам по элементам и витрине. Создание самого инфоблока — см. `../02-create-iblock.md` и `../03-add-properties.md` (это предусловие).

## Шаги
1. **Создайте инфоблок товаров** (рецепт `../02-create-iblock.md`), получите `IBLOCK_ID`. Желательно задать `API_CODE` и `VERSION=2`.
2. **Зарегистрируйте инфоблок как каталог** — запись в `b_catalog_iblock` (`CCatalog::Add` или `CatalogIblockTable::add`). Без неё компоненты цен не отрисуют цену, а `GetOptimalPrice` вернёт пусто.
3. **Убедитесь, что есть базовый тип цены** (`GroupTable::getBasePriceType()` — тип с `BASE='Y'`). В новой установке он создаётся. К нему привязывают розничную цену.
4. **Подберите единицу измерения** (`MeasureTable` / ОКЕИ-код, напр. шт. = `796`). Понадобится поле `MEASURE` товара.
5. **Создайте элемент инфоблока** (`CIBlockElement::Add`) — получите `$elementId`.
6. **Сделайте элемент товаром** — строка `b_catalog_product` через `Model\Product::add` (или `CCatalogProduct::Add`). **ID товара = ID элемента инфоблока.**
7. **(Опц.) Торговые предложения (SKU):** второй инфоблок (предложений) со свойством «привязка к элементу», его ID → в `CatalogIblockTable.SKU_PROPERTY_ID`; родитель получает `TYPE = TYPE_SKU`, каждое предложение — `TYPE = TYPE_OFFER`.
8. Запустите установочный скрипт **один раз** (CLI/временный URL), затем удалите из публичной зоны.

## Рабочий сниппет
Разовый установочный скрипт. Положите в `/local/` (не в `bitrix/`), запустите один раз, затем удалите.

Файл: `/local/install/commerce_01_catalog_setup.php`

```php
<?php
// Разовый установочный скрипт. ЗАПУСТИТЬ ОДИН РАЗ, затем УДАЛИТЬ.
require($_SERVER['DOCUMENT_ROOT'] . '/bitrix/modules/main/include/prolog_before.php');

use Bitrix\Main\Loader;
use Bitrix\Catalog\ProductTable;
use Bitrix\Catalog\GroupTable;
use Bitrix\Catalog\Model\Product;
use Bitrix\Catalog\Model\Price;
use Bitrix\Catalog\CatalogIblockTable;

if (!Loader::includeModule('iblock') || !Loader::includeModule('catalog')) {
    die('Modules iblock/catalog are not installed');
}
// Цены требуют валюты: без currency валюта цены не создастся.
Loader::includeModule('currency');

$report = [];
$iblockId = 7; // ID существующего инфоблока товаров

// 1. Зарегистрировать инфоблок как каталог (b_catalog_iblock).
//    Идемпотентность: не создавать запись повторно.
$alreadyCatalog = CatalogIblockTable::getList([
    'filter' => ['=IBLOCK_ID' => $iblockId],
    'select' => ['IBLOCK_ID'],
    'limit'  => 1,
])->fetch();

if (!$alreadyCatalog) {
    // Legacy-фасад: одной строкой регистрирует обычный каталог (без offers).
    CCatalog::Add([
        'IBLOCK_ID'    => $iblockId,
        'YANDEX_EXPORT'=> 'N',
        'SUBSCRIPTION' => 'N',
    ]);
    // D7-эквивалент:
    // CatalogIblockTable::add([
    //     'IBLOCK_ID'         => $iblockId,
    //     'PRODUCT_IBLOCK_ID' => 0, // 0 — это инфоблок товаров, не offers
    //     'SKU_PROPERTY_ID'   => 0,
    // ]);
    $report[] = "Инфоблок {$iblockId} зарегистрирован как каталог.";
}

// 2. Базовый тип цены (BASE='Y') — к нему вешаем розничную цену.
$base = GroupTable::getBasePriceType();
if (!$base) {
    die('Базовый тип цены (BASE=Y) не найден — проверьте установку catalog.');
}
$baseTypeId = (int)$base['ID'];

// 3. Единица измерения: шт. (ОКЕИ 796). Берём дефолтную из справочника.
$measure = \Bitrix\Catalog\MeasureTable::getList([
    'filter' => ['=CODE' => 796],
    'select' => ['ID'],
    'limit'  => 1,
])->fetch();
$measureId = $measure ? (int)$measure['ID'] : null;

// 4. Создать элемент инфоблока (товар как контентная сущность).
$el = new CIBlockElement;
$elementId = (int)$el->Add([
    'IBLOCK_ID' => $iblockId,
    'NAME'      => 'Тестовый товар',
    'ACTIVE'    => 'Y',
]);
if ($elementId <= 0) {
    die('CIBlockElement::Add: ' . $el->LAST_ERROR);
}

// 5. Сделать элемент товаром (строка b_catalog_product).
//    ID товара ВСЕГДА равен ID элемента инфоблока.
$addRes = Product::add([
    'ID'             => $elementId,
    'QUANTITY'       => 100,
    'QUANTITY_TRACE' => 'N',
    'CAN_BUY_ZERO'   => 'N',
    'WEIGHT'         => 500,           // граммы
    'MEASURE'        => $measureId,
    'TYPE'           => ProductTable::TYPE_PRODUCT, // 1 — простой товар
]);
// AVAILABLE не задаём вслепую: его вычисляет Model на основе
// QUANTITY / CAN_BUY_ZERO / QUANTITY_TRACE.
if (!$addRes->isSuccess()) {
    die('Product::add: ' . implode(', ', $addRes->getErrorMessages()));
}
// legacy-эквивалент: CCatalogProduct::Add(['ID'=>$elementId, ...]);

// 6. Назначить розничную цену на базовый тип.
$priceRes = Price::add(['fields' => [
    'PRODUCT_ID'       => $elementId,
    'CATALOG_GROUP_ID' => $baseTypeId,
    'PRICE'            => 1990,
    'CURRENCY'         => 'RUB',
]]);
if (!$priceRes->isSuccess()) {
    die('Price::add: ' . implode(', ', $priceRes->getErrorMessages()));
}
// legacy-эквивалент:
// CPrice::Add(['PRODUCT_ID'=>$elementId,'CATALOG_GROUP_ID'=>$baseTypeId,
//              'PRICE'=>1990,'CURRENCY'=>'RUB']);

$report[] = "Товар {$elementId} создан, цена назначена.";
echo implode("\n", $report) . "\nЭЛЕМЕНТ_ID = {$elementId}\n";
```

### Торговые предложения (SKU) — опциональный блок
Сценарий «товар с вариациями» (цвет/размер). Нужны **два** инфоблока: товаров и предложений (offers).

```php
// Дано: $iblockId — инфоблок товаров, $offersIblockId — инфоблок предложений,
//       $skuPropertyId — ID свойства «привязка к элементу» в инфоблоке offers
//       (тип свойства E — привязка к элементу инфоблока товаров).

// Связать инфоблок предложений с инфоблоком товаров.
CatalogIblockTable::add([
    'IBLOCK_ID'         => $offersIblockId,
    'PRODUCT_IBLOCK_ID' => $iblockId,      // ← указывает на инфоблок товаров
    'SKU_PROPERTY_ID'   => $skuPropertyId, // ← свойство-привязка offer → товар
]);

// Родитель (товар в инфоблоке товаров) — TYPE_SKU.
Product::update($parentElementId, ['TYPE' => ProductTable::TYPE_SKU]); // 3

// Каждое предложение (элемент инфоблока offers) — TYPE_OFFER.
Product::add([
    'ID'       => $offerElementId,
    'QUANTITY' => 10,
    'MEASURE'  => $measureId,
    'TYPE'     => ProductTable::TYPE_OFFER, // 4
]);
// + у элемента offer проставить значение свойства-привязки на $parentElementId.

// Чтение связки (по инфоблоку предложений):
// CCatalogSku::GetInfoByOfferIBlock($offersIblockId);
// По offer → родитель: CCatalogSku::GetProductInfo($offerElementId);
```

## Выбор API
Для **создания товара/цены** рекомендуется **Model-слой** (`Bitrix\Catalog\Model\Product::add` / `Model\Price::add`):
- Это «движок» add/update/delete: он пересчитывает доступность (`AVAILABLE`), наборы, рассылку подписок. Legacy-фасады (`CCatalogProduct::Add`, `CPrice::Add`) — тонкие обёртки, делегирующие сюда же. Это две поддерживаемые версии API — обе валидны; Model возвращает типизированный `Result` и точнее по диагностике.
- Для **регистрации каталога** legacy `CCatalog::Add` короче (один вызов для обычного каталога); `CatalogIblockTable::add` уместен, когда проект стандартизирован на ORM и нужно явно задать `PRODUCT_IBLOCK_ID`/`SKU_PROPERTY_ID` для offers.
- Для **чтения** — ORM `getList` (`ProductTable`, `PriceTable`, `GroupTable`, `MeasureTable`) и логика SKU через `CCatalogSku`.

⚠️ **Объектная v2-модель (`Bitrix\Catalog\v2\...`, `ProductFactory`/`Sku`) помечена `@internal` и «alpha, not stable».** Она применяется внутри карточки товара, но в генерируемом коде на неё опираться не следует — используйте Model-слой и legacy-фасады.

Цену **к показу/покупке** не читайте напрямую из `b_catalog_price` — мимо скидок, НДС, групп пользователя и конвертации валют. В кастомном коде используйте `CCatalogProduct::GetOptimalPrice($id, $qty, $userGroups)`; в шаблонах витрины цены приходят через `CIBlockPriceTools::GetItemPrices`/`GetCatalogPrices`.

## Проверка
**Режим «только файлы» (без живого Битрикса):**
- Скрипт лежит в `/local/`, а не в `bitrix/`.
- В коде есть: `Loader::includeModule('catalog')` (+ `currency`), регистрация каталога (`CCatalog::Add` / `CatalogIblockTable::add`) с проверкой на дубль, получение `GroupTable::getBasePriceType()`, `Product::add` с явным `TYPE` и `MEASURE`, обработка `Result::isSuccess()`.
- ID товара передаётся равным `$elementId` (а не генерируется отдельно). Валюта цены задана и модуль `currency` подключён.
- Для SKU: задан `PRODUCT_IBLOCK_ID` и `SKU_PROPERTY_ID`, родитель `TYPE_SKU`, offer `TYPE_OFFER`.

**Режим «живой Битрикс»:**
- Скрипт печатает `ЭЛЕМЕНТ_ID = N`.
- Админка: «Магазин → Настройки → Торговый каталог» / у инфоблока активна вкладка «Торговый каталог»; у элемента появилась вкладка с количеством, ценой, единицей.
- Контроль кодом:
  ```php
  \Bitrix\Catalog\ProductTable::getList([
      'select' => ['ID','QUANTITY','AVAILABLE','TYPE','MEASURE'],
      'filter' => ['=ID' => $elementId],
  ])->fetch(); // AVAILABLE='Y' при QUANTITY>0
  $opt = CCatalogProduct::GetOptimalPrice($elementId, 1, $USER->GetUserGroupArray());
  // $opt['RESULT_PRICE']['DISCOUNT_PRICE'] — цена к покупке (не пусто)
  ```
- Для SKU: `CCatalogSku::GetInfoByOfferIBlock($offersIblockId)` возвращает связку (не пусто).

## ⚠️ Риски
- ⚠️ **Прямые INSERT в `b_catalog_product`/`b_catalog_price`** ломают пересчёт доступности, скидок и налогов — это потеря целостности данных каталога и заказа. Всегда через `Model\Product`/`Model\Price` (или legacy-фасады), которые делегируют в Model.
- ⚠️ **Скрипт-инсталлятор в публичной зоне — риск безопасности и повторного запуска.** Удалите файл сразу после прогона. Перед регистрацией каталога и созданием товара проверяйте существование, чтобы повторный запуск не создал дубль.
- ⚠️ **Цена для покупателя из `b_catalog_price` напрямую — риск неверной суммы заказа** (мимо скидок/НДС/валюты). Используйте `GetOptimalPrice` / `CIBlockPriceTools`.
- **ID товара = ID элемента инфоблока.** Нельзя создать товар без предварительно созданного элемента — `CCatalogProduct::Add` без `ID` вернёт `false`.
- **Без регистрации в `b_catalog_iblock`** инфоблок не считается каталогом: цены не отрисуются, `GetOptimalPrice` пуст.
- **`TYPE` обязателен для логики SKU.** Родитель — `TYPE_SKU` (3), offer — `TYPE_OFFER` (4); неверный тип ломает доступность и подбор предложений. `AVAILABLE` вычисляется (`calculateAvailable`), а не задаётся вслепую.
- **Зависимости.** Каталог требует `iblock` (товары) и `currency` (валюта цены обязательна); для продаж — `sale` (корзина/заказ через провайдер `Bitrix\Catalog\Product\CatalogProvider`).
- **Витринные компоненты (`catalog.element`, `catalog.section`) физически в модуле `iblock`**, не в `catalog` — искать витрину надо там.

## Связано
- `../02-create-iblock.md` — создание инфоблока товаров (предусловие этого рецепта).
- `../03-add-properties.md` — свойства, включая свойство «привязка к элементу» (тип E) для связки offer → товар.
- `../../00-overview.md` — карта под-скиллов и модулей платформы.
- `../../api-map.md` — модель iblock/catalog, две версии API, права, провайдер для `sale`.
