# 05. Оформление заказа и личный кабинет

## Цель

Собрать страницу оформления заказа и личный кабинет покупателя на штатных
компонентах модуля `sale` (ядро 26.x, sale): корзина `bitrix:sale.basket.basket`,
оформитель `bitrix:sale.order.ajax` (классический мастер) или
`bitrix:sale.order.checkout` (новый, на `Main\Engine\Controller`), кабинет на
семействе `bitrix:sale.personal.*`. Кастом — копией шаблона в `/local`, без
переписывания логики. Отдельно — корректное согласие на обработку персональных
данных (ПДн) на форме оформления.

## Когда применять

- Нужна страница `/personal/order/make/` с выбором доставки/оплаты и сохранением заказа.
- Нужен личный кабинет: список заказов, детали, отмена, доплата/смена платёжной системы.
- Корп-сайт с заявками-счетами (без полноценной витрины) — тот же оформитель + ПС «счёт».
- Требуется кастом разметки/шагов оформления или вёрстки кабинета под дизайн проекта.

## Шаги

1. **Корзина** на `/personal/cart/` — компонент `bitrix:sale.basket.basket`
   (класс `CBitrixBasketComponent`). Мини-корзина в шапке — `sale.basket.basket.line`.
   Параметр `PATH_TO_ORDER` ведёт на страницу оформления.

2. **Выбрать оформитель** (см. «Выбор API»). Для типового магазина и корп-сайта —
   `bitrix:sale.order.ajax`, шаблон `bootstrap_v4`. Для SPA-витрины —
   `bitrix:sale.order.checkout`.

3. **Поставить оформитель** на `/personal/order/make/`. У `sale.order.ajax`
   эталон параметров — из тиражного решения «1С-Битрикс: Магазин» (eshop):
   `PATH_TO_BASKET`, `PATH_TO_PAYMENT`, `PATH_TO_PERSONAL`,
   `DELIVERY_TO_PAYSYSTEM` (порядок шагов «доставка↔оплата»),
   `ALLOW_NEW_PROFILE`, `PAY_FROM_ACCOUNT`, `SHOW_VAT_PRICE`,
   `SHOW_NOT_CALCULATED_DELIVERIES`. Компонент сам грузит корзину текущего
   пользователя, создаёт `Order`, отгрузку и оплату, считает доставку и список ПС,
   а после сохранения дёргает `initiatePay()` для онлайн-оплаты.

4. **Согласие на обработку ПДн.** ⚠️ Форма сбора ФИО/телефона/адреса —
   обработка персональных данных. Включить и привязать соглашение в админке
   (Настройки → Защита ПДн / соглашения) и параметрах оформителя:
   у `sale.order.ajax` — группа параметров согласия (`USE_PHONE_NORMALIZATION`
   и блок согласия в шаблоне `bootstrap_v4`), у `sale.order.checkout` — экшен
   `userConsentRequestAction` (запрос соглашения через
   `BX.ajax.runComponentAction(...)`). Кнопка «Оформить» должна быть недоступна
   без отметки согласия.

5. **Личный кабинет** на `/personal/`:
   - корень — `bitrix:sale.personal.section` (меню разделов кабинета);
   - список заказов — `bitrix:sale.personal.order.list`
     (`PATH_TO_DETAIL`, `ORDERS_PER_PAGE` по умолчанию 20, `NAV_TEMPLATE`);
   - детали — `bitrix:sale.personal.order.detail`;
   - отмена — `bitrix:sale.personal.order.cancel`;
   - профили покупателя — `bitrix:sale.personal.profile.*`;
   - внутренний счёт/баланс — `bitrix:sale.personal.account`;
   - доплата/смена ПС по заказу — `bitrix:sale.order.payment`.

6. **Кастом шаблонов — только копией в `/local`.** Скопировать штатный шаблон в
   `/local/templates/<тема>/components/bitrix/<компонент>/<свой>/` и править там
   разметку. Логику (сборку заказа) оставлять в `class.php` компонента — не
   переписывать оформление с нуля.

