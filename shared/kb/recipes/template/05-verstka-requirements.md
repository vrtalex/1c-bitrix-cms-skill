# 05. Требования к вёрстке шаблона

## Цель

Сделать шаблон сайта, который проходит требования вендора и «Монитор качества»: правильное разделение CSS (`styles.css` / `template_styles.css`), ровно один H1 через `ShowTitle`, контентная область с классом-обёрткой, корректная работа визуального редактора, адаптивность, блок авторизации в двух состояниях и валидная разметка.

## Когда применять

- Готовите шаблон к сдаче проекта (проверка «Монитор качества»: Настройки → Инструменты → Контроль качества).
- Интегрируете готовую HTML-вёрстку в `header.php` / `footer.php`.
- Контент-менеджер должен редактировать страницы визуальным редактором, а вы — гарантировать SEO-корректную структуру.
- Чек-лист перед код-ревью шаблона.

## Шаги

1. **Разделите CSS по назначению.** Оформление самого шаблона (шапка, подвал, меню) → `template_styles.css`. Стили, доступные контент-менеджеру для контента страниц → `styles.css`. Оба файла лежат в корне шаблона и подключаются ядром автоматически (`Asset::addTemplateCss`) — `<link>` на них в `header.php` не пишут.
2. **Опишите контентные стили в `.styles.php`.** Только классы, перечисленные в этом массиве, появятся в выпадающем списке «Стиль» визуального редактора. Сам класс должен иметь правило в `styles.css`.
3. **Вынесите заголовок в шаблон одним H1.** В `header.php` — `<h1><?php $APPLICATION->ShowTitle(false)?></h1>`, значение приходит из `SetTitle()` страницы/компонента. В `<head>` — `<title><?php $APPLICATION->ShowTitle()?></title>`.
4. **Оберните рабочую область классом-контейнером.** `header.php` открывает контейнер (например `<div class="workarea">`), `footer.php` его закрывает; граница зон — метка `#WORK_AREA#`.
5. **Добавьте viewport и подключите CSS/JS через `ShowHead()`.** Никаких ручных `<link>`/`<script>` и инлайн-стилей в вёрстке.
6. **Замените статическую форму входа компонентом** `bitrix:system.auth.form` (два состояния: гость / авторизован).
7. **Проверьте в «Мониторе качества»** и валидаторе.

## Рабочий сниппет

`/local/templates/<my_template>/header.php` (фрагмент: head + контентная обёртка + H1):

```php
<?php if (!defined("B_PROLOG_INCLUDED") || B_PROLOG_INCLUDED !== true) die();
IncludeTemplateLangFile(__FILE__); ?>
<!DOCTYPE html>
<html lang="<?=LANGUAGE_ID?>">
<head>
    <meta charset="<?=LANG_CHARSET?>">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?php $APPLICATION->ShowTitle()?></title>
    <?php $APPLICATION->ShowHead();?><?php // мета-теги + ВСЕ CSS/JS, в т.ч. styles.css и template_styles.css ?>
</head>
<body>
<?php $APPLICATION->ShowPanel();?>
<header class="site-header">
    <?php $APPLICATION->IncludeComponent("bitrix:system.auth.form", "", array(), false);?>
    <?php $APPLICATION->IncludeComponent("bitrix:menu", "", array("ROOT_MENU_TYPE" => "top"), false);?>
</header>

<main class="workarea">
    <?php if ($APPLICATION->GetCurPage(false) !== SITE_DIR):?>
        <?php $APPLICATION->IncludeComponent("bitrix:breadcrumb", "", array(), false);?>
        <h1><?php $APPLICATION->ShowTitle(false)?></h1>
    <?php endif?>
    <?php // ниже #WORK_AREA# — тело страницы (контент) ?>
```

`footer.php` закрывает то же, что открыл `header.php`:

```php
<?php if (!defined("B_PROLOG_INCLUDED") || B_PROLOG_INCLUDED !== true) die(); ?>
</main><?php // закрыли .workarea ?>
<footer class="site-footer">
    <?php $APPLICATION->IncludeComponent("bitrix:main.include", "", array(
        "AREA_FILE_SHOW" => "file",
        "PATH" => SITE_DIR."include/footer_phone.php",
    ), false);?>
</footer>
</body>
</html>
```

`.styles.php` — стили для визуального редактора (контентные классы):

