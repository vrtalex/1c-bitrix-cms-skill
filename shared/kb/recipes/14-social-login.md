# 14. Вход через соцсети (модуль socialservices)

## Цель

Включить на сайте вход и регистрацию через внешних OAuth-провайдеров (VK ID,
Yandex, Google, Apple, Mail.ru, Office365 и др.): кнопки соц-входа на формах
авторизации/регистрации/в чекауте, привязка и отвязка соц-аккаунтов в личном
кабинете, при необходимости — собственный провайдер. Модуль `socialservices`.

## Когда применять

- Корпоративный сайт или магазин: нужен быстрый вход без пароля и авто-регистрация
  новых клиентов по соц-аккаунту.
- В личном кабинете нужна страница «Мои аккаунты» (привязать/отвязать VK, Google и т.п.).
- Нужно подружить соц-вход с существующей базой пользователей (матчинг по e-mail),
  чтобы не плодить дубли.
- Нужен свой OAuth-провайдер (корпоративный SSO), не входящий в штатный реестр.

## Шаги

1. **Создать приложение у провайдера** (VK ID, Google Cloud Console, Yandex OAuth,
   Apple Developer). Получить `appid` (client_id) и `appsecret` (client_secret).
2. **Прописать Redirect URI** в приложении провайдера: точное значение
   `https://<домен>/bitrix/tools/oauth/<provider>.php` (например `vkontakte.php`,
   `google.php`, `yandex.php`). Точный URI Битрикс показывает в `note` настроек
   провайдера на странице модуля — копировать оттуда байт-в-байт.
3. **Включить провайдеров в админке**: Настройки → Настройки продукта →
   Настройки модулей → «Социальные сети и сервисы». Отметить нужные сервисы,
   вставить `appid`/`appsecret`.
4. **Включить регистрацию в ДВУХ местах**: опция `main.new_user_registration = Y`
   и `socialservices.allow_registration = Y`. Без обеих новый пользователь не
   создастся (вернётся `SOCSERV_REGISTRATION_DENY`), вход смогут выполнить только те,
   у кого уже есть привязка.
5. **Кнопки появятся автоматически**: штатные `system.auth.form`, `main.register`
   и `sale.order.ajax` уже встраивают `socserv.auth.form`. Отдельно подключать
   компонент не нужно.
6. **Привязка в кабинете**: на странице профиля разместить `socserv.auth.split`
   для управления привязанными аккаунтами.
7. (Опционально) матчинг с существующими пользователями и/или свой провайдер —
   через события (см. сниппет ниже).

После входа в таблице `b_socialservices_user` создаётся строка-привязка
(`USER_ID` + `EXTERNAL_AUTH_ID` + `XML_ID`), и пользователь логинится.

## Рабочий сниппет

Файл: `/local/php_interface/init.php` (матчинг по e-mail + свой провайдер).

