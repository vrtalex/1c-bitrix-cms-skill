# Рецепт 07. Кастомизировать шаблон компонента без правки ядра

## Цель
Изменить HTML-вывод и подготовку данных стандартного компонента (например `bitrix:news.list`) под дизайн сайта, не редактируя файлы в `/bitrix/components`. Делается копированием шаблона компонента в шаблон сайта и точечной правкой через хук-файлы `result_modifier.php` (внутри кэша) и `component_epilog.php` (вне кэша).

## Когда применять
- Нужно поменять разметку списка/детальной, добавить вёрстку, классы, обёртки.
- Нужно добавить в каждый элемент вычисляемое поле (формат цены, обрезка текста, доп. URL) — без своего `component.php`.
- Нужно поставить `SetTitle` / хлебные крошки / счётчик просмотров так, чтобы они работали даже при включённом кэше.
- Дизайн различается между шаблонами сайта — кастом должен жить рядом с конкретным шаблоном сайта.

Не применять, если требуется изменить саму выборку данных (другой фильтр, доп. запрос) — это логика `component.php`; тогда делают собственный компонент в `/local/components/...` или класс-наследник. Здесь же мы работаем только со слоем представления.

## Шаги
1. Определите активный шаблон сайта — константа `SITE_TEMPLATE_ID` (имя папки). Целевой каталог — `/local/templates/<SITE_TEMPLATE_ID>/components/bitrix/<имя_компонента>/<имя_шаблона>/`. Приоритет `/local` над `/bitrix` подтверждён в `CSiteTemplate::GetList()` (сканирует `/local/templates`, затем `/bitrix/templates`).
2. Выберите имя шаблона компонента. Удобно завести своё (например `custom`), чтобы не пересекаться с обновлениями. Можно использовать `.default`, но тогда правки затрагивают все вызовы без явного имени шаблона.
3. Скопируйте в этот каталог только нужные файлы из штатного шаблона компонента (`template.php` обязателен; при необходимости `result_modifier.php`, `component_epilog.php`, `style.css`, `script.js`, `lang/`). Файлы `style.css` и `script.js` подключаются ядром автоматически.
4. В вызове `$APPLICATION->IncludeComponent(...)` укажите имя своего шаблона вторым аргументом:
   ```php
   $APPLICATION->IncludeComponent("bitrix:news.list", "custom", array(/* params */), false);
   ```
5. Правьте разметку в `template.php`. Доступны `$arResult`, `$arParams`, `$arLangMessages`, `$templateName`, `$templateFile`, `$templateFolder`, `$componentPath`, `$component`, `$this`, а также `$APPLICATION`, `$USER`, `$DB`.
6. Подготовку данных (новые поля, переформатирование) выносите в `result_modifier.php` — он выполняется до `template.php` и попадает в кэш.
7. SEO-вывод (title, цепочка навигации, счётчики) выносите в `component_epilog.php` — он выполняется вне кэша на каждом хите.
8. Поля, которые `component_epilog.php` должен видеть после кэш-хита, пометьте через `setResultCacheKeys()` (см. раздел «Риски»).

Порядок выполнения внутри `CBitrixComponentTemplate::IncludeTemplate()`: lang → `result_modifier.php` → авто-CSS/JS → `template.php`; `component_epilog.php` регистрируется после вывода и запускается вне кэша.

## Рабочий сниппет

Файл: `/local/templates/main/components/bitrix/news.list/custom/result_modifier.php`
```php
<?php
if (!defined("B_PROLOG_INCLUDED") || B_PROLOG_INCLUDED !== true) die();

// Внутри кэша: добавляем вычисляемые поля в каждый элемент.
// В логике берём "сырое" значение свойства (~), для безопасной выборки.
// strip_tags НЕ экранирует — он лишь срезает теги; "&" и "<" текстовых данных
// останутся. Поэтому собранную выжимку дополнительно прогоняем через
// htmlspecialcharsbx() (см. security/02).
foreach ($arResult["ITEMS"] as &$item) {
    $raw = $item["PROPERTIES"]["PRICE"]["VALUE"] ?? 0;
    $item["PRICE_FORMATTED"] = number_format((float)$raw, 0, "", " ") . " ₽";
    $item["PREVIEW_SHORT"]   = htmlspecialcharsbx(
        mb_substr(strip_tags($item["PREVIEW_TEXT"] ?? ""), 0, 160)
    );
}
unset($item);
```

