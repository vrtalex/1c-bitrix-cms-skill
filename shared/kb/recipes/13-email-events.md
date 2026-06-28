# 13. Транзакционные письма (email-события)

## Цель

Отправлять транзакционные письма (уведомление о заявке, заказе, смене статуса)
через штатный механизм Bitrix: тип почтового события → шаблон письма с
плейсхолдерами `#FIELD#` → постановка в очередь и отправка. Без прямых вызовов
`mail()` — чтобы шаблоны редактировались в админке, работали привязка к сайту,
SMTP, blacklist и отписка.

## Когда применять

- Своя форма обратной связи / заявка на корп-сайте.
- Уведомления интернет-магазина (`SALE_NEW_ORDER` и пр.) — обычно правка готовых
  шаблонов, а не свой код.
- Любое письмо «по событию» (регистрация, восстановление пароля, кастомное
  событие модуля).

Не применять для массовых рассылок/маркетинга — там модуль `sender`.

## Шаги

Модель трёхуровневая:

1. **Тип события** (`b_event_type`, `CEventType` / `EventTypeTable`) — справочник
   «какие события бывают» (`EVENT_NAME`, язык `LID`, человекочитаемые
   `NAME`/`DESCRIPTION`). Нужен для админки «Настройки → Почтовые события», на
   саму рассылку напрямую не влияет. Заводится один раз, на каждый язык.
2. **Шаблон письма** (`b_event_message`, `CEventMessage` / `EventMessageTable`) —
   конкретное письмо: `EMAIL_FROM`, `EMAIL_TO`, `SUBJECT`, `MESSAGE` (тело с
   `#FIELD#`), `BODY_TYPE` (`text`/`html`), привязка к сайтам через
   `b_event_message_site`. У одного события может быть несколько шаблонов (разные
   сайты/языки) — уйдут все подходящие.
3. **Отправка** из кода: `CEvent::Send($event, $lid, $arFields)`.

Шаги для своей формы:

1. Зарегистрировать тип события (инсталлятор модуля или админка) с `EVENT_NAME`,
   например `FEEDBACK_FORM`.
2. Создать шаблон письма (`CEventMessage::Add` или админка), привязать к сайту,
   расставить `#NAME#`, `#EMAIL#`, `#MESSAGE#` и т.д.
3. Вызвать `CEvent::Send('FEEDBACK_FORM', SITE_ID, $arFields)` из обработчика.

Готовый компонент `bitrix:main.feedback` уже шлёт `FEEDBACK_FORM` — для типовой
формы свой код не нужен, достаточно настроить шаблон.

⚠️ Если форма собирает персональные данные (имя/e-mail/телефон) и по ней уходит
письмо, до отправки нужно зафиксировать согласие на обработку ПДн (152-ФЗ). Согласие
записывается через `\Bitrix\Main\UserConsent\Consent::addByContext($consentId)` (метод
автозаполняет IP/URL и возвращает ID записи), полученные согласия видны в журнале
«Полученные согласия» в контекстном меню соглашения (Настройки → Настройки продукта →
Соглашения). Текст соглашения — отдельный документ, галочка не должна быть преднажата.
Источник (вендор): https://dev.1c-bitrix.ru/api_d7/bitrix/main/userconsent/consent/addbycontext.php

## Рабочий сниппет

Установщик типа+шаблона и отправка. Путь:
`/local/php_interface/include/feedback_mail.php` (подключается из `init.php`)
или одноразовый скрипт установки модуля.

