# Рецепт template-08 — Скорость и современный фронтенд шаблона

> Основан на изучении ядра «1С-Битрикс: Управление сайтом» (SM_VERSION 26.x, модуль `main`, менеджер ассетов `\Bitrix\Main\Page\Asset`) и официальной документации вендора, а также веб-стандартов (MDN, web.dev).

## Цель

Собрать быстрый шаблон сайта: убрать render-blocking ресурсы, отдать критический
CSS сразу, остальное — отложенно; уложить картинки в адаптивный `srcset` + WebP без
скачков вёрстки (CLS); подключить шрифты без «невидимого текста»; раскладывать
страницу на CSS Grid + Flexbox; и сохранить персонализированные блоки живыми внутри
закэшированной композитной страницы. Цель — хорошие Core Web Vitals (LCP, CLS) при
работающем кэше и личном кабинете.

## Когда применять

- Шаблон проходит приёмку по скорости или Core Web Vitals просели в PageSpeed/CrUX.
- В `<head>` много `<link>`/`<script>`, которые блокируют первую отрисовку.
- На страницах есть крупное «геройское» изображение (LCP-элемент) или галереи.
- Нужно ускорить отдачу при включённом «Композите», но оставить живыми корзину,
  авторизацию, счётчики.
- Вводите сборку фронтенда (минификация/бандл) и хотите сделать это аккуратно
  поверх штатного менеджера ассетов, а не вместо него.

## Шаги

1. **Управляйте ассетами через `\Bitrix\Main\Page\Asset`.** В `header.php`/`footer.php`
   подключайте CSS и JS методами `addCss()`/`addJs()`, а inline-строки — `addString()`
   с указанием зоны (`AssetLocation`). Зона `BODY_END` уводит сторонние/виджетные
   скрипты в самый конец `<body>`, чтобы они не блокировали отрисовку.
2. **Сдвиньте JS вниз страницы.** В конце `footer.php` вызывайте
   `$APPLICATION->ShowBodyScripts()` — туда выводятся скрипты, помеченные для нижней
   зоны. Глобально перенести JS в конец `<body>` помогает `CMain::MoveJSToBody()`
   (включается константой `MAIN_MOVE_JS_TO_BODY`).
3. **Критический CSS — инлайном, остальное — отложенно.** CSS первого экрана
   (above-the-fold) встройте строкой через `addString(..., AssetLocation::BEFORE_CSS)`,
   а полную таблицу стилей подгрузите с `preload` и переключением носителя
   (`media="print" onload="this.media='all'"`). Это снимает блокировку рендера
   основным CSS.
4. **Картинки — адаптивно и в современном формате.** Для контентных изображений
   используйте `srcset`+`sizes` (или `<picture>` с `<source type="image/webp">`) и
   ВСЕГДА задавайте `width`/`height` (или `aspect-ratio`), чтобы исключить сдвиг
   вёрстки (CLS).
5. **LCP-изображение не делайте ленивым.** Главную картинку первого экрана НЕ
   помечайте `loading="lazy"`; наоборот — добавьте `fetchpriority="high"` и `preload`.
   Для всех остальных, ниже сгиба, ставьте `loading="lazy"`.
6. **Шрифты — `font-display: swap` + preload только критичного WOFF2.** Подключайте
   `@font-face` с `font-display: swap` (текст рисуется системным шрифтом, пока
   грузится свой) и делайте `preload` только для одного-двух WOFF2 первого экрана.
7. **Раскладка — Grid для каркаса, Flexbox для компонентов.** Каркас страницы
   (header / sidebar / content / footer) собирайте на CSS Grid, внутренние ряды
   компонентов — на Flexbox. Порядок в DOM держите равным визуальному (для клавиатуры
   и скринридеров), не переставляйте блоки только средствами `order`/`grid-area`.
8. **Сохраните личные блоки в «Композите».** При включённом «Композите» статическая
   часть страницы кэшируется и отдаётся мгновенно; динамические зоны (корзина,
   приветствие, счётчики) оборачивайте во фрейм — `$this->createFrame()` в шаблоне
   компонента или `\Bitrix\Main\Composite\Frame::startDynamicWithID()` в произвольном
   месте, — тогда внутри закэшированной страницы они дозагружаются отдельным запросом.
9. **Отдавайте текстовые ассеты сжато и по HTTP/2.** Включите объединение/минификацию
   CSS/JS в настройках модуля `main`, на стороне сервера/CDN — Brotli (или gzip) для
   text-ресурсов и HTTP/2, чтобы много мелких файлов не упирались в лимит соединений.

## Рабочий сниппет

