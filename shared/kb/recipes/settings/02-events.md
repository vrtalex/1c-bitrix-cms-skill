# 02-events: обработчики событий ядра

## Цель

Подписаться на события «1С-Битрикс: Управление сайтом» (ядро 26.x) и/или
рассылать собственные: валидация и постобработка данных (заказ, элемент
инфоблока, пользователь), интеграция между модулями. Использовать корректный
из двух поддерживаемых вариантов API так, чтобы сигнатура обработчика
совпадала с тем, что присылает ядро.

## Когда применять

- Нужно вмешаться в стандартную операцию ядра до её завершения
  (`OnBeforeIBlockElementUpdate`, `OnBeforeUserAdd`) — проверить или отменить.
- Нужно отреагировать после операции (`OnAfterIBlockElementAdd`,
  `OnSaleOrderSaved`) — отправить уведомление, обновить связанные данные.
- Свой модуль публикует событие для других модулей.
- НЕ для периодических фоновых задач — это агенты (см. соседний рецепт по агентам).
- НЕ для почтовых событий рассылки — это отдельная подсистема (см. ../13-email-events.md).

## Шаги

1. **Выбери место регистрации.**
   - Code-обработчики проекта — в `/local/php_interface/init.php`
     (рантайм, не пишет в БД, живёт один хит).
   - Обработчики своего модуля — в `install/index.php` модуля через
     `registerEventHandler(...)` (постоянная запись в `b_module_to_module`),
     снятие — в `uninstall` через `unRegisterEventHandler(...)`.
2. **Выбери вариант API** (см. раздел «Выбор API»). От него зависит,
   что получит callback: объект `\Bitrix\Main\Event` или позиционные аргументы.
3. **Напиши callback** в виде статического метода класса (класс должен быть
   доступен автозагрузчику или подключён в init.php).
4. **Для `OnBefore*`** — реализуй отмену: бросить исключение или вернуть `false`
   (зависит от контракта конкретного события).
5. **Проверь** (раздел «Проверка»).

## Рабочий сниппет (путь в /local)

`/local/php_interface/init.php` — рантайм-подписка через современный API:

```php
<?php
use Bitrix\Main\EventManager;
use Bitrix\Main\Event;
use Bitrix\Main\EventResult;

// Современный вариант: callback получит \Bitrix\Main\Event $event
EventManager::getInstance()->addEventHandler(
    'iblock',
    'OnAfterIBlockElementAdd',
    ['MyHandlers', 'onElementAdd']
);

class MyHandlers
{
    public static function onElementAdd(Event $event): void
    {
        $fields = $event->getParameter('arFields');
        // постобработка: уведомление, пересчёт, лог
    }

    // OnBefore*: отмена операции через исключение
    public static function onBeforeUserAdd(Event $event): EventResult
    {
        $params = $event->getParameters();
        if (empty($params['EMAIL'])) {
            throw new \Bitrix\Main\SystemException('EMAIL обязателен');
        }
        return new EventResult(EventResult::SUCCESS, $params, 'mymodule');
    }
}
```

Старый вариант подписки в том же init.php (callback получает позиционные
аргументы, не объект `Event`):

```php
// AddEventHandler регистрирует обработчик version=1
AddEventHandler('main', 'OnBeforeUserAdd', ['MyLegacy', 'onBeforeUserAdd']);

class MyLegacy
{
    // Отмена: вернуть false (или бросить исключение, по контракту события)
    public static function onBeforeUserAdd(&$arFields)
    {
        if (empty($arFields['EMAIL'])) {
            global $APPLICATION;
            $APPLICATION->throwException('EMAIL обязателен');
            return false;
        }
        return true;
    }
}
```

Регистрация постоянного обработчика из своего модуля
(`install/index.php` модуля — пишет в `b_module_to_module`):

```php
$eventManager = \Bitrix\Main\EventManager::getInstance();
$eventManager->registerEventHandler(
    'sale', 'OnSaleOrderSaved',
    'mymodule', 'MyModule\\Handlers\\Order', 'onSaved'
);
// в uninstall:
$eventManager->unRegisterEventHandler(
    'sale', 'OnSaleOrderSaved',
    'mymodule', 'MyModule\\Handlers\\Order', 'onSaved'
);
```

Публикация собственного события из кода модуля:

```php
$event = new \Bitrix\Main\Event('mymodule', 'OnAfterOrderProcess', ['ORDER_ID' => $id]);
$event->send();
foreach ($event->getResults() as $result) {
    if ($result->getType() === \Bitrix\Main\EventResult::SUCCESS) {
        $data = $result->getParameters();
    }
}
```

## Выбор API

В ядре две поддерживаемые версии API событий. Разница — в том, что приходит
в callback. Это самый частый источник «тихих» расхождений: код регистрации
не совпадает с сигнатурой обработчика.

| Регистрация | Версия | Что получает callback |
|---|---|---|
| `EventManager::addEventHandler(...)` | v2 | один аргумент — `\Bitrix\Main\Event $event` |
| `EventManager::registerEventHandler(...)` | v2 | `\Bitrix\Main\Event $event` |
| `AddEventHandler(...)` (legacy) | v1 | развёрнутые позиционные аргументы |
| `RegisterModuleDependences(...)` (legacy) | v1 | позиционные аргументы |

- Из `Event` читай параметры через `getParameter($key)` или `getParameters()`.
- Чтобы вернуть данные вызывающему коду — верни
  `new EventResult(EventResult::SUCCESS, [...], 'mymodule')`.
  Если вернёшь не-`EventResult`, ядро обернёт значение как `UNDEFINED`.
- `sort` управляет порядком: меньший вызывается раньше.
- Параметры события можно передать как `\Closure` — тогда они вычисляются
  лениво при первом обращении (полезно, если расчёт дорогой, а подписчиков
  может не быть).
- Рекомендация для нового кода — версия v2 (`addEventHandler` /
  `registerEventHandler` + объект `Event`). Legacy-функции остаются
  тонкими обёртками над тем же диспетчером и применимы, когда нужно совпасть
  со старой сигнатурой существующих обработчиков.

Когда что регистрировать:
- **`addEventHandler`** — рантайм, на текущий хит, без записи в БД. Это
  основной выбор для логики проекта в `init.php`.
- **`registerEventHandler` / `RegisterModuleDependences`** — постоянная запись
  в общее хранилище `b_module_to_module`, живёт между хитами. Это для модулей
  (регистрация в `install.php`/`install/index.php`, снятие в uninstall).

## Проверка

**Режим «только файлы»** (без запущенного Битрикса):
- `init.php` лежит в `/local/php_interface/`, а не в `/bitrix/php_interface/`.
- `php -l /local/php_interface/init.php` — синтаксис корректен.
- Имя события и модуль-источник совпадают с реальным контрактом ядра
  (строка модуля в нижнем регистре: `iblock`, `sale`, `main`).
- Сигнатура callback соответствует выбранной версии API (объект `Event`
  для v2; позиционные аргументы для v1).
- Класс обработчика доступен автозагрузчику или подключён в init.php.

**Режим «живой Битрикс»:**
- Добавь во временный лог в обработчике (`AddMessage2Log(...)` или запись
  в файл) и выполни целевое действие в админке/на сайте.
- Для `OnBefore*` проверь, что отмена реально блокирует операцию и показывает
  сообщение об ошибке.
- Постоянный обработчик виден в таблице `b_module_to_module`; после
  регистрации/снятия диспетчер сам сбрасывает свой кэш списка обработчиков.

## ⚠️ Риски

- ⚠️ **`init.php` не загружается в контексте админки в части сценариев.**
  Не размещай в нём логику, без которой ломаются админ-операции; критичные
  для модуля обработчики регистрируй постоянно через `registerEventHandler`
  в `install/index.php`.
- ⚠️ **Не стартуй сессию в `init.php`.** Старт сессии на этом этапе нарушает
  работу страниц и кэширования.
- ⚠️ **Несовпадение версии API и сигнатуры callback** даёт обработчик,
  который «молча» получает не те аргументы и не срабатывает как ожидалось.
  Сверяй таблицу из раздела «Выбор API».
- ⚠️ **Кэш списка обработчиков.** Диспетчер кэширует содержимое
  `b_module_to_module`. После прямой правки этой таблицы в обход
  `registerEventHandler` обработчики не видны до сброса соответствующего
  управляемого кэша — меняй таблицу только через API.
- В `OnBefore*` отмена выполняется через исключение или `return false`
  по контракту конкретного события — проверяй документацию события,
  не угадывай.

## Связано

- [Обзор подсистемы настроек](../../00-overview.md)
- [Карта API](../../api-map.md)
- [Соглашения и структура /local](../../conventions.md)
- [Почтовые события и рассылки](../13-email-events.md)
