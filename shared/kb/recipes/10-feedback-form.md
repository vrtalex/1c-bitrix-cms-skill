# Рецепт 10 — Форма обратной связи на модуле `form`

> Основан на изучении ядра «1С-Битрикс: Управление сайтом» (SM_VERSION 26.x) и официальной документации вендора.

## Цель

Сделать на публичной странице форму обратной связи («Напишите нам», «Заказать
звонок», «Стать партнёром») средствами модуля `form`: создать веб-форму, где поля —
это «вопросы»; встроить её компонентом `bitrix:form`; провести валидацию (обязательные
поля + капча); сохранить заявку через `CFormResult::Add`; завести workflow статусов;
отправить почтовое письмо администратору и пользователю через `CEvent`. Опционально —
отдать собранные e-mail в рассылку модуля `sender`.

Это классический механизм заявок, данные ложатся в таблицы `b_form*`, а **не** в
инфоблоки. Это **не** CRM-формы Битрикс24 и не landing-формы.

## Когда применять

- Нужна готовая админка результатов (таблица заявок), статусы, экспорт и письма «из
  коробки» без написания серверного кода обработки POST.
- Поля формы плоские (имя, e-mail, телефон, сообщение), сценарий — один шаг.
- Письмо администратору/автору заявки настраивается шаблоном почтового события.

Когда взять другой инструмент:
- Запись в каталог/отзывы товара → инфоблок + `CIBlockElement::Add` (рецепты 04–05).
- Сложные многошаговые/динамические формы или brand-конструктор → CRM-формы Б24 /
  landing (вне фокуса) либо собственный компонент.
- «Купить в 1 клик» c глубокой логикой заказа → собственный AJAX + `sale`/CRM.

## Шаги

1. **Создай форму.** В админке `Сервисы → Веб-формы → Добавить` или программно
   `CForm::Set([...])`. Задай `SID` латиницей (например `FEEDBACK`), кнопку отправки,
   привяжи к сайту (`arSITE`), включи капчу `USE_CAPTCHA => "Y"` для публичной формы
   (антиспам). При сохранении форма автоматически создаёт почтовое событие
   `FORM_FILLING_<SID>` и шаблоны писем.
2. **Добавь поля-вопросы** (`CFormField::Set` или в админке): «Имя» (`text`, required),
   «Email» (`email`, required), «Телефон» (`text`), «Сообщение» (`textarea`).
   Обязательность — флаг `REQUIRED => "Y"`. `SID` поля — только `[A-Za-z_0-9]`.
   Тип ввода живёт в варианте ответа (`arANSWER[].FIELD_TYPE`), не в самом поле.
3. **Навесь валидаторы** (по необходимости): `text_len` на текстовые/email-поля,
   `num` на телефон/число. Свой валидатор — через событие `onFormValidatorBuildList`.
4. **Проверь права группы** «Все пользователи (в т.ч. неавторизованные)» на форму:
   право < 10 блокирует заполнение публичной формой.
5. **Встрой на страницу** компонентом `bitrix:form` (или его частью
   `bitrix:form.result.new` — только страница отправки, без личного кабинета).
   Поток внутри компонента: POST → `CForm::Check()` (обязательные поля, типы, капча,
   валидаторы) → `CFormResult::Add()` → события `onAfterResultAdd` → письмо.
6. **Настрой письма.** Шаблон события `FORM_FILLING_<SID>` (кому уходит заявка —
   e-mail отдела продаж/администратора) и при необходимости шаблон статуса для письма
   автору. Редактируется в `Настройки → Почтовые события`.
7. **Сделай страницу «Спасибо»** — задай `SUCCESS_URL` в параметрах компонента.

## Рабочий сниппет

Страница с формой (в document root). Кастом шаблона компонента —
`/local/templates/<site_template>/components/bitrix/form/.default/template.php`.