Файл: `/local/templates/main/components/bitrix/news.list/custom/template.php`
```php
<?php
if (!defined("B_PROLOG_INCLUDED") || B_PROLOG_INCLUDED !== true) die();
?>
<?php
// Штатный news.list пред-экранирует NAME через GetNext(), но кастомные/сырые (~)
// поля и DETAIL_PAGE_URL — НЕТ. Всегда экранируй на выводе (см. security/02).
?>
<div class="news-grid">
<?php foreach ($arResult["ITEMS"] as $item): ?>
    <article class="news-card" id="<?= $this->GetEditAreaId($item["ID"]) ?>">
        <a href="<?= htmlspecialcharsbx($item["DETAIL_PAGE_URL"]) ?>"><?= htmlspecialcharsbx($item["NAME"]) ?></a>
        <span class="news-card__price"><?= htmlspecialcharsbx($item["PRICE_FORMATTED"]) ?></span>
        <p><?= $item["PREVIEW_SHORT"] ?></p>
    </article>
<?php endforeach; ?>
</div>
```

Файл: `/local/templates/main/components/bitrix/news.list/custom/component_epilog.php`
```php
<?php
if (!defined("B_PROLOG_INCLUDED") || B_PROLOG_INCLUDED !== true) die();

// Вне кэша, на каждом хите: SEO и хлебные крошки.
// Доступны $arResult/$arParams, помеченные через setResultCacheKeys.
global $APPLICATION;
if (!empty($arResult["NAME"])) {
    $APPLICATION->SetTitle($arResult["NAME"]);
}
if (!empty($arResult["SECTION"]["PATH"])) {
    foreach ($arResult["SECTION"]["PATH"] as $sec) {
        $APPLICATION->AddChainItem($sec["NAME"], $sec["~SECTION_PAGE_URL"] ?? "");
    }
}
```

Чтобы `component_epilog.php` гарантированно получил эти поля при кэш-хите, в `result_modifier.php` (или в `component.php` своего компонента) объявите ключи:
```php
$component->setResultCacheKeys(["NAME", "SECTION", "ITEMS"]);
```

## Выбор API (что рекомендовано для ЭТОЙ задачи и почему)
- **Слой представления:** переопределённый `template.php` в шаблоне сайта — единственный поддерживаемый способ менять вёрстку без правки ядра. Резолв шаблона учитывает `SITE_TEMPLATE_ID` и приоритет `/local`.
- **Подготовка данных к выводу:** `result_modifier.php`. Выполняется один раз и кэшируется вместе с `$arResult`, поэтому тяжёлые преобразования здесь дешевле, чем в `template.php`.
- **Динамика вне кэша:** `component_epilog.php`. Только здесь корректно ставить `SetTitle`, `AddChainItem`, инкремент счётчиков — иначе значения «застынут» из кэша.
- **Экранирование:** в логике и фильтрах используйте `$arParams['~CODE']` (raw), в HTML — `$arParams['CODE']` (экранированный). Это правило из движка компонентов (`__prepareComponentParams`).
- **Локализация:** строки шаблона — через `lang/<язык>/template.php` (`$MESS[...]`) и `GetMessage()`; в новом коде допустимо `\Bitrix\Main\Localization\Loc::loadMessages(__FILE__)` + `Loc::getMessage()`.