## Рабочий сниппет (путь в /local)

Страница оформления `/local/.../order/make/index.php` — оформитель
`sale.order.ajax` с эталонными параметрами:

```php
<?php
require($_SERVER['DOCUMENT_ROOT'].'/bitrix/header.php');
$APPLICATION->SetTitle('Оформление заказа');

$APPLICATION->IncludeComponent(
    'bitrix:sale.order.ajax',
    'bootstrap_v4',
    [
        'PATH_TO_BASKET'      => '/personal/cart/',
        'PATH_TO_PAYMENT'     => '/personal/order/payment/',
        'PATH_TO_PERSONAL'    => '/personal/',
        'DELIVERY_TO_PAYSYSTEM' => 'd2p',   // сначала доставка, потом оплата
        'ALLOW_NEW_PROFILE'   => 'Y',
        'PAY_FROM_ACCOUNT'    => 'N',
        'SHOW_VAT_PRICE'      => 'Y',
        'SHOW_NOT_CALCULATED_DELIVERIES' => 'L',
        'DISABLE_BASKET_REDIRECT' => 'N',
        // согласие на обработку ПДн привязывается в админке/шаблоне
        'COMPATIBLE_MODE'     => 'Y',
        'TEMPLATE_LOCATION'   => 'popup',
    ],
    false
);

require($_SERVER['DOCUMENT_ROOT'].'/bitrix/footer.php');
```

Личный кабинет `/local/.../personal/orders/index.php` — список заказов:

```php
<?php
require($_SERVER['DOCUMENT_ROOT'].'/bitrix/header.php');
$APPLICATION->SetTitle('Мои заказы');

$APPLICATION->IncludeComponent('bitrix:sale.personal.section', '.default', []);

$APPLICATION->IncludeComponent(
    'bitrix:sale.personal.order.list',
    '.default',
    [
        'PATH_TO_DETAIL'  => '/personal/orders/detail/#ID#/',
        'PATH_TO_CANCEL'  => '/personal/orders/cancel/#ID#/',
        'ORDERS_PER_PAGE' => 20,
        'NAV_TEMPLATE'    => '',
        'SET_TITLE'       => 'Y',
    ],
    false
);

require($_SERVER['DOCUMENT_ROOT'].'/bitrix/footer.php');
```

Кастом шаблона — копия штатного `bootstrap_v4` в
`/local/templates/<тема>/components/bitrix/sale.order.ajax/<свой>/`; в вызове
указать `'<свой>'` вместо `'bootstrap_v4'`. Менять только `template.php` и
вёрстку шагов.

## Выбор API

| Задача | Компонент / приём |
|---|---|
| Корзина (полная) | `bitrix:sale.basket.basket` |
| Мини-корзина в шапке | `bitrix:sale.basket.basket.line` / `.small` |
| Классическое оформление (магазин, корп-сайт) | `bitrix:sale.order.ajax`, шаблон `bootstrap_v4` |
| SPA-витрина / кастомный фронт оформления | `bitrix:sale.order.checkout` |
| Корень кабинета (меню) | `bitrix:sale.personal.section` |
| Список / детали / отмена заказов | `sale.personal.order.list` / `.detail` / `.cancel` |
| Доплата, смена платёжной системы | `bitrix:sale.order.payment` |
| Внутренний счёт покупателя | `bitrix:sale.personal.account` |

- **`sale.order.ajax`** — единый оформитель-мастер (класс
  `SaleOrderAjax extends CBitrixComponent`); собирает заказ внутри `class.php`,
  AJAX-параметры подписаны `Main\Security\Sign\Signer`. Рабочая лошадка для
  типовых магазинов и заявок-счетов. Кастомизируется копией шаблона.
