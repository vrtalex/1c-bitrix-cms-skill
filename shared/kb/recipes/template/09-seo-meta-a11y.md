# Рецепт template-09 — SEO-метаданные и доступность на уровне шаблона

> Основан на изучении ядра «1С-Битрикс: Управление сайтом» (SM_VERSION 26.x, модуль `main`, методы заголовков/свойств страницы) и официальной документации вендора, а также веб-стандартов (Google Search Central, Schema.org, W3C WCAG 2.2).

## Цель

Корректно отдать на уровне шаблона видимый H1 и `<title>` браузера, мета-теги
(description, canonical, robots, Open Graph), `hreflang` для локализаций и
структурированные данные (JSON-LD), а также заложить базовую доступность по WCAG 2.2
AA: текстовые альтернативы, контраст, семантику, порядок заголовков, реальные
интерактивные элементы и защиту форм (экранирование вывода + CSRF).

## Когда применять

- Собираете `header.php`/`footer.php` и шаблоны компонентов с заголовками и мета.
- Заголовок/описание зависят от данных закэшированного компонента (каталог, новость)
  и «отстают» на одну загрузку.
- Нужны canonical/robots/OG, мультиязычные версии (`hreflang`) или микроразметка
  (хлебные крошки, FAQ, карточка страницы).
- Шаблон проходит приёмку по доступности или аудит Lighthouse по a11y.
- В шаблоне есть собственные формы (подписка, обратная связь, фильтр).

## Шаги

1. **Видимый H1 — через заголовок страницы.** Текст H1 задаётся
   `$APPLICATION->SetTitle('...')`, а в разметке шаблона выводится
   `$APPLICATION->ShowTitle(false)` (аргумент `false` — НЕ использовать свойство
   `title`, взять именно заголовок страницы). Не хардкодьте H1 в вёрстке — он должен
   приходить из данных страницы/раздела.
2. **`<title>` браузера — отдельным свойством.** Тег `<title>` берётся из свойства
   `title`: задайте `$APPLICATION->SetPageProperty('title', '...')` и выведите
   `$APPLICATION->ShowTitle()` (с учётом свойства). Если «заголовок окна браузера»
   задан выше по дереву сайта, `SetTitle()` его не перебивает — нужен именно
   `SetPageProperty('title', ...)`.
3. **Мета, зависящие от кэша, ставьте в `component_epilog.php`.** Если значения
   (title/description/canonical) вычисляются из `$arResult` компонента, задавайте их
   в `component_epilog.php` — он выполняется и при отдаче из кэша, тогда как
   `template.php` из кэша не перевыполняется (см. `../07-customize-component-template.md`).
4. **description / robots / canonical / OG — через свойства страницы.** Задавайте
   `SetPageProperty('description', ...)`, `SetPageProperty('robots', ...)`, а
   canonical и OG — отложенными функциями (`AddViewContent`/`SetPageProperty`),
   которые выводятся `$APPLICATION->ShowMeta('...')` / `ShowProperty('...')` в `<head>`.
5. **`hreflang` для локализованных версий.** Для каждой языковой/региональной версии
   страницы добавляйте `<link rel="alternate" hreflang="..." href="...">` (включая
   `x-default`), причём ссылки должны быть взаимными между всеми версиями.
6. **Структурированные данные — JSON-LD.** Предпочитайте один блок
   `<script type="application/ld+json">` со Schema.org (`BreadcrumbList`, `WebPage`,
   `FAQPage`) вместо разрозненных `itemprop` по разметке — его проще поддерживать и
   валидировать.
7. **Доступность по WCAG 2.2 AA.** Каждой картинке — текстовая альтернатива (`alt`),
   декоративным — пустой `alt=""`. Контраст текста ≥ 4.5:1 (для крупного — ≥ 3:1).
   Семантическая структура (landmarks, списки, таблицы) и корректный порядок
   заголовков (один `<h1>`, далее без пропусков уровней). Интерактив — настоящий
   `<button>`/`<a>`, а не `<div>` с обработчиком. Габарит зоны нажатия — около
   48×48 CSS-пикселей.
8. **Формы шаблона — экранирование + CSRF.** Любые выводимые данные пропускайте через
   `htmlspecialcharsbx()`. В формы, меняющие состояние, добавляйте CSRF-токен
   `bitrix_sessid_post()` и проверяйте его на приёме `check_bitrix_sessid()`.

## Рабочий сниппет

