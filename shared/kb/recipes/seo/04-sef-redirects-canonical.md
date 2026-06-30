# Рецепт 04. ЧПУ-правила, 301-редиректы и canonical (борьба с дублями)

## Цель

Привести публичные URL к одному каноническому виду и убрать дубли из индекса: добавить
точечное правило ЧПУ в `urlrewrite.php`, поставить 301-редирект со старого/неканонического
адреса на новый, вывести `rel=canonical` на страницах с GET-параметрами (пагинация,
сортировка, умный фильтр) и нормализовать слэш/`www`/протокол. ЧПУ самих комплексных
компонентов (`bitrix:news`, `bitrix:catalog`) — отдельная тема, см. `../08-complex-component-sef.md`.

## Когда применять

- Сменили структуру URL (новые ЧПУ, переезд раздела) — нужны массовые 301 со старых адресов,
  чтобы не потерять ссылочный вес. ⚠️ Без 301 после смены URL — провал индексации.
- Одна страница доступна по нескольким адресам: со слэшем и без, с `index.php`, с `?sort=`,
  `?PAGEN_1=`, фильтр — поисковик видит дубли, нужен `canonical` на базовый URL раздела.
- Нужен собственный ЧПУ-маршрут на физический файл, которого нет среди штатных компонентов
  (отдельная посадочная, алиас на существующую страницу).
- Сводите сайт к одному зеркалу: `www` ↔ без `www`, `http` ↔ `https`.

## Шаги

1. **Определите канонический вид URL** для каждого типа страниц (со слэшем на конце, нижний
   регистр, без `index.php`, без служебных GET). Это «эталон», на который будут вести 301 и
   указывать `canonical`.
2. **Точечное ЧПУ-правило** добавьте в корневой `/urlrewrite.php` через D7
   `\Bitrix\Main\UrlRewriter::add()` (или legacy `CUrlRewriter::Add()`) — для своих маршрутов
   на физический файл. Штатные компоненты дописывают правила сами при включении SEF.
3. **301-редирект** организуйте на нужном уровне: единичные/межхостовые (слэш, `www`,
   протокол) — в `.htaccess`; точечные внутренние замены адресов — через `LocalRedirect()`
   в `init.php`/шаблоне или через таблицу-словарь старый→новый URL.
4. **canonical** включите в комплексном компоненте (`SET_CANONICAL_URL=Y`) или поставьте
   вручную `$APPLICATION->SetPageProperty('canonical', ...)` в `detail.php`/`section.php`;
   выведите в `header.php`.
5. **Реиндексируйте** правила (`UrlRewriter::reindexAll()`), пересоберите sitemap, отдайте на
   переобход в Яндекс.Вебмастер и Google Search Console.

## Рабочий сниппет

Файл: `/local/php_interface/init.php` (обработчик редиректов + регистрация ЧПУ-правила),
плюс фрагменты `header.php` / `detail.php`.

```php
<?php
// /local/php_interface/init.php
use Bitrix\Main\UrlRewriter;
use Bitrix\Main\Context;

// --- 1. Точечное ЧПУ-правило на физический файл (одноразовая регистрация) ---
// Запускать однократно (например, при установке) — правило ляжет в /urlrewrite.php.
function registerLandingRule(): void
{
    $siteId = Context::getCurrent()->getSite();   // 's1' и т.п.
    // Идемпотентность: фильтр проверки должен совпадать с ТЕМ ЖЕ ключом, который
    // вставляем (CONDITION), иначе повторный запуск добавит дубль правила.
    $condition = '#^/promo/([\\w-]+)/#';          // regexp по REQUEST_URI
    $rules = UrlRewriter::getList($siteId, ['CONDITION' => $condition]);
    if (empty($rules)) {
        UrlRewriter::add($siteId, [
            'CONDITION' => $condition,                // тот же ключ, что в getList()
            'RULE'      => 'CODE=$1',                 // → $_GET['CODE']
            'ID'        => '',                        // ID компонента (для своего файла пусто)
            'PATH'      => '/promo/index.php',        // физический обработчик
            'SORT'      => 100,
        ]);
    }
}

// --- 2. 301 на канонический вид: нормализация слэша и неканонических адресов ---
$request = Context::getCurrent()->getRequest();
$uri = $request->getRequestUri();                  // путь + query

// 2a. словарь точечных переездов «старый → новый»
$map = [
    '/blog/old-category/' => '/blog/new-category/',
    '/old-page.php'       => '/new-page/',
];
$path = parse_url($uri, PHP_URL_PATH);
if (isset($map[$path])) {
    LocalRedirect($map[$path], false, '301 Moved Permanently');
}
```

