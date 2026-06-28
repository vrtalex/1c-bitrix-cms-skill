# 04. Оплата и доставка заказа

## Цель

Подключить к интернет-магазину платёжные системы и службы доставки и связать их
с заказом: создать обработчик платёжной системы (handler) и службы доставки,
зарегистрировать их через менеджеры `\Bitrix\Sale\PaySystem\Manager` /
`\Bitrix\Sale\Delivery\Services\Manager`, привязать к заказу через коллекции
`PaymentCollection` / `ShipmentCollection`, настроить передачу реквизитов через
Business Value (карта `PERSON_TYPE → поле заказа`) и кратко — фискализацию по
54-ФЗ через `\Bitrix\Sale\Cashbox`.

## Когда применять

- Добавляете в магазин свою платёжную систему (свой банк/агрегатор), которой нет
  среди встроенных обработчиков `handlers/paysystem/`.
- Добавляете свою службу доставки (свой курьер/тариф/API перевозчика) поверх
  встроенных `handlers/delivery/` или настраиваемой `configurable`/REST-службы.
- Программно (скрипт/REST/импорт) привязываете платёж и отгрузку к создаваемому
  заказу.
- Нужно отдать платёжной системе реквизиты плательщика/магазина (ИНН, ФИО, сумма)
  и при необходимости пробить чек на онлайн-кассе.

Не применять для базового сбора заказа из корзины — это конвейер
`sale.order.ajax::getOrder()` (создание заказа целиком). Здесь — именно блок
оплаты/доставки.

## Шаги

1. **Платёжная система — обработчик.** Каталог `handlers/paysystem/<code>/` с двумя
   файлами: `handler.php` (класс наследует `\Bitrix\Sale\PaySystem\ServiceHandler`,
   реализует `initiatePay()` — форма/редирект оплаты, и при наличии callback —
   `processRequest()`, `refund()`, `cancel()`, `confirm()`) и `.description.php`
   (массив `NAME`, `SORT`, `CODES` — поля настройки ПС). ⚠️ Реквизиты ПС жёстко
   завязаны на ключи `CODES` из `.description.php`: handler читает их через
   `$this->getBusinessValue($payment, '<CODE>')`, и переименование/опечатка кода
   оставит реквизит пустым.
2. **Регистрация ПС.** В админке «Магазин → Настройки → Платёжные системы»
   добавить ПС, указав обработчик `<code>`; заполнить поля из `CODES` (значения
   через Business Value по типу плательщика). Объект ПС в коде —
   `PaySystem\Manager::getObjectById($id)`.
3. **Служба доставки — обработчик.** Каталог `handlers/delivery/<code>/` с классом,
   наследующим `\Bitrix\Sale\Delivery\Services\Base` (метод `calculate(Shipment)`
   возвращает `CalculationResult` со стоимостью/сроком). Альтернатива своему
   handler — настраиваемая `configurable` или REST-служба.
4. **Регистрация доставки.** В админке «Магазин → Настройки → Службы доставки»
   добавить службу; ограничения (по сумме/весу/местоположению/типу плательщика) —
   через restrictions. Объект в коде — `Delivery\Services\Manager::getObjectById($id)`.
5. **Привязка к заказу.** Платёж — через `getPaymentCollection()->createItem($ps)`,
   отгрузка — через `getShipmentCollection()->createItem($delivery)` и перенос
   позиций корзины в `ShipmentItemCollection`.
6. **Business Value.** Сопоставить поля ПС/чека (ФИО, e-mail, сумма) с источником
   данных по типу плательщика в «Бизнес-значения» — handler берёт их через
   `getBusinessValue()`.
7. **Касса (54-ФЗ), при необходимости.** Подключить обработчик
   `\Bitrix\Sale\Cashbox\Cashbox` — чек формируется автоматически по оплате/отгрузке.

## Рабочий сниппет