```php
<?php
use Bitrix\Main\Loader;
use Bitrix\Main\UserTable;

// 1. Сматчить соц-вход с существующим пользователем по e-mail вместо создания дубля.
//    Возврат >0 — ID найденного пользователя (его и залогинят); 0 — обычная ветка.
//    ⚠️ Матчинг по одному только e-mail = захват аккаунта (account takeover):
//    если провайдер отдаёт НЕподтверждённый e-mail, злоумышленник регистрирует у
//    провайдера чужой адрес и молча логинится в чужой аккаунт Битрикса.
//    Поэтому матчим строго при выполнении ВСЕХ условий:
AddEventHandler('socialservices', 'OnFindSocialservicesUser', function (&$fields) {
    if (empty($fields['EMAIL'])) {
        return 0;
    }

    // 1a. Доверяем только провайдерам из явного белого списка (EXTERNAL_AUTH_ID),
    //     про которые знаем, что они подтверждают e-mail.
    $trusted = ['GoogleOAuth', 'YandexOAuth'];   // подставь свои проверенные ID
    if (empty($fields['EXTERNAL_AUTH_ID']) || !in_array($fields['EXTERNAL_AUTH_ID'], $trusted, true)) {
        return 0;
    }

    // 1b. Матчим, ТОЛЬКО если провайдер пометил e-mail как подтверждённый.
    //     Имя флага зависит от провайдера (Google: email_verified, Yandex:
    //     is_email_verified и т.п.) — он лежит в сырых данных OAuth-ответа.
    //     По умолчанию считаем НЕподтверждённым.
    $emailVerified = !empty($fields['EMAIL_VERIFIED']);
    if (!$emailVerified) {
        return 0;   // нет подтверждения → не логиним молча, идёт обычная ветка
    }

    $user = UserTable::getRow([
        'select' => ['ID', 'ADMIN', 'GROUP_ID'],
        'filter' => ['=EMAIL' => $fields['EMAIL'], '=ACTIVE' => 'Y'],
    ]);
    if (empty($user['ID'])) {
        return 0;
    }

    // 1c. Никогда не матчим в привилегированные аккаунты (админы и т.п.) —
    //     для них только явная привязка под уже выполненной авторизацией.
    if (CSocServAuth::isAdminUser((int)$user['ID'])) {
        return 0;
    }

    return (int)$user['ID'];
});
// Безопаснее silent-матча: НЕ логинить по первому совпадению e-mail, а предлагать
// уже авторизованному пользователю явный шаг «привязать аккаунт»
// (компонент socserv.auth.split в личном кабинете) — тогда владелец почты
// подтверждает связку под своей сессией.

// 2. Контроль перед входом: дописать поля, навесить группу, отменить вход.
AddEventHandler('socialservices', 'OnBeforeSocServUserAuthorize', function (&$socservUserFields) {
    // напр. согласие на оферту магазина / группа «соц-клиенты»
    // вернуть false — отменить вход
    return true;
});

// 3. Регистрация СВОЕГО провайдера в реестре (корпоративный SSO).
AddEventHandler('socialservices', 'OnAuthServicesBuildList', function () {
    return [
        'ID'    => 'CorpSSO',                 // == EXTERNAL_AUTH_ID
        'NAME'  => 'Корпоративный вход',
        'CLASS' => 'CSocServCorpSSO',         // наследник CSocServAuth
        'ICON'  => 'corp-sso',
        'DISABLED' => false,
    ];
});

// Прочитать привязки текущего пользователя — для страницы «Мои аккаунты».
function getMySocialAccounts(int $userId): array
{
    if (!Loader::includeModule('socialservices')) {
        return [];
    }
    return \Bitrix\Socialservices\UserTable::getList([
        'filter' => ['=USER_ID' => $userId],
        'select' => ['ID', 'EXTERNAL_AUTH_ID', 'LOGIN', 'PERSONAL_PHOTO'],
    ])->fetchAll();
}
```

Ручной рендер кнопок (если своя форма авторизации):

```php
if (\Bitrix\Main\Loader::includeModule('socialservices')) {
    $mgr = new CSocServAuthManager();
    $services = $mgr->GetActiveAuthServices(['BACKURL' => '/personal/']);
    foreach ($services as $id => $s) {
        // ONCLICK уже содержит открытие popup-окна авторизации
        echo '<a href="javascript:void(0)" onclick="'.$s['ONCLICK'].'">'.htmlspecialcharsbx($s['NAME']).'</a>';
    }
}
```

## Выбор API

- **`CSocServAuthManager`** (`new CSocServAuthManager()`) — точка входа для рендера
  кнопок (`GetActiveAuthServices()`), проверки активности сервиса
  (`isActiveAuthService($id)`), запуска callback (`Authorize($id)`). Это основной
  способ работы с логикой входа.
- **`CSocServAuth`** — база провайдера и доступ к опциям/ограничениям:
  `GetOption()/SetOption()`, `setGroupsDenyAuth()`, `setGroupsDenySplit()`.
- **`\Bitrix\Socialservices\UserTable`** — ORM-чтение/запись привязок и токенов
  (страница «Мои аккаунты», ревизия привязок). Токены `OATOKEN`/`OASECRET`/
  `REFRESH_TOKEN` шифруются прозрачно через `CryptoField`.
- **События** (`OnAuthServicesBuildList`, `OnFindSocialservicesUser`,
  `OnBeforeSocServUserAuthorize`) — расширение поведения без правки ядра.

Модуль использует обе поддерживаемые версии API: высокоуровневая логика входа
живёт в классах `CSocServAuthManager`/`CSocServAuth`, а хранилище привязок и
шифрование токенов — это D7-слой (`lib/`, `\Bitrix\Socialservices\...`).
Отдельного D7-фасада «авторизуй через VK» нет — точка входа всегда менеджер.

## Проверка

**Режим «только файлы» (без запущенного Битрикса):**

