# 02. Структура проекта: document root, /bitrix, /local

## Цель

Понимать раскладку файлов сайта на «1С-Битрикс: Управление сайтом» (ядро 26.x):
что лежит в document root, чем `/bitrix` отличается от `/local`, как ядро
резолвит приоритет `/local`, и какой минимальный набор файлов нужен публичной
части. Это база для размещения собственного кода так, чтобы он переживал
обновления ядра.

## Когда применять

- Перед тем как класть первый собственный шаблон, компонент, модуль или
  обработчик события — чтобы выбрать правильную папку.
- При разборе чужого проекта: понять, что относится к ядру, а что — к кастому.
- При воспроизведении структуры document root вручную (без мастера установки)
  или при переносе проекта в git.
- Перед настройкой `dbconn.php`, `init.php`, `.settings.php`.

## Шаги

1. **Определить document root.** Это корень сайта, который видит веб-сервер.
   Внутри него: публичные `.php`-страницы, папка `/upload` (загрузки),
   `/bitrix` (ядро), `/local` (свой код), корневой `urlrewrite.php`, `.htaccess`.
   Document root — это НЕ `/bitrix`.

2. **Различить `/bitrix` и `/local`.**
   - `/bitrix` — ядро: модули (`bitrix/modules/`), штатные компоненты, штатные
     шаблоны, js/css, админка (`bitrix/admin/`). ⚠️ Эту папку перезаписывает
     система обновлений — собственные правки здесь будут потеряны.
   - `/local` — собственный код проекта: модули, компоненты, шаблоны, события.
     Обновления ядра её не трогают, она легко переносится в git.

3. **Запомнить приоритет `/local` над `/bitrix`.** Ядро при поиске модулей,
   компонентов, шаблонов и конфигов сначала смотрит в `/local`, затем в
   `/bitrix`. То есть одноимённый файл из `/local` «перекрывает» штатный.
   Это работает через резолверы `Loader::getLocal` / `Loader::getLocalPath`
   (см. ниже).

4. **Выбрать папку под свой код:**
   - шаблоны сайта → `/local/templates/<id>/`;
   - компоненты → `/local/components/<vendor>/<name>/`;
   - модули → `/local/modules/<name>/`;
   - общий PHP-код и обработчики событий → `/local/php_interface/init.php`;
   - конфиг рантайма → `/local/.settings.php`.

5. **Настроить boot-файлы** (`dbconn.php`, `init.php`, `.settings.php`) — см.
   ниже раздел «Рабочий сниппет/конфиг».

## Рабочий сниппет/конфиг

### Минимальная раскладка document root

```
DOCUMENT_ROOT/
├── index.php                 # публичная стартовая страница
├── urlrewrite.php            # корневой массив $arUrlRewrite (ЧПУ)
├── .htaccess                 # rewrite на /bitrix/urlrewrite.php
├── upload/                   # пользовательские загрузки
├── bitrix/                   # ядро (обновляется системой)
│   ├── header.php            # пролог: подключает modules/main/include/prolog.php
│   ├── footer.php            # эпилог: подключает modules/main/include/epilog.php
│   ├── modules/              # ядровые модули
│   ├── templates/.default/   # штатный шаблон
│   └── php_interface/        # dbconn.php / init.php / .settings.php (вариант)
└── local/                    # собственный код (приоритет, не затирается)
    ├── modules/
    ├── components/
    ├── templates/
    ├── php_interface/
    │   └── init.php
    └── .settings.php         # перекрывает /bitrix/.settings.php
```

### Каноническая публичная страница

Любая страница в document root оборачивается прологом и эпилогом:

```php
<?php require($_SERVER["DOCUMENT_ROOT"]."/bitrix/header.php"); ?>
<!-- рабочая область: HTML, $APPLICATION->IncludeComponent(...) -->
<?php require($_SERVER["DOCUMENT_ROOT"]."/bitrix/footer.php"); ?>
```

- `header.php` поднимает ядро (через `prolog.php`) и подключает визуальную
  обёртку шаблона (`SITE_TEMPLATE_PATH/header.php`).