Привязка платежа и отгрузки к создаваемому заказу. Путь:
`/local/php_interface/include/commerce/attach_pay_delivery.php`
(подключается из `init.php`) или одноразовый скрипт.

```php
<?php
// /local/php_interface/include/commerce/attach_pay_delivery.php
use Bitrix\Main\Loader;
use Bitrix\Sale;

Loader::includeModule('sale');
Loader::includeModule('catalog');

/** @var Sale\Order $order — уже создан, корзина и тип плательщика заданы */

// --- Отгрузка: выбрать службу доставки и перенести позиции корзины ---
$deliveryId = 2; // id настроенной службы доставки
$shipmentCollection = $order->getShipmentCollection();
$shipment = $shipmentCollection->createItem(
    Sale\Delivery\Services\Manager::getObjectById($deliveryId)
);
$shipment->setField('DELIVERY_ID', $deliveryId);

$shipmentItemCollection = $shipment->getShipmentItemCollection();
foreach ($order->getBasket() as $basketItem) {
    $shipmentItem = $shipmentItemCollection->createItem($basketItem);
    $shipmentItem->setQuantity($basketItem->getQuantity());
}

// Стоимость доставки рассчитает служба (расчёт нужен на непустой отгрузке):
$calc = Sale\Delivery\Services\Manager::calculateDeliveryPrice($shipment, $deliveryId);
if ($calc->isSuccess()) {
    // Предпочтительно — метод API отгрузки: выставляет и BASE_PRICE_DELIVERY,
    // и флаг ручной цены согласованно.
    $shipment->setBasePriceDelivery($calc->getPrice(), true); // (цена, $custom = true)
    // Иллюстративно — прямая установка полей (то же самое «руками»):
    // $shipment->setField('BASE_PRICE_DELIVERY', $calc->getPrice());
    // $shipment->setField('CUSTOM_PRICE_DELIVERY', 'Y');
}

// --- Платёж: выбрать платёжную систему и задать сумму ---
$paySystemId = 1; // id настроенной платёжной системы
$paymentCollection = $order->getPaymentCollection();
$payment = $paymentCollection->createItem(
    Sale\PaySystem\Manager::getObjectById($paySystemId)
);
$payment->setFields([
    'SUM'      => $order->getPrice(),     // сумма заказа после скидок/доставки
    'CURRENCY' => $order->getCurrency(),
]);

// Пересчёт скидок/налогов ОБЯЗАТЕЛЕН перед сохранением:
$order->doFinalAction(true);
$result = $order->save();
if (!$result->isSuccess()) {
    // $result->getErrorMessages() — диагностика
}
```

Доступные для конкретного заказа/отгрузки списки (для UI выбора):

```php
// ПС, прошедшие ограничения для заказа и суммы:
$psList = Sale\PaySystem\Manager::getListWithRestrictionsByOrder($order, $payment->getSum());
// Службы доставки, доступные для отгрузки:
$delivList = Sale\Delivery\Services\Manager::getRestrictedObjectsList($shipment);
```

Скелет обработчика платёжной системы (handler + description):

```php
<?php
// handlers/paysystem/mybank/.description.php
$data = [
    'NAME'  => 'Мой банк (эквайринг)',
    'SORT'  => 500,
    'CODES' => [
        'MYBANK_MERCHANT' => ['NAME' => 'ID магазина', 'SORT' => 100],
        'MYBANK_SECRET'   => ['NAME' => 'Секретный ключ', 'SORT' => 200],
    ],
];
```