```php
<?php
// /feedback/index.php  →  URL /feedback/
require($_SERVER["DOCUMENT_ROOT"]."/bitrix/header.php");
/** @var CMain $APPLICATION */

$APPLICATION->SetTitle("Обратная связь");
?>

<h1>Напишите нам</h1>

<?php
$APPLICATION->IncludeComponent(
    "bitrix:form",
    ".default",
    [
        "WEB_FORM_ID"    => 1,           // ID веб-формы (или используй SEF + SID)
        "SEF_MODE"       => "N",
        "START_PAGE"     => "new",       // страница отправки заявки
        "SUCCESS_URL"    => "/feedback/thanks/",  // редирект после успеха
        "CHAIN_ITEM_TEXT"=> "Обратная связь",
        "IGNORE_CUSTOM_TEMPLATE" => "N", // уважать HTML-шаблон формы из админки
        // Личный кабинет заявок отключаем — нужна только отправка:
        "SHOW_LIST_PAGE" => "N",
        "SHOW_EDIT_PAGE" => "N",
        "SHOW_VIEW_PAGE" => "N",
        "SHOW_STATUS"    => "N",
        // Кэш страницы new при капче обычно не критичен, но проверяй (см. Риски):
        "CACHE_TYPE"     => "A",
        "CACHE_TIME"     => "3600",
    ]
);
?>

<?php
require($_SERVER["DOCUMENT_ROOT"]."/bitrix/footer.php");
```

Программное создание формы и полей (например, в инсталляторе своего модуля). Скрипт —
`/local/php_interface/install_feedback_form.php`, запускать из CLI/админки разово:

```php
<?php
use Bitrix\Main\Loader;
if (!Loader::includeModule("form")) {
    throw new \RuntimeException("Модуль form не подключён");
}

// 1) Форма. Set() сам создаст почтовое событие FORM_FILLING_FEEDBACK.
$formId = CForm::Set([
    "NAME"        => "Обратная связь",
    "SID"         => "FEEDBACK",          // символьный код, уникальный
    "BUTTON"      => "Отправить",
    "USE_CAPTCHA" => "Y",                 // антиспам на публичной форме
    "DESCRIPTION" => "Форма обратной связи сайта",
    "arSITE"      => ["s1"],              // привязка к сайту(ам)
    "C_SORT"      => 100,
]);
if (!$formId) {
    throw new \RuntimeException($GLOBALS["APPLICATION"]->GetException()->GetString());
}

// 2) Поля-вопросы. Тип ввода задаётся в arANSWER[].FIELD_TYPE.
$fields = [
    ["SID" => "NAME",    "TITLE" => "Ваше имя",  "REQUIRED" => "Y", "TYPE" => "text",     "WIDTH" => 40],
    ["SID" => "EMAIL",   "TITLE" => "E-mail",    "REQUIRED" => "Y", "TYPE" => "email",    "WIDTH" => 40],
    ["SID" => "PHONE",   "TITLE" => "Телефон",   "REQUIRED" => "N", "TYPE" => "text",     "WIDTH" => 40],
    ["SID" => "MESSAGE", "TITLE" => "Сообщение", "REQUIRED" => "Y", "TYPE" => "textarea", "WIDTH" => 40],
];
foreach ($fields as $sort => $q) {
    $fid = CFormField::Set([
        "FORM_ID"   => $formId,
        "SID"       => $q["SID"],         // только [A-Za-z_0-9]
        "TITLE"     => $q["TITLE"],
        "REQUIRED"  => $q["REQUIRED"],    // обязательное поле
        "IN_RESULTS_TABLE" => "Y",
        "C_SORT"    => ($sort + 1) * 100,
        "arANSWER"  => [[
            "FIELD_TYPE"  => $q["TYPE"],  // text | textarea | email | ...
            "FIELD_WIDTH" => $q["WIDTH"],
            "VALUE"       => "",
            "C_SORT"      => 100,
        ]],
    ], false, "N");
    if (!$fid) {
        throw new \RuntimeException($GLOBALS["APPLICATION"]->GetException()->GetString());
    }
    // Длину сообщения ограничим валидатором text_len:
    if ($q["SID"] === "MESSAGE") {
        CFormValidator::Set($formId, $fid, "text_len", ["MIN_LEN" => 5, "MAX_LEN" => 2000]);
    }
}
```