```php
<?php IncludeTemplateLangFile(__FILE__);
return array(
    "text-lead"  => array("tag" => "p",   "title" => GetMessage("ST_LEAD"),  "section" => "text"),
    "note-block" => array("tag" => "div", "title" => GetMessage("ST_NOTE"), "section" => "block"),
);
```

Те же классы (`.text-lead`, `.note-block`) должны иметь правила в `styles.css`.

## Выбор API

Шаблоны сайта строятся на двух поддерживаемых линиях API одновременно:

- **`$APPLICATION` / `CMain`** (`ShowHead`, `ShowTitle`, `ShowPanel`, `SetTitle`, `IncludeComponent`) — обязательный «язык» шаблона; без него шаблон не написать. Применяйте его в `header.php` / `footer.php`.
- **`\Bitrix\Main\Page\Asset`** — современный слой подключения ассетов; именно он автоматически добавляет `styles.css` и `template_styles.css`. Для подключения UI-расширений используйте `\Bitrix\Main\UI\Extension::load([...])`, а не ручные `<link>`/`<script>`.

Для контентных стилей единственный путь подачи в визуальный редактор — файл `.styles.php` (массив именованных классов).

## Проверка

**Режим «только файлы» (без запуска Битрикса):**
- `styles.css` и `template_styles.css` существуют в корне шаблона; на них нет ручных `<link>` в `header.php`.
- Каждый класс из `.styles.php` имеет правило в `styles.css`.
- В шаблоне ровно один `<h1>` и ровно один `<?php $APPLICATION->ShowTitle(false)?>`; статического текста заголовка нет.
- В `<head>` есть `ShowHead()`, `<title>` через `ShowTitle()`, `meta viewport`; в вёрстке нет инлайн-`style="..."` и инлайн `<script>`.
- Контентная область обёрнута классом-контейнером; `header.php` открывает, `footer.php` закрывает те же теги.
- Формы входа из исходной вёрстки нет — стоит `bitrix:system.auth.form`.

**Режим «живой Битрикс»:**
- Откройте страницу гостем и под авторизованным пользователем — блок авторизации показывает оба состояния (вход/регистрация vs профиль/выход); сценарии `logout=yes`, `register=yes`, `forgot_password=yes` работают.
- Контент-менеджер видит классы из `.styles.php` в списке «Стиль» визуального редактора, и они применяются.
- Сузьте окно/мобильный режим — раскладка адаптивна, не появляется горизонтальный скролл.
- Запустите «Монитор качества» (Настройки → Инструменты → Контроль качества) и пройдите обязательные тесты; условия — на закладке «Рекомендации».
- Проверьте страницу внешним валидатором HTML.

## ⚠️ Риски

- ⚠️ **Контентные классы только в `template_styles.css`** (не описаны в `.styles.php`) — контент-менеджер не увидит их в визуальном редакторе и не сможет оформлять контент. Стили контента кладите в `styles.css` + описывайте в `.styles.php`.
- ⚠️ **Несколько H1 или статический заголовок** ломают семантику и SEO. Один H1 через `ShowTitle(false)`, заголовок окна — `ShowTitle()`; на главной H1 и хлебные крошки можно скрыть условием.
- ⚠️ **Инлайн-стили и ручные `<link>`/`<script>`** вместо `ShowHead()` мешают сборке ассетов и переопределению через CSS-файлы; выносите стили в `styles.css` / `template_styles.css`.
- ⚠️ **Ручной `<link>` на `styles.css` / `template_styles.css`** даёт двойную загрузку — эти файлы уже подключает ядро автоматически.
- ⚠️ **Шаблон сайта не редактируется визуальным редактором** (отключено с версии 14.0) — правьте его в исходном коде; визуальный редактор работает с контентом страниц и включаемыми областями.
- ⚠️ **Нет `meta viewport`** — мобильные браузеры рендерят страницу как десктоп (~980px), адаптивность не работает.
- ⚠️ **Незакрытые теги между `header.php` и `footer.php`** ломают вёрстку всех страниц: что открыл `header.php`, должен закрыть `footer.php`. По отдельности эти файлы валидными не бывают — это «бутерброд» вокруг `#WORK_AREA#`.

## Связано

- [api-map](../../api-map.md) — какой метод/класс к какой задаче
- [00-overview](../../00-overview.md) — обзор под-скилла шаблонов
- [06. Вывод заголовка/мета на странице](../06-output-on-page.md) — `SetTitle` / `SetPageProperty` / свойства страницы
- [07. Кастомизация шаблона компонента](../07-customize-component-template.md) — переопределение шаблонов компонентов под дизайн
