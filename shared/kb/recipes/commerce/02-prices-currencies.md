# Рецепт 02 (commerce): Цены и валюты товара

Под-скилл: `1c-bitrix-cms-commerce` • Платформа: «1С-Битрикс: Управление сайтом», ядро 26.x, модули `currency`, `catalog` 25.x, `sale`.

## Цель
Подготовить ценовую основу интернет-магазина: убедиться, что есть **базовая валюта** (модуль `currency`) и **базовый тип цены** `BASE` (модуль `catalog`), назначить товару розничную цену (`b_catalog_price`), привязать ставку НДС и узнать **цену к покупке** через `CCatalogProduct::GetOptimalPrice` (с учётом скидок, групп пользователей, НДС). Результат — товар, который корректно соберётся в корзину и заказ.

## Когда применять
- Создаёте товар и назначаете ему цену программно (миграция, импорт, CI), а не вручную в карточке.
- Нужно прочитать «настоящую» цену к оплате в кастомном коде (виджет, расчёт доставки, AJAX).
- Заводите второй тип цены (опт, для группы) или ставку НДС.

Предусловие: инфоблок уже создан и **зарегистрирован как каталог** (`b_catalog_iblock`), элемент-товар существует, ему присвоена строка в `b_catalog_product` (см. рецепт по созданию товара). Этот рецепт — про ценовой слой поверх готового товара.

## Шаги
1. **Проверьте базовую валюту.** Без неё цену не создать: поле `CURRENCY` обязательно. Базовую валюту хранит модуль `currency` (`CCurrency` / `\Bitrix\Currency\CurrencyManager`).
2. **Получите ID базового типа цены** `BASE` — `\Bitrix\Catalog\GroupTable::getBasePriceType()`. Розничную цену вешают именно на него.
3. **(Опц.) Заведите ставку НДС** (`b_catalog_vat`) и привяжите её к товару (`VAT_ID`, `VAT_INCLUDED` в `b_catalog_product`).
4. **Назначьте цену** товару (`CPrice::Add` / `\Bitrix\Catalog\Model\Price::add`) на базовый тип цены в базовой валюте.
5. **(Опц.) Доп. типы цен** (опт, группа) создайте через `CCatalogGroup::Add`; цены на них либо задаются явно, либо пересчитываются от базы.
6. **Читайте цену к покупке** через `CCatalogProduct::GetOptimalPrice` — никогда не показывайте покупателю «сырое» значение из `b_catalog_price`.

## Рабочий сниппет
Разовый установочный скрипт. Положите в `/local/`, запустите один раз, затем удалите.

Файл: `/local/install/commerce_02_prices.php`