`/local/templates/my_template/header.php` — критический CSS, preload основного,
шрифт, LCP-картинка:
```php
<?php
if (!defined('B_PROLOG_INCLUDED') || B_PROLOG_INCLUDED !== true) die();

use Bitrix\Main\Page\Asset;
use Bitrix\Main\Page\AssetLocation;

$asset = Asset::getInstance();

// Критический CSS первого экрана — инлайном, до остальных стилей
$asset->addString(
    '<style>/* above-the-fold: каркас, шапка, hero */</style>',
    true,
    AssetLocation::BEFORE_CSS
);
// Полный CSS грузим без блокировки рендера + preload одного WOFF2
$asset->addString(
    '<link rel="preload" as="style" href="' . SITE_TEMPLATE_PATH . '/css/main.css">'
    . '<link rel="stylesheet" media="print" onload="this.media=\'all\'" href="'
    . SITE_TEMPLATE_PATH . '/css/main.css">'
    . '<noscript><link rel="stylesheet" href="' . SITE_TEMPLATE_PATH . '/css/main.css"></noscript>'
    . '<link rel="preload" as="font" type="font/woff2" crossorigin '
    . 'href="' . SITE_TEMPLATE_PATH . '/fonts/inter.woff2">',
    true,
    AssetLocation::AFTER_CSS
);
?>
<!DOCTYPE html>
<html lang="<?= LANGUAGE_ID ?>">
<head>
    <meta charset="<?= LANG_CHARSET ?>">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title><?php $APPLICATION->ShowTitle()?></title>
    <?php $APPLICATION->ShowHead();?>
</head>
<body>
<?php $APPLICATION->ShowPanel();?>
<div class="page"><!-- CSS Grid-каркас, закроется в footer.php -->
    <header class="page__header">
        <picture>
            <source type="image/webp"
                    srcset="<?= SITE_TEMPLATE_PATH ?>/img/hero.webp 1x,
                            <?= SITE_TEMPLATE_PATH ?>/img/hero@2x.webp 2x">
            <img src="<?= SITE_TEMPLATE_PATH ?>/img/hero.jpg"
                 width="1200" height="480"
                 fetchpriority="high"
                 alt="<?= htmlspecialcharsbx(GetMessage('TPL_HERO_ALT')) ?>">
        </picture>
    </header>
```

`@font-face` в `main.css`:
```css
@font-face {
    font-family: "Inter";
    src: url("../fonts/inter.woff2") format("woff2");
    font-weight: 400;
    font-display: swap;       /* системный шрифт, пока грузится свой */
}
.page {                       /* каркас — Grid */
    display: grid;
    grid-template-columns: 1fr min(1100px, 100%) 1fr;
}
.card-row {                   /* компоненты — Flexbox */
    display: flex;
    flex-wrap: wrap;
    gap: 16px;
}
```

`/local/templates/my_template/footer.php` — JS внизу + динамическая зона корзины:
```php
    <footer class="page__footer">…</footer>
</div><!-- .page -->
<?php
// Динамическая зона внутри закэшированной (Композит) страницы
$frame = $this->createFrame()->begin();
?>
<div class="user-cart" data-count="<?= (int)($arResult['CART_COUNT'] ?? 0) ?>">
    <?= htmlspecialcharsbx(GetMessage('TPL_CART')) ?>
</div>
<?php
$frame->end();

// Все «нижние» скрипты — в конец body
$APPLICATION->ShowBodyScripts();
?>
</body>
</html>
```

Перенос JS вниз глобально (в `/local/php_interface/init.php` или `.settings.php`):
```php
<?php
// Включает вывод подключённого JS перед </body> вместо <head>
define('MAIN_MOVE_JS_TO_BODY', true);
```

## Выбор API

| Задача | API / приём | Примечание |
|---|---|---|
| Добавить CSS/JS файл | `Asset::getInstance()->addCss()/addJs()` | участвует в объединении |
| Inline в конец `<body>` | `addString($s, false, AssetLocation::BODY_END)` | для виджетов/счётчиков |
| Вывести нижние скрипты | `$APPLICATION->ShowBodyScripts()` | в конце `footer.php` |
| Перенести весь JS вниз | `CMain::MoveJSToBody()` / `MAIN_MOVE_JS_TO_BODY` | глобально |
| Динамическая зона в кэше | `$this->createFrame()` (в шаблоне компонента) | возвращает объект фрейма |
| Динамическая зона вне компонента | `\Bitrix\Main\Composite\Frame::startDynamicWithID($id)` | парный `finishDynamicWithID()` |
| Адаптивная картинка | `srcset`/`sizes` или `<picture>` | + `width`/`height` против CLS |
| Приоритет LCP-картинки | `fetchpriority="high"` + `preload` | без `loading="lazy"` |
| Отложенная картинка | `loading="lazy"` | только ниже первого экрана |