```php
<?php
// handlers/paysystem/mybank/handler.php
namespace Sale\Handlers\PaySystem;

use Bitrix\Sale\Payment;
use Bitrix\Sale\PaySystem;
use Bitrix\Main\Request;

class MybankHandler extends PaySystem\ServiceHandler
{
    public function initiatePay(Payment $payment, Request $request = null): PaySystem\ServiceResult
    {
        $result = new PaySystem\ServiceResult();
        // реквизиты берутся ПО КЛЮЧАМ из CODES (.description.php):
        $merchant = $this->getBusinessValue($payment, 'MYBANK_MERCHANT');
        $secret   = $this->getBusinessValue($payment, 'MYBANK_SECRET');
        // ... подготовить форму/редирект на шлюз, $this->showTemplate(...)
        return $result;
    }

    /**
     * Callback (server-to-server) шлюза об оплате. ⚠️ ВЕСЬ контроль безопасности
     * платежа здесь: без проверки любой может POST'ом подделать «оплачено».
     * СПОСОБ проверки ЗАВИСИТ ОТ ШЛЮЗА (см. развилку «Проверка callback» ниже):
     *   - generic (симметричная подпись): подпись над СЫРЫМ телом через
     *     hash_equals() + сумма == $payment->getSum() — этот дефолтный скелет;
     *   - YooKassa: IP-allowlist + ПЕРЕЗАПРОС статуса через API (НЕ HMAC);
     *   - Sberbank: HMAC-SHA256 callback-токеном по отсортированной строке.
     * Только после успешной проверки — setPaid('Y').
     */
    public function processRequest(Payment $payment, Request $request): PaySystem\ServiceResult
    {
        $result = new PaySystem\ServiceResult();

        // Секрет шлюза — через Business Value (НЕ хардкод, НЕ из тела запроса):
        $secret = (string)\Bitrix\Sale\PaySystem\Service::getBusinessValue($payment, 'MYBANK_SECRET');

        // 1. ⚠️ Подпись считаем над СЫРЫМ телом callback (как прислал шлюз),
        //    а не над уже распарсенным/пересобранным массивом.
        $rawBody  = file_get_contents('php://input');
        $gotSign  = (string)$request->getHeader('X-Mybank-Signature');
        $expected = hash_hmac('sha256', $rawBody, $secret);

        // Сравнение по постоянному времени; при несовпадении — ОТКАЗ.
        if ($secret === '' || $gotSign === '' || !hash_equals($expected, $gotSign)) {
            $result->addError(new \Bitrix\Main\Error('Bad callback signature'));
            return $result; // setPaid НЕ вызываем
        }

        $data = json_decode($rawBody, true);
        if (!is_array($data)) {
            $result->addError(new \Bitrix\Main\Error('Bad callback body'));
            return $result;
        }

        // 2. ⚠️ Защита от подмены суммы/недоплаты: сумма из callback ДОЛЖНА
        //    совпасть с суммой платежа в заказе (сравнение денег — с эпсилон).
        $callbackSum = (float)($data['amount'] ?? -1);
        if (abs($callbackSum - (float)$payment->getSum()) > 0.01) {
            $result->addError(new \Bitrix\Main\Error('Amount mismatch'));
            return $result; // НЕ помечаем оплаченным при расхождении суммы
        }

        // 3. Только теперь — отметить оплату.
        $payment->setPaid('Y');
        return $result;
    }

    public function getCurrencyList(): array { return ['RUB']; }
}
```

⚠️ `processRequest()` — единственная точка, где платёж признаётся оплаченным по
сигналу извне; держите проверку в начале метода и выходите с ошибкой ДО любого
`setPaid('Y')`.

### Проверка callback зависит от шлюза

Скелет выше — дефолт для шлюзов с **симметричной подписью** (HMAC над телом).
Но RU-шлюзы различаются по модели проверки — выберите ветку по своему шлюзу:

**Ветка A. YooKassa (ЮKassa) — НЕ HMAC.** Самый массовый RU-шлюз. Официальная
модель проверки вебхука: (1) сверить **IP-источник** по списку диапазонов
YooMoney (allowlist) и (2) **перезапросить объект платежа через API**
`GET /payments/{id}` и сверить `status`/`amount` с заказом. Телу уведомления НЕ
доверяем — берём статус и сумму из ответа API.