```php
<?php
// Разовый скрипт настройки цен. ЗАПУСТИТЬ ОДИН РАЗ, затем УДАЛИТЬ.
require($_SERVER['DOCUMENT_ROOT'] . '/bitrix/modules/main/include/prolog_before.php');

use Bitrix\Main\Loader;
use Bitrix\Currency\CurrencyManager;
use Bitrix\Catalog\GroupTable;

if (!Loader::includeModule('currency') || !Loader::includeModule('catalog')) {
    die('Modules currency/catalog are not installed');
}

$report = [];
$elementId = 42;   // ID элемента инфоблока, уже сделанного товаром (b_catalog_product)

// ---------------------------------------------------------------------------
// 1. БАЗОВАЯ ВАЛЮТА — без неё цена не создастся.
// ---------------------------------------------------------------------------
$baseCurrency = CurrencyManager::getBaseCurrency(); // напр. 'RUB'
if (!$baseCurrency) {
    // Завести валюту, если её нет (обычно ставится при установке).
    CCurrency::Add([
        'CURRENCY'        => 'RUB',
        'BASE'            => 'Y',          // базовая валюта
        'AMOUNT_CNT'      => 1,
        'AMOUNT'          => 1,
        'SORT'            => 100,
        'CURRENT_BASE'    => 1,
    ]);
    CCurrencyLang::Add([
        'CURRENCY'        => 'RUB',
        'LID'             => 'ru',
        'FORMAT_STRING'   => '#  руб.',
        'DEC_POINT'       => '.',
        'THOUSANDS_SEP'   => ' ',
        'DECIMALS'        => 2,
    ]);
    $baseCurrency = 'RUB';
    $report[] = "Базовая валюта создана: {$baseCurrency}.";
} else {
    $report[] = "Базовая валюта: {$baseCurrency}.";
}

// ---------------------------------------------------------------------------
// 2. БАЗОВЫЙ ТИП ЦЕНЫ (BASE='Y') — к нему привязываем розницу.
// ---------------------------------------------------------------------------
$base = GroupTable::getBasePriceType();   // ['ID'=>.., 'NAME'=>'BASE', 'BASE'=>'Y', ...]
if (!$base) {
    // ⚠️ На свежей установке базовый тип цены может отсутствовать (проверено на 26.x).
    // Создаём его. CCatalogGroup::Add ТРЕБУЕТ USER_GROUP/USER_GROUP_BUY (группы с правом
    // просмотра/покупки по этому типу цен), иначе вернёт false. 2 = «Все пользователи».
    $baseTypeId = (int)CCatalogGroup::Add([
        'NAME' => 'BASE', 'BASE' => 'Y', 'SORT' => 100, 'XML_ID' => 'BASE',
        'USER_GROUP' => [2], 'USER_GROUP_BUY' => [2],
    ]);
    if (!$baseTypeId) {
        die('Не удалось создать базовый тип цены.');
    }
} else {
    $baseTypeId = (int)$base['ID'];
}
$report[] = "Базовый тип цены ID = {$baseTypeId}.";

// ---------------------------------------------------------------------------
// 3. (Опц.) СТАВКА НДС и её привязка к товару.
// ---------------------------------------------------------------------------
$vatId = 0;
$vat = CCatalogVat::GetList([], ['ACTIVE' => 'Y', 'RATE' => 20], false, ['nTopCount' => 1])->Fetch();
if ($vat) {
    $vatId = (int)$vat['ID'];
} else {
    $vatId = (int)CCatalogVat::Add(['NAME' => 'НДС 20%', 'RATE' => 20, 'ACTIVE' => 'Y']);
}
CCatalogProduct::Update($elementId, [
    'VAT_ID'       => $vatId,
    'VAT_INCLUDED' => 'Y',   // цена уже включает НДС
]);
$report[] = "НДС привязан к товару: VAT_ID = {$vatId}.";

// ---------------------------------------------------------------------------
// 4. ЦЕНА на базовый тип в базовой валюте.
//    Идемпотентно: если базовая цена уже есть — обновляем.
// ---------------------------------------------------------------------------
$existing = CPrice::GetBasePrice($elementId);   // базовая цена товара или false
$priceFields = [
    'PRODUCT_ID'       => $elementId,
    'CATALOG_GROUP_ID' => $baseTypeId,
    'PRICE'            => 1990,
    'CURRENCY'         => $baseCurrency,
];
if ($existing && !empty($existing['ID'])) {
    CPrice::Update($existing['ID'], $priceFields);
    $report[] = "Цена обновлена (PRICE_ID = {$existing['ID']}).";
} else {
    $priceId = CPrice::Add($priceFields);
    $report[] = "Цена создана (PRICE_ID = {$priceId}).";
}

// ---------------------------------------------------------------------------
// 5. (Опц.) ДОП. ТИП ЦЕНЫ — напр. оптовый.
// ---------------------------------------------------------------------------
// $optId = CCatalogGroup::Add(['NAME' => 'OPT', 'BASE' => 'N', 'SORT' => 200, 'USER_GROUP' => [2], 'USER_GROUP_BUY' => [2]]);
// CPrice::Add(['PRODUCT_ID'=>$elementId,'CATALOG_GROUP_ID'=>$optId,'PRICE'=>1490,'CURRENCY'=>$baseCurrency]);

// ---------------------------------------------------------------------------
// 6. ЦЕНА К ПОКУПКЕ — учитывает скидки/НДС/группы пользователя.
// ---------------------------------------------------------------------------
global $USER;
$userGroups = is_object($USER) ? $USER->GetUserGroupArray() : [2]; // 2 = «Все пользователи»
$opt = CCatalogProduct::GetOptimalPrice($elementId, 1, $userGroups);
if ($opt) {
    $toPay = $opt['RESULT_PRICE']['DISCOUNT_PRICE'];   // цена с учётом скидок
    $report[] = "Цена к покупке: {$toPay} {$opt['RESULT_PRICE']['CURRENCY']}.";
}

require($_SERVER['DOCUMENT_ROOT'] . '/bitrix/modules/main/include/epilog_after.php');
echo '<pre>' . implode("\n", $report) . '</pre>';
```

### Эквивалент через Model-слой (D7)
Тот же результат на ORM-движке. `CPrice::Add` и так делегирует сюда.

```php
use Bitrix\Catalog\Model\Price;

$res = Price::add(['fields' => [
    'PRODUCT_ID'       => $elementId,
    'CATALOG_GROUP_ID' => $baseTypeId,
    'PRICE'            => 1990,
    'CURRENCY'         => $baseCurrency,
]]);
if (!$res->isSuccess()) {
    // implode(', ', $res->getErrorMessages())
}
// Пересчёт прайс-листа от базовой цены (для доп. типов с правилом наценки):
Price::recountPricesFromBase($elementId);
```