`header.php` — заголовок, `<title>`, мета и hreflang:
```php
<?php
if (!defined('B_PROLOG_INCLUDED') || B_PROLOG_INCLUDED !== true) die();

// Значения по умолчанию для шаблона (страница/раздел/компонент могут переопределить)
if (!$APPLICATION->GetPageProperty('description')) {
    $APPLICATION->SetPageProperty('description', GetMessage('TPL_DEFAULT_DESCRIPTION'));
}

// hreflang для локализованных версий (пример — две версии + x-default)
$asset = \Bitrix\Main\Page\Asset::getInstance();
$asset->addString('<link rel="alternate" hreflang="ru" href="https://example.com/">');
$asset->addString('<link rel="alternate" hreflang="en" href="https://example.com/en/">');
$asset->addString('<link rel="alternate" hreflang="x-default" href="https://example.com/">');
?>
<!DOCTYPE html>
<html lang="<?= LANGUAGE_ID ?>">
<head>
    <meta charset="<?= LANG_CHARSET ?>">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <!-- <title> из свойства title (заголовок окна браузера) -->
    <title><?php $APPLICATION->ShowTitle()?></title>
    <?php
    // ShowHead выведет meta description/keywords/robots/canonical и ассеты
    $APPLICATION->ShowHead();
    ?>
</head>
<body>
<?php $APPLICATION->ShowPanel();?>
<main class="content" role="main">
    <!-- Видимый H1: ровно один на страницу, берётся из заголовка страницы -->
    <h1><?php $APPLICATION->ShowTitle(false)?></h1>
```

`component_epilog.php` шаблона компонента (каталог/новость) — мета из закэшированных
данных:
```php
<?php
if (!defined('B_PROLOG_INCLUDED') || B_PROLOG_INCLUDED !== true) die();

global $APPLICATION;

// Значения из SEO-свойств инфоблока (вычислены компонентом, кэшируются)
$ipr = $arResult['IPROPERTY_VALUES'] ?? [];

if (!empty($ipr['ELEMENT_META_TITLE'])) {
    $APPLICATION->SetPageProperty('title', $ipr['ELEMENT_META_TITLE']);
}
if (!empty($ipr['ELEMENT_META_DESCRIPTION'])) {
    $APPLICATION->SetPageProperty('description', $ipr['ELEMENT_META_DESCRIPTION']);
}
if (!empty($ipr['ELEMENT_PAGE_TITLE'])) {
    $APPLICATION->SetTitle($ipr['ELEMENT_PAGE_TITLE']); // видимый H1
}
$APPLICATION->SetPageProperty(
    'canonical',
    'https://example.com' . htmlspecialcharsbx($arResult['DETAIL_PAGE_URL'] ?? '/')
);
```

JSON-LD хлебных крошек (в шаблоне `bitrix:breadcrumb`):
```php
<?php
if (!defined('B_PROLOG_INCLUDED') || B_PROLOG_INCLUDED !== true) die();

$items = [];
foreach ($arResult as $i => $crumb) {
    $items[] = [
        '@type'    => 'ListItem',
        'position' => $i + 1,
        'name'     => $crumb['TITLE'],
        'item'     => $crumb['LINK'] ?: null,
    ];
}
$ld = [
    '@context'        => 'https://schema.org',
    '@type'           => 'BreadcrumbList',
    'itemListElement' => $items,
];
?>
<script type="application/ld+json"><?= \Bitrix\Main\Web\Json::encode($ld) ?></script>
```

Доступная форма с экранированием и CSRF:
```php
<?php if (!defined('B_PROLOG_INCLUDED') || B_PROLOG_INCLUDED !== true) die(); ?>
<form method="post" action="">
    <?= bitrix_sessid_post() ?><!-- CSRF-токен -->
    <label for="fb-email"><?= htmlspecialcharsbx(GetMessage('TPL_FORM_EMAIL')) ?></label>
    <input type="email" id="fb-email" name="EMAIL"
           value="<?= htmlspecialcharsbx($_POST['EMAIL'] ?? '') ?>"
           required autocomplete="email">
    <!-- настоящая кнопка, зона нажатия ~48x48 px задаётся в CSS -->
    <button type="submit"><?= htmlspecialcharsbx(GetMessage('TPL_FORM_SEND')) ?></button>
</form>
<?php
// На приёме формы:
if ($_SERVER['REQUEST_METHOD'] === 'POST' && check_bitrix_sessid()) {
    // обработка $_POST['EMAIL'] ...
}
```

## Выбор API

