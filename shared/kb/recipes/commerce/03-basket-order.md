# 03. Корзина и заказ (D7-модель Sale)

## Цель

Программно собрать заказ интернет-магазина на ядре 26.x (модуль `sale`,
catalog 25.x): создать корзину `\Bitrix\Sale\Basket`, добавить в неё товары
каталога, создать заказ `\Bitrix\Sale\Order::create(...)`, задать тип
плательщика (PERSON_TYPE), заполнить свойства заказа
(`PropertyValueCollection` — ФИО, телефон, адрес), пересчитать итог и
сохранить через `$order->save()` с проверкой `Result`. Подключение оплаты
(Payment) и доставки (Shipment) — отдельные подсистемы; здесь — базовая
сборка «корзина → заказ → save».

## Когда применять

- Заказ создаётся не из формы оформления, а из кода: импорт, миграция,
  REST/Webhook, синхронизация с внешней системой, тестовые данные.
- Нужно положить товар в корзину текущего пользователя из своего
  обработчика (акция «купить в 1 клик», быстрый заказ).
- Разбираетесь, как штатный оформитель `bitrix:sale.order.ajax` собирает
  заказ, чтобы повторить или расширить его логику.
- Не для случая «есть готовая страница оформления» — там работает компонент
  `bitrix:sale.order.ajax` / `bitrix:sale.order.checkout`, заказ собирать
  вручную не нужно.

## Шаги

Эталонная последовательность сборки повторяет `SaleOrderAjax::getOrder()` и
`SaleOrderCheckout` (`Controller\Action\Entity\SaveOrderAction`). Порядок
важен: persontype задаём ДО свойств, корзину — до пересчёта.

1. **Подключить модули.** `\Bitrix\Main\Loader::includeModule('sale')` и
   `includeModule('catalog')`. Без `catalog` позиция не свяжется с товаром
   (нет цены/наличия).

2. **Получить корзину.** Для текущего посетителя — корзина по `fuser`:
   `Basket::loadItemsForFUser(\Bitrix\Sale\Fuser::getId(), $siteId)`.
   Для чистой сборки в скрипте — новая: `Basket::create($siteId)`.

3. **Добавить позиции.** `$basket->createItem('catalog', $productId)` →
   `setFields([...])` с `QUANTITY`, `CURRENCY`, `LID` и обязательным
   `PRODUCT_PROVIDER_CLASS => '\CCatalogProductProvider'` — это связывает
   позицию с каталогом (цена/наличие/резерв тянутся провайдером).

4. **Создать заказ.** Только через фабрику: `$order = Order::create($siteId,
   $userId, $currency)`. Параметр `$currency` опционален — без него валюта
   берётся из настроек сайта/базовой валюты; ⚠️ несовпадение валют корзины и
   заказа ломает расчёт.

5. **Открыть транзакцию полей.** `$order->isStartField()` перед блоком установки
   полей/свойств — как в эталонном `sale.order.ajax`. Метод возвращает признак
   «старт ещё не начат» и откладывает каскадные пересчёты до `doFinalAction()`,
   что снимает краевые случаи рекурсии событий при пакетной установке полей.

6. **Задать тип плательщика.** `$order->setPersonTypeId($personTypeId)`
   (типовые: 1 — физлицо, 2 — юрлицо). От PERSON_TYPE зависят набор свойств
   заказа и доступные оплаты/доставки — потому задаём первым.

7. **Привязать корзину к заказу.** `$order->setBasket($basket)`.

8. **Заполнить свойства заказа.** Через
   `$order->getPropertyCollection()` — точечно по id свойства или пакетно
   `setValuesFromPost(...)`. Набор свойств зависит от PERSON_TYPE.

9. **Закрыть транзакцию полей.** `$order->clearStartField()` (передайте `true`,
   если открывали верхним вызовом) — парный к `isStartField()`, после него
   каскадные пересчёты снова активны.

10. **Пересчитать.** `$order->doFinalAction(true)` — пересчёт скидок, налогов
   и итоговой цены. ⚠️ Без него суммы не сойдутся.

11. **Сохранить и проверить.** `$result = $order->save()` — это
   `\Bitrix\Sale\Result`, а не bool. Читать `isSuccess()` /
   `getErrorMessages()`, затем `$order->getId()`.

## Рабочий сниппет (путь в /local)