- `footer.php` подключает `SITE_TEMPLATE_PATH/footer.php` и отдаёт буфер
  страницы. Он сам проверяет `B_PROLOG_INCLUDED === true` и при отсутствии
  пролога ничего не делает.

### Приоритет /local в коде ядра

Ядро резолвит путь по правилу «сначала `/local`, затем `/bitrix`»:

- современное API: `\Bitrix\Main\Loader::getLocal($path)` —
  `/local/$path`, иначе `/bitrix/$path`;
- legacy-аналог: `getLocalPath($path, $base = "/bitrix")` — то же правило.

Подключение модуля (берёт `/local/modules/<name>` с приоритетом над
`/bitrix/modules/<name>`):

```php
use Bitrix\Main\Loader;
if (Loader::includeModule('iblock')) {
    // доступны \Bitrix\Iblock\... и CIBlock...
}
```

### Boot-файлы

- `php_interface/dbconn.php` — параметры подключения к БД. Ищется ядром
  через `getLocalPath('php_interface/dbconn.php', BX_PERSONAL_ROOT)`, то есть
  работает и `/local/php_interface/dbconn.php`, и `/bitrix/php_interface/dbconn.php`.
- `php_interface/init.php` — точка для собственного PHP-кода и регистрации
  обработчиков событий. Грузится ядром автоматически. Предпочтительно класть в
  `/local/php_interface/init.php`.
- `.settings.php` (и `.settings_extra.php`) — главный конфиг рантайма (две
  поддерживаемые версии API читают его через `Configuration`). Резолвится
  через `Loader::getLocal`, поэтому `/local/.settings.php` перекрывает
  `/bitrix/.settings.php`. Per-module конфиги: `modules/<id>/.settings.php`.
  Модульные `.settings.php` внутри `/bitrix/modules/*/` — это дефолты ядра.

## Проверка

- `/local` существует и доступен веб-серверу на чтение **до** первого запроса,
  поднимающего ядро (см. ⚠️ ниже).
- Публичная страница содержит ровно один `require .../bitrix/header.php` в
  начале и `require .../bitrix/footer.php` в конце; страница открывается без
  ошибок про неопределённые `$APPLICATION` / `SITE_ID`.
- Собственный шаблон из `/local/templates/<id>/` подхватывается вместо
  штатного при том же `id`.
- `Loader::includeModule('<свой модуль>')` находит модуль из
  `/local/modules/<name>/` (вернёт `true`).
- В `/bitrix` нет собственных правок — все кастомы лежат в `/local`.

## ⚠️ Риски

- ⚠️ **`/local` должен существовать на момент загрузки ядра.** Резолвер
  `getLocalPath` статически кэширует факт `is_dir(/local)` в рамках процесса.
  Если папку `/local` создать «на лету» во время уже идущего запроса, приоритет
  `/local` в этом запросе не подхватится. Создавайте `/local` до старта
  обработки запросов.
- ⚠️ **Правки в `/bitrix` теряются при обновлении.** Систему обновлений ядра
  перезаписывает содержимое `/bitrix`. Любой собственный код, шаблон или
  компонент, положенный туда напрямую, будет затёрт. Кастом — строго в `/local`.
- ⚠️ **`BX_PERSONAL_ROOT` может отличаться от `/bitrix`.** Если задана
  `$_SERVER["BX_PERSONAL_ROOT"]`, туда пишутся managed cache, кэш composite
  (`html_pages`) и временные файлы. Это влияет на резолв `dbconn.php`
  (через `BX_PERSONAL_ROOT`) и на расположение кэша — учитывайте при
  бэкапах и переносе проекта.
- Жёсткий порядок include: без `header.php` в начале файла не определены
  `$APPLICATION`, `SITE_ID`, `B_PROLOG_INCLUDED` — страница не соберётся.
- Две параллельные цепочки пролога/эпилога: публичная и админская
  (`/bitrix/admin/*` использует свою). Не смешивать.

## Связано

- [Обзор подсистемы](../../00-overview.md)
- [Операции](../../operations.md)
- [Конвенции](../../conventions.md)
- [Интроспекция проекта](../01-introspect-project.md)