```bash
# наличие redirect-эндпоинтов провайдеров
ls /path/to/site/bitrix/tools/oauth/

# обработчики событий зарегистрированы
grep -n "OnFindSocialservicesUser\|OnAuthServicesBuildList\|OnBeforeSocServUserAuthorize" \
  /path/to/site/local/php_interface/init.php

# в init.php нет синтаксических ошибок
php -l /path/to/site/local/php_interface/init.php
```

**Режим «живой Битрикс» (CLI-скрипт с подключённым ядром):**

```php
// проверка, что провайдер активен и кнопки строятся
$mgr = new CSocServAuthManager();
var_dump($mgr->isActiveAuthService('VKontakte'));         // ожидаем true
var_dump(array_keys($mgr->GetActiveAuthServices([])));    // список ID активных

// обе опции регистрации включены
var_dump(COption::GetOptionString('main', 'new_user_registration'));     // 'Y'
var_dump(COption::GetOptionString('socialservices', 'allow_registration')); // 'Y'

// зона лицензии не блокирует нужных провайдеров
var_dump(CSocServAuthManager::listServicesBlockedByZone(LANGUAGE_ID));
```

Финальная живая проверка — пройти вход через провайдера в браузере и убедиться,
что в `b_socialservices_user` появилась строка с нужным `EXTERNAL_AUTH_ID`.

## ⚠️ Риски

- ⚠️ **Регистрация в двух местах.** Если включить только одну опцию из
  `main.new_user_registration` / `socialservices.allow_registration`, первый вход
  незнакомого пользователя завершится `SOCSERV_REGISTRATION_DENY` — кнопки есть,
  а войти нельзя. Включать обе.
- ⚠️ **Redirect URI должен совпадать байт-в-байт** с тем, что показано в настройках
  провайдера (формируется как `/bitrix/tools/oauth/<provider>.php`). Расхождение
  протокола (http/https) или домена → ошибка на стороне провайдера.
- ⚠️ **Захват аккаунта через матчинг по неподтверждённому e-mail (account
  takeover).** Обработчик `OnFindSocialservicesUser`, который матчит по одному
  только `=EMAIL` и возвращает ID найденного пользователя, молча логинит
  входящего в чужой аккаунт. Если провайдер отдаёт e-mail БЕЗ подтверждения,
  атакующий регистрируется у провайдера на чужой адрес и заходит в чужой профиль
  Битрикса. Матчь по e-mail только когда провайдер пометил адрес как
  VERIFIED (провайдер-специфичный флаг, напр. `email_verified`), ограничивай
  доверенным `EXTERNAL_AUTH_ID`, исключай привилегированные аккаунты
  (`CSocServAuth::isAdminUser`) и предпочитай явный шаг «привязать аккаунт» под
  уже выполненной авторизацией вместо тихого автологина по первому совпадению.
- ⚠️ **Перепривязка соц-аккаунта (split).** Один соц-аккаунт может быть привязан к
  другому пользователю Битрикса при разрешённой смене владельца — для магазина это
  потенциальный перехват аккаунта. Контролируйте логику в
  `OnBeforeSocServUserAuthorize` и ограничивайте привязку группам через
  `setGroupsDenySplit()`.
- ⚠️ **Состояние OAuth хранится в сессии** (PKCE `code_verifier`, `state`, ключ
  анти-replay). На нескольких серверах без общего хранилища сессий вход прерывается —
  обеспечьте единое хранилище сессий.
- **Зональные ограничения изолированной коробки.** VK / Yandex / Odnoklassniki /
  Mail.ru блокируются вне зон ru/kz/by (`listServicesBlockedByZone()`): на лицензии
  иной зоны этих кнопок не будет. Проверяйте зону до настройки.
- **Шифрование токенов.** Токены шифруются только при доступном шифровании; иначе
  пишутся в `b_socialservices_user` в открытом виде — проверьте `cryptoAvailable()`.
- **VK — только VK ID** (`id.vk.ru`, PKCE S256): создавайте приложение VK ID,
  приложения старого «ВКонтакте API» могут не подойти.

## Связано

- `06-output-on-page.md` — подключение компонентов (`socserv.auth.form`,
  `socserv.auth.split`) на страницы.
- `../api-map.md` — регистрация обработчиков событий в `init.php`.
- `14-social-login.md` — штатная регистрация и опция `new_user_registration`.
- Источник: модуль `socialservices` — dev.1c-bitrix.ru.
