# Рецепт settings/01 — config-settings: конфигурация ядра и настройки модулей

> Подсистема: 1c-bitrix-cms-settings. Ядро БУС 26.x. Две поддерживаемые версии API (D7 и legacy) — обе официальны.
> Основан на изучении ядра «1С-Битрикс: Управление сайтом» (SM_VERSION 26.x) и официальной документации вендора.

## Цель

Разложить по полкам три разных хранилища настроек Bitrix и научиться выбирать
нужное:

1. **`\Bitrix\Main\Config\Configuration`** — файловые параметры окружения из
   `.settings.php` (БД-соединения, кэш, сессии, обработка исключений, crypto,
   http, routing, services). Меняются редко, на уровне сервера/проекта.
2. **`\Bitrix\Main\Config\Option`** — настройки модулей в БД (таблица
   `b_option`), те самые, что правятся в админке «Настройки → Настройки
   продукта → Настройки модулей».
3. **ServiceLocator** (секция `services` в `.settings.php`) — DI-контейнер для
   регистрации собственных сервисов.

Итог — понимание, что класть в файл, что в БД, и как переопределять поведение
без правки ядра.

## Когда применять

- Нужно прочитать/изменить параметр окружения: кэш-движок, параметры сессии,
  composer-путь, набор файлов роутинга — это `Configuration`.
- Нужно прочитать/сохранить настройку модуля (свою или штатную), которую видно в
  админке, — это `Option`.
- Нужно зарегистрировать собственный сервис (репозиторий, мейлер, клиент API) для
  получения через контейнер — это `services` + `ServiceLocator`.
- Нужно переопределить параметр на конкретном окружении (dev/stage/prod), не
  трогая основной файл, — это `.settings_extra.php`.
- Кастомизация без правки ядра: всё кладём в `/local`, который приоритетнее
  `/bitrix`.

## Шаги

1. **Определить тип настройки.** Если параметр меняется из админки и должен жить в
   БД — `Option`. Если это инфраструктура (соединения/кэш/сессии/services) —
   `Configuration` (файл `.settings.php`). Если это объект-зависимость для DI —
   секция `services`.
2. **Configuration — чтение.** `Configuration::getValue($name)` (статический
   шорткат) или `Configuration::getInstance()->get($name)` для глобального
   конфига. Помодульный — `Configuration::getInstance($moduleId)`. Хранение в
   файле: `[$name => ['value' => ..., 'readonly' => bool]]`; `get()` возвращает
   именно `['value']`.
3. **Configuration — запись.** `getInstance()->add($name, $value)` /
   `setValue($name, $value)`, затем `saveConfiguration()` (пишет файл через
   `var_export`). ⚠️ Запись поддержана только для **глобального** конфига; для
   модуля бросается `InvalidOperationException` («There is no support to rewrite
   .settings.php in module»).
4. **Слой переопределений.** Поверх `.settings.php` накладывается
   `.settings_extra.php` (та же структура) — удобно для секрет-значений и
   различий между окружениями, основной файл остаётся под контролем версий.
   Файлы из `/local` приоритетнее `/bitrix` (`Loader::getLocal`).
5. **Option — чтение/запись.** `Option::get('module.id', 'KEY', $default,
   $siteId)` читает значение; `Option::getReal(...)` — значение без подстановки
   дефолта из описания опции; `Option::set('module.id', 'KEY', $value, $siteId)`
   сохраняет; `Option::delete('module.id', ['name' => 'KEY'])` удаляет. Модуль
   должен быть подключён (`Loader::includeModule`) для своих опций.
6. **Свой сервис в DI.** Описать в `<module>/.settings.php` (или в корневом для
   глобальных) секцию `services` и получать через `ServiceLocator::getInstance()
   ->get($code)`. Сервисы модуля поднимаются автоматически после
   `Loader::includeModule()`.

## Рабочий сниппет

Файл подключается из `init.php` либо запускается одноразово под админом. Путь:
`/local/php_interface/include/settings_demo.php`. Ядро не трогаем.