```php
<?php
// YooKassa: внутри processRequest() — вместо HMAC-ветки.
// 1. IP-allowlist: $request->getRemoteAddress() в диапазонах YooMoney
//    (CIDR из офиц. документации). Несовпадение — addError() и выход БЕЗ setPaid().
// 2. Re-fetch: НЕ доверяя телу, перезапросить объект платежа (Basic shopId:secretKey):
//      GET https://api.yookassa.ru/v3/payments/{payment_id}
$paymentId = (string)($data['object']['id'] ?? '');
// $apiPayment = ...; // и сверить статус/сумму из ОТВЕТА API, а не из тела:
// if (($apiPayment['status'] ?? '') !== 'succeeded') { return $errResult; }
// if (abs((float)($apiPayment['amount']['value'] ?? -1) - (float)$payment->getSum()) > 0.01) { return $errResult; }
$payment->setPaid('Y');
```

Источник: ВЕНДОР YooKassa, https://yookassa.ru/developers/using-api/webhooks

**Ветка B. Sberbank acquiring — симметричный checksum.** Контрольная сумма
callback — `HMAC-SHA256` с **callback-токеном мерчанта** по строке из всех
параметров callback **кроме `checksum`**, отсортированных по алфавиту
(формат — конкатенированные пары `name;value;`); hex в верхнем регистре,
сравнивается с присланным `checksum` через `hash_equals()`. Дополнительно —
сверить сумму с заказом. ⚠️ Точный формат строки (полный список исключаемых
параметров) и асимметричный (RSA) вариант **сверьте с официальной документацией
шлюза** до продакшена.

```php
<?php
// Sberbank: внутри processRequest() — вместо generic-ветки.
$token  = (string)\Bitrix\Sale\PaySystem\Service::getBusinessValue($payment, 'SBER_CALLBACK_TOKEN');
$params = $request->getQueryList()->toArray(); // параметры callback
$got    = (string)($params['checksum'] ?? '');
unset($params['checksum']);
ksort($params);
$dataStr = '';
foreach ($params as $k => $v) {
    $dataStr .= $k . ';' . $v . ';';
}
$expected = strtoupper(hash_hmac('sha256', $dataStr, $token));
if ($token === '' || $got === '' || !hash_equals($expected, $got)) {
    $result->addError(new \Bitrix\Main\Error('Bad Sber checksum'));
    return $result; // setPaid НЕ вызываем
}
// + сверка суммы с $payment->getSum() (как в дефолтном скелете) ДО setPaid('Y').
```

⚠️ Формат строки сверить: ВЕНДОР шлюза,
https://securepayments.sberbank.ru/wiki/doku.php/integration:api:callback:start

**Ветка C. Generic / дефолт.** Для шлюзов с симметричной подписью оставьте
скелет выше: `hash_hmac()` над СЫРЫМ телом + `hash_equals()` + сверка
`callbackSum == $payment->getSum()`.

decay: QIWI и WebMoney как платёжные системы **сняты** на новых ядрах (`sale` 24.300.0 / ЮKassa 23.400.0) — не рекомендуйте их для новых интеграций.

## Выбор API

Bitrix даёт две поддерживаемые версии API; для оплаты/доставки нового кода
используйте D7-объекты.

- **D7, `\Bitrix\Sale\PaySystem` / `\Bitrix\Sale\Delivery`** — основной путь.
  ПС: `PaySystem\Manager::getObjectById()`, `getListWithRestrictionsByOrder()`,
  `getInnerPaySystemId()`; объект `PaySystem\Service` —
  `initiatePay($payment, $request)`, `processRequest()`, `refund()`, `cancel()`,
  `confirm()`. Доставка: `Delivery\Services\Manager::getObjectById()` /
  `getObjectByCode()`, `getRestrictedObjectsList($shipment)`,
  `calculateDeliveryPrice($shipment, $deliveryId, $extraServices)`,
  `calculate($shipment)` → `CalculationResult`. Привязка к заказу — через
  коллекции `Payment`/`Shipment` (`createItem(...)`, `setFields(...)`).
