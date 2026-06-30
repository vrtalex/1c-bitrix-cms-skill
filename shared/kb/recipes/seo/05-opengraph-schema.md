# Рецепт SEO-05 — Open Graph и микроразметка schema.org

> Основан на изучении ядра «1С-Битрикс: Управление сайтом» (SM_VERSION 26.x), операционных практик и официальной документации вендора.

## Цель

Сделать так, чтобы детальные страницы (товар, новость, услуга) отдавали корректные
Open Graph-теги (`og:title`, `og:description`, `og:image`, `og:url`, `og:type`) для
красивых превью в соцсетях/мессенджерах и валидную микроразметку schema.org
(`Product`/`Offer`, `BreadcrumbList`) для rich snippets в выдаче. Значения берём из
наследуемых SEO-свойств и полей инфоблока, картинку OG — из детального изображения
через `CFile`.

## Когда применять

- Карточки каталога/новостей шарятся в соцсети, а превью пустое или «съезжает».
- Нужны rich snippets (цена, наличие, рейтинг, хлебные крошки) в Яндекс/Google.
- Пишется кастомный шаблон `catalog.element`/`news.detail` — нужно не потерять уже
  встроенную разметку и добавить OG.
- ⚠️ OG и schema.org **из коробки не генерируются**: модуль `seo` и `iblock` их не
  ставят автоматически — это всегда работа шаблона сайта/компонента. Не планируй задачу
  как «галочку в настройках».

## Шаги

1. **Реши, где формировать значения.** OG-теги ставятся в `component_epilog.php` или
   `template.php` компонента детальной страницы — там, где доступен `$arResult` элемента.
   Микроразметку `Product`/`Offer` держи в `template.php` карточки (`itemprop`-атрибуты),
   `BreadcrumbList` — в шаблоне `bitrix:breadcrumb`.
2. **Собери источники.** Заголовок/описание — из наследуемых SEO-свойств
   (`ElementValues::getValues()`, коды `ELEMENT_META_TITLE`/`ELEMENT_META_DESCRIPTION`)
   или полей элемента (`NAME`, `PREVIEW_TEXT`). Картинку — из `DETAIL_PICTURE` элемента.
3. **Получи абсолютный URL картинки** через `CFile::GetPath($fileId)` (вернёт путь от
   корня сайта) и допиши схему+домен — соцсети требуют абсолютный `og:image`.
   `og:url` собирай из доверенного имени сервера (Context `getServerName()` /
   `SITE_SERVER_NAME` / опция `main->server_name`) + `DETAIL_PAGE_URL`, а не из
   сырого `$_SERVER['SERVER_NAME']` (host-header injection).
4. **Поставь OG-свойства страницы** через `$APPLICATION->SetPageProperty('og:title', ...)`.
   Свойства буферизуются и попадут в `<head>`, отрисованный шаблоном сайта.
5. **Выведи OG в `<head>`.** В `header.php` шаблона сайта добавь вывод свойств через
   `ShowProperty('og:title')` (внутри тега `<meta property="og:title" content="...">`),
   либо ставь готовые `<meta>` строкой через `Asset`/`AddHeadString` прямо из эпилога
   компонента — тогда правка `header.php` не нужна.
6. **Сохрани/добавь schema.org в шаблоне карточки.** При кастомизации `catalog.element`
   не удаляй существующие `itemscope`/`itemtype`/`itemprop` — иначе потеряешь rich
   snippets. Рейтинг/отзывы (`AggregateRating`, `Review`) добавляй вручную.
7. **Проверь** хлебные крошки: типовой `bitrix:breadcrumb` поддерживает разметку
   навигационной цепочки (`BreadcrumbList`) — используй его и проверь вывод.
8. **Очисти кэш** компонента/страницы после правки шаблонов — иначе увидишь старую
   разметку.

## Рабочий сниппет

Файл (кастом-шаблон карточки):
`/local/templates/<site_template>/components/bitrix/catalog.element/<template>/component_epilog.php`
для OG и `.../template.php` для микроразметки.

`component_epilog.php` — формируем Open Graph из данных элемента:

