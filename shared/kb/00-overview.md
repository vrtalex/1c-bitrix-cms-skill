# 00 · Обзор: ментальная модель «1С-Битрикс: Управление сайтом»

Карта платформы для агента. Продукт — BUS (редакция Бизнес), ядро `SM_VERSION = 26.x`.
Пять опорных моделей ниже задают всё остальное; детали — в тематических узлах базы знаний.

---

## 1. Жизненный цикл публичной страницы (5 стадий)

Публичная страница — это реальный `.php`-файл в корне сайта между двумя `require`:

```php
<?php require($_SERVER["DOCUMENT_ROOT"]."/bitrix/header.php"); ?>
   ... HTML / $APPLICATION->IncludeComponent(...) ...      // work area (тело)
<?php require($_SERVER["DOCUMENT_ROOT"]."/bitrix/footer.php"); ?>
```

`header.php` = `require .../main/include/prolog.php`; `footer.php` = `epilog.php`
(подключается только при `B_PROLOG_INCLUDED === true`). Цепочка с машиной состояний
`$GLOBALS["BX_STATE"]`:

| # | Стадия | BX_STATE | Что происходит |
|---|---|---|---|
| 1 | service prolog | `PB` | `prolog_before.php`: глобалы `$USER/$APPLICATION/$DB`, подъём ядра (`include.php`), `CMain::PrologActions()` |
| 2 | visual prolog / header | `PA` → `WA` | `prolog_after.php`: Content-Type, лицензионные ворота, проверка `main.site_stopped`; `Asset::startTarget('TEMPLATE')` → `include SITE_TEMPLATE_PATH."/header.php"` → `startTarget('PAGE')`; `RestartWorkarea()` — граница шаблон/контент |
| 3 | тело (work area) | `WA` | контент страницы: HTML + `$APPLICATION->IncludeComponent(...)` |
| 4 | visual epilog / footer | `EB` | `epilog_before.php`: `startTarget('TEMPLATE')` → `include SITE_TEMPLATE_PATH."/footer.php"` |
| 5 | service epilog | `EA` | `epilog_after.php`: событие `main:OnEpilog`, `EndBufferContentMan()` → `CMain::FinalActions($buffer)` → отдача ответа |

Итог: **PB → PA → WA → EB → EA**.

⚠️ До стадии 1 `prolog.php` проверяет composite (`html_pages/.enabled`): при попадании
в кэш страница может быть отдана как статический HTML **минуя весь PHP**. Логику,
зависящую от запроса, нельзя считать гарантированно выполненной на каждом хите.

Отложенный рендер: `$APPLICATION->ShowHead()/ShowTitle()` в `<head>` печатают «из
будущего» через буфер (`AddBufferContent`), поэтому компонент в теле может задать title
позже, чем выведен `<head>`. Title/meta/крошки ставятся только через `$APPLICATION`
(D7-аналога нет) — и не на стадиях, попадающих в кэш компонента.

Параллельная ветка `/bitrix/admin/*` использует свою цепочку
(`prolog_admin_*`/`epilog_admin_*`) — не путать с публичной.

---

## 2. Три зоны на диске и приоритет `/local`

Физически один document root, логически три зоны:

| Зона | Что содержит | Кто пишет |
|---|---|---|
| **document root** (корень) | публичные `*.php`-страницы, `/urlrewrite.php`, `/upload/`, `/local/`, `/bitrix/` | разработчик/агент + загрузки |
| **`/bitrix`** | ядро: `modules/`, `components/bitrix/`, `templates/`, `js/`, `css/`, `admin/`, `php_interface/`, `.settings.php` | ⚠️ система обновлений Битрикс — **затирается при апдейте** |
| **`/local`** | кастом: `modules/`, `components/`, `templates/`, `php_interface/init.php`, `routes/`, `.settings.php` | разработчик/агент — **не затирается** |

**Главное правило: `/local` приоритетнее `/bitrix`.** Приоритет зашит в резолверах:
модули (`Loader::includeModule` ищет `/local/modules/<m>` раньше `/bitrix/modules/<m>`),
файлы/конфиги (`Loader::getLocal()` [D7] и `getLocalPath()` [legacy]), шаблоны
(`CSiteTemplate::GetList` сканирует `/local/templates` перед `/bitrix/templates`),
компоненты, `.settings.php`, маршруты.

Куда класть кастом агенту:
- шаблоны сайта → `/local/templates/<id>/`
- компоненты → `/local/components/<vendor>/<name>/`
- модули → `/local/modules/<name>/`
- инициализация/обработчики событий → `/local/php_interface/init.php`
- переопределение сервисов/конфига → `/local/.settings.php`
- переопределение шаблона компонента под дизайн →
  `/local/templates/<site_tpl>/components/<vendor>/<comp>/<tpl>/template.php`

⚠️ Никогда не править файлы в `/bitrix/` напрямую — изменения перезатрутся обновлением.
Особенность: `getLocalPath` кэширует `is_dir(/local)` в рантайме — папку `/local`,
созданную в ходе того же запроса, текущий хит не подхватит.

---

## 3. D7 и legacy — две поддерживаемые версии API

Платформа несёт два слоя API; оба поддерживаются. **D7** — для нового кода;
**legacy** — рабочий слой, для ряда задач остаётся основным (на нём написаны все
публичные компоненты, через него идут title/SEO/крошки).