- **legacy `CSalePaySystem` / `CSaleDelivery*`** — совместимостная обёртка для
  старого кода; внутри частично проксирует на D7. В новом коде не применять.

Развилки:

- **Свой handler vs настраиваемая служба.** Для доставки с фиксированными
  правилами достаточно `configurable`/REST-службы из админки (свой код не нужен).
  Свой handler в `handlers/delivery/<code>/` — когда нужна интеграция с API
  перевозчика. Аналогично для ПС: типовые шлюзы уже есть среди встроенных
  обработчиков `handlers/paysystem/`.
- **Внутренний счёт (оплата с баланса).** ПС-обработчик `inner`, id —
  `PaySystem\Manager::getInnerPaySystemId()`; платёж распознаётся через
  `$payment->isInner()`.
- **Business Value.** Реквизиты ПС/чека handler читает не из заказа напрямую, а
  через `getBusinessValue($payment, '<CODE>')` — значение настраивается в
  «Бизнес-значениях» как карта `PERSON_TYPE → источник` (поле заказа, свойство,
  константа). Так одна ПС отдаёт разные реквизиты физлицу и юрлицу.
- **Касса (54-ФЗ).** `\Bitrix\Sale\Cashbox\Cashbox` — обработчики онлайн-касс
  (ОФД). Чек формируется автоматически по событиям оплаты/отгрузки на основе
  состава заказа и ставок НДС; в коде заказа касса отдельно не вызывается —
  достаточно её настроить и привязать к ПС в админке.

## Проверка

**Режим «только файлы»** (без живого Битрикса):

- PHP-линт: `php -l /local/php_interface/include/commerce/attach_pay_delivery.php`
  и `php -l handlers/paysystem/<code>/handler.php`.
- Сверить ключи: каждый код, читаемый в handler через `getBusinessValue($payment,
  '<CODE>')`, присутствует в массиве `CODES` файла `.description.php`
  (совпадение по символам). Это главный источник «пустых реквизитов».
- Проверить, что класс handler наследует `PaySystem\ServiceHandler`
  (доставка — `Delivery\Services\Base`) и реализует обязательные методы.
- Убедиться, что перед `$order->save()` вызван `$order->doFinalAction(true)`, а
  результат проверяется через `isSuccess()`.

**Режим «живой Битрикс»**:

- В админке ПС и служба доставки видны и активны; у заказа в карточке
  появляются платёж и отгрузка.
- Через консоль/CLI: создать тестовый заказ, привязать платёж и отгрузку,
  проверить `$order->save()->isSuccess()` и непустой `$order->getId()`.
- Расчёт доставки: `Manager::calculateDeliveryPrice($shipment, $deliveryId)` на
  НЕПУСТОЙ отгрузке возвращает `isSuccess()=true` и ненулевую цену.
- Оплата: пометить платёж `setPaid('Y')`, сохранить, убедиться, что
  `$payment->isPaid()` и пересчитался статус оплаты заказа.
- Чек (если включена касса): в «Магазин → Кассы → Чеки» появляется чек по
  оплате/отгрузке со статусом успешной фискализации.

## ⚠️ Риски

- ⚠️ **Реквизиты ПС завязаны на `CODES` из `.description.php`.** handler читает
  каждый реквизит по строковому ключу через `getBusinessValue($payment, '<CODE>')`.
  Опечатка/переименование кода в `.description.php` или в коде → реквизит молча
  приходит пустым, оплата уходит с неверными данными. Меняя код, правьте оба места.
- ⚠️ **Сумма платежа должна сойтись с заказом.** `SUM` платежа задавайте после
  `doFinalAction(true)` (когда учтены скидки и доставка). Иначе заказ остаётся
  недоплаченным/переплаченным — расхождение денег.