```php
<?php
// /local/php_interface/include/feedback_mail.php
use Bitrix\Main\Loader;

// --- 1. Тип события (один раз, идемпотентно по EVENT_NAME+LID) ---
$exists = CEventType::GetList(['EVENT_NAME' => 'FEEDBACK_FORM', 'LID' => 'ru'])->Fetch();
if (!$exists) {
    (new CEventType)->Add([
        'LID'         => 'ru',                 // ВАЖНО: тут ЯЗЫК, не сайт
        'EVENT_NAME'  => 'FEEDBACK_FORM',
        'NAME'        => 'Заявка с сайта',
        'DESCRIPTION' => 'Поля: #NAME#, #EMAIL#, #PHONE#, #MESSAGE#, #DATE#',
    ]);
}

// --- 2. Шаблон письма (b_event_message), привязка к сайту обязательна ---
$tpl = CEventMessage::GetList('id', 'desc', ['EVENT_NAME' => 'FEEDBACK_FORM'])->Fetch();
if (!$tpl) {
    (new CEventMessage)->Add([
        'ACTIVE'     => 'Y',
        'EVENT_NAME' => 'FEEDBACK_FORM',
        'LID'        => ['s1'],                // массив САЙТОВ -> b_event_message_site
        'EMAIL_FROM' => '#DEFAULT_EMAIL_FROM#',
        'EMAIL_TO'   => 'sales@example.com',
        'BCC'        => '',
        'SUBJECT'    => 'Заявка с сайта от #NAME#',
        'BODY_TYPE'  => 'text',               // или 'html'
        'MESSAGE'    => "Имя: #NAME#\nEmail: #EMAIL#\nТелефон: #PHONE#\n"
                      . "Дата: #DATE#\n\nСообщение:\n#MESSAGE#",
    ]);
}

// --- 3. Отправка из обработчика формы ---
function sendFeedback(array $post): void
{
    // САНИТИЗАЦИЯ перед отправкой. NAME/EMAIL/PHONE попадают в скомпилированные
    // заголовки письма (From/To/Subject) — сырой \r\n = инъекция заголовков.
    // 3a. Вырезаем CR/LF из всех полей, идущих в заголовок/SUBJECT, и режем длину.
    $stripHeader = static function ($v): string {
        $v = preg_replace('/[\r\n]+/', ' ', trim((string)$v));
        return mb_substr($v, 0, 200);
    };
    $name  = $stripHeader($post['name'] ?? '');
    $phone = $stripHeader($post['phone'] ?? '');
    // MESSAGE идёт в тело, не в заголовок — CRLF там безопасен, режем только длину.
    $message = mb_substr(trim((string)($post['message'] ?? '')), 0, 5000);

    // 3b. Валидируем e-mail: невалидный адрес очищаем (или прерываем отправку).
    $email = $stripHeader($post['email'] ?? '');
    if ($email !== '' && !check_email($email)) {
        // check_email() (модуль main) — штатная проверка; альтернатива:
        // \Bitrix\Main\Mail\Mail::validateEmail($email)
        $email = '';   // не пускаем мусор в заголовок; при желании return здесь
    }

    // Отложенно: кладёт запись в b_event, письмо уйдёт на ближайшем хите/кроне.
    CEvent::Send('FEEDBACK_FORM', SITE_ID, [
        'NAME'    => $name,
        'EMAIL'   => $email,
        'PHONE'   => $phone,
        'MESSAGE' => $message,
        'DATE'    => date('d.m.Y H:i'),
    ]);
}
```

D7-вариант постановки в очередь (та же логика, ORM-сигнатуры):

```php
use Bitrix\Main\Mail\Event;
$res = Event::send([
    'EVENT_NAME' => 'FEEDBACK_FORM',
    'LID'        => 's1',                       // сайт; можно массив или 's1,s2'
    'C_FIELDS'   => ['NAME' => $name, 'EMAIL' => $email, 'DATE' => date('d.m.Y H:i')],
]);
// $res — Bitrix\Main\ORM\Data\AddResult
```

## Выбор API

Bitrix даёт две поддерживаемые версии API; обе делают одно и то же:

- **legacy `CEvent` / `CEventMessage` / `CEventType`** — `CEvent::Send(...)` не
  помечен `@deprecated` и остаётся штатным публичным способом поставить письмо в
  очередь. CRUD шаблонов/типов через `CEventMessage::Add/Update/Delete/GetList`,
  `CEventType::Add/Update/Delete/GetList`. Самый короткий путь для прикладного
  кода.
- **D7 `\Bitrix\Main\Mail\Event`** — `Event::send($data): AddResult`,
  `Event::sendImmediate($data): string`. ORM-таблицы
  `\Bitrix\Main\Mail\Internal\EventMessageTable` / `EventTypeTable` /
  `EventTable`. Предпочтительно в новом коде на ORM/сервисах. `CEvent` —
  тонкая обёртка над этими классами.

Развилка отправки (обе версии):

- **`Send` / `Event::send`** — отложенно: только пишет строку в `b_event`
  (`SUCCESS_EXEC='N'`), возвращает ID/`AddResult`. Реальная отправка — позже,
  агентом `EventManager::checkEvents()` на хите или по крону. Для веб-форм
  предпочтительно: посетитель не ждёт SMTP.
- **`SendImmediate` / `Event::sendImmediate`** — синхронно: компилирует и шлёт
  сразу, в `b_event` не пишет, возвращает код результата:
  `Y` (всё ушло), `F` (всё с ошибкой), `P` (частично), `0` (нет активного
  шаблона), `N` (событие пропущено хуком). Применять, когда нужен немедленный
  результат (CLI, проверка) или подтверждение факта отправки.

SMTP вместо `mail()` — в `bitrix/.settings.php`:

```php
'smtp' => [
  'value' => [
    'enabled' => true,
    'host' => 'smtp.example.com', 'port' => 465,
    'login' => 'user', 'password' => '***',
    'encryption_type' => 'smtps',   // 'smtp' | 'tls' | 'smtps'
  ],
  'readonly' => false,
],
```

При `enabled=true` и наличии host+login письма идут через SMTP-мейлер; иначе —
`custom_mail()` либо системный `@mail()`. Адрес по умолчанию для
`#DEFAULT_EMAIL_FROM#` — опция `main → email_from` в админке.

## Проверка

**Режим «только файлы»** (без живого Битрикса):

- PHP-линт сниппета: `php -l /local/php_interface/include/feedback_mail.php`.
- Проверить, что в шаблоне `EMAIL_FROM`/`EMAIL_TO`/`SUBJECT`/`MESSAGE` заданы и
  каждый `#FIELD#` присутствует в массиве `$arFields` вызова `Send`.
