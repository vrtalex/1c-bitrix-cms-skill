# Conventions — 1С-Битрикс: Управление сайтом (ядро 26.x)

> Позитивные инвариант-правила для разработки и сдачи сайтов на Bitrix Framework.
> Формат: **что делать** — _почему_ — источник. Критичные правила (безопасность, потеря данных, поломка прода) помечены ⚠️.
> Две поддерживаемые версии API: **D7** (`Bitrix\...`, namespace, ORM) — для нового кода; **legacy** (`C*`-классы, `CIBlockElement` и т.п.) — рабочий и для ряда задач основной. Обе официальны.

> Провенанс-ссылки — происхождение факта, не материал для чтения; база самодостаточна. В сеть — только за версионно-зависимым фактом, которого здесь нет.

---

## 0. Право исполнять (классы операций)

Знать операцию и иметь право её ИСПОЛНЯТЬ — разное. Рецепты полностью описывают любые операции; но необратимое и привилегированное по умолчанию не запускается на боевом сайте.

| Класс | Что это | Где можно |
|---|---|---|
| **E1** — чтение/диагностика | CLI-интроспекция (`IblockTable::getList()`, `detect-bitrix.sh`), чтение публичной страницы в браузере/preview, чтение консоли, просмотр в админке | везде, включая прод |
| **E2** — обратимая запись | файлы в `/local` (компоненты, шаблоны, конфиг проекта) под контролем git | везде под git — это основная работа |
| **E3** — необратимое/привилегированное | мастер обновлений, восстановление из бэкапа (`restore.php`), откат БД и миграции `down`, `git reset --hard`, `rm -rf`, деструктив в админке прода | НЕ на проде по умолчанию: дать инструкцию человеку ИЛИ выполнить на изолированной копии (локально — [env-docker](recipes/setup/05-dev-setup.md); либо staging — [изолированная копия](recipes/update/09-staging-clone-safety.md)) |

Админка и браузер: чтение и диагностика в админке — это E1, можно. Привилегированное ИСПОЛНЕНИЕ через клики в боевой админке (мастер обновлений, удаление сущностей, деструктив) — по умолчанию нет. Что структура создана (инфоблок/тип/элемент), проверять CLI-интроспекцией (`getList`/introspect), а не кликами в админке.

---

## 1. Структура проекта и /local

- Весь собственный код держать в `/local` (подпапки: components, templates, modules, php_interface, activities, gadgets, js, routes, blocks, .settings.php) — _при одноимённых элементах приоритет всегда у /local; обновление ядра не затрагивает этот каталог_. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&LESSON_ID=2705)
- Кастомные сущности размещать в собственном пространстве имён, не в `bitrix` — _при обновлении система перезаписывает всё в пространстве bitrix_. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&LESSON_ID=2815)
- ⚠️ Не править файлы ядра (`/bitrix/modules/`, системные компоненты `/bitrix/components/bitrix/`) и не менять структуру таблиц БД ядра напрямую — _правка ломает обновления и совместимость, снимает право на техподдержку; гарантия совместимости действует только для немодифицированного ядра_. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&LESSON_ID=2815)
- Стандартный компонент кастомизировать копией в `/local/components/bitrix/` или в своём пространстве имён, оригинал в `/bitrix` оставлять нетронутым. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&CHAPTER_ID=04779)
- Собственные модули размещать в `/local/modules/`; партнёрский id вида `partner.modulename`, namespace `Partner\Modulename`. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&LESSON_ID=4809)
- Классы D7 класть в `/lib/` модуля, имя файла в нижнем регистре = имени класса (`MyClass` → `/lib/myclass.php`) — _тогда автозагрузка работает без регистрации_. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&LESSON_ID=4809)
- Обязательные файлы модуля: `include.php`, `install/index.php`, `install/version.php` (версия не равна нулю), `default_option.php`; `options.php` — настройки в админке. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&LESSON_ID=2823)
- В начале служебных PHP-файлов (шаблоны, компоненты, `.parameters.php`, `result_modifier.php`) ставить защиту `if(!defined('B_PROLOG_INCLUDED') || B_PROLOG_INCLUDED!==true) die();` — _блокирует прямой вызов файла извне_. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&LESSON_ID=2815)
- Расширять логику через события: code-обработчики через `AddEventHandler('module','Event','Handler')` в `init.php`; постоянные обработчики модуля через `RegisterModuleDependences(...)` в `install.php`. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&LESSON_ID=3395)
- Подключать модуль только через `\Bitrix\Main\Loader::includeModule('module_id')` с проверкой результата (`bool`) — _id чувствителен к регистру, пишется строчными_. [src](https://dev.1c-bitrix.ru/api_d7/bitrix/main/loader/includemodule.php)
- ⚠️ Разрабатывать на тестовой копии в режиме «Установка для разработки», а не на боевом сайте; перед изменениями иметь свежий бекап и доступ по FTP/SSH — _при правке на проде админка может стать недоступной_. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&LESSON_ID=2815)
- Под контроль версий брать только свой код (`/local/`, свои модули/шаблоны); исключать ядро и изменяемые данные: `/bitrix/cache`, `/bitrix/managed_cache`, `/bitrix/stack_cache`, `/bitrix/tmp`, `/upload`, `/bitrix/updates/`, `/bitrix/components/bitrix/`, `/bitrix/modules/bitrix.*`. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&LESSON_ID=5119)
- `composer.json` своего проекта размещать вне DOCUMENT_ROOT; для своих модулей — в `/local/`. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&LESSON_ID=4637)
- В `init.php` не запускать сессию вручную и не строить логику на `$_SESSION` — _ядро стартует сессию позже, переменная ещё недоступна; в админразделе init.php не подключается автоматически_. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&LESSON_ID=2916)