```php
<?php
if (!defined("B_PROLOG_INCLUDED") || B_PROLOG_INCLUDED !== true) die();
/** @var array $arResult */
/** @var CMain $APPLICATION */

use Bitrix\Iblock\InheritedProperty\ElementValues;

// 1) Заголовок/описание: сначала наследуемое SEO-свойство, потом поля элемента.
$iprop = (new ElementValues($arResult["IBLOCK_ID"], $arResult["ID"]))->getValues();

$ogTitle = $iprop["ELEMENT_META_TITLE"] ?: $arResult["NAME"];
$ogDesc  = $iprop["ELEMENT_META_DESCRIPTION"]
    ?: mb_substr(strip_tags((string)$arResult["PREVIEW_TEXT"]), 0, 200);

// 2) og:image — абсолютный URL из детальной картинки (CFile).
// ⚠️ Хост берём из доверенной конфигурации, НЕ из $_SERVER["SERVER_NAME"]: на
// nginx+php-fpm SERVER_NAME выводится из клиентского заголовка Host, если он не
// запинен → host-header injection (подмена og:url/og:image на чужой домен,
// отравление кэша, перехват превью). Источник правды — имя сервера сайта.
$proto = \Bitrix\Main\Context::getCurrent()->getRequest()->isHttps() ? "https" : "http";
$host  = \Bitrix\Main\Context::getCurrent()->getServer()->getServerName(); // из настроек сайта
if (!$host && defined("SITE_SERVER_NAME")) {
    $host = SITE_SERVER_NAME;                                               // Настройки → Сайты
}
if (!$host) {
    $host = \Bitrix\Main\Config\Option::get("main", "server_name");         // глобальная опция
}
$ogImage = "";
if (!empty($arResult["DETAIL_PICTURE"]["ID"])) {
    $path = CFile::GetPath($arResult["DETAIL_PICTURE"]["ID"]); // путь от корня сайта
    if ($path) {
        $ogImage = $proto . "://" . $host . $path;
    }
}

// 3) og:url — абсолютный адрес карточки.
$ogUrl = $proto . "://" . $host . $arResult["DETAIL_PAGE_URL"];

// 4) Ставим свойства страницы (попадут в <head> через шаблон сайта).
$APPLICATION->SetPageProperty("og:type",        "product");
$APPLICATION->SetPageProperty("og:title",       $ogTitle);
$APPLICATION->SetPageProperty("og:description", $ogDesc);
$APPLICATION->SetPageProperty("og:url",         $ogUrl);
if ($ogImage !== "") {
    $APPLICATION->SetPageProperty("og:image", $ogImage);
}
```

Вывод OG в `<head>` (в `header.php` шаблона сайта, до `</head>`):

```php
<meta property="og:type"        content="<?= $APPLICATION->ShowProperty("og:type") ?>" />
<meta property="og:title"       content="<?= $APPLICATION->ShowProperty("og:title") ?>" />
<meta property="og:description" content="<?= $APPLICATION->ShowProperty("og:description") ?>" />
<meta property="og:url"         content="<?= $APPLICATION->ShowProperty("og:url") ?>" />
<meta property="og:image"       content="<?= $APPLICATION->ShowProperty("og:image") ?>" />
```

Микроразметка `Product`/`Offer` в `template.php` карточки (фрагмент — структура,
которую нельзя терять при кастомизации):

> Переменные фрагмента задаются в начале `template.php` из `$arResult`:
> `$price` — цена из каталога (например, `$arResult["MIN_PRICE"]["VALUE"]` или
> `$arResult["PRICES"][...]["VALUE"]`), `$ogImage` — абсолютный URL детального
> изображения (`$arResult["DETAIL_PICTURE"]["SRC"]` либо собранный через `CFile`,
> как в эпилоге выше). Без них `content=""` уйдёт пустым и Rich Results Test
> забракует `Offer` (нет обязательной цены).