Если форму обрабатываете не компонентом, а своим кодом — валидируйте и сохраняйте
строго парой `Check` → `Add` (ключи POST: `form_text_<ANSWER_ID>` для текстовых,
`form_<type>_<FIELD_SID>` для select/radio, `captcha_word`/`captcha_sid` для капчи):

```php
$err = CForm::Check($formId, false, false, "N");  // false → берёт $_REQUEST
if ($err === "") {
    $resultId = CFormResult::Add($formId);        // вернёт RESULT_ID или false
    // onAfterResultAdd → CFormEventHandlers::sendOnAfterResultStatusChange → CEvent::Send
}
```

Для письма из полностью своего обработчика (без модуля `form`) — прямой `CEvent`.
⚠️ Поля `AUTHOR`/`AUTHOR_EMAIL` уходят в скомпилированные заголовки письма
(`From`/`To`/`Subject`) — сырой ввод с `\r\n` = инъекция заголовков. Санитизируй
ДО `Send`: вырезай CR/LF из header-полей, валидируй e-mail, режь длину:

```php
<?php
// Санитизация header-полей: убираем CR/LF и ограничиваем длину.
$stripHeader = static function ($v): string {
    return mb_substr(preg_replace('/[\r\n]+/', ' ', trim((string)$v)), 0, 200);
};
$name  = $stripHeader($post['name'] ?? '');

// E-mail в заголовке: вырезаем переводы строк И валидируем; невалидный — отбрасываем.
$email = $stripHeader($post['email'] ?? '');
if ($email !== '' && !check_email($email)) {  // или \Bitrix\Main\Mail\Mail::validateEmail($email)
    $email = '';                              // не пускаем мусор в заголовок
}

// MESSAGE идёт в тело — CRLF там безопасен, режем только длину.
$message = mb_substr(trim((string)($post['message'] ?? '')), 0, 5000);

CEvent::Send("FORM_FILLING_FEEDBACK", SITE_ID, [
    "AUTHOR" => $name, "AUTHOR_EMAIL" => $email,
    "TEXT"   => $message, "DATE" => date("d.m.Y H:i"),
]);  // отложенно: кладёт в очередь b_event, письмо уйдёт на хите/кроне
```

## Согласие на обработку ПДн (152-ФЗ)

Публичная форма собирает персональные данные (имя, e-mail, телефон) — значит, до
сохранения заявки нужно зафиксировать согласие на обработку ПДн. Битрикс делает это
нативно через механизм «Соглашения» (Настройки → Настройки продукта → Соглашения):
готовый шаблон соглашения + компонент `bitrix:main.userconsent.request` (чекбокс с
подписью, открывающей модальное окно с текстом). Согласие сохраняется через
`\Bitrix\Main\UserConsent\Consent::addByContext()`, который автоматически заполняет
контекст (IP, URL) и возвращает ID записи; полученные согласия видны в контекстном
меню соглашения («Полученные согласия»).

⚠️ Нативная поддержка `USER_CONSENT` встроена лишь в ограниченный набор стандартных
компонентов. Компонент `bitrix:main.feedback` поддержки согласия из коробки НЕ имеет —
её добавляют вручную:

1. В `.parameters.php` компонента добавить секцию согласия:
   ```php
   <?php
   $arComponentParameters["PARAMETERS"]["USER_CONSENT"] = array();
   ```
2. В шаблон, **перед кнопкой submit**, вставить компонент запроса согласия (опц.
   `AUTO_SAVE => "Y"` — сохранить согласие сразу при отправке формы):
   ```php
   <?php
   $APPLICATION->IncludeComponent(
       "bitrix:main.userconsent.request",
       ".default",
       [
           "ID"              => $arParams["USER_CONSENT_ID"], // ID соглашения
           "IS_CHECKED"      => "N",      // галочка НЕ преднажата (требование закона)
           "AUTO_SAVE"       => "Y",      // сохранить согласие при сабмите
           "IS_LOADED"       => "Y",
       ]
   );
   ```
3. Для AJAX/кастомных потоков согласие пишут через API:
   `\Bitrix\Main\UserConsent\Consent::addByContext($consentId)`.