301-редиректы зеркала (`www`, протокол) и завершающего слэша надёжнее держать в `.htaccess` —
до запуска PHP:

```apache
# /.htaccess (внутри <IfModule mod_rewrite.c> ... RewriteEngine On)
# без-www → на голый домен, https
RewriteCond %{HTTP_HOST} ^www\.(.+)$ [NC]
RewriteRule ^(.*)$ https://%1/$1 [R=301,L]
# единичный внутренний переезд
Redirect 301 /blog/old-category/page/ /blog/new-category/page/
```

После того как весь сайт и поддомены стабильно работают по HTTPS, закрепите канонический
протокол заголовком **HSTS** (браузер больше не пойдёт на `http://`, нет first-hop downgrade).
⚠️ Включать только когда HTTPS везде — откатить сложно (браузеры запомнят `max-age`). Не забудьте
поправить протокол/`Host` в `robots.txt` и `Sitemap:` после переезда на HTTPS.

```nginx
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
```

canonical в шаблоне компонента (`detail.php`/`section.php`) — на базовый URL без GET.
⚠️ Хост бери из доверенной конфигурации, НЕ из `$_SERVER['SERVER_NAME']`: на
nginx+php-fpm `SERVER_NAME` обычно выводится из клиентского заголовка `Host`, если
`server_name` не запинен — это даёт отравление кэша / open-redirect через
подменённый canonical. Источник правды — настроенное имя сайта:

```php
<?php  // template detail.php / section.php
use Bitrix\Main\Context;

// Доверенный хост: имя сервера из настроек сайта (Context), затем — константа
// SITE_SERVER_NAME, затем — опция main->server_name. Клиентский Host не используем.
$host = Context::getCurrent()->getServer()->getServerName();   // host из настроек сайта
if (!$host && defined('SITE_SERVER_NAME')) {
    $host = SITE_SERVER_NAME;                                  // имя сервера сайта (Настройки → Сайты)
}
if (!$host) {
    $host = \Bitrix\Main\Config\Option::get('main', 'server_name');  // глобальная опция
}

$canonical = 'https://' . $host . $arResult['DETAIL_PAGE_URL'];
$APPLICATION->SetPageProperty('canonical', $canonical);
```

Вывод в `header.php` (если компонент не выводит сам):

```php
<?php
if ($APPLICATION->GetPageProperty('canonical')) {
    $APPLICATION->ShowProperty('canonical');   // <link rel="canonical" ...> штатно по свойству
}
// либо явно:
// echo '<link rel="canonical" href="'.htmlspecialcharsbx($canon).'">';
```

Для страниц пагинации/сортировки/фильтра (`?PAGEN_1=`, `?sort=`) каноном ставьте базовый
URL раздела без GET — так дубли схлопываются в один документ.

## Выбор API (что рекомендовано для ЭТОЙ задачи и почему)

- **ЧПУ-правило — D7 `\Bitrix\Main\UrlRewriter`** (`add($siteId, $arFields)`,
  `getList()`, `update()`, `delete()`, `reindexAll($maxExecutionTime, $ns)`). Для нового кода —
  D7; legacy `CUrlRewriter::Add()/::Reindex()` (две поддерживаемые версии API) делает то же и
  встречается в старых решениях. Формат правила одинаков: `CONDITION` (regexp по URI), `RULE`
  (query с `$1,$2`), `ID`, `PATH`, `SORT`.
