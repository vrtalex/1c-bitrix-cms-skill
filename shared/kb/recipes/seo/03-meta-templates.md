# Рецепт SEO-03: Мета-шаблоны инфоблока (наследуемые SEO-свойства)

Под-скилл: `1c-bitrix-cms-seo` • Платформа: «1С-Битрикс: Управление сайтом», ядро 26.x, модуль `iblock`.

## Цель
Задать **наследуемые SEO-свойства** инфоблока — шаблоны `title`, `META_TITLE`, `META_KEYWORDS`, `META_DESCRIPTION` (а также `alt`/`title` картинок) с плейсхолдерами движка шаблонов. Шаблоны наследуются по дереву **инфоблок → раздел → элемент** и вычисляются для каждой страницы автоматически. Один шаблон закрывает сотни карточек/разделов, мета доходит до `<head>` через компонент или `$APPLICATION->SetPageProperty()` / `SetTitle()`.

## Когда применять
- Каталог или контентный инфоблок (новости, услуги, товары): мета нужны на сотнях страниц, ручное заполнение нерационально.
- Нужна **воспроизводимая** установка SEO-шаблонов (миграция, перенос между стендами, CI), а не ручной ввод во вкладке «SEO».
- Нужно прочитать вычисленную мету из кода (свой шаблон карточки/раздела, OG-теги из детальной картинки).

Если на странице используется типовой `news.detail`/`catalog.element` с включёнными опциями вывода мета — отдельный код вывода не нужен (см. «Шаг 4»); рецепт нужен для записи шаблонов и для кастомных шаблонов страниц.

## Шаги
1. **Спроектируйте уровень шаблона.** Корень наследования — инфоблок (`IblockTemplates`, закрывает всё). Точечные исключения — раздел (`SectionTemplates`) или элемент (`ElementTemplates`). Нижний уровень перебивает верхний; флаг `INHERITED` показывает, унаследовано значение или задано локально.
2. **Запишите шаблоны** через `set([...])` с предопределёнными кодами (`ELEMENT_META_TITLE`, `SECTION_META_DESCRIPTION` и т.д.) и плейсхолдерами `{=this.Name}`, `{=property.CODE.Value}`.
3. **Сбросьте кеш вычисленных значений** после массовой смены шаблонов: `clearValues()` (иначе на страницах останутся старые мета из `b_iblock_element_iprop` / `b_iblock_section_iprop`).
4. **Включите вывод в компоненте** (`SET_TITLE`, `SET_BROWSER_TITLE`, `SET_META_KEYWORDS`, `SET_META_DESCRIPTION`, `SET_CANONICAL_URL`) — типовые `news.detail`/`catalog.element` сами читают `ElementValues` и зовут `SetPageProperty`/`SetTitle`. Для кастомного шаблона выведите мету сами (см. сниппет, блок «вывод»).
5. **Проверьте вывод в шаблоне сайта**: `header.php` должен звать `$APPLICATION->ShowTitle()`, `ShowMeta("keywords")`, `ShowMeta("description")`, `ShowProperty("canonical")`.

## Рабочий сниппет
Разовый установочный скрипт записи шаблонов. Положите в `/local/`, запустите один раз, затем удалите.

Файл: `/local/install/seo_03_meta_templates.php`

