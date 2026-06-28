# Объявить свой REST-метод

## Цель

Добавить в REST API сайта на «1С-Битрикс: Управление сайтом» (ядро 26.x) собственный метод — чтобы внешняя система или JS-фронтенд могли вызвать его как `mymodule.foo.add`, `mymodule.foo.list` и т.п. Рассмотрены два подхода: классический через событие `OnRestServiceBuildDescription` (массивы коллбэков) и современный D7-контроллер (`restIntegration`). Современный V3 на PHP 8-атрибутах упоминается отдельно.

## Когда применять

- Нужен программный доступ к данным/логике сайта по REST из своего модуля.
- Хочется вызывать собственный метод из самой системы (из админки/публички через `BX.rest.callMethod`) без регистрации OAuth-приложения.
- Внешняя интеграция должна дёргать кастомную бизнес-логику через входящий вебхук.

В этом ядре REST существует в двух поддерживаемых поколениях, и они работают одновременно: классическое (`OnRestServiceBuildDescription` / `IRestService`) и D7-контроллеры (`restIntegration`), плюс новейшее V3 на атрибутах. Для нового кода предпочтителен D7-контроллер.

## Шаги

### Подход A — классический (событие `OnRestServiceBuildDescription`)

1. В `install/index.php` своего модуля зарегистрировать обработчик события `OnRestServiceBuildDescription` модуля `rest`.
2. Создать класс-сервис, наследующий `IRestService`. Метод `OnRestServiceBuildDescription()` возвращает дерево `scope → [имя_метода => callback]`.
3. Реализовать коллбэки с сигнатурой `function($params, $start, CRestServer $server)`. Ошибки бросать через `RestException`.
4. Для пагинации `*.list` использовать хелперы `IRestService::getNavData($start)` и `setNavData()` (стандарт — страница по 50 записей).

### Подход B — D7-контроллер (`restIntegration`, предпочтительно)

1. В `.settings.php` своего модуля включить `controllers.restIntegration.enabled = true`.
2. Создать контроллер `\Vendor\Module\Controller\Foo extends \Bitrix\Main\Engine\Controller` с публичными `*Action`-методами — они станут REST-методами `module.foo.*`.
3. Правами рулить через `getDefaultPreFilters()` / `configureActions()` (фильтры `Scope`, `Csrf`, кастомные `ActionFilter`).
4. Сбросить кэш скоупов: `ScopeManager::cleanCache()` (список скоупов кэшируется на 7 дней в каталоге `/rest/scope/`).

### Регистрация scope

Скоуп по умолчанию равен ID модуля. Дополнительные имена задаются опцией `scopes` в `restIntegration`, скрыть скоуп-модуль — `hideModuleScope`. Имена могут иметь алиасы (например, `tasks → task`), поэтому не полагайтесь на буквальное совпадение имени модуля и скоупа.

### Локальный вызов своего REST изнутри системы

Объявленный метод вызывается из админки/публички через JS-расширение `rest.integration` и `BX.rest.callMethod` по авторизации сессии (`SessionAuth`) — отдельное OAuth-приложение не требуется.

## Рабочий сниппет/конфиг

Путь: `/local/modules/vendor.module/`

`/local/modules/vendor.module/install/index.php` (фрагмент `DoInstall()`):

```php
$eventManager = \Bitrix\Main\EventManager::getInstance();
$eventManager->registerEventHandler(
    'rest', 'OnRestServiceBuildDescription',
    'vendor.module', '\\Vendor\\Module\\RestService', 'onBuildDescription'
);
```

`/local/modules/vendor.module/lib/restservice.php` — классический сервис:

```php
namespace Vendor\Module;

use CRestServer;
use RestException;

class RestService extends \IRestService
{
    public static function onBuildDescription(): array
    {
        return [
            'mymodule' => [
                'mymodule.foo.add'  => [__CLASS__, 'fooAdd'],
                'mymodule.foo.list' => [__CLASS__, 'fooList'],
            ],
        ];
    }

    // Сигнатура коллбэка: ($params, $start, CRestServer $server)
    public static function fooAdd(array $params, $start, CRestServer $server)
    {
        if (empty($params['TITLE']))
        {
            // Точную форму ошибки сверять с доками вендора.
            throw new RestException('TITLE is required');
        }
        // ... бизнес-логика ...
        return ['id' => 123];
    }

    public static function fooList(array $params, $start, CRestServer $server)
    {
        // Пагинация: страница по 50 (IRestService::LIST_LIMIT = 50)
        $nav = self::getNavData($start); // ['limit'=>50,'offset'=>...] или ['nPageSize'=>50,'iNumPage'=>...]
        $items = []; // выборка с учётом $nav
        $total = 0;  // общее число записей
        // setNavData добавляет к ответу total и next (следующая страница по 50)
        return self::setNavData($items, ['count' => $total, 'offset' => 0]);
    }
}
```

Альтернатива — D7-контроллер. В `.settings.php` модуля:

```php
// /local/modules/vendor.module/.settings.php
return [
    'controllers' => [
        'value' => [
            'defaultNamespace' => '\\Vendor\\Module\\Controller',
            'restIntegration'  => ['enabled' => true],
        ],
        'readonly' => true,
    ],
];
```

```php
// /local/modules/vendor.module/lib/controller/foo.php
namespace Vendor\Module\Controller;

use Bitrix\Main\Engine\Controller;

class Foo extends Controller
{
    // Пустой configureActions() применяет ДЕФОЛТНЫЕ префильтры
    // (Authentication + Csrf + Scope). Это аутентификация и проверка scope,
    // но НЕ object-level права — их проверяем в самом экшене (см. ниже).
    public function configureActions() { return []; /* prefilters: Authentication, Csrf, Scope */ }

    public function addAction(array $fields)
    {
        // ⚠️ Object-level авторизация для write-метода — ОБЯЗАТЕЛЬНА и явная.
        // Scope-префильтр пускает по токену, но не знает о правах на объект.
        global $USER;
        if (!$USER->CanDoOperation('edit_php')) {
            $this->addError(new \Bitrix\Main\Error('Access denied', 'access_denied'));
            return null;
        }
        // Для инфоблочных сущностей — права именно на этот инфоблок:
        // if (\CIBlockRights::UserHasRightTo($iblockId, $iblockId, 'element_edit') ...) { ... }
        /* => mymodule.foo.add */
        return ['id' => 1];
    }

    public function listAction() { /* => mymodule.foo.list */ return []; }
}
```

Современное поколение V3 (PHP 8): контроллер наследует `Bitrix\Rest\V3\Controller\RestController`, поля описываются DTO с атрибутами (`#[OrmEntity]`, `#[Filterable]`, `#[Sortable]`), трейты `ListOrmActionTrait` / `GetOrmActionTrait` дают CRUD/list поверх ORM и автогенерацию OpenAPI. Конфигурируется через ключ `rest` в `.settings.php` модуля. Подробные контракты атрибутов — в документации вендора.

Локальный вызов из JS системы:

```js
BX.rest.callMethod('mymodule.foo.list', { /* params */ }, function (result) {
    if (result.error()) { console.error(result.error()); }
    else { console.log(result.data()); }
});
```

Пакетный вызов `batch` объединяет до 50 команд за один запрос.

## Проверка

Режим «только файлы» (без запущенного Битрикса):

- `find /local/modules/vendor.module -name index.php -path '*install*'` — есть установщик с `registerEventHandler`.
- `php -l /local/modules/vendor.module/lib/restservice.php` — синтаксис корректен; класс наследует `IRestService` (или контроллер — `\Bitrix\Main\Engine\Controller`).
- Для подхода B: в `.settings.php` присутствует `controllers.restIntegration.enabled = true`.
- Сигнатура коллбэка — три параметра `($params, $start, $server)`; ошибки через `RestException`.

Режим «живой Битрикс»:

- Метод появляется в ответе глобального `methods` (scope `_global`) и в `scope`.
- Вызов изнутри системы: `BX.rest.callMethod('mymodule.foo.list', {})` в консоли браузера на странице админки возвращает данные.
- Вызов через входящий вебхук: `https://<site>/rest/<userId>/<webhookToken>/mymodule.foo.list` (требуется HTTPS).
- Для подхода B после правки контроллера: `\Bitrix\Rest\Engine\ScopeManager::cleanCache()` — иначе новый скоуп не появится (кэш 7 дней).

## ⚠️ Риски

- ⚠️ **Object-level права — явно в каждом write-экшене.** Пустой `configureActions()` применяет ДЕФОЛТНЫЕ префильтры (`Authentication` + `Csrf` + `Scope`): это аутентификация и проверка scope, но НЕ права на конкретный объект. Для мутирующих методов (`add`/`update`/`delete`) проверку прав делайте явно внутри экшена — `$USER->CanDoOperation(...)`, `CIBlockRights::UserHasRightTo($iblockId, ...)` или явная роль; при отказе возвращайте ошибку `access_denied`. Без этого метод откроет запись за пределами полномочий пользователя — особенно при вызове через вебхук.
- ⚠️ **Кэш скоупов 7 дней.** После добавления D7-контроллера новый скоуп не появится, пока не вызван `ScopeManager::cleanCache()`. На проде это выглядит как «метод не виден».
- ⚠️ **Точную форму возврата и ошибок сверять с документацией вендора.** Формат успешного ответа, поля пагинации (`total`/`next`) и контракт `RestException` уточняйте по актуальной документации вендора под конкретную сборку.
- Входящие вебхуки требуют HTTPS — на HTTP метод по вебхуку не вызовется.
- Лимит пагинации `*.list` — 50 записей за вызов (`IRestService::LIST_LIMIT = 50`); `batch` — до 50 команд за запрос. Проектируйте клиента под постраничную выборку.
- Не смешивайте поколения произвольно: для одного метода выбирайте один способ объявления (классический ИЛИ D7-контроллер ИЛИ V3).

## Связано

- [REST: карта API](../../api-map.md)
- [Обзор подсистем](../../00-overview.md)
- [События модуля main](../settings/02-events.md)