```php
<?php
// /local/php_interface/include/create_order.php
use Bitrix\Main\Loader;
use Bitrix\Sale;

Loader::includeModule('sale');
Loader::includeModule('catalog');

$siteId   = 's1';
$userId   = 1;            // зарегистрированный покупатель
$currency = 'RUB';

// 1. Фабрика классов (поддерживает кастомные классы заказа/корзины).
$registry  = Sale\Registry::getInstance(Sale\Registry::REGISTRY_TYPE_ORDER);
$orderCls  = $registry->getOrderClassName();   // \Bitrix\Sale\Order
$basketCls = $registry->getBasketClassName();  // \Bitrix\Sale\Basket

// 2. Корзина и позиции.
$basket = $basketCls::create($siteId);
$item   = $basket->createItem('catalog', $productId);   // module, productId
$item->setFields([
    'QUANTITY'               => 2,
    'CURRENCY'               => $currency,
    'LID'                    => $siteId,
    'PRODUCT_PROVIDER_CLASS' => '\CCatalogProductProvider', // связь с каталогом
]);

// 3. Заказ — ТОЛЬКО через create(), не new Order(...).
$order = $orderCls::create($siteId, $userId, $currency);

// Транзакция полей (как в sale.order.ajax): откладывает каскадные пересчёты
// и снимает краевые случаи рекурсии событий при пакетной установке полей.
$isStartField = $order->isStartField();

$order->setPersonTypeId(1);          // 1 — физлицо
$order->setBasket($basket);          // привязка корзины

// 4. Свойства заказа (зависят от PERSON_TYPE).
$props = $order->getPropertyCollection();
// Точечно по id свойства:
if ($fioProp = $props->getItemByOrderPropertyId($fioPropertyId)) {
    $fioProp->setValue('Иванов Иван Иванович');
}
if ($phoneProp = $props->getItemByOrderPropertyId($phonePropertyId)) {
    $phoneProp->setValue('+7 999 000-00-00');
}
// Либо пакетно из формы:
// $props->setValuesFromPost(['PROPERTIES' => $_POST['PROPERTIES']], $_FILES);

// Закрываем транзакцию полей парным вызовом.
if ($isStartField) {
    $order->clearStartField();
}

// 5. Пересчёт скидок/налогов и сохранение.
$order->doFinalAction(true);
$result = $order->save();            // -> \Bitrix\Sale\Result

if ($result->isSuccess()) {
    $orderId       = $order->getId();
    $accountNumber = $order->getField('ACCOUNT_NUMBER'); // номер для покупателя
} else {
    foreach ($result->getErrorMessages() as $msg) {
        // залогировать $msg — заказ не создан или создан частично
    }
}
```

Свойство по коду (а не по id) удобно искать через
`$props->getItemByOrderPropertyCode('FIO')` — коды задаются при настройке
свойств заказа. Управление готовым заказом (смена статуса, отметка оплаты,
разрешение доставки) — через объект и повторный `save()`:
`$order->setField('STATUS_ID', 'F'); $order->save();`.

## Выбор API

- **Сборка заказа — D7-объекты** (`Order`, `Basket`, `BasketItem`,
  `PropertyValueCollection`). Это основной поддерживаемый путь: заказ
  собирается в памяти и пишется одним `save()` со всеми скидками, налогами и
  резервами. Прямые INSERT в `b_sale_*` их обходят.
- **Создание сущностей — через `Registry` / `create()`**, не `new`. Тип
  реестра (`REGISTRY_TYPE_ORDER`) и геттеры классов
  (`getOrderClassName()` / `getBasketClassName()`) позволяют CRM, архиву и
  возвратам подменять классы; прямой `new Order(...)` сломает совместимость.
- **Корзина: `loadItemsForFUser` против `create`.** Корзина посетителя
  привязана к `fuser` (`Sale\Fuser::getId()`), а не к `USER_ID`. Для заказа
  от лица текущего посетителя — `loadItemsForFUser`; для чистой программной
  сборки — `create($siteId)`.
- **[legacy] `CSaleOrder` / `CSaleBasket`** (`bitrix/modules/sale/general/`):
  `CSaleOrder::DoSaveOrder(...)`, `CSaleBasket::Add(...)`. Это вторая
  поддерживаемая версия API — совместимостная обёртка для старого мастера
  `sale.order`. В новом коде использовать D7-объекты. ⚠️ Два пути сохранения
  (`CSaleOrder::DoSaveOrder` и `Order::save`) в рамках одной операции не
  смешивать.
