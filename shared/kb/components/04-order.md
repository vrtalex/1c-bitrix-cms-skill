# Компоненты: оформление заказа и кабинет

Оформление заказа одной страницей — полная карточка; личный кабинет покупателя —
заглушка (набор компонентов `sale.personal.*`). Объектная модель заказа —
`../api-map.md` (§10), рецепт `../recipes/commerce/05-checkout-cabinet.md`.

---

## `bitrix:sale.order.ajax`

1. **Назначение.** Оформление заказа на одной странице по AJAX: персональные
   данные, доставка, оплата, свойства заказа — без перезагрузки, с пересчётом.
2. **Когда брать.** Рабочая лошадка чекаута (`/personal/order/make/`). Когда нужен
   React-чекаут на `\Bitrix\Main\Engine\Controller` — `bitrix:sale.order.checkout`;
   но для большинства проектов берут `sale.order.ajax`.
3. **Ключевые `arParams`.**
   - `PATH_TO_BASKET` — вернуться в корзину.
   - `PATH_TO_PAYMENT` — страница оплаты после оформления.
   - `PATH_TO_PERSONAL` — личный кабинет.
   - `ALLOW_AUTO_REGISTER` — авто-регистрация покупателя.
   - `SEND_NEW_ORDER_EMAIL` — письмо о новом заказе.
   - `DELIVERY_TO_PAYSYSTEM` — порядок «доставка→оплата».
   - `ALLOW_NEW_PROFILE`, `SHOW_PAYMENT_SERVICES_NAMES` — профили/оплаты.
   - `COMPATIBLE_MODE` — режим совместимости со старыми шаблонами.
4. **Типовой вызов.**
   ```php
   $APPLICATION->IncludeComponent("bitrix:sale.order.ajax", ".default", [
       "PATH_TO_BASKET"      => "/personal/cart/",
       "PATH_TO_PAYMENT"     => "/personal/order/payment/",
       "PATH_TO_PERSONAL"    => "/personal/orders/",
       "ALLOW_AUTO_REGISTER" => "Y",
       "SEND_NEW_ORDER_EMAIL"=> "Y",
       "DELIVERY_TO_PAYSYSTEM" => "d2p",
   ]);
   ```
5. **Что кастомизируют в `/local`.** Шаблон копируют в
   `/local/templates/<tpl>/components/bitrix/sale.order.ajax/<tpl>/`. Это крупный
   шаблон со своим JS — правят разметку шагов в `template.php`, но AJAX-контейнеры
   и data-атрибуты сохраняют. Бизнес-логику (доставка/оплата/скидки) меняют в
   настройках систем доставки/оплаты и обработчиках, не в шаблоне.
6. **Типовые ошибки.**
   - Не настроены платёжные системы/доставки → шаги оформления пустые.
   - Письмо о заказе не уходит — `SEND_NEW_ORDER_EMAIL=N` или нет SMTP/шаблона.
   - Сломанный AJAX после удаления нужных контейнеров из шаблона.
   - `PATH_TO_*` рассинхронены с реальными страницами корзины/оплаты/кабинета.
7. **Источник.** [src](https://dev.1c-bitrix.ru/user_help/components/magazin/zakaz/sale_order_ajax.php)

---

## `bitrix:sale.personal.*` (заглушка — личный кабинет)

1. **Назначение.** Набор компонентов личного кабинета покупателя: список заказов,
   деталь заказа, профили доставки, оплата неоплаченного заказа
   (`sale.personal.order.list`, `sale.personal.order.detail` и т.п.).
2. **Когда брать.** Раздел `/personal/` (история и статусы заказов). Компоненты
   ставятся мастером раздела личного кабинета; набор и пути конфигурируются в
   шаблоне раздела `/personal/`, поэтому полную карточку с `arParams` здесь не
   разворачиваем — отсылаем к рецепту `../recipes/commerce/05-checkout-cabinet.md`.
7. **Источник.** [src](https://dev.1c-bitrix.ru/user_help/components/magazin/profiles/index.php)

---

## Связано

- [`00-index.md`](./00-index.md) — индекс каталога.
- [`03-basket.md`](./03-basket.md) — корзина (вход в оформление).
- [`../recipes/commerce/05-checkout-cabinet.md`](../recipes/commerce/05-checkout-cabinet.md) — оформление и личный кабинет.
- [`../api-map.md`](../api-map.md) — заказы и коммерция (§10): `Order`/`Basket`/`save()`.