- Убедиться, что `LID` в `CEventMessage::Add` передан массивом сайтов, а `LID` в
  `CEventType::Add` — кодом языка.

**Режим «живой Битрикс»**:

- Через консоль/CLI вызвать синхронно и проверить код результата:
  ```php
  $r = CEvent::SendImmediate('FEEDBACK_FORM', 's1', ['NAME'=>'Test','EMAIL'=>'a@b.c']);
  // ожидаем 'Y'; '0' = нет активного шаблона для сайта/языка
  ```
- Проверить очередь отложенной отправки: в `b_event` запись с
  `SUCCESS_EXEC='N'` → после хита/крона `SUCCESS_EXEC='Y'` и заполнен
  `DATE_EXEC`. `SUCCESS_EXEC='E'` = исключение при обработке.
- В админке «Настройки → Почтовые события» виден тип и шаблон; отправить тестовое
  письмо из карточки шаблона.
- При SMTP — проверить доставку на реальный ящик и заголовок `X-EVENT_NAME` в
  исходнике письма (его проставляет компилятор) для диагностики.

## ⚠️ Риски

- ⚠️ **`Send` ≠ моментальная отправка.** `CEvent::Send` лишь кладёт запись в
  `b_event`; письмо уйдёт на ближайшем хите с `CheckEvents` или по крону. Для
  «прямо сейчас» — `SendImmediate`.
- ⚠️ **Нет активного шаблона → тишина.** Если нет `b_event_message` с
  `ACTIVE='Y'`, привязанного к нужному сайту/языку, `handleEvent` вернёт `'0'` и
  письмо не уйдёт без явной ошибки. Частая причина «не приходят письма».
- ⚠️ **Привязка к сайту обязательна.** Фильтр шаблонов включает
  `EVENT_MESSAGE_SITE.SITE_ID IN (сайты)`. Шаблон без привязанных сайтов не
  подберётся — при `CEventMessage::Add` всегда передавайте `LID` массивом сайтов.
- ⚠️ **`CEventType.LID` — это ЯЗЫК, а `LID`/привязка шаблона — это САЙТ.** Тип
  заводят на каждый язык (`ru`/`en`), шаблон — на каждый сайт.
- ⚠️ **Charset обязателен.** Если у культуры сайта нет `CHARSET`, обработка молча
  выходит (`return '0'`).
- ⚠️ **`MESSAGE_PHP` кешируется.** Тело шаблона компилируется в PHP в колонку
  `MESSAGE_PHP` при сохранении. Правка `MESSAGE` напрямую в БД мимо
  `EventMessageTable::update` не сбросит кеш — уйдёт старое тело. Меняйте шаблон
  через админку или `CEventMessage::Update`.
- ⚠️ **Инъекция заголовков письма (CRLF).** Сырой ввод (`NAME`/`EMAIL`/`PHONE`)
  попадает в скомпилированные заголовки письма (`From`/`To`/`Subject`). Символы
  `\r\n` в значении = инъекция заголовков (подмена `Bcc`, открытый спам-релей,
  левые получатели). Перед `CEvent::Send` всегда вырезай `\r\n` из полей,
  идущих в заголовок/SUBJECT (`preg_replace('/[\r\n]+/', ' ', ...)`), валидируй
  e-mail (`check_email()` / `\Bitrix\Main\Mail\Mail::validateEmail`) и ограничивай
  длину.
- ⚠️ **Безопасность: тело письма исполняется через `eval()`.** Это штатный
  механизм Bitrix (внутри HTML-письма можно вызывать компоненты), но не давайте
  недоверенным пользователям редактировать `MESSAGE` шаблона — это исполнение
  произвольного PHP.
- **Blacklist отписки.** Адрес из чёрного списка (`BlacklistTable`)
  отфильтруется в `Mail::canSend()` — письмо легально «не дойдёт».
- **`DUPLICATE='N'`** не означает дедупликацию: флаг управляет только
  добавлением `all_bcc` (имя историческое).
- При высокой нагрузке включают крон-обработку (`define('BX_CRONTAB_SUPPORT',
  true)` + крон-задача `cron_events.php`): тогда письма шлёт только крон, не
  посетители, и `Send` мгновенно кладёт в очередь.

## Связано

- Источник: модуль `main` (`CEvent`, типы почтовых событий) — dev.1c-bitrix.ru.
- Ключевые классы: `CEvent`, `CEventMessage`, `CEventType`,
  `\Bitrix\Main\Mail\Event`, `\Bitrix\Main\Mail\EventManager`,
  `\Bitrix\Main\Mail\Internal\EventMessageTable`.
- Таблицы: `b_event_type`, `b_event_message`, `b_event_message_site`, `b_event`.
- Готовый отправитель формы: компонент `bitrix:main.feedback`.
- Регистрация типов/шаблонов магазина — `sale` (события `SALE_NEW_ORDER` и др.).