- **Чтение заказов** — `Order::load($id)`,
  `Order::loadByAccountNumber($value)`,
  `Order::getList(['filter' => ..., 'select' => ..., 'order' => ...])`
  (ORM поверх `OrderTable`). Для legacy — `CSaleOrder::GetByID` / `GetList`.

## Проверка

Проверка рендера и структуры — по общему паттерну: [verification](../../operations.md) (CLI для структуры, браузер/preview для рендера; на dev-стенде).

**Режим «только файлы»** (без запуска Битрикса):

- Заказ создаётся через `Order::create(...)` (или `Registry` +
  `$orderCls::create`), а не `new Order(...)`.
- Перед `save()` есть `doFinalAction(true)`.
- Результат `save()` проверяется: `isSuccess()` + `getErrorMessages()`,
  а не трактуется как bool.
- У позиции корзины задан `PRODUCT_PROVIDER_CLASS` (обычно
  `\CCatalogProductProvider`), `QUANTITY`, `CURRENCY`, `LID`.
- `setPersonTypeId(...)` вызван ДО заполнения свойств заказа.
- Подключены оба модуля: `sale` и `catalog`.

**Режим «живой Битрикс»** (проверка результата):

1. Заказ в базе: `SELECT ID, ACCOUNT_NUMBER, PRICE, CURRENCY, PERSON_TYPE_ID,
   STATUS_ID, CANCELED FROM b_sale_order ORDER BY ID DESC LIMIT 5`.
   `PRICE` совпадает с суммой корзины (если 0 при непустой корзине —
   пропущен `doFinalAction` или провайдер не дал цену).
2. Позиции: `SELECT ID, PRODUCT_ID, QUANTITY, PRICE, CURRENCY FROM
   b_sale_basket WHERE ORDER_ID = <id>`. Пустой результат при «успешном»
   save → корзина не привязана (`setBasket`) или потеряна на fuser/user.
3. Свойства: `b_sale_order_props_value` по `ORDER_ID` содержит заполненные
   значения; набор соответствует PERSON_TYPE заказа.
4. Заказ виден в админке (Магазин → Заказы), статус — начальный из
   `OrderStatus::getInitialStatus()`.

## ⚠️ Риски

- ⚠️ **`new Order(...)` запрещён.** Создавать заказ только через
  `Order::create()` / `Registry`. Прямой `new` обходит фабрику классов и
  ломает совместимость с CRM, архивом и возвратами.
- ⚠️ **`save()` возвращает `Result`, а не bool.** Без проверки
  `isSuccess()` тихие ошибки (нет резерва, недоступная оплата, провайдер не
  дал цену) дают «полусохранённый» заказ: запись в `b_sale_order` есть, а
  позиций/суммы нет. Это потеря данных заказа — всегда читать
  `getErrorMessages()`.
- ⚠️ **`doFinalAction(true)` обязателен перед `save()`.** Без него не
  пересчитаются скидки, налоги и итог; сумма заказа разойдётся с корзиной, и
  последующая оплата не сойдётся с суммой к оплате — прямой денежный риск.
- ⚠️ **Валюта.** Если корзина и заказ в разных валютах, расчёт итога ломается.
  Передавать единую валюту в `createItem(...)->setFields(['CURRENCY' => ...])`
  и в `Order::create($siteId, $userId, $currency)`.
- **Provider товара.** Без корректного `PRODUCT_PROVIDER_CLASS` (обычно
  `\CCatalogProductProvider`) позиция не свяжется с каталогом — не будет цены,
  наличия и резерва.
- **Путаница fuser / user.** Корзина посетителя привязана к
  `Fuser::getId()`, заказ — к `USER_ID`. Сборка корзины не из того fuser →
  «пропавшие» товары в заказе.
- **PERSON_TYPE влияет на всё.** Набор свойств заказа и доступные оплаты/
  доставки фильтруются по `PERSON_TYPE_ID`. Сначала `setPersonTypeId`, потом
  свойства — иначе свойства могут не примениться.
- **Купоны — до пересчёта.** Если применяете купон,
  `DiscountCouponsManager::init(...)` нужно вызвать ДО `doFinalAction`,
  иначе скидка не применится к этому экземпляру заказа.

## Связано

- ../../00-overview.md — обзор скилла и карта под-скиллов.
- ../../api-map.md — карта классов и ORM-таблиц.
- ../02-create-iblock.md — инфоблоки как основа каталога товаров.
- ../03-add-properties.md — свойства инфоблока (характеристики товара).