| Задача | API | Вывод в `<head>`/разметку |
|---|---|---|
| Видимый H1 | `$APPLICATION->SetTitle($h1)` | `$APPLICATION->ShowTitle(false)` |
| `<title>` браузера | `$APPLICATION->SetPageProperty('title', $t)` | `$APPLICATION->ShowTitle()` |
| description / keywords | `SetPageProperty('description'|'keywords', ...)` | `$APPLICATION->ShowMeta('description')` |
| robots | `SetPageProperty('robots', 'index,follow')` | через `ShowHead()` |
| canonical | `SetPageProperty('canonical', $url)` | через `ShowHead()` |
| OG / произвольный meta | `SetPageProperty('og:title', ...)` | `$APPLICATION->ShowProperty('og:title')` |
| hreflang / JSON-LD | `Asset::addString('<link …>')` | в `<head>` |
| CSRF в форме | `bitrix_sessid_post()` | проверка `check_bitrix_sessid()` |

Где задавать значения:
- Статичные дефолты шаблона — в `header.php` (с проверкой, что свойство ещё не задано).
- Значения, вычисленные компонентом из БД, — в `component_epilog.php` (исполняется
  и при отдаче из кэша); `template.php` для этого не подходит — он из кэша не
  перевыполняется.

## Проверка

Режим «только файлы» (без запущенного Битрикс):
- В шаблоне ровно один `<h1>` и он выводится `ShowTitle(false)`, а не захардкожен.
- `<title>` — `ShowTitle()` (со свойством); description через `SetPageProperty`.
- Мета/заголовок, зависящие от данных компонента, заданы в `component_epilog.php`,
  а не только в `template.php`.
- Весь эховый вывод обёрнут в `htmlspecialcharsbx()`; в формах есть
  `bitrix_sessid_post()` и приём проверяет `check_bitrix_sessid()`.
- У всех `<img>` есть `alt` (у декоративных — пустой `alt=""`); интерактив — на
  `<button>`/`<a>`, а не на `<div>`.

Режим «живой Битрикс»:
- В исходнике страницы один `<h1>`, корректные `<title>`, meta description, canonical,
  взаимные `hreflang` и валидный JSON-LD (проверить в Google Rich Results Test).
- При прогретом кэше каталога/новости title и description соответствуют элементу
  (значит, заданы в `component_epilog.php`).
- Lighthouse → Accessibility: контраст ≥ 4.5:1, порядок заголовков без пропусков,
  размеры зон нажатия (tap targets) в норме, у изображений есть альтернативы.
- Отправка формы с неверным/отсутствующим CSRF-токеном отклоняется.

## ⚠️ Риски

- ⚠️ SEO-мета, заданные только в `template.php`, при отдаче из кэша не применяются —
  title/description «отстают»; для зависящих от данных значений используйте
  `component_epilog.php`.
- ⚠️ Захардкоженный `<h1>` в вёрстке вместо `ShowTitle(false)` даёт одинаковый или
  дублирующийся заголовок на разных страницах.
- ⚠️ `SetTitle()` не перебивает свойство `title`, заданное выше по дереву сайта, —
  для `<title>` нужен `SetPageProperty('title', ...)`.
- ⚠️ Несимметричные или односторонние `hreflang` (нет обратных ссылок, нет
  `x-default`) поисковые системы игнорируют.
- ⚠️ Вывод данных без `htmlspecialcharsbx()` — XSS; форма без `bitrix_sessid_post()`/
  `check_bitrix_sessid()` уязвима к CSRF.
- ⚠️ Интерактив на `<div>` вместо `<button>` недоступен с клавиатуры и для
  скринридеров; декоративная картинка без пустого `alt=""` зачитывается лишним шумом.

## Связано

- [08-frontend-performance.md](08-frontend-performance.md) — скорость и Core Web Vitals
  шаблона.
- [05-verstka-requirements.md](05-verstka-requirements.md) — семантика и требования к
  вёрстке, на которые опирается доступность.
- [../06-output-on-page.md](../06-output-on-page.md) — вывод заголовка/мета/областей
  на странице.
- [../07-customize-component-template.md](../07-customize-component-template.md) —
  `component_epilog.php` и переопределение шаблона компонента.

<!--
Источники (vendor / стандарты):
- SetTitle / ShowTitle / SetPageProperty / ShowProperty / ShowMeta:
  https://dev.1c-bitrix.ru/api_help/main/reference/cmain/index.php
- SEO-свойства инфоблоков (IPROPERTY_VALUES):
  https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&LESSON_ID=4690
- CSRF (bitrix_sessid_post / check_bitrix_sessid):
  https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=43&LESSON_ID=2934
- hreflang: https://developers.google.com/search/docs/specialty/international/localized-versions
- Структурированные данные / BreadcrumbList:
  https://developers.google.com/search/docs/appearance/structured-data/breadcrumb
- Schema.org: https://schema.org/BreadcrumbList
- WCAG 2.2: https://www.w3.org/TR/WCAG22/
- Контраст текста (1.4.3): https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html
- Размеры зон нажатия: https://web.dev/articles/accessible-tap-targets
-->