```php
<?php
// /local/php_interface/include/settings_demo.php
use Bitrix\Main\Config\Configuration;
use Bitrix\Main\Config\Option;
use Bitrix\Main\DI\ServiceLocator;
use Bitrix\Main\Loader;

if (!defined('B_PROLOG_INCLUDED') || B_PROLOG_INCLUDED !== true) {
    die();
}

// --- 1. Configuration: параметры окружения из .settings.php ---
$cacheCfg = Configuration::getValue('cache');           // ['type' => 'files', ...]
$cacheType = $cacheCfg['type'] ?? 'files';
$routing  = Configuration::getValue('routing');         // ['config' => [...]]

// Изменить ГЛОБАЛЬНЫЙ конфиг (например, добавить свой параметр окружения):
$conf = Configuration::getInstance();
$conf->setValue('my_app', ['feature_x' => true]);       // правит in-memory
$conf->saveConfiguration();                             // пишет в bitrix/.settings.php
// Помодульный конфиг через setValue/saveConfiguration не пишется (исключение).

// --- 2. Option: настройки модуля в БД (b_option) ---
// Чтение штатной опции main: размер кэша/прочее правится в админке.
$adminEmail = Option::get('main', 'email_from', 'noreply@example.com');

// Своя настройка собственного модуля (Loader::includeModule для своих опций):
if (Loader::includeModule('vendor.mymodule')) {
    $apiKey = Option::get('vendor.mymodule', 'API_KEY', '');     // с дефолтом
    $rawKey = Option::getReal('vendor.mymodule', 'API_KEY');     // без дефолта из описания
    Option::set('vendor.mymodule', 'LAST_SYNC', date('c'));      // сохранить в БД
    // Удалить одну опцию:
    Option::delete('vendor.mymodule', ['name' => 'TMP_TOKEN']);
}

// --- 3. ServiceLocator: получить зарегистрированный сервис ---
if (Loader::includeModule('vendor.mymodule')) {
    $locator = ServiceLocator::getInstance();
    if ($locator->has('vendor.mymodule.repository')) {
        $repo = $locator->get('vendor.mymodule.repository');     // синглтон
    }
}
```

Регистрация сервиса — в `.settings.php` модуля
(`/local/modules/vendor.mymodule/.settings.php`) либо в корневом
`/local/.settings.php` для глобальных:

```php
<?php
// секция services читается ServiceLocator
return [
    'services' => ['value' => [
        // autowiring: конструктор public, все параметры типизированы классами
        'vendor.mymodule.repository' => [
            'className' => \Vendor\MyModule\Repository::class,
        ],
        // фабрика-замыкание для скалярных/сложных зависимостей:
        \Vendor\MyModule\MailerInterface::class => [
            'constructor' => static fn() => new \Vendor\MyModule\SmtpMailer('smtp.example.com'),
        ],
    ]],
];
```

## Выбор API

| Задача | Инструмент | Хранилище |
|--------|-----------|-----------|
| БД-соединения, кэш, сессии, crypto, http, routing, services | `Configuration` | файл `.settings.php` |
| Параметр окружения dev/stage/prod | `.settings_extra.php` (поверх) | файл |
| Настройка модуля из админки (свой/штатный модуль) | `Option::get/set/getReal/delete` | БД `b_option` |
| Регистрация объекта-зависимости (DI) | `services` + `ServiceLocator::get` | файл `.settings.php` |

Правила различения:

- **`Configuration` vs `Option`.** Оба лежат в неймспейсе
  `\Bitrix\Main\Config\*` и легко путаются. `Configuration` — это **файл**
  `.settings.php` (инфраструктура, под контролем версий, меняется редко).
  `Option` — это **БД** (`b_option`), значения правятся из админки, у каждого
  может быть привязка к сайту (`$siteId`). Класс `Option` — D7, но семантически
  продолжает старую систему опций `COption`; для нового кода берём `Option`.