То же относится к модулю `form` из этого рецепта: компонент `bitrix:form` нативной
поддержки согласия не имеет — `bitrix:main.userconsent.request` вставляют в его шаблон
перед кнопкой отправки, а при своём POST-обработчике согласие фиксируют через
`Consent::addByContext()` вместе с `CFormResult::Add()`.

⚠️ Текст согласия — это **отдельный документ** (создаётся в Настройки → Настройки
продукта → Соглашения), а НЕ политика конфиденциальности. Галочка согласия не должна
быть преднажата: согласие не может выражаться молчанием/бездействием, требуется
активное утвердительное действие пользователя.

Источники (вендор):
- https://dev.1c-bitrix.ru/api_d7/bitrix/main/userconsent/consent/addbycontext.php
- https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=35&LESSON_ID=6636

## Выбор API

- **Модуль `form` — это legacy-классы, и это рекомендованный путь.** D7-обёрток
  (`\Bitrix\Form\...Table`) у него нет; единственный namespaced-класс —
  `\Bitrix\Form\SenderConnectorForm` (интеграция рассылок). Поэтому форму, поля,
  результаты и статусы создаём через статические `CForm`/`CFormField`/`CFormResult`/
  `CFormStatus`/`CFormValidator` — это одна из двух поддерживаемых версий API.
- **Сохранение заявки — `CFormResult::Add($WEB_FORM_ID)`.** Без массива значений он
  читает `$_REQUEST`; статус берёт из `status_<SID>` или `CFormStatus::GetDefault()`;
  дёргает `onBeforeResultAdd`/`onAfterResultAdd`; учитывает ограничения частоты
  (`USE_RESTRICTIONS`). Возвращает int `RESULT_ID` или `false`.
- **Валидация — `CForm::Check()` до `Add()`.** Проверяет обязательные поля
  (`REQUIRED='Y'`), типы (url/email/date), капчу (только при `USE_CAPTCHA='Y'`, новой
  заявке и вне `ADMIN_SECTION`) и подключённые валидаторы. Пустая строка результата =
  валидно. Компонент `bitrix:form` делает это сам.
- **Письма — почтовые события `CEvent`, а не прямой `mail()`.** `CForm::Set` заводит
  событие `FORM_FILLING_<SID>`; обработчик `sendOnAfterResultStatusChange` на
  `onAfterResultAdd` шлёт `CEvent::Send(...)` по активным шаблонам статуса. `Send` —
  отложенная постановка в очередь `b_event`; для «прямо сейчас» есть `SendImmediate`.
- **Статусы — `CFormStatus` как простой workflow.** «Новая → в обработке → закрыта»,
  у статуса свой `MAIL_EVENT_TYPE`; смена через `CFormResult::SetStatus`. Если у
  статуса пустой `MAIL_EVENT_TYPE` или нет автора-`USER_ID`, письмо не уходит.
- **Рассылка (опционально) — `SenderConnectorForm`.** Доступен только при включённом
  модуле `sender`; даёт источник адресатов «Веб-форма» (пары `NAME`/`EMAIL` из
  результатов). Маппинг полей задаётся в коннекторе.
- **Кастом дизайна — копией шаблона компонента, не правкой `/bitrix`.** Свой
  `template.php` клади в `/local/templates/<tpl>/components/bitrix/form/.default/`.

## Проверка

**Режим «только файлы» (без живого Битрикс):**
- Страница с формой лежит в document root (путь = URL), открыта/закрыта парой
  `require(... "/bitrix/header.php")` / `... "/bitrix/footer.php")`.
- В вызове компонента имя — `"bitrix:form"` (или `"bitrix:form.result.new"`), есть
  `WEB_FORM_ID`, `START_PAGE => "new"`, задан `SUCCESS_URL`.
- В инсталляторе: `CModule::IncludeModule("form")`/`Loader::includeModule("form")`
  перед вызовами; у каждого поля `FIELD_TYPE` в `arANSWER`, `SID` соответствует
  маске `[A-Za-z_0-9]`; обязательные поля помечены `REQUIRED => "Y"`.
- PHP-синтаксис: `php -l /path/to/feedback/index.php` (если есть PHP CLI).