Сборка фронтенда (минификация, бандл, tree-shaking) — опциональный слой: подойдёт
любой инструмент, который кладёт собранные файлы в `/local/templates/<id>/...`,
после чего они подключаются тем же `Asset`/`Extension`. Жёстко предписанного
сборщика в платформе нет — штатное объединение/минификация модуля `main` уже даёт
базовый выигрыш без отдельного тулчейна.

## Проверка

Проверка рендера и структуры — по общему паттерну: [verification](../../operations.md) (CLI для структуры, браузер/preview для рендера; на dev-стенде).

Режим «только файлы» (без запущенного Битрикс):
- В конце `footer.php` есть ровно один `$APPLICATION->ShowBodyScripts()`.
- У LCP-картинки нет `loading="lazy"`, но есть `width`/`height` и
  `fetchpriority="high"`; у картинок ниже сгиба — `loading="lazy"`.
- `@font-face` содержит `font-display: swap`; preload только для критичных WOFF2.
- Каркас — `display:grid`, ряды компонентов — `display:flex`; порядок DOM совпадает
  с визуальным (нет переноса блоков только через `order`).
- Динамические блоки обёрнуты `createFrame()`/`startDynamicWithID()`.

Режим «живой Битрикс»:
- DevTools → Network: основной CSS не блокирует рендер; нижние скрипты идут перед
  `</body>`; WOFF2 грузится с приоритетом, текст виден сразу (swap).
- Lighthouse / PageSpeed: LCP по «геройской» картинке, CLS близок к 0.
- При включённом «Композите» в ответе есть заголовок `X-Bitrix-Composite`
  (`Cached`/`Dynamic`), а корзина/счётчики обновляются отдельным запросом и
  показывают актуальные данные после прогрева кэша.
- В заголовках ответа для text-ассетов виден `content-encoding: br` (Brotli) и
  протокол HTTP/2.

## ⚠️ Риски

- ⚠️ `loading="lazy"` на LCP-изображении откладывает главный элемент первого экрана
  и ухудшает LCP — для него нужен `preload`/`fetchpriority`, а не ленивая загрузка.
- ⚠️ Картинка без `width`/`height` (или `aspect-ratio`) даёт скачок вёрстки (CLS)
  при дозагрузке.
- ⚠️ Прямой `Asset::addCss()/addJs()` внутри шаблона компонента не повторяется при
  отдаче из кэша — ассет «пропадёт» после прогрева; в шаблоне компонента используйте
  `$this->addExternalCss()/addExternalJS()` (см. `../07-customize-component-template.md`).
- ⚠️ Перестановка блоков только средствами Grid/Flexbox (`order`, `grid-area`) при
  ином порядке в DOM ломает навигацию с клавиатуры и логику скринридера.
- ⚠️ Личные блоки (корзина, ФИО, счётчики) без обёртки во фрейм при включённом
  «Композите» закэшируются вместе со страницей и покажут чужие/неактуальные данные.
- ⚠️ Шрифт без `font-display: swap` даёт «невидимый текст» (FOIT) на время загрузки.
- Нативного флага `defer`/`async` у `Asset::addJs()` нет; отложенность достигается
  выводом в нижнюю зону (`BODY_END`/`ShowBodyScripts`) или пост-обработкой буфера —
  не указывайте несуществующий параметр в коде.

## Связано

- [04-assets.md](04-assets.md) — базовое подключение CSS/JS и UI-расширений.
- [05-verstka-requirements.md](05-verstka-requirements.md) — требования к вёрстке и
  семантике, на которые опирается раскладка.
- [09-seo-meta-a11y.md](09-seo-meta-a11y.md) — SEO-метаданные и доступность шаблона.
- [../07-customize-component-template.md](../07-customize-component-template.md) —
  ассеты и фреймы внутри шаблона компонента.

<!--
Источники (vendor / стандарты):
- Asset (addCss/addJs/addString, AssetLocation, BODY_END):
  https://docs.1c-bitrix.ru/api/classes/Bitrix-Main-Page-Asset.html
- ShowBodyScripts / MoveJSToBody, объединение и минификация CSS/JS:
  https://dev.1c-bitrix.ru/learning/course/index.php?COURSE_ID=35&LESSON_ID=4469
- Композит и динамические области (createFrame / Composite\Frame::startDynamicWithID):
  https://dev.1c-bitrix.ru/api_help/main/composite.php
- LCP / fetchpriority: https://web.dev/articles/optimize-lcp
- CLS: https://web.dev/articles/cls
- Критический CSS: https://web.dev/articles/extract-critical-css
- Адаптивные изображения (srcset/sizes/picture):
  https://developer.mozilla.org/en-US/docs/Web/HTML/Responsive_images
- font-display и preload шрифтов: https://web.dev/articles/font-display
- HTTP/2: https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Protocol_upgrade_mechanism
- Brotli (Accept-Encoding/Content-Encoding):
  https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Encoding
-->
