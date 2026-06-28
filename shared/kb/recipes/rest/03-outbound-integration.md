# 03-outbound-integration: исходящая интеграция (push данных во внешний сервис/CRM)

## Цель

По событию ядра «1С-Битрикс: Управление сайтом» (26.x) — например
`OnSaleOrderSaved` или `OnAfterIBlockElementAdd` — передать данные во внешний
сервис (CRM, ERP, webhook стороннего API). Сетевой вызов выполняет
`\Bitrix\Main\Web\HttpClient` (PSR-18-совместимый, с `main` 23.0.0), но
не синхронно внутри обработчика, а через очередь и агент с ретраями, чтобы
сохранение заказа/элемента не зависело от доступности внешнего сервиса.

## Когда применять

- Нужно при создании/изменении сущности отправить её во внешнюю систему
  (заявка → CRM, заказ → ERP/1С, регистрация → рассылочный сервис).
- Внешний сервис может быть недоступен или медленным, и его недоступность
  не должна ломать пользовательскую операцию на сайте.
- Нужны гарантии доставки: повтор при сбое, отсутствие дублей (идемпотентность),
  журнал обращений.
- НЕ для входящего REST (внешняя система читает данные сайта) — это вебхуки.
- НЕ для почтовых уведомлений — это подсистема email (см. ## Связано).

## Шаги

1. **Подписаться на событие** в `/local/php_interface/init.php`. Для
   постобработки подходят `OnSaleOrderSaved`, `OnAfterIBlockElementAdd`,
   `OnAfterIBlockElementUpdate` и подобные `OnAfter*`. Контракт callback
   (объект `\Bitrix\Main\Event` или позиционные аргументы) — см. ## Связано.

2. **В обработчике НЕ ходить в сеть.** Вместо синхронного HTTP-вызова положить
   задание в очередь — отдельную таблицу (D7 ORM). Запись содержит тип сущности,
   её ID, полезную нагрузку (или достаточно ID, чтобы собрать payload при
   отправке), ключ идемпотентности и счётчик попыток.

3. **Отправлять очередь агентом.** Агент (`CAgent::AddAgent`, перевод на cron на
   production) выбирает пачку незавершённых заданий, по каждому делает HTTP-вызов
   через `HttpClient`, при успехе помечает `DONE`, при сбое увеличивает счётчик
   попыток и оставляет на повтор; после лимита попыток — статус `FAILED` и запись
   в журнал.

4. **Секреты — вне VCS.** URL и токен внешнего сервиса хранить в
   `bitrix/.settings.php` (секция `utf_mode`-соседняя пользовательская секция или
   собственный ключ) либо в опциях модуля (`Option::set`), а не в коде обработчика
   и не в git. Файл `.settings.php` должен быть в `.gitignore`.

5. **Логировать.** Каждую попытку (URL без секрета, HTTP-статус, длительность,
   тело ответа при ошибке) писать в журнал — таблицу очереди и/или
   `AddMessage2Log` / PSR-3-логгер ядра.

## Рабочий сниппет (путь в /local)

`/local/php_interface/init.php` — подписка и постановка в очередь:

```php
use Bitrix\Main\EventManager;

EventManager::getInstance()->addEventHandler(
    'sale', 'OnSaleOrderSaved',
    ['\\Local\\Integration\\OutboundQueue', 'onOrderSaved']
);
EventManager::getInstance()->addEventHandler(
    'iblock', 'OnAfterIBlockElementAdd',
    ['\\Local\\Integration\\OutboundQueue', 'onElementAdd']
);
```

`/local/php_interface/include/integration/outbound_queue.php` — очередь и агент:

```php
namespace Local\Integration;

use Bitrix\Main\Web\HttpClient;
use Bitrix\Main\Web\Json;
use Bitrix\Main\Config\Configuration;
use Bitrix\Main\Type\DateTime;

class OutboundQueue
{
    private const MAX_ATTEMPTS = 5;
    private const BATCH = 20;

    // Обработчик события: только ставим задание, без сети.
    public static function onOrderSaved(\Bitrix\Main\Event $event): void
    {
        /** @var \Bitrix\Sale\Order $order */
        $order = $event->getParameter('ENTITY');
        if (!$order) {
            return;
        }
        self::enqueue('order', (int)$order->getId());
    }

    // version=1: позиционные аргументы (OnAfter* инфоблока).
    public static function onElementAdd(array $fields): void
    {
        if (!empty($fields['ID'])) {
            self::enqueue('iblock_element', (int)$fields['ID']);
        }
    }

    private static function enqueue(string $type, int $entityId): void
    {
        // Ключ идемпотентности: один и тот же объект не задвоится в очереди.
        $idemKey = $type . ':' . $entityId;
        $exists = OutboundJobTable::getList([
            'filter' => ['=IDEM_KEY' => $idemKey, '@STATUS' => ['NEW', 'RETRY']],
            'select' => ['ID'],
            'limit'  => 1,
        ])->fetch();
        if ($exists) {
            return;
        }
        OutboundJobTable::add([
            'ENTITY_TYPE' => $type,
            'ENTITY_ID'   => $entityId,
            'IDEM_KEY'    => $idemKey,
            'STATUS'      => 'NEW',
            'ATTEMPTS'    => 0,
            'CREATED_AT'  => new DateTime(),
        ]);
    }

    // Агент: вызывается строкой, ОБЯЗАН вернуть строку своего перезапуска.
    public static function run(): string
    {
        $cfg = Configuration::getValue('outbound_integration') ?: [];
        $url = (string)($cfg['url'] ?? '');
        $token = (string)($cfg['token'] ?? '');
        if ($url === '') {
            // Нет конфига — не теряем агент, перезапускаем.
            return '\\Local\\Integration\\OutboundQueue::run();';
        }

        $jobs = OutboundJobTable::getList([
            'filter' => ['@STATUS' => ['NEW', 'RETRY']],
            'order'  => ['ID' => 'ASC'],
            'limit'  => self::BATCH,
        ]);

        while ($job = $jobs->fetch()) {
            self::deliver($job, $url, $token);
        }

        return '\\Local\\Integration\\OutboundQueue::run();';
    }

    private static function deliver(array $job, string $url, string $token): void
    {
        $payload = self::buildPayload($job['ENTITY_TYPE'], (int)$job['ENTITY_ID']);

        $http = new HttpClient(['socketTimeout' => 10, 'streamTimeout' => 20]);
        $http->setHeader('Content-Type', 'application/json');
        $http->setHeader('Authorization', 'Bearer ' . $token);
        // Idempotency-Key: внешний сервис не создаст дубль при повторе.
        $http->setHeader('Idempotency-Key', (string)$job['IDEM_KEY']);

        $ok = $http->post($url, Json::encode($payload));
        $status = (int)$http->getStatus();

        if ($ok && $status >= 200 && $status < 300) {
            OutboundJobTable::update($job['ID'], [
                'STATUS'    => 'DONE',
                'HTTP_CODE' => $status,
                'DONE_AT'   => new DateTime(),
            ]);
            return;
        }

        $attempts = (int)$job['ATTEMPTS'] + 1;
        $failed = $attempts >= self::MAX_ATTEMPTS;
        OutboundJobTable::update($job['ID'], [
            'STATUS'    => $failed ? 'FAILED' : 'RETRY',
            'ATTEMPTS'  => $attempts,
            'HTTP_CODE' => $status,
            'LAST_ERROR'=> mb_substr((string)$http->getResult(), 0, 1000),
        ]);
        \AddMessage2Log(
            "outbound {$job['IDEM_KEY']} attempt {$attempts} http={$status}",
            'outbound_integration'
        );
    }

    private static function buildPayload(string $type, int $id): array
    {
        // Собираем актуальные данные на момент отправки (а не на момент события).
        // ... выборка заказа/элемента по $id ...
        return ['type' => $type, 'id' => $id];
    }
}
```

Регистрация агента (однократно — консольный скрипт в `/local` или
`install/index.php` модуля; перевод на cron — см. рецепт по агентам):

```php
\CAgent::AddAgent(
    '\\Local\\Integration\\OutboundQueue::run();',
    'main', 'N', 60   // каждые 60 с (на хитах); на проде — cron
);
```

Секреты — в `bitrix/.settings.php` (вне git):

```php
'outbound_integration' => [
    'value' => [
        'url'   => 'https://crm.example.com/api/v1/orders',
        'token' => 'CHANGE_ME',   // реальное значение только на сервере
    ],
    'readonly' => true,
],
```

Подключение include-файла — в `init.php` (если класс не на автозагрузчике):

```php
require_once __DIR__ . '/include/integration/outbound_queue.php';
```

## Проверка

**Режим «только файлы»** (без живого Битрикса):

- PHP-линт: `php -l /local/php_interface/init.php` и
  `php -l /local/php_interface/include/integration/outbound_queue.php`.
- Проверить, что обработчик не вызывает `HttpClient`/`post`/`get` напрямую —
  сеть только в агенте `run()`/`deliver()`.
- Убедиться, что `enqueue()` проверяет `IDEM_KEY` перед вставкой (нет дублей),
  а `run()` всегда возвращает строку своего перезапуска.
- Проверить, что URL и токен читаются из `Configuration::getValue(...)`/опций,
  а не зашиты в код, и что `.settings.php` в `.gitignore`.

**Режим «живой Битрикс»**:

- Создать тестовый заказ/элемент → в таблице очереди появляется запись
  `STATUS='NEW'` с заполненным `IDEM_KEY`.
- Дёрнуть агент вручную (CLI/админка «Настройки → Агенты») при поднятом
  заглушечном эндпоинте → запись переходит в `DONE`, `HTTP_CODE` 2xx.
- Эмулировать сбой внешнего сервиса (5xx/таймаут) → `STATUS='RETRY'`,
  `ATTEMPTS` растёт; после `MAX_ATTEMPTS` → `FAILED` и строка в журнале
  (`AddMessage2Log` → «Настройки → Инструменты → Журнал событий», тег
  `outbound_integration`).
- Повторно сохранить ту же сущность до отправки → второй записи в очереди нет
  (идемпотентность на стороне сайта); повтор доставки несёт тот же
  `Idempotency-Key` (идемпотентность на стороне сервиса).

## ⚠️ Риски

- ⚠️ **Не блокировать сохранение сетевым вызовом.** Синхронный `HttpClient`
  в обработчике `OnSaleOrderSaved`/`OnAfter*` означает: внешний таймаут =
  зависшее или сорванное сохранение заказа у покупателя. Сеть — только в агенте
  очереди, обработчик лишь ставит задание.
- ⚠️ **Идемпотентность обязательна.** Без ключа `IDEM_KEY` повторный запуск
  события или ретрай агента создаст дубль во внешней CRM. Дедуп нужен с двух
  сторон: проверка перед `enqueue` на сайте и заголовок `Idempotency-Key`
  для сервиса.
- ⚠️ **Секреты вне VCS.** Токен/URL — в `bitrix/.settings.php` или опциях модуля,
  файл настроек в `.gitignore`. Не коммитить ключи и не писать их в код
  обработчика; в журнал — URL без токена.
- ⚠️ **Возврат агента = его судьба.** Метод-агент обязан вернуть строку своего
  вызова; пустая строка удалит агент после первого прохода, и очередь перестанет
  отправляться (см. рецепт по агентам в ## Связано).
- ⚠️ **`global $USER` в агенте = null.** При сборке payload в `run()` нельзя
  полагаться на текущего пользователя/права — берите данные по ID сущности.
- **Таймауты HttpClient.** Без `socketTimeout`/`streamTimeout` вызов может висеть
  на «зависшем» сервисе; задавайте оба и ограничивайте `BATCH`, чтобы один проход
  агента не растягивался.
- **Лимит попыток и «ядовитые» задания.** Без `MAX_ATTEMPTS` сбойное задание
  будет ретраиться вечно и тормозить очередь; после лимита переводите в `FAILED`
  и разбирайте по журналу.
- **HttpClient PSR-18 — с `main` 23.0.0.** На более раннем ядре сигнатуры могут
  отличаться; рецепт ориентирован на 26.x. Проверяйте `getStatus()` отдельно от
  возвращаемого `post()` флага — успех транспорта не равен успешному HTTP-коду.
- **Постановка в очередь, а не отправка.** Между событием и реальной доставкой
  есть задержка (интервал агента/cron). Для «почти realtime» уменьшайте интервал,
  но сеть всё равно держите вне пользовательского запроса.

## Связано

- ../../api-map.md — карта API: HttpClient, ORM-таблицы, выбор D7 vs legacy.
- ../settings/02-events.md — подписка на события ядра и контракт callback
  (объект `Event` vs позиционные аргументы для `OnAfter*`).
- ../settings/03-agents-cron.md — регистрация агента, контракт возврата строки,
  перевод запуска очереди с «на хитах» на cron для production.