```php
<?php
// Разовый установочный скрипт. ЗАПУСТИТЬ ОДИН РАЗ, затем УДАЛИТЬ.
require($_SERVER['DOCUMENT_ROOT'] . '/bitrix/modules/main/include/prolog_before.php');

use Bitrix\Main\Loader;
use Bitrix\Iblock\InheritedProperty\IblockTemplates;
use Bitrix\Iblock\InheritedProperty\SectionTemplates;
use Bitrix\Iblock\InheritedProperty\IblockValues;

if (!Loader::includeModule('iblock')) {
    die('Module iblock is not installed');
}

$iblockId = 12; // ваш ID инфоблока

// 1. Корень наследования: шаблоны на уровне инфоблока — закроют все разделы и элементы.
$ibTpl = new IblockTemplates($iblockId);
$ibTpl->set([
    // browser <title> для карточки товара/элемента
    'ELEMENT_META_TITLE'       => 'Купить {=this.Name} в Москве — цена, доставка',
    'ELEMENT_META_KEYWORDS'    => '{=this.Name}, купить, цена, {=property.BRAND.Value}',
    'ELEMENT_META_DESCRIPTION' => '{=this.Name} по цене {=property.PRICE.Value} ₽. '
                                . 'Характеристики, фото, отзывы. Доставка по РФ.',
    // H1 / заголовок страницы (SetTitle)
    'ELEMENT_PAGE_TITLE'       => '{=this.Name}',
    // alt/title детальной картинки
    'ELEMENT_DETAIL_PICTURE_FILE_ALT'   => '{=this.Name}',
    'ELEMENT_DETAIL_PICTURE_FILE_TITLE' => '{=this.Name} — фото',

    // мета для страниц-разделов (категорий каталога)
    'SECTION_META_TITLE'       => '{=this.Name} — каталог, цены',
    'SECTION_META_DESCRIPTION' => 'Раздел «{=this.Name}»: товары в наличии, цены, доставка.',
    'SECTION_PAGE_TITLE'       => '{=this.Name}',
]);

// 2. Точечное исключение: свой шаблон для конкретного раздела (перебьёт инфоблочный).
$sectionId = 45;
$secTpl = new SectionTemplates($iblockId, $sectionId);
$secTpl->set([
    'SECTION_META_TITLE'       => 'Распродажа {=this.Name} — скидки до 50%',
    'SECTION_META_DESCRIPTION' => '{=this.Name} со скидкой. Ограниченное предложение.',
]);

// 3. Сброс кеша вычисленных значений (b_iblock_element_iprop / b_iblock_section_iprop),
//    чтобы новые шаблоны пересчитались. Иначе на страницах останутся старые мета.
(new IblockValues($iblockId))->clearValues();

echo "SEO-шаблоны записаны для инфоблока {$iblockId}. Кеш значений сброшен.";
```

Чтение вычисленной меты в кастомном шаблоне страницы (`detail.php` / свой `template.php`):

```php
<?php
use Bitrix\Iblock\InheritedProperty\ElementValues;

// $arResult['IBLOCK_ID'], $arResult['ID'] — из компонента-источника
$iprop  = new ElementValues($arResult['IBLOCK_ID'], $arResult['ID']);
$values = $iprop->getValues(); // значения уже прошли движок и HTML-экранированы

global $APPLICATION;
$APPLICATION->SetPageProperty('title',       $values['ELEMENT_META_TITLE']);       // <title>
$APPLICATION->SetPageProperty('keywords',    $values['ELEMENT_META_KEYWORDS']);
$APPLICATION->SetPageProperty('description', $values['ELEMENT_META_DESCRIPTION']);
$APPLICATION->SetTitle($values['ELEMENT_PAGE_TITLE'] ?: $arResult['NAME']);        // H1

// Бонус: OG-картинка из вычисленного alt/title детальной картинки
// (OG-теги модуль не ставит автоматически — выводим вручную).
$APPLICATION->SetPageProperty('og:title', $values['ELEMENT_META_TITLE']);
```

## Выбор API
- Записывать/читать шаблоны — только **[D7] `\Bitrix\Iblock\InheritedProperty\*`**: `IblockTemplates` / `SectionTemplates` / `ElementTemplates` (запись через `set()`), `IblockValues` / `SectionValues` / `ElementValues` (чтение вычисленного через `getValues()` / `getValue($code)`, сброс кеша через `clearValues()`). Legacy-аналога нет — это и есть штатный механизм наследуемых свойств.
- Выводить мету на страницу — `$APPLICATION->SetPageProperty()` / `SetTitle()` (это `\CMain`, штатный способ установки свойств страницы), в шаблоне сайта — `ShowTitle()` / `ShowMeta()` / `ShowProperty()`. Это одна из двух поддерживаемых версий API для свойств страницы; D7-замены для `SetPageProperty` нет.
- Плейсхолдеры обрабатывает `\Bitrix\Iblock\Template\Engine`: области `this` / `parent` / `sections` / `iblock` / `property`; поля `{=this.Name}`, `{=this.Code}`, `{=this.PreviewText}`, `{=property.CODE.Value}`; функции `upper`, `lower`, `translit`, `concat`, `limit`, модификаторы `/l` (lower), `/t-` (translit). Значения из `getValues()` уже экранированы (`HtmlFilter::encode`) — повторно не экранировать.

