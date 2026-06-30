# Компоненты: корзина

Корзина магазина: страница корзины и мини-корзина в шапке. Корзина живёт на
`FUSER` (анонимная сессия), а не на `USER`. Сбор и сохранение заказа — `04-order.md`;
объектная модель — `../api-map.md` (§10), рецепт `../recipes/commerce/03-basket-order.md`.

---

## `bitrix:sale.basket.basket`

1. **Назначение.** Страница корзины: список добавленных товаров, изменение
   количества, удаление, пересчёт сумм и скидок, переход к оформлению.
2. **Когда брать.** Полная корзина на `/personal/cart/`. Для компактного
   индикатора в шапке (счётчик/сумма) — `bitrix:sale.basket.basket.line`.
3. **Ключевые `arParams`.**
   - `PATH_TO_ORDER` — URL страницы оформления (`/personal/order/make/`).
   - `COLUMNS_LIST` — какие колонки показывать (`NAME`, `PRICE`, `QUANTITY`…).
   - `PRICE_VAT_SHOW_VALUE` — показывать НДС.
   - `USE_PREPAYMENT`, `AUTO_CALCULATION` — пересчёт/предоплата.
   - `HIDE_COUPON` — скрыть поле купона.
   - `OFFERS_PROPS` — свойства SKU в строке корзины.
   - `QUANTITY_FLOAT` — дробное количество.
4. **Типовой вызов.**
   ```php
   $APPLICATION->IncludeComponent("bitrix:sale.basket.basket", ".default", [
       "PATH_TO_ORDER" => "/personal/order/make/",
       "COLUMNS_LIST"  => ["NAME", "PROPS", "PRICE", "QUANTITY", "SUM", "DELETE"],
       "HIDE_COUPON"   => "N",
       "PRICE_VAT_SHOW_VALUE" => "Y",
       "AUTO_CALCULATION_PRICE" => "Y",
   ]);
   ```
5. **Что кастомизируют в `/local`.** Шаблон копируют в
   `/local/templates/<tpl>/components/bitrix/sale.basket.basket/<tpl>/`. Правят
   разметку таблицы корзины в `template.php`; AJAX-пересчёт штатный — обработчики
   и data-атрибуты не ломать. Логику цен/скидок в шаблоне не дублировать.
6. **Типовые ошибки.**
   - `PATH_TO_ORDER` ведёт не на страницу с `sale.order.ajax` → тупик оформления.
   - Сломанный AJAX после правки разметки (удалены нужные классы/контейнеры).
   - Корзина «теряется» — путают `FUSER` и `USER`; корзина на `Fuser::getId()`.
7. **Источник.** [src](https://dev.1c-bitrix.ru/user_help/components/magazin/basket/sale_basket_basket.php)

---

## `bitrix:sale.basket.basket.line`

1. **Назначение.** Мини-корзина в шапке: ссылка на корзину/личный кабинет, счётчик
   позиций и сумма; опционально выпадающий список товаров.
2. **Когда брать.** Индикатор корзины в шаблоне сайта (header). Полную страницу
   корзины рисует `bitrix:sale.basket.basket`.
3. **Ключевые `arParams`.**
   - `PATH_TO_BASKET` — URL страницы корзины.
   - `PATH_TO_ORDER` — URL оформления.
   - `PATH_TO_PERSONAL` — URL личного кабинета.
   - `SHOW_NUM_PRODUCTS`, `SHOW_TOTAL_PRICE` — что показывать в шапке.
   - `SHOW_PRODUCTS` — выпадающий список товаров.
   - `POSITION_FIXED` — закрепить на экране.
4. **Типовой вызов.**
   ```php
   $APPLICATION->IncludeComponent("bitrix:sale.basket.basket.line", ".default", [
       "PATH_TO_BASKET"   => "/personal/cart/",
       "PATH_TO_ORDER"    => "/personal/order/make/",
       "PATH_TO_PERSONAL" => "/personal/",
       "SHOW_NUM_PRODUCTS"=> "Y",
       "SHOW_TOTAL_PRICE" => "Y",
       "SHOW_PRODUCTS"    => "Y",
   ]);
   ```
5. **Что кастомизируют в `/local`.** Шаблон — в
   `…/sale.basket.basket.line/<tpl>/template.php`. Правят разметку индикатора и
   выпадашки; обновление по AJAX при добавлении товара — штатное, контейнеры
   обновления сохранять.
6. **Типовые ошибки.**
   - Счётчик не обновляется — компонент вынесен из динамической области под
     composite-кэшем (показывает старое значение).
   - Пути `PATH_TO_*` не совпали с реальными страницами корзины/кабинета.
7. **Источник.** [src](https://dev.1c-bitrix.ru/user_help/components/magazin/basket/sale_basket_basket_line.php)

---

## Связано

- [`00-index.md`](./00-index.md) — индекс каталога.
- [`04-order.md`](./04-order.md) — оформление заказа (куда ведёт `PATH_TO_ORDER`).
- [`02-catalog.md`](./02-catalog.md) — кнопки «в корзину» на витрине.
- [`../recipes/commerce/03-basket-order.md`](../recipes/commerce/03-basket-order.md) — объектная модель `Basket`/`Order`.
