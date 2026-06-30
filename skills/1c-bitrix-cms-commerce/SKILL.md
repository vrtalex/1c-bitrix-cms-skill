---
name: 1c-bitrix-cms-commerce
description: "Интернет-магазин на «1С-Битрикс: Управление сайтом» — каталог (товары, цены, валюты, торговые предложения/SKU, единицы), корзина и заказы (Order/Basket), платёжные системы и доставка, оформление заказа и личный кабинет, обмен с 1С (CommerceML). Используй для e-commerce задач на сайте Битрикс (не Битрикс24)."
---
# 1c-bitrix-cms-commerce

Интернет-магазин на Битрикс (модули catalog, sale, currency). Гейты оркестратора: код в `/local`, ядро не трогать, перед сдачей — `check-conventions`. Каталог — надстройка над инфоблоком (см. `1c-bitrix-cms-content` для базовых инфоблоков).

## Среда
- «только файлы» → код установки/обработчиков + инструкция; «живой Битрикс» → можно создать товар/заказ и проверить.

## Задача → рецепт (`../../shared/kb/recipes/commerce/`)
- каталог: товар, торговые предложения (SKU), единицы измерения → `commerce/01-catalog-setup.md`
- типы цен и валюты → `commerce/02-prices-currencies.md`
- корзина и заказ (D7 Order/Basket, статусы) → `commerce/03-basket-order.md`
- платёжные системы и доставка (handlers, Business Value) → `commerce/04-payment-delivery.md`
- оформление заказа и личный кабинет (компоненты) → `commerce/05-checkout-cabinet.md`
- обмен с 1С (CommerceML: каталог и заказы) → `commerce/06-1c-exchange.md`

## База знаний
Каталог/заказ — `../../shared/kb/api-map.md` (commerce-строки); инфоблоки — под-скилл `1c-bitrix-cms-content`. Каталог штатных компонентов (`catalog.*`, корзина/заказ — их параметры и что копировать в `/local`) — `../../shared/kb/components/00-index.md` (не грузить целиком, брать нужную карточку). ⚠️ заказ собирается объектами `\Bitrix\Sale\Order`/`Basket` и сохраняется `$order->save()` (не прямой SQL); проверять `Result::isSuccess()`.

## Завершение
`../../shared/scripts/check-conventions.sh <каталог_проекта>`