- ⚠️ **Расчёт доставки на пустой/системной отгрузке.** Пока позиции не перенесены
  в отгрузку из корзины, стоимость не рассчитается. Сначала наполните
  `ShipmentItemCollection`, затем считайте `calculateDeliveryPrice`.
- ⚠️ **Тип плательщика фильтрует ПС и доставку.** Доступные платёжные системы и
  службы зависят от `PERSON_TYPE_ID` и restrictions. Сначала задайте тип
  плательщика, потом подбирайте/привязывайте ПС и доставку — иначе список пуст.
- ⚠️ **`save()` возвращает `Result`, а не bool.** Всегда проверяйте `isSuccess()`
  и читайте `getErrorMessages()`. Тихая ошибка (недоступная ПС, нет резерва) даёт
  «полусохранённый» заказ без платежа/отгрузки.
- ⚠️ **Business Value по типу плательщика.** Если карта `PERSON_TYPE → поле` не
  настроена для нужного типа, handler получит пустые реквизиты/реквизиты другого
  типа. Проверяйте сопоставление для каждого активного типа плательщика.
- ⚠️ **Касса и НДС.** Чек 54-ФЗ пробивается по ставкам НДС позиций заказа.
  Неверная/незаполненная ставка НДС товара → некорректный фискальный чек
  (нарушение 54-ФЗ). Проверьте ставки НДС в каталоге до подключения кассы.
- ⚠️ **Callback платёжной системы — проверка ОБЯЗАТЕЛЬНА, способ зависит от шлюза.**
  `processRequest()` отрабатывает уведомление шлюза об оплате. Без проверки любой
  может POST'ом подделать «оплачено». Модель проверки РАЗНАЯ (см. развилку
  «Проверка callback зависит от шлюза»): **YooKassa** — НЕ HMAC, а IP-allowlist +
  перезапрос статуса через API `GET /payments/{id}` (телу не доверять);
  **Sberbank** — HMAC-SHA256 callback-токеном по отсортированной строке (формат
  сверить с офиц. документацией шлюза); **generic** — `hash_hmac()` над СЫРЫМ
  телом + `hash_equals()`. При неуспехе — `ServiceResult` с ошибкой и БЕЗ
  `setPaid('Y')`. Секрет/токен берите через
  `PaySystem\Service::getBusinessValue($payment, '<CODE>')`, а не из тела запроса.
- ⚠️ **Сумма callback должна сойтись с платежом.** Перед `setPaid('Y')` сверяйте
  сумму из уведомления с `$payment->getSum()`. Иначе — подмена суммы/недоплата:
  заказ помечается оплаченным на меньшую (или произвольную) сумму.

## Связано

- Источник: модуль `sale` (PaySystem/Delivery) — dev.1c-bitrix.ru.
- Проверка callback шлюзов: YooKassa — https://yookassa.ru/developers/using-api/webhooks ;
  Sberbank — https://securepayments.sberbank.ru/wiki/doku.php/integration:api:callback:start .
- Ключевые классы: `\Bitrix\Sale\PaySystem\Manager`,
  `\Bitrix\Sale\PaySystem\ServiceHandler`, `\Bitrix\Sale\PaySystem\Service`,
  `\Bitrix\Sale\Delivery\Services\Manager`, `\Bitrix\Sale\Delivery\Services\Base`,
  `\Bitrix\Sale\Payment`, `\Bitrix\Sale\Shipment`, `\Bitrix\Sale\PersonType`,
  `\Bitrix\Sale\Cashbox`.
- Обзор и карта API: [../../00-overview.md](../../00-overview.md),
  [../../api-map.md](../../api-map.md).
- Инфоблоки и свойства (каталог товаров): [../02-create-iblock.md](../02-create-iblock.md),
  [../03-add-properties.md](../03-add-properties.md).