---

## 2. Безопасность

- ⚠️ Любые пользовательские данные при выводе в HTML экранировать через `htmlspecialcharsbx()` или `Bitrix\Main\Text\HtmlFilter::encode()`; значения атрибутов заключать в **двойные** кавычки — _защита от XSS_. [src](https://dev.1c-bitrix.ru/support/forum/forum6/topic68421/)
- ⚠️ Для `href`/`src` `htmlspecialcharsbx()` необходим, но НЕ достаточен: валидировать схему URL по белому списку (только `http`/`https`/`mailto`; для внутренних — относительный путь), отклонять `javascript:`/`data:`/`vbscript:`, protocol-relative (`//host`) и схему с ведущими пробелами/управляющими символами; схему извлекать через `Bitrix\Main\Web\Uri::getScheme()` — _экранирование не блокирует исполняемые схемы в ссылках_. [src](https://dev.1c-bitrix.ru/api_d7/bitrix/main/web/uri/index.php)
- ⚠️ В HTML-атрибутах использовать только двойные кавычки: `htmlspecialcharsbx()` не экранирует одинарные; не применять `htmlspecialcharsEx()` (работает по чёрному списку, неполон). [src](https://habr.com/ru/companies/bitrix/articles/886090/)
- Для вывода в JS использовать `CUtil::JSEscape()`, для JSON/JS-объектов `Bitrix\Main\Web\Json::encode()`; в смешанных контекстах (`onclick`) экранировать и под HTML, и под JS. [src](https://habr.com/ru/companies/bitrix/articles/886090/)
- ⚠️ HTML, присланный пользователем, очищать через `CBXSanitizer` (`SanitizeHtml`/`Sanitize`) по белому списку тегов и атрибутов; вызывать на экземпляре, уровень задавать `SetLevel()`. [src](https://dev.1c-bitrix.ru/api_help/main/reference/cbxsanitizer/sanitizehtml.php)
- ⚠️ Все изменяющие/критические действия подписывать токеном сессии и проверять `check_bitrix_sessid()` (`true`, если `$_REQUEST[$varname]==bitrix_sessid()`); в формах — `bitrix_sessid_post()`, в ссылках — `bitrix_sessid_get()` — _без проверки sessid возможен CSRF через `<img src=...delete=Y>` или поддельную форму_. [src](https://dev.1c-bitrix.ru/api_help/main/functions/other/check_bitrix_sessid().php)
- Включить флаг «Защитить формы авторизации от CSRF» (доступно с 26.0.0) в Главном модуле. [src](https://dev.1c-bitrix.ru/learning/course/?COURSE_ID=35&LESSON_ID=3081)
- ⚠️ Работать с БД предпочтительно через ORM (`DataManager`)/`getList`, а не сырой SQL — _единый параметризованный синтаксис фильтров_. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&LESSON_ID=2379)
- ⚠️ Против SQL-инъекций: числовые данные приводить к типу (`(int)`/`(float)`/`intval`), строки в сыром SQL экранировать `$DB->ForSql()` (в кавычках) или `SqlHelper::forSql($value, $maxLength)`; для вставки/обновления — `$DB->PrepareInsert()`/`$DB->PrepareUpdate()`, а не ручная конкатенация. [src](https://dev.1c-bitrix.ru/docs/articles/develop/208621/)
- ⚠️ В ORM-фильтры передавать только проверенные ключи: валидировать `select`/`filter`/`order` по белому списку, использовать методы построителя (`whereIn`, `whereLike`, `whereColumn`); не подставлять непроверенные данные в `SqlExpression`/`ExpressionField` и в ключи с префиксом `~`. [src](https://docs.1c-bitrix.ru/pages/orm/querying-data.html)
- ⚠️ Имена подключаемых файлов (`include`/`require`) проверять по белому списку, ограничивая латиницей и цифрами, исключая null-byte `%00` — _защита от LFI/PHP including_. [src](https://dev.1c-bitrix.ru/docs/articles/develop/208621/)
- При вызове `system()`/shell подставлять только значения из разрешённого множества и экранировать через `escapeshellcmd()`/`escapeshellarg()`. [src](https://dev.1c-bitrix.ru/docs/articles/develop/208621/)
- Данные из HTTP-запросов по умолчанию небезопасны — санитизировать (экранирование, фильтрация, кодирование) до вывода или попадания в SQL; инициализировать все переменные перед использованием. [src](https://dev.1c-bitrix.ru/community/blogs/information_security/static_taint_analysis_tool.php)
- Проверять права пользователя на чувствительные операции на серверной стороне; не доверять клиентской валидации; не открывать админ-функции без аутентификации. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&CHAPTER_ID=04802&LESSON_PATH=3913.3435.4802)
- ⚠️ Загрузку файлов хардить по трём слоям сразу: валидировать по белому списку расширений/MIME (а не по чёрному списку), хранить вне `DOCUMENT_ROOT` либо в каталоге с запретом исполнения скриптов и отдавать через скрипт-посредник, и отключить исполнение PHP/Python/Perl в `/upload/` (см. ниже) — _одной проверки расширения недостаточно: двойные расширения и `.htaccess` обходят чёрные списки_. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&CHAPTER_ID=04802&LESSON_PATH=3913.3435.4802)
- Выдавать группам минимально необходимые права (принцип наименьших привилегий); группе администраторов выставить «Уровень безопасности группы» = повышенный. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=35&LESSON_ID=2669)
- ⚠️ Регулярно ставить обновления продукта и работать на поддерживаемой версии ядра; перед обновлением делать полную резервную копию сайта и БД — _обновления устраняют известные уязвимости; система хранит 3 актуальные копии_. [src](https://www.1c-bitrix.ru/products/cms/security/)
- Включить Проактивный фильтр (WAF) без исключений, Контроль активности, CAPTCHA при регистрации — _условия стандартного уровня защиты_. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=35&LESSON_ID=2669)
- ⚠️ Отключить вывод ошибок посетителям: в `dbconn.php` использовать `$DBDebug = code` (видно только админам), а не `$DBDebug = true`; `error_reporting` — «Только ошибки» или «Не выводить». [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=35&LESSON_ID=2669)
- Включить OTP/двухэтапную авторизацию минимум для администраторов и критических аккаунтов. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=35&LESSON_ID=2674)
- Хранить сессии в БД (секция `session` в `bitrix/.settings.php`), включить смену идентификатора сессии — _исключает чтение сессий с соседних виртуальных хостов_. [src](https://dev.1c-bitrix.ru/user_help/settings/security/security_session.php)
- Включить защиту от Clickjacking (`X-Frame-Options: SAMEORIGIN`), защиту редиректов от фишинга и Веб-антивирус; журнал заражений за 7 дней держать = 0. [src](https://dev.1c-bitrix.ru/user_help/settings/security/security_panel.php)
- Поверх `X-Frame-Options` задавать заголовки defense-in-depth: `Content-Security-Policy` (ограничить источники скриптов/стилей, по возможности убрать `unsafe-inline`), `Strict-Transport-Security` (HSTS), `X-Content-Type-Options: nosniff`, `Referrer-Policy` — _снижают поверхность XSS/clickjacking/утечки Referer_. Заголовки выставлять через `Context::getCurrent()->getResponse()->addHeader('Content-Security-Policy', ...)` (D7) или `header()` до вывода тела, либо на уровне веб-сервера; CSP вводить в режиме `Report-Only`, затем ужесточать. [src](https://dev.1c-bitrix.ru/api_d7/bitrix/main/httpresponse/addheader.php)
- Для собственных форм/AJAX-обработчиков (логин, отправка заявок, поиск) добавлять прикладной rate-limiting/анти-брутфорс на уровне приложения (счётчик попыток по IP/аккаунту в кэше или БД с временем блокировки) поверх «Контроля активности» модуля `security` — _WAF и Контроль активности не покрывают логику конкретного эндпоинта_. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=35&LESSON_ID=2669)
- ⚠️ Любой fetch URL, полученного от пользователя (вебхуки, импорт по ссылке, превью), защищать от SSRF: разрешать только белый список хостов/схем, резолвить и блокировать внутренние диапазоны (`127.0.0.0/8`, `10/8`, `172.16/12`, `192.168/16`, `169.254/16`, `::1`), запрещать редиректы на внутренние адреса — _иначе сервер используют для запросов во внутреннюю сеть и к облачным метаданным_. [src](https://dev.1c-bitrix.ru/community/blogs/information_security/static_taint_analysis_tool.php)
- ⚠️ При разборе недоверенного XML отключать внешние сущности (`libxml_set_external_entity_loader(null)`, не использовать `LIBXML_NOENT`/`LIBXML_DTDLOAD` на пользовательских данных) — _защита от XXE (чтение файлов, SSRF через сущности)_. [src](https://dev.1c-bitrix.ru/community/blogs/information_security/static_taint_analysis_tool.php)
- ⚠️ Не применять `unserialize()` к данным из вебхуков/обмена/внешних источников (object injection через магические методы) — для внешнего обмена использовать `Bitrix\Main\Web\Json::decode()` или `unserialize($s, ['allowed_classes' => false])`. [src](https://dev.1c-bitrix.ru/community/blogs/information_security/static_taint_analysis_tool.php)
- ⚠️ Модули и решения из Маркетплейса/партнёрские модули исполняются с полными правами ядра — проверять источник и код перед установкой на проде, ставить сначала на тестовую копию; непроверенный модуль = потенциальный бэкдор. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&LESSON_ID=4809)
- Использовать HTTPS (SSL) для рабочих проектов — _без него безопасная авторизация не защищает сессию полностью_. [src](https://dev.1c-bitrix.ru/learning/course/?COURSE_ID=35&LESSON_ID=3081)
- ⚠️ В `/upload/` запретить исполнение PHP/Python/Perl и Content Negotiation, перенести правила `.htaccess` в конфиг веб-сервера; удалить `bitrixsetup.php`/`restore.php`, закрыть `.git`/`.hg`, запретить листинг директорий. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=35&LESSON_ID=5801)

---

## 3. Стандарты кода

- Использовать табы (TAB) для отступов, ровно один таб на уровень вложенности; не смешивать табы с пробелами. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&LESSON_ID=3095)
- Строки заканчивать только LF (Unix), не CRLF; не оставлять завершающих пробелов — _чище diff в системе контроля версий_. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&LESSON_ID=3095)
- Длину строки кода держать ≤120 символов; пробел после запятых и вокруг операторов; фигурные скобки на отдельной строке; одно выражение на строку. [src](https://dev.1c-bitrix.ru/docs/articles/develop/277171/)
- ⚠️ Использовать кодировку UTF-8 — _с ядра main 24.0.0 продукты полностью на UTF-8, cp1251 для 26.x не поддерживается_. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&LESSON_ID=2919)
- Комментарии писать на английском; комментировать публичные классы/методы и логические блоки, без очевидных комментариев. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&LESSON_ID=3095)
- В D7: классы и namespace — UpperCamelCase латиницей, классы-существительные без префикса `C`; методы lowerCamelCase с глагола (`getName`, `setImage`); свойства/переменные lowerCamelCase без префиксов; константы UPPER_CASE_WITH_UNDERSCORES. [src](https://dev.1c-bitrix.ru/community/blogs/vad/naming-conventions-for-the-new-kernel.php)
- В legacy-ядре: классы с префиксом `C` + торговая марка модуля, PascalCase (`CIBlockElement`); методы PascalCase с `is`/`get`/`set`; переменным дают типовые префиксы `ar`/`ob`/`db`/`b`; константы `BX_...`. _Это рабочая конвенция legacy-кода, применяемая при правке существующих классов._ [src](https://dev.1c-bitrix.ru/docs/articles/develop/277171/)
- Классы стандартного дистрибутива — в namespace `Bitrix` (`Bitrix\Main`, `Bitrix\Iblock`); партнёрские — `ИмяПартнёра\ИмяМодуля`, namespace соответствует структуре каталогов; подключать классы через `use`. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&LESSON_ID=3524)
- Часто используемые классы модуля регистрировать для автозагрузки в `include.php` через `Loader::registerAutoLoadClasses($moduleName, ['Namespace\\Class' => '/path/Class.php'])`. [src](https://dev.1c-bitrix.ru/api_d7/bitrix/main/loader/registerautoloadclasses.php)
- Ошибки в D7 обрабатывать исключениями (`try/catch`), базовый класс `\Bitrix\Main\SystemException`; бросать наиболее специфичный класс (`ArgumentException`, `IO\FileNotFoundException`, `AccessDeniedException` и т.д.). [src](https://dev.1c-bitrix.ru/api_d7/bitrix/main/systemexception/index.php)
- Разделять логику и представление: бизнес-логику в `component.php`/`class.php` (`executeComponent()`), HTML — только в `template.php`; валидацию параметров — в `onPrepareComponentParams()`. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&LESSON_ID=2028)
- Вместо `echo`/`var_dump`/`print_r` использовать штатные логгеры ядра на PSR-3 (`\Psr\Log\LoggerInterface`, с main 21.900.0); получать через `Diag\Logger::create`, настраивать в `.settings.php`. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&LESSON_ID=15330)
- Для автоформатирования по стандарту Битрикс использовать `php_beautifier` с профилем `Lowercase Bitrix` — _стиль форматирования собственный (не PSR-12)_. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&LESSON_ID=5759)
- **CLI-bootstrap (запуск сниппетов вне веб-запроса).** При запуске PHP-скрипта из CLI или агента, до строки `require .../bitrix/modules/main/include/prolog_before.php`, задать `$_SERVER['DOCUMENT_ROOT']` (абсолютный путь до корня сайта) и при необходимости `$_SERVER['SERVER_NAME']` — иначе ядро не резолвит конфигурацию и файлы модулей. Типичный заголовок установочного скрипта:
  ```php
  <?php
  $_SERVER['DOCUMENT_ROOT'] = '/var/www/html';  // путь до корня, без слэша на конце
  $_SERVER['SERVER_NAME']   = 'site.ru';
  require $_SERVER['DOCUMENT_ROOT'] . '/bitrix/modules/main/include/prolog_before.php';
  ```

---

## 4. Кэш и производительность

- Кэшировать только данные, общие для всех пользователей; персонализированный контент не кэшировать. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&LESSON_ID=4780)
- ⚠️ Ключ кэша строить только из подготовленных (типизированных) параметров (`IntVal`), исключая сырые параметры с префиксом `~` — _иначе атакующий забивает дисковый кэш вызовами с произвольными ID (DoS)_. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&LESSON_ID=3053)
- Если данные не найдены — прерывать кэширование `$this->AbortResultCache()`; в собственных компонентах восстанавливать данные шаблона `$this->SetTemplateCachedData()`. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&LESSON_ID=3053)
- Код, который должен выполняться на каждом хите даже при кэше (`SetTitle`, навигация, счётчики, права), выносить в `component_epilog.php` — _доступны только ключи `$arResult`, заданные через `SetResultCacheKeys()`_. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&LESSON_ID=2975)
- Модификацию `$arResult` до вывода делать в `result_modifier.php` — _помнить: при включённом кэше шаблон не подключается и этот файл пропускается; не ставить здесь динамические SEO-свойства_. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&LESSON_ID=2830)
- `IncludeComponentTemplate()` вызывать внутри кэшируемой области; `startResultCache()` использовать для кэширования `$arResult` (данных), а не HTML; состав ограничивать `setResultCacheKeys()`. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&LESSON_ID=2028)
- Тегированный кэш включать `define("BX_COMP_MANAGED_CACHE", true)` в `dbconn.php`; соблюдать парность `StartTagCache()`/`EndTagCache()`, длина тега ≤100 символов; теги регистрировать `$CACHE_MANAGER->RegisterTag()`. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&LESSON_ID=2978)
- Держать файл кэша одного компонента ≤1 МБ; кэшировать только нужные ключи, не весь `$arResult`; не использовать короткоживущие ключи (`date()` посекундно), для редко меняющихся данных ставить большой TTL (например 604800 сек). [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&LESSON_ID=13328)
- ⚠️ Запросы к БД и тяжёлые вычисления для меню выносить в `menu_ext.php`, не в `template.php`/`result_modifier.php` меню — _иначе файл кэша создаётся на каждой странице ×каждый тип меню ×число групп, папка кэша разрастается_. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&LESSON_ID=5402)
- Не выполнять запрос к БД/элементу ИБ в цикле (N+1): не вызывать `getById()`/`GetByID()` внутри `foreach` — _собрать ID в массив (`array_unique`) и сделать один запрос с фильтром по массиву (`@`/`whereIn`)_. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&LESSON_ID=3594)
- В ORM-фильтре всегда указывать оператор сравнения явно (`=`, `!=`, `%`, `>`, `<`, `@`) — _без оператора по умолчанию выполняется медленный LIKE_. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&LESSON_ID=5753)
- ⚠️ Для запросов со связями 1:N/N:M использовать `QueryHelper::decompose(...)` вместо `setLimit`/`limit` напрямую — _LIMIT режет SQL-строки, а не объекты, и декартово произведение делает выборку неполной_. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&LESSON_ID=3250)
- JOIN-выборки кэшировать осознанно: по умолчанию JOIN не кэшируются, включать только явно (`cache_joins=>true`/`cacheJoins(true)`). [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&LESSON_ID=5753)
- В файле `/bitrix/php_interface/init.php` не делать запросов к БД и ресурсоёмких операций — _выполняется на каждом хите, бьёт по производительности_. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=32&LESSON_ID=7167)
- ⚠️ Перед включением Композита очистить кэш компонентов; динамические зоны явно оборачивать (`createFrame()->begin()/end()` или `startDynamicWithID/finishDynamicWithID`), некэшируемое помечать `markNonCacheable()`; не использовать `die()`/`exit()` на кэшируемых страницах и не вкладывать динамические зоны друг в друга. [src](https://docs.1c-bitrix.ru/pages/performance/composite-site.html)
- Группы с доступом к админпанели исключать из кэшируемых Композитом. [src](https://docs.1c-bitrix.ru/pages/performance/composite-site.html)
- Для фильтрации каталога использовать фасетный индекс (модуль инфоблоков 15.0+, таблицы `b_iblock_X_index`, ускорение в 10–20 раз); пересоздавать вручную при изменении состава свойств фильтра и перемещении разделов, полную индексацию — в период минимальной нагрузки. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&LESSON_ID=6923)
- Сессии и кэш под нагрузкой выносить в memcache/Redis, а не в ядро БД; оптимизацию начинать с окружения и настроек платформы по замерам Панели производительности. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=70&CHAPTER_ID=03067)
- Замер производительности выполнять под характерной нагрузкой; Монитор включать на ограниченное время (до 1 часа в обычном режиме). [src](https://dev.1c-bitrix.ru/user_help/settings/perfmon/perfmon_panel.php)

---

## 5. Окружение и ORM/инфоблоки

### 5.0. Платформенный baseline (ядро 24.x–26.x) — проверять при апгрейде ядра

> **Канонический источник данных (machine-readable):** `shared/kb/version-baseline.json`. Числовые факты ниже (версии PHP/MySQL, снятые API) дублируются человекочитаемо; при расхождении ведущим считать JSON. Сверку JSON с вендором помогает делать `shared/scripts/refresh-version-baseline.sh` (best-effort, факты не переписывает — сигналит к ручному ревью).

- ⚠️ **PHP ≥ 8.2.0** — минимум с 01.02.2026; рекомендуется **8.4 и выше**. Пока PHP не поднят до 8.2, система обновлений коробки блокирует установку любых апдейтов (и фиксов, и нового функционала) — продукт замирает на старом ядре. [src](https://dev.1c-bitrix.ru/user_help/reqintro.php)
- ⚠️ **MySQL ≥ 8.0** с кодировкой **utf8mb4** (по умолчанию utf8mb4 — с main 24.0.200; мастер установки требует MySQL 8.0). На Linux как альтернатива — **MariaDB 10.x/11.x** (`utf8mb4_unicode_ci`); для MySQL 8.x рекомендуется сортировка `utf8mb4_0900_ai_ci`. PostgreSQL ≥ 11 только для Enterprise. Веб-сервер: Apache 2.0+ или Nginx. [src](https://dev.1c-bitrix.ru/user_help/reqintro.php)
- ⚠️ **Только UTF-8** — поддержка windows-1251 прекращена с версии main **24.0.0**; продукты поставляются только в UTF-8, однобайтовые установки не поддерживаются. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&LESSON_ID=7495)

### 5.1. REMOVED API / decay matrix (ядро 24.x–26.x)

> Перечисленные ниже API **удалены** или **сняты** на актуальных ветках ядра. Любой рецепт под **PHP ≤ 8.1 / MySQL 5.7 / windows-1251** или под эти API подлежит перепроверке при апгрейде ядра.
>
> Машиночитаемый перечень снятых API (поле `removed_api`) — в `shared/kb/version-baseline.json`; этот раздел — его прозаическое отражение.

- **CAll\*-классы** (`CAllMain`, `CAllUser` и др.) — **удалены в main 25.800.0**. Прямое обращение к ним даёт фатальную ошибку «Class not found»; использовать актуальные `CMain`/`CUser` или D7-эквиваленты. [src](https://dev.1c-bitrix.ru/docs/versions.php?lang=ru&module=main)
- **JS-расширения `core_fx` и `core_ls`** — **удалены в main 25.900.0**: API анимации перенесён в `core`, обёртка над localStorage — в `core`. Вызовы `CJSCore::Init(['core_fx'])` / `['core_ls']` заменять на `'core'`. [src](https://dev.1c-bitrix.ru/docs/versions.php?lang=ru&module=main)
- **Способы оплаты QIWI и WebMoney** — **сняты** (QIWI — в sale 24.300.0, ранее WebMoney из ЮKassa); платёжные рецепты не должны на них ссылаться (плюс они юридически неактуальны в РФ). [src](https://dev.1c-bitrix.ru/docs/versions.php?lang=ru&module=sale)
- **Прямой доступ к свойству `->LAST_ERROR`** классов `CIBlock`/`CIBlockSection`/`CIBlockElement`/`CIBlockProperty` — заменён методом **`getLastError()`** (добавлен в iblock 24.0.0); прямое обращение к `LAST_ERROR` снято с рекомендаций. [src](https://www.bitrix24.ru/features/box/box-versions.php?module=iblock)
- **Библиотека `iblock.field-selector`** — снята; на смену пришла **`ui.field-selector`** (`Element::renderSelector` / `Section::renderSelector` переехали туда). [src](https://www.bitrix24.ru/features/box/box-versions.php?module=iblock)

### 5.2. ORM и инфоблоки

- Установить обязательные PHP-расширения: GD+FreeType, XML/DOM, Zlib, OpenSSL, mbstring, Hash, ZIP, mysqli или pgsql. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=32&LESSON_ID=2593)
- Значения php.ini: `memory_limit` ≥128M (Старт) / ≥256M (Бизнес), `max_input_vars=10000`, `max_execution_time=300`, `post_max_size=1024M`, `upload_max_filesize=1024M`, `file_uploads=On`, `default_charset=UTF-8`. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=32&LESSON_ID=2593)
- Удалить настройку `mbstring.func_overload` — _с Main 20.100.0 не поддерживается и вызывает ошибку проверки_. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=32&LESSON_ID=30130)
- OPcache (эталон BitrixEnv): `opcache.max_accelerated_files=100000`, `opcache.revalidate_freq=0`; для системы обновлений `opcache.validate_timestamps=On` — _Off вызывает ошибку «Class CUpdateExpertMode not found»_. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=32&LESSON_ID=20924)
- Права по умолчанию: 0644 для файлов, 0755 для папок; избегать 777; задавать константы в `dbconn.php`: `define("BX_FILE_PERMISSIONS", 0644)`, `define("BX_DIR_PERMISSIONS", 0755)`. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=32&LESSON_ID=3294)
- BitrixEnv 9.x ставить только на чистую поддерживаемую ОС (CentOS Stream 9, Rocky/Alma/Oracle Linux 9.x) с официального сайта; перед установкой отключить SELinux; работать с файлами по SSH/SFTP. [src](https://dev.1c-bitrix.ru/learning/course/?COURSE_ID=37&LESSON_ID=29234)
- ⚠️ Перед обновлением иметь резервные копии БД и файлов; при обновлении выбирать все связанные модули вместе либо ни один; обеспечить окружение (права на запись, `fsockopen()`, исходящий порт 80, RAM ≥512 МБ). [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=32&LESSON_ID=2693)
- Для новых сущностей использовать единый D7 ORM (`DataManager`) вместо собственных `GetList/Add/Update/Delete` и сырого SQL — _единый синтаксис фильтров и автоматические события add/update/delete_. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&CHAPTER_ID=05748)
- Для инфоблоков 2.0 в фильтре обязательно указывать `IBLOCK_ID` — _сквозная выборка по типу ИБ + коду свойства невозможна_. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&LESSON_ID=2723)
- ⚠️ При записи элементов/разделов через ORM-сущность инфоблока (с 19.0.0) не вызываются события, авто-ресайз картинок, обновление фасетного индекса, SEO, сброс кэша, права, бизнес-процессы, индексация поиска, пересчёт LEFT/RIGHT_MARGIN — реализовывать вручную или использовать `CIBlockElement::Add/Update`. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&CHAPTER_ID=012864)
- ⚠️ Перевод инфоблока v1→v2 невозможен при числе свойств >50; смена типа свойства меняет тип хранения в БД и необратима — _менять по одному свойству за раз_. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&LESSON_ID=2723)
- Highload-блоки не использовать для иерархических данных (иерархия не поддерживается); ORM-сущность получать через `HighloadBlockTable::compileEntity()->getDataClass()`. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&CHAPTER_ID=05745)

---

## 6. Перед сдачей (Монитор качества)

- Прогнать «Монитор качества» (Настройки → Инструменты) и пройти все 26 обязательных тестов — _обязательный тест можно перевести в «Пропущен» только с комментарием-обоснованием разработчика_. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&LESSON_ID=3083)
- Пройти тест статического анализа уязвимостей (XSS, SQLi, выполнение PHP, инъекции команд, HTTP Response Splitting, File Inclusion). [src](https://dev.1c-bitrix.ru/community/blogs/information_security/static_taint_analysis_tool.php)
- Удалить тестовые данные (учётки `test/123456`, тестовые страницы/домены) и элементы дефолтных шаблонов; активировать лицензионный ключ, заполнить информацию об интеграторе и техподдержке. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&CHAPTER_ID=04957)
- Протестировать под тремя ролями (гость/пользователь/админ), проверить повторную отправку форм (F5), битые ссылки и работу под включённым кэшем. [src](https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&CHAPTER_ID=04957)