| Признак | D7 (новый код) | legacy (рабочий, местами единственный) |
|---|---|---|
| Именование | `\Bitrix\Main\…`, namespaces, `getInstance()`, lowerCamel | префикс `C` (`CMain`, `CUser`, `CIBlock`), `GetList()` с заглавной |
| Подключение модуля | `Loader::includeModule('iblock')` | `CModule::IncludeModule()` |
| Точка входа | `Application` / `HttpApplication` | глобал `$APPLICATION` (= `CMain`) |
| БД / данные | ORM (`\Bitrix\Main\ORM\*`), `Application::getConnection()` | `$GLOBALS['DB']` (`CDatabase`), `Cxxx::GetList()` |
| Конфиг | `Configuration` (файловый), `Option` (БД-настройки) | `COption` |
| DI | `ServiceLocator` (PSR-11) | — |
| Пользователь | `CurrentUser`, `UserTable` | `$USER` (`CUser`) |
| Title / SEO / крошки | аналога нет | `$APPLICATION->SetTitle/SetPageProperty/AddChainItem` |

«Чистого D7» в рантайме нет — слои переплетены: `Application::terminate()` зовёт
`\CMain::RunFinalActionsInternal()`, `start.php` поднимает и `HttpApplication`, и
`$GLOBALS['DB'] = new CDatabase()`. Практическое правило: новый код — на D7 и в `/local`;
для title/meta/крошек/подключения компонентов на странице — `$APPLICATION` (legacy).
`\Bitrix\Main\Entity\*` — алиасы на `\Bitrix\Main\ORM\*` (для нового кода берём ORM).

---

## 4. Триада «инфоблок → компонент 2.0 → шаблон сайта»

Сквозной поток вывода контента на классическом сайте:

```
инфоблок (данные)  →  компонент 2.0 (логика+кэш)  →  шаблон сайта (вёрстка)
```

- **Инфоблок (iblock)** — основной способ хранения контента (новости, товары, услуги,
  страницы-карточки): универсальная EAV-модель с разделами, свойствами, правами, SEO.
  Моделировать контент следует через инфоблоки, а не через собственные таблицы, если не
  нужна принципиально иная схема. Создавать структуру кодом надёжнее через legacy-API
  (`CIBlockType::Add` → `CIBlock::Add` с `API_CODE` латиницей и `VERSION=2` →
  `CIBlockProperty::Add`); читать в backend — D7 `IblockTable::compileEntity('news')`.
  Справочники для свойств типа `directory` (цвета, бренды, города) — highload-блоки.

- **Компонент 2.0** — инкапсуляция: выборка данных в `$arResult` (`component.php`),
  отделённая от HTML в шаблоне. Подключается `$APPLICATION->IncludeComponent($name,
  $template, $arParams)`. Готовые компоненты вместо своего SQL: `bitrix:news.list` /
  `bitrix:news.detail`, `bitrix:catalog.section` + `bitrix:catalog.smart.filter` +
  `bitrix:catalog.element`, `bitrix:menu`, `bitrix:breadcrumb`. Кэш `$arResult` —
  `startResultCache()/endResultCache()` (`CACHE_TYPE='A'`), инвалидация по тегам
  инфоблоков из коробки.
  ⚠️ `result_modifier.php` выполняется внутри кэша (вычисляемые поля);
  `component_epilog.php` — вне кэша на каждый хит (сюда `SetTitle`/`AddChainItem`/
  счётчики). Установку title/крошек в кэш класть нельзя — «застынут».

- **Шаблон сайта** — папка `header.php` + `footer.php`, «оборачивающая» контент:
  `header.php` открывает теги (DOCTYPE/head/body/шапка/меню/крошки) и заканчивается
  открытыми тегами, `footer.php` их закрывает. Подключается ядром на стадиях 2 и 4.
  Кастомный дизайн компонента — копией шаблона из `.default` в шаблон сайта и правкой
  `template.php`; логика — через `result_modifier.php` рядом. Автоподключение
  `styles.css`/`template_styles.css` через `Asset::addTemplateCss()` — `<link>` вручную
  не писать. UI-расширения — `\Bitrix\Main\UI\Extension::load([...])`.

---

## 5. Подключение модулей: `Loader::includeModule`

Единственный канонический способ задействовать прикладной модуль и его API:

```php
use Bitrix\Main\Loader;
if (Loader::includeModule('iblock')) {
    // здесь доступны \Bitrix\Iblock\*Table, CIBlock*, сервисы модуля
}
Loader::requireModule('iblock');   // тот же эффект, бросает LoaderException при отсутствии
```

Что делает `includeModule`: регистрирует namespace `Bitrix\<Ucfirst(m)>` →
`…/modules/<m>/lib`, подключает `include.php` модуля и вызывает
`ServiceLocator::registerByModuleSettings($m)`. ⚠️ Поэтому `*Table`-классы и сервисы
прикладных модулей доступны **только после** `includeModule`; сущности `main`
(`UserTable` и др.) — сразу. Резолвинг учитывает приоритет `/local` над `/bitrix`.
Legacy-эквивалент `CModule::IncludeModule('iblock')` рабочий; для нового кода — `Loader`.

Сервисы переопределяются через `.settings.php`: глобальный
(`registerByGlobalSettings`, путь через `Loader::getLocal('.settings.php')`) побеждает
помодульный — это механизм подмены реализаций на уровне проекта из `/local`.

---

## Куда дальше

- Файловая структура, bootstrap ядра, `$APPLICATION`/`CMain`, граница D7/legacy — узлы по
  подсистемам «структура/bootstrap», «D7-ядро», «legacy + API страниц».
- Данные (ORM, события, агенты, кэш, инфоблоки, highload-блоки) — узлы «ORM/БД»,
  «события/агенты/кэш», «инфоблоки», «highload».
- Представление (движок компонентов, шаблоны, меню/ЧПУ, UI-кит) — узлы «движок
  компонентов», «шаблоны», «fileman/меню/ЧПУ», «ui».