## Выбор API
- **Назначение цены — `CPrice::Add` / `Model\Price::add`.** Это две поддерживаемые версии API; `CPrice` — тонкий фасад над `Model\Price`, результат идентичен. Legacy короче для разовых скриптов; Model-слой даёт `Result`-объект и единый стиль в ORM-проектах. Параметр `CPrice::Add($fields, $recount=true)` ставит пересчёт прайс-листа от базы.
- **Базовый тип цены — читать через `\Bitrix\Catalog\GroupTable::getBasePriceType()`** (или `CCatalogGroup::GetBaseGroup()`). Не хардкодьте ID = 1: на разных стендах он различается.
- **Базовая валюта — `\Bitrix\Currency\CurrencyManager::getBaseCurrency()`.** Создание валюты — `CCurrency::Add` + локализация `CCurrencyLang::Add`.
- **Цена к покупке — только `CCatalogProduct::GetOptimalPrice`** (или `GetOptimalPriceList` для пакета). Возвращает массив с `RESULT_PRICE` (`BASE_PRICE`, `DISCOUNT_PRICE`, `CURRENCY`, `VAT_RATE`). На витрине ту же роль выполняет `CIBlockPriceTools::GetItemPrices` внутри `catalog.*`-компонентов.

## Проверка
**Режим «только файлы» (без живого Битрикса):**
- Скрипт в `/local/`, есть `Loader::includeModule('currency')` и `'catalog'`.
- Валюта берётся из `CurrencyManager::getBaseCurrency()`, а не зашита строкой без проверки.
- Тип цены получен через `GroupTable::getBasePriceType()` (не хардкод ID).
- Цена показывается через `GetOptimalPrice`, а не прямым чтением `b_catalog_price`.
- Скрипт идемпотентен: перед `CPrice::Add` проверяется `CPrice::GetBasePrice`.

**Режим «живой Битрикс»:**
- Запустите скрипт — он печатает `PRICE_ID` и `Цена к покупке: N RUB`.
- Админка: «Магазин → Настройки → Валюты» — есть базовая; «Магазин → Настройки → Типы цен» — есть `BASE`.
- Карточка товара → вкладка «Торговый каталог»: цена и НДС проставлены.
- Контроль кодом:
  ```php
  $p = CPrice::GetBasePrice($elementId);                 // PRICE, CURRENCY
  $o = CCatalogProduct::GetOptimalPrice($elementId, 1);  // RESULT_PRICE
  ```

## ⚠️ Риски
- ⚠️ **Без базовой валюты и базового типа цены заказ не соберётся.** Поле `CURRENCY` у цены обязательно; розница должна висеть на типе `BASE='Y'`. Если их нет — корзина и `GetOptimalPrice` вернут пусто, оформление заказа сломается. Проверяйте оба условия до записи цены.
- ⚠️ **Базовый тип цены должен быть единственным с `BASE='Y'`.** Два «базовых» типа ломают логику пересчёта (`recountPricesFromBase`) и подбор оптимальной цены. Не назначайте `BASE='Y'` второму типу.
- ⚠️ **Смена базовой валюты на работающем магазине меняет трактовку всех сохранённых цен** (значения не конвертируются автоматически) — операция планируется отдельно, не на лету.
- **Не читайте цену из `b_catalog_price` напрямую для покупателя** — мимо скидок, НДС, групп пользователя и конвертации валют. Только `GetOptimalPrice` / `CIBlockPriceTools::GetItemPrices`.
- **`VAT_INCLUDED='Y'`** означает «цена уже с НДС». Несогласованность этого флага с тем, как заведены цены, приводит к расхождению сумм в заказе — фиксируйте политику НДС один раз для всего каталога.
- **Скидки каталога** (`b_catalog_discount`, правила условий) — отдельная подсистема; они применяются автоматически внутри `GetOptimalPrice`, отдельно их в цене учитывать не нужно. Создание скидок — за рамками этого рецепта.

## Связано
- [Создание инфоблока](../02-create-iblock.md) — предусловие: инфоблок товаров.
- [Добавление свойств](../03-add-properties.md) — характеристики товара/предложений.
- [Обзор базы знаний](../../00-overview.md) — модули и их зависимости (`catalog` → `iblock` + `currency` + `sale`).
- [Карта API](../../api-map.md) — две поддерживаемые версии API, Model-слой и legacy-фасады.
```