```php
<?php
// В начале template.php — наполняем переменные фрагмента из $arResult:
$price   = $arResult["MIN_PRICE"]["VALUE"] ?? "";              // цена из каталога
$ogImage = $arResult["DETAIL_PICTURE"]["SRC"] ?? "";          // абс. URL картинки
?>
<div itemscope itemtype="http://schema.org/Product">
  <h1 itemprop="name"><?= $arResult["NAME"] ?></h1>
  <?php if ($ogImage ?? false): ?>
    <meta itemprop="image" content="<?= $ogImage ?>" />
  <?php endif ?>
  <div itemprop="offers" itemscope itemtype="http://schema.org/Offer">
    <meta itemprop="price"        content="<?= $price ?>" />
    <meta itemprop="priceCurrency" content="RUB" />
    <link itemprop="availability" href="http://schema.org/InStock" />
  </div>
</div>
```

## Выбор API

- **Чтение SEO-мета** — `Bitrix\Iblock\InheritedProperty\ElementValues($iblockId, $elementId)->getValues()`
  (D7). Возвращает вычисленные, HTML-экранированные значения (`ELEMENT_META_TITLE`,
  `ELEMENT_META_DESCRIPTION`, `ELEMENT_*_FILE_ALT/TITLE` и т.д.). Для разделов —
  `SectionValues`, для инфоблока — `IblockValues`.
- **Свойства страницы / `<head>`** — `$APPLICATION->SetPageProperty()` + `ShowProperty()`
  (это `CMain`, штатный механизм, прямого D7-аналога для page property нет). Альтернатива
  без правки `header.php` — `$APPLICATION->AddHeadString('<meta property="og:..." ...>')`.
- **Путь к картинке** — `CFile::GetPath($fileId)` для одного файла; `CFile::ResizeImageGet()`,
  если для OG нужна нарезка под рекомендуемый размер. Это две поддерживаемые версии API:
  `CFile` (legacy) — штатный путь к файлам; объектная обёртка не требуется для чтения пути.
- **OG vs JSON-LD vs Microdata.** Встроенные шаблоны `catalog.element` несут Microdata
  (`itemprop`). Можно вместо этого собирать JSON-LD в `<head>`/конце `<body>`. ⚠️ Не дублируй
  оба формата (Microdata + JSON-LD) на одной странице — выбери один.

## Другие типы schema.org (не только Product)

`Product`/`Offer` и `BreadcrumbList` закрывают карточку и навигацию; ниже — типы, которые
часто нужны на остальных страницах. Формат — **JSON-LD** в `<head>` (через `AddHeadString`),
по одному блоку на сущность; не дублировать с Microdata той же страницы.

- **`Organization`** — на всех страницах (обычно из `header.php`/`footer.php` шаблона сайта):
  название, логотип, контакты, `sameAs` (соцсети). Помогает формировать карточку организации.
  ```php
  $org = ['@context'=>'https://schema.org','@type'=>'Organization',
    'name'=>'ООО Ромашка','url'=>'https://site.ru/',
    'logo'=>'https://site.ru/logo.png',
    'contactPoint'=>['@type'=>'ContactPoint','telephone'=>'+7-495-000-00-00','contactType'=>'sales'],
    'sameAs'=>['https://vk.com/romashka','https://t.me/romashka']];
  $APPLICATION->AddHeadString('<script type="application/ld+json">'.
    json_encode($org, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES).'</script>', true);
  ```
- **`LocalBusiness`** (подтип `Organization`) — для сайтов с физическими точками: добавьте
  `address` (`PostalAddress`), `geo` (`GeoCoordinates`), `openingHours`. Для мультирегиона —
  свой блок под каждый филиал/город.
- **`FAQPage`** — для блоков «вопрос-ответ» (нужен **видимый** на странице FAQ; разметка скрытого
  контента — нарушение). Массив `mainEntity` из `Question` → `acceptedAnswer`/`Answer`.
- **`Article`/`NewsArticle`/`BlogPosting`** — для новостей/блога: `headline`, `datePublished`,
  `dateModified`, `author`, `image`. Значения берите из полей элемента и наследуемых SEO-свойств.
- **`AggregateRating`/`Review`** — рейтинг и отзывы товара (внутри `Product`). ⚠️ Значения должны
  соответствовать реально показанным на странице отзывам, иначе риск санкций.

Google ужесточает требования к товарным сниппетам (merchant listings): для расширенного показа
желательны `Offer` с `priceValidUntil`, `shippingDetails`, `hasMerchantReturnPolicy`. Проверяйте
актуальные обязательные/желательные поля в Google Rich Results Test.