- **301-редирект — три уровня по задаче:** межхостовые/слэш/протокол → `.htaccess` (отрабатывает
  до PHP, дёшево); точечные внутренние → `LocalRedirect($url, false, '301 Moved Permanently')`
  в `init.php`/шаблоне; массовые управляемые правила → таблица-словарь (свой обработчик на
  событии `OnBeforeProlog`) или готовое решение Marketplace «Редиректы для SEO» (импорт из
  Excel, автогенерация при смене ЧПУ).
- **canonical — `$APPLICATION->SetPageProperty('canonical', $url)`** + вывод
  `ShowProperty('canonical')`; в комплексных компонентах включается параметром
  `SET_CANONICAL_URL=Y` (см. рецепт `01-seo`/inherited properties). Это штатный механизм
  свойств страницы (legacy `CMain`, но единственный путь для SEO-мета публичной страницы).
- **Приоритет резолва (важно для конфликтов):** физические файлы на диске → правила
  `urlrewrite.php` → D7 `\Bitrix\Main\Routing` (фолбэк). Legacy `urlrewrite.php` имеет
  приоритет над D7-роутингом; для штатных ЧПУ используйте `urlrewrite`, для своих API —
  Routing. Подробнее о связке см. `../../api-map.md`.

## Проверка

Проверка рендера и структуры — по общему паттерну: [verification](../../operations.md) (CLI для структуры, браузер/preview для рендера; на dev-стенде).

**Режим «только файлы» (без живого Битрикса):**
- В `init.php` редирект-словарь использует `LocalRedirect(..., '301 Moved Permanently')`, а не
  302/`header('Location')` без кода (302 не передаёт вес).
- ЧПУ-правило задаёт все поля (`CONDITION`, `RULE`, `PATH`, `SORT`); `CONDITION` — корректный
  regexp с разделителями `#...#`; `PATH` указывает на существующий `.php`-файл вне `/bitrix/`
  и `/upload/`.
- `canonical` собирается на абсолютный URL (`https://` + хост + путь) **без GET-параметров**;
  значение проходит экранирование при ручном выводе.
- Хост для `canonical` берётся из доверенного источника (`Context::getServerName()` /
  `SITE_SERVER_NAME` / опция `main->server_name`), а **не** из сырого
  `$_SERVER['SERVER_NAME']` / `HTTP_HOST` (иначе host-header injection → отравление
  кэша/open-redirect).
- В `.htaccess` правила зеркала стоят внутри `<IfModule mod_rewrite.c>` с `RewriteEngine On`,
  флаг `[R=301,L]`.

**Режим «живой Битрикс»:**
- `curl -I http://site/old-page.php` → `HTTP/1.1 301` и заголовок `Location:` на новый URL
  (не 302, не цепочка нескольких 301).
- `curl -I http://www.site/` → 301 на канонический хост; `http://` → 301 на `https://`.
- Страница раздела с GET (`/catalog/?PAGEN_1=2`) содержит `<link rel="canonical">` на базовый
  URL раздела без `?PAGEN_1`.
- Новый ЧПУ-маршрут `/promo/<code>/` отдаёт 200 и подключает `/promo/index.php` с заполненным
  `$_GET['CODE']`; правило видно в корневом `/urlrewrite.php` после `reindexAll()`.
- В админке «Настройки → ЧПУ → Реиндексация» правила пересчитаны без ошибок.

## ⚠️ Риски

- ⚠️ **Смена URL без 301 — потеря трафика и ссылочного веса.** Перед массовой сменой ЧПУ
  заранее протестируйте 1–2 правила (на `www` и без), замену делайте одним заходом, затем
  сразу пересоберите sitemap и отдайте на переобход. Старые адреса должны отдавать 301, а не
  404.
- ⚠️ **Цепочки и циклы редиректов.** Несколько 301 подряд (слэш → www → https) сливают вес и
  замедляют обход; настраивайте так, чтобы один запрос давал максимум один 301 на финальный
  канонический URL. Взаимное `A→B` и `B→A` даёт бесконечный цикл.