- **`sale.order.checkout`** — оформитель на контроллер-экшн архитектуре
  (`Main\Engine\Controller`); фронт общается с бэком через
  `BX.ajax.runComponentAction('bitrix:sale.order.checkout', 'saveOrder'|'initiatePay'|'recalculateBasket', {...})`,
  серверная логика разнесена по `Controller\Action\Entity\*`. Берут под
  SPA-подобную витрину. ⚠️ Штатный каталог шаблонов у него пустой — шаблон
  приходит из редакции/решения; не рассчитывайте на готовый `bootstrap_v4`.
- Шаблоны и логику между двумя оформителями **не переносить** — это разные
  архитектуры (две поддерживаемые версии API).
- Эталон параметров оформления и кабинета берите из тиражного решения eshop:
  оно задаёт согласованный набор путей `PATH_TO_*` и порядок шагов.

## Проверка

Проверка рендера и структуры — по общему паттерну: [verification](../../operations.md) (CLI для структуры, браузер/preview для рендера; на dev-стенде).

**Режим «только файлы» (без запуска Битрикс):**

- В вызовах `IncludeComponent` имена компонентов точны:
  `bitrix:sale.order.ajax` / `bitrix:sale.order.checkout`,
  `bitrix:sale.personal.section`, `sale.personal.order.list/.detail/.cancel`.
- Пути `PATH_TO_BASKET` / `PATH_TO_PAYMENT` / `PATH_TO_DETAIL` соответствуют
  реальным страницам проекта; шаблоны параметров согласованы (eshop-набор).
- Кастомный шаблон лежит в `/local/templates/.../components/...`, имя шаблона в
  вызове совпадает с именем папки.
- В шаблоне оформления присутствует блок согласия на обработку ПДн.

**Режим «живой Битрикс»:**

- Открыть `/personal/cart/` → «Оформить» → пройти шаги доставки и оплаты;
  убедиться, что список служб доставки и ПС не пуст (иначе сработали ограничения).
- Кнопка «Оформить» недоступна без отметки согласия на обработку ПДн.
- После сохранения — заказ виден в админке (Магазин → Заказы) и в кабинете
  `/personal/`; для онлайн-ПС происходит переход на оплату (`initiatePay`).
- В кабинете список/детали/отмена работают; доплата открывает `sale.order.payment`.

## ⚠️ Риски

- ⚠️ **Согласие на ПДн.** Без подключённого соглашения и блокировки отправки
  формы до отметки согласия сбор ФИО/телефона/адреса нарушает требования по
  обработке персональных данных. Соглашение настраивается в админке, не правкой
  файлов.
- ⚠️ **Не смешивать оформители.** Перенос шаблона/JS между `sale.order.ajax` и
  `sale.order.checkout` ломает оформление — у них разные точки входа
  (подписанный AJAX vs `runComponentAction`).
- ⚠️ **Правка ядра.** Не редактировать компоненты в `/bitrix/components/...`:
  изменения затрутся обновлением и можно сломать оформление заказа. Кастом —
  только копией шаблона в `/local`.
- ⚠️ **Пропавшие доставка/ПС.** Если на оформлении не видно службы или платёжной
  системы — почти всегда сработало ограничение (по цене, локации, типу
  плательщика, ПС), а не ошибка. Проверять список ограничений службы/ПС в админке.
- **Тип плательщика влияет на всё.** Набор свойств заказа и доступные ПС/доставки
  фильтруются по типу плательщика (физлицо/юрлицо). Для заявок-счетов корп-сайта
  выбирать тип «Юр. лицо» и заводить реквизиты как свойства заказа.

## Связано

- [../../00-overview.md](../../00-overview.md) — обзор платформы и модулей
- [../../api-map.md](../../api-map.md) — карта API (модуль `sale`, компоненты)
- [../02-create-iblock.md](../02-create-iblock.md) — каталог товаров на инфоблоках
- [../03-add-properties.md](../03-add-properties.md) — свойства (товара/заказа)