## Проверка

Проверка рендера и структуры — по общему паттерну: [verification](../../operations.md) (CLI для структуры, браузер/preview для рендера; на dev-стенде).

**Режим «только файлы» (без запуска Битрикс):**

- `php -l component_epilog.php` и `php -l template.php` — синтаксис без ошибок.
- Grep: `SetPageProperty(\"og:` присутствует в эпилоге; `itemtype=` и `itemprop=`
  сохранены в `template.php` карточки.
- Хост для `og:url`/`og:image` берётся из доверенного источника
  (`Context::getServerName()` / `SITE_SERVER_NAME` / опция `main->server_name`),
  а **не** из сырого `$_SERVER['SERVER_NAME']`/`HTTP_HOST` (иначе host-header
  injection → подмена превью/отравление кэша).
- Убедись, что путь шаблона лежит под `/local/templates/.../components/bitrix/catalog.element/`,
  а не правит файлы дистрибутива в `/bitrix`.

**Режим «живой Битрикс»:**

- Открой детальную страницу товара → в исходном HTML видны `<meta property="og:title">`,
  `og:image` (абсолютный URL, открывается в браузере), `og:url`.
- Прогони URL через Google Rich Results Test и валидатор микроразметки Яндекс.Вебмастера —
  `Product`/`Offer`/`BreadcrumbList` распознаются, обязательные поля заполнены.
- Проверь превью в дебаггере соцсети (карточка ссылки показывает title/описание/картинку).
- После правки шаблона очисти кэш и перезагрузи — старая разметка не должна остаться.

## ⚠️ Риски

- ⚠️ **OG не из коробки.** Ни `seo`, ни `iblock` не ставят `og:*` автоматически. Забыли
  шаблон → пустые превью, SEO-провал шаринга. Закладывай ручную работу в смету.
- ⚠️ **Потеря rich snippets при кастомизации.** Кастомный `template.php` без `itemscope`/
  `itemprop` теряет структурированные данные. Перед заменой сверь наличие разметки.
- ⚠️ **Относительный `og:image`.** Соцсети требуют абсолютный URL (схема+домен). Относительный
  путь из `CFile::GetPath()` без хоста → картинка превью не подтянется.
- ⚠️ **Host-header injection в `og:url`/`og:image`.** `$_SERVER['SERVER_NAME']` на
  nginx+php-fpm обычно выводится из клиентского заголовка `Host`, если он не запинен —
  атакующий подменяет хост, и превью/`og:url` указывают на чужой домен (перехват
  превью, отравление кэша, open-redirect). Бери хост из доверенной конфигурации
  (`Context::getServerName()` / константа `SITE_SERVER_NAME` / опция
  `main->server_name`) и ОБЯЗАТЕЛЬНО запинь хост на веб-сервере: явный `server_name`
  в nginx (дефолтный server-блок на `444`) или `UseCanonicalName On` в Apache — чтобы
  `SERVER_NAME` не контролировался клиентом.
- ⚠️ **Расхождение разметки с видимым контентом.** Цена/наличие в schema.org должны совпадать
  с тем, что на странице — иначе риск санкций поисковика.
- **Дубль форматов.** JSON-LD + Microdata одновременно — частая ошибка; оставь один.
- **Кэш мета-значений.** Наследуемые свойства кешируются; после массовой смены SEO-шаблонов
  сбрось кэш (`clearValues()` / переиндексация), иначе OG соберётся из старых значений.
- **Пропуск обязательных полей** (`name`, `price`, `offers`) — разметка невалидна, snippet
  не покажется. Проверяй валидатором.

## Связано

- [../02-create-iblock.md](../02-create-iblock.md) — инфоблок и его свойства (источник
  значений для OG/мета и привязки SEO-свойств).
- [../08-complex-component-sef.md](../08-complex-component-sef.md) — ЧПУ/SEF комплексного
  компонента: корректные `DETAIL_PAGE_URL` нужны для `og:url` и канонических адресов.
- [../../api-map.md](../../api-map.md) — карта API: `InheritedProperty\*`, `CFile`,
  `CMain::SetPageProperty`.