- ⚠️ **Ручная правка корневого `/urlrewrite.php` для правил штатных компонентов затирается**
  при реиндексации (`reindexAll()`) и пересохранении настроек компонента. Свои правила
  держите в коде через `UrlRewriter::add()` (идемпотентно — проверяйте `getList()` перед
  добавлением) либо в отдельном источнике.
- ⚠️ **302 вместо 301.** `LocalRedirect($url)` без третьего аргумента отдаёт 302 (временный) —
  он не передаёт вес. Для SEO-переездов всегда указывайте `'301 Moved Permanently'`.
- **Конфликт приоритетов.** Если URL совпал с правилом `urlrewrite.php`, D7-маршрут на тот же
  путь не сработает (legacy приоритетнее). Для своего API выбирайте путь, не пересекающийся со
  штатными ЧПУ.
- **canonical с GET.** Канонический URL с `?sort=`/`?PAGEN_=` внутри не схлопывает дубли —
  всегда указывайте базовый адрес без служебных параметров.
- ⚠️ **Host-header injection в canonical.** `$_SERVER['SERVER_NAME']` на nginx+php-fpm
  обычно выводится из клиентского заголовка `Host`, если он не запинен — атакующий
  подменяет хост и сайт отдаёт canonical/редирект на чужой домен (отравление кэша,
  open-redirect, перехват превью). Бери хост из доверенной конфигурации
  (`Context::getServerName()` / константа `SITE_SERVER_NAME` / опция `main->server_name`)
  и ОБЯЗАТЕЛЬНО запинь хост на веб-сервере: явный `server_name` в nginx (отдавать
  только свои домены, дефолтный server-блок на `444`) или `UseCanonicalName On` в
  Apache — чтобы `SERVER_NAME` не контролировался клиентом.
- **`mod_rewrite`/nginx.** Вся схема ЧПУ держится на правиле веб-сервера
  (`.htaccess` → `/bitrix/urlrewrite.php`, на nginx — аналог `try_files`). Без него правила и
  редиректы уровня PHP не отработают.
- **Предпосылка: файл `/bitrix/urlrewrite.php` должен существовать в webroot.** На свежем или неполном окружении файл может отсутствовать — тогда неизвестные URI не попадают в диспетчер ядра и ЧПУ не работает. Если файл отсутствует, создать его стандартной однострочной версией (ядро не трогая):
  ```php
  <?php
  require $_SERVER['DOCUMENT_ROOT'] . '/bitrix/modules/main/include/urlrewrite.php';
  ```
  Этот файл — точка входа диспетчера; его наличие и правило веб-сервера, направляющее туда неизвестные URI, — обязательные условия работы SEF/ЧПУ.

## Связано

- `../08-complex-component-sef.md` — ЧПУ (SEF) штатных комплексных компонентов
  (`bitrix:news`/`bitrix:catalog`): `SEF_MODE`, `SEF_FOLDER`, `SEF_URL_TEMPLATES` и
  авто-генерация правил.
- [SEO-06. Дубли и коды ответа](./06-duplicates-response-codes.md) — soft-404, `Clean-param`,
  `noindex`/`X-Robots-Tag` и выбор инструмента склейки под каждый поисковик.
- [SEO-07. SEO умного фильтра](./07-smart-filter-seo.md) — ЧПУ фасетов и дубли `/clear/apply/`.
- [SEO-09. Пагинация](./09-pagination.md) — canonical/301 для `PAGEN_` и ЧПУ страниц `/page-N/`.
- `../02-create-iblock.md` — инфоблок и символьные коды (`CODE`, транслит, уникальность) —
  основа человеко-понятных URL разделов и элементов.
- `../../api-map.md` — таблица соответствий D7 ↔ legacy: `\Bitrix\Main\UrlRewriter` vs
  `CUrlRewriter`, `SetPageProperty('canonical')`, приоритет резолва urlrewrite ↔ D7 Routing.