## Проверка

Проверка рендера и структуры — по общему паттерну: [verification](../../operations.md) (CLI для структуры, браузер/preview для рендера; на dev-стенде).

**Режим «только файлы» (без живого Битрикса):**
- Установочный скрипт использует классы из `Bitrix\Iblock\InheritedProperty\*`, коды шаблонов — из предопределённого набора (`ELEMENT_META_*`, `ELEMENT_PAGE_TITLE`, `SECTION_META_*`, `*_PICTURE_FILE_ALT/TITLE`).
- Плейсхолдеры в шаблонах имеют корректный синтаксис `{= ... }` с областью (`this.` / `property.` / `parent.`); у свойства указан суффикс `.Value`.
- После записи шаблонов в скрипте присутствует сброс кеша `clearValues()`.
- В кастомном шаблоне мета читается через `getValues()` и выводится через `SetPageProperty`/`SetTitle`; значения не экранируются повторно.
- В `header.php` шаблона сайта есть `ShowTitle()`, `ShowMeta("keywords")`, `ShowMeta("description")`.

**Режим «живой Битрикс»:**
- Открыть карточку элемента → в `<head>` присутствуют `<title>`, `<meta name="keywords">`, `<meta name="description">`, собранные по шаблону (имя элемента подставлено вместо `{=this.Name}`).
- Открыть раздел с точечным шаблоном (`$sectionId`) → его мета отличается от инфоблочного (локальный шаблон перебил наследуемый).
- Во вкладке «SEO» элемента без локального значения поле показано как унаследованное (флаг `INHERITED`), значение совпадает с инфоблочным шаблоном.
- После повторной правки шаблона и `clearValues()` мета на странице обновилась (а не осталась из кеша `b_iblock_*_iprop`).
- В компоненте `news.detail`/`catalog.element` включены `SET_BROWSER_TITLE=Y`, `SET_META_DESCRIPTION=Y`, `SET_CANONICAL_URL=Y` — мета ставится без дубля.

## ⚠️ Риски
- ⚠️ **Кеш вычисленных значений не сбрасывается сам.** После массовой смены шаблонов значения остаются в `b_iblock_element_iprop` / `b_iblock_section_iprop`, и на страницах останется прежняя мета — это прямой SEO-провал (поисковик переиндексирует неактуальные title/description). Обязательно `clearValues()` после `set()`.
- ⚠️ **Приоритет источников: свойство инфоблока перебивает SEO-шаблон.** Если в параметрах компонента указано свойство как `BROWSER_TITLE` / `META_DESCRIPTION` и оно заполнено в карточке, оно перекроет наследуемый шаблон (`Collection::firstNotEmpty`). Учитывайте при массовой генерации — заполненное вручную поле «победит» шаблон.
- ⚠️ **Элемент в нескольких разделах:** при наследовании берётся только основной/первый раздел. Шаблон второго раздела к такому элементу не применится — проверяйте мету у мультираздельных элементов отдельно.
- **Open Graph и микроразметка не из шаблонов мета.** `<meta property="og:*">` и `schema.org/Product` модуль автоматически не ставит — это ручная работа в шаблоне страницы/компонента (`og:image` удобно брать из детальной картинки, см. сниппет).
- **Дубль мета.** Если включены и наследуемые свойства, и старые опции вывода метатегов компонента — в `<head>` появятся два `<meta description>`. Оставьте один источник.

## Связано
- [Создать инфоблок](../02-create-iblock.md) — корневая сущность, на уровне которой задаётся `IblockTemplates`; здесь же `CODE`/`API_CODE`, нужные для ЧПУ и URL в мете.
- [Комплексный компонент в SEF-режиме](../08-complex-component-sef.md) — ЧПУ-страницы списка/раздела/элемента, на которые ложатся вычисленные мета-шаблоны; там же канонические URL для SEF-раздела.
- [api-map](../../api-map.md) — карта классов `\Bitrix\Iblock\InheritedProperty\*` и соответствие D7 / legacy для свойств страницы.