Две поддерживаемые версии API сосуществуют: legacy-окружение шаблона (`$APPLICATION`, `GetMessage`) обязательно для шаблонов; D7-слой (`Loc`, `\Bitrix\Main\Page\Asset`) применяется поверх. Для кастомизации шаблона компонента достаточно legacy-окружения, которое движок сам пробрасывает в файлы хуков.

## Проверка

Проверка рендера и структуры — по общему паттерну: [verification](../operations.md) (CLI для структуры, браузер/preview для рендера; на dev-стенде).

Режим «только файлы» (без запущенного Битрикса):
- Каталог соответствует схеме `/local/templates/<SITE_TEMPLATE_ID>/components/bitrix/<имя_компонента>/<имя_шаблона>/`.
- В каталоге есть `template.php` со стражем `B_PROLOG_INCLUDED`.
- Имя шаблона из второго аргумента `IncludeComponent` совпадает с именем папки (опечатка → молча подхватится `.default` компонента).
- В `/bitrix/components/...` ничего не изменено (сравните, что правки только в `/local`).
- Подсветка синтаксиса: `php -l template.php`, `php -l result_modifier.php`, `php -l component_epilog.php`.

Режим «живой Битрикс»:
- Откройте страницу с компонентом — должна примениться новая вёрстка и новые поля.
- Сбросьте кэш компонента и проверьте, что `result_modifier.php` отработал (новые поля видны после очистки кэша). Программный сброс: `CBitrixComponent::clearComponentCache("bitrix:news.list", SITE_ID)`.
- Проверьте, что `SetTitle`/крошки из `component_epilog.php` обновляются при кэш-хите (например на детальных страницах с разными элементами title меняется).
- Проверьте в режиме правки (админ-панель), что области редактирования элементов работают (`GetEditAreaId`).

## ⚠️ Риски
- ⚠️ Не редактируйте файлы в `/bitrix/components/bitrix/...` — изменения перезапишутся при обновлении ядра. Кастом только в шаблоне сайта (`/local/templates/...` или `/bitrix/templates/...`).
- ⚠️ `setResultCacheKeys()` урезает `$arResult`: после кэш-хита в шаблоне и в `component_epilog.php` будут доступны ТОЛЬКО перечисленные ключи. Если поле нужно в epilog, обязательно включите его в список — иначе после кэш-хита оно окажется пустым.
- ⚠️ `SetTitle`/счётчики в `result_modifier.php` или `template.php` «застынут» в кэше: при следующем хите выполнится не код, а закэшированный вывод. Такую динамику размещайте только в `component_epilog.php`.
- ⚠️ При выводе значений в HTML экранируйте через `htmlspecialcharsbx()`. Штатный `news.list` пред-экранирует `NAME` через `GetNext()`, но кастомные/сырые (`~`) поля, `DETAIL_PAGE_URL` и вычисляемые в `result_modifier.php` значения — НЕТ. `strip_tags()` тоже не экранирует (срезает теги, но `&<>"` остаются) — выжимки вроде `PREVIEW_SHORT` оборачивайте в `htmlspecialcharsbx()` ОДИН раз (в `result_modifier.php` ИЛИ в `template.php`, не дважды). Подробнее — `security/02`. (`$arParams['CODE']` уже экранирован, «сырые» `~`-поля — нет.)
- Персональные данные (корзина, имя пользователя) во вьюхе без оборачивания во фрейм отключают composite-кэш всей страницы. Динамику оборачивайте через `$this->createFrame()`.

## Связано
- Рецепт `08-result-modifier-vs-epilog` — детальное разграничение «внутри кэша / вне кэша» и `setResultCacheKeys`.
- Рецепт `06-place-component-on-page` — вставка компонента и его параметры (`.parameters.php`).
- Рецепт `11-site-template-structure` — структура шаблона сайта, `header.php`/`footer.php`, приоритет `/local`.
- KB: `../00-overview.md` (жизненный цикл, кэш, хуки шаблона), `../api-map.md` (резолв шаблона компонента, `SITE_TEMPLATE_ID`).