**Режим «живой Битрикс»:**
- Открыть URL страницы — форма рендерится, видна капча (если `USE_CAPTCHA='Y'`).
- Отправка с пустым обязательным полем → ошибка валидации, заявка не создаётся.
- Корректная отправка → редирект на `SUCCESS_URL`, в `Сервисы → Веб-формы →
  Результаты` появилась заявка с дефолтным статусом.
- Письмо администратору пришло (или лежит в `b_event` с `SUCCESS_EXEC='N'`, ждёт
  хита/крона). Если тишина — проверить активный шаблон события `FORM_FILLING_<SID>`
  и его привязку к сайту.
- Смена статуса заявки в админке отрабатывает workflow и шлёт письмо статуса.

## ⚠️ Риски

- ⚠️ **`CEvent::Send` — не моментальная отправка.** Письмо лишь ставится в очередь
  `b_event` и уйдёт на ближайшем хите (`CheckEvents`) или по крону. Для синхронной
  отправки — `CEvent::SendImmediate`.
- ⚠️ **Нет активного шаблона письма → тишина без ошибки.** Если шаблона
  `FORM_FILLING_<SID>` (или шаблона статуса) с `ACTIVE='Y'` и привязкой к нужному
  сайту нет, заявка сохранится, но уведомление не уйдёт. Частая причина «письма не
  приходят».
- ⚠️ **Инъекция заголовков письма (CRLF) в своём обработчике.** Сырой ввод
  (`name`/`email`/`phone`), переданный в `CEvent::Send` как `AUTHOR`/`AUTHOR_EMAIL`/
  любое header- или SUBJECT-поле, при наличии `\r\n` = инъекция заголовков
  (подмена `Bcc`, открытый спам-релей). Всегда вырезай `\r\n`
  (`preg_replace('/[\r\n]+/', ' ', ...)`), валидируй e-mail
  (`check_email()` / `\Bitrix\Main\Mail\Mail::validateEmail`) и ограничивай длину
  ДО вызова `Send`. Штатный компонент `bitrix:form` и пара `Check`→`Add` делают
  это сами — риск только при полностью своём POST-обработчике.
- ⚠️ **Капча легко теряется в кастомном шаблоне.** Капча проверяется лишь при
  `USE_CAPTCHA='Y'` + новой заявке + вне `ADMIN_SECTION`; её ввод (`captcha_word`/
  `captcha_sid`) должен быть в HTML-шаблоне формы. Свой `template.php` без блока
  капчи открывает форму спаму.
- ⚠️ **Имена POST-полей зависят от `ANSWER_ID`/`FIELD_SID`.** При программной
  передаче значений в `Add()`/`Check()` ключи должны быть строго `form_<type>_<id>`,
  `status_<SID>` — иначе данные не подхватятся. Безопаснее не передавать массив и
  дать методам прочитать `$_REQUEST` от штатного компонента.
- ⚠️ **Права группы < 10 блокируют заполнение.** Для публичной формы проверь право
  группы «Все пользователи (в т.ч. неавторизованные)»; иначе посетитель получит
  отказ доступа.
- ⚠️ **Ограничения частоты слабы для анонимов.** `USE_RESTRICTIONS` считается по
  `USER_ID`; для неавторизованных опирается на сессию — не заменяет капчу как
  антиспам.
- ⚠️ **`SenderConnectorForm` существует только при модуле `sender`.** Класс объявлен
  внутри `Loader::includeModule('sender')`; без модуля интеграции рассылки нет.

## Связано

- `04-sections-elements`, `05-query-elements` — когда заявку нужно писать в инфоблок,
  а не в `b_form*`.
- `06-output-on-page` — обвязка публичной страницы (`header.php`/`footer.php`,
  `$APPLICATION->SetTitle`, `IncludeComponent`).
- `07-customize-component-template` — свой `template.php` для `bitrix:form`,
  `result_modifier.php`, `component_epilog.php`.
- `kb/api-map` — строки про веб-форму и транзакционное письмо (`CForm*`, `CEvent`).
- `kb/glossary` — термины «Веб-форма (form)», «Почтовое событие».
- Официальная документация разработчика: https://dev.1c-bitrix.ru/