- **Приоритет файлов.** `/local/.settings.php` приоритетнее `/bitrix/.settings.php`
  (резолв через `Loader::getLocal`). Кастомные сервисы и переопределения кладём в
  `/local`.
- **Приоритет регистраций сервисов.** Глобальный `.settings.php` побеждает
  помодульный: `registerByModuleSettings` пропускает уже зарегистрированные коды.
  Это штатный механизм переопределения сервиса на уровне проекта — описать тот же
  код в корневом конфиге.
- **ServiceLocator — контейнер синглтонов.** `get()` кэширует объект; повторный
  вызов вернёт тот же экземпляр. Для нового объекта на каждый вызов контейнер не
  подходит — используйте фабрику в своём коде.
- **`Option::get` vs `getReal`.** `get` подставляет значение по умолчанию из
  описания опции, если в БД пусто; `getReal` возвращает строго то, что в БД.

## Проверка

**Режим «только файлы»** (есть код, нет живого ядра/БД):

- Найти `.settings.php` в `/local` и `/bitrix` (`/local` приоритетнее);
  убедиться, что это PHP-массив с секциями (`connections`, `cache`, `session`,
  `services` и т.д.) формата `['<name>' => ['value' => ..., 'readonly' => ...]]`.
- Для сервисов — проверить наличие секции `services` и корректность ключей
  `className` / `constructor` / `constructorParams`.
- Проверить, что кастомизации лежат в `/local`, а не в `/bitrix`.

**Режим «живой Битрикс»**:

- `Configuration::getValue('cache')` — вернёт текущую конфигурацию кэша; так же
  проверяются `connections`, `session`, `routing`.
- После `Option::set(...)` повторный `Option::get(...)` (или
  `Option::getReal(...)`) возвращает записанное; в админке «Настройки модулей»
  значение видно.
- Для сервиса: `ServiceLocator::getInstance()->has($code)` после
  `Loader::includeModule(...)` → `true`, а `get($code)` отдаёт объект ожидаемого
  класса.

## ⚠️ Риски

- ⚠️ **`saveConfiguration()` перезаписывает `.settings.php` целиком** через
  `var_export`. Ошибка в значении или прерывание записи может повредить файл,
  через который поднимается всё ядро (БД-соединения). Перед записью — резервная
  копия файла; правьте на стенде, не на проде вслепую.
- ⚠️ **Секреты в `.settings.php`.** Файл содержит пароль БД и `crypto`-ключи.
  Выносите чувствительные переопределения в `.settings_extra.php` и держите его
  вне публичного контроля версий, чтобы избежать утечки доступов.
- ⚠️ **Запись помодульного конфига не поддержана.** Попытка `saveConfiguration()`
  для `Configuration::getInstance($moduleId)` бросит `InvalidOperationException` —
  модульные настройки правьте через `Option` (БД), а не через файл модуля.
- **Autowiring строг.** Конструктор сервиса обязан быть `public`, каждый
  параметр — типизирован реальным классом/интерфейсом (нельзя `array`/`mixed`/
  нетипизированный без значения по умолчанию), иначе `ServiceNotFoundException`.
  Скалярные зависимости передавайте через `constructor`-замыкание или
  `constructorParams`.
- **Сервис недоступен до `includeModule`.** Регистрации из `<module>/.settings.php`
  поднимаются только после `Loader::includeModule()`. Обращение к
  `ServiceLocator::get($code)` раньше — `ServiceNotFoundException`.
- **`Option` требует подключённого модуля** для своих опций и учитывает
  `$siteId`: одно и то же имя может иметь разное значение на разных сайтах —
  передавайте сайт явно, когда настройка сайт-зависимая.

## Связано

- [Обзор подсистемы](../../00-overview.md)
- [Карта API D7 ↔ legacy](../../api-map.md)
- [Соглашения и стиль кода](../../conventions.md)
- [Транзакционные письма (email-события)](../13-email-events.md)
