# 16. Свой компонент 2.0 с нуля

## Цель

Создать собственный компонент «Компоненты 2.0» в `/local/components/<vendor>/<name>/`: с полной структурой (логика, метаданные, параметры, шаблон, переводы), управляемым кэшем `$arResult`, корректной установкой заголовка и крошек вне кэша через `component_epilog.php` и опциональным AJAX-экшеном на классе. Подключить компонент на странице через `IncludeComponent`.

## Когда применять

- Нужна выборка/вывод данных, которых нет в штатных компонентах (`bitrix:news.list` и др.), и кастомизации одного шаблона недостаточно — см. 07-customize-component-template.md.
- Логика повторяется на нескольких страницах и её хочется инкапсулировать в одну переносимую папку.
- Нужны серверные AJAX-экшены с подписанными параметрами (подгрузка «ещё», live-фильтр).

Если задача — только поменять вёрстку существующего компонента, отдельный компонент не нужен: копируйте шаблон (07-customize-component-template.md). Если нужен только вывод готовых данных инфоблока — рассмотрите `bitrix:news.list` (06-output-on-page.md).

## Шаги

1. Создайте папку `/local/components/<vendor>/<name>/` (например `/local/components/acme/news.feed/`). Каталог `/local/components` имеет приоритет над `bitrix/components` и не затрагивается обновлениями ядра.
2. `component.php` — точка входа. Подключает модули, формирует `$arResult` внутри кэш-блока, вызывает `$this->includeComponentTemplate()`. ⚠️ Только логика и данные, без HTML.
3. `class.php` (опционально, но рекомендуется) — класс, наследующий `CBitrixComponent`: нормализация параметров в `onPrepareComponentParams()`, выборка в `executeComponent()`, AJAX-экшены. При наличии `class.php` ядро инстанцирует именно этот класс; `component.php` тогда — тонкий мост `$this->executeComponent()`.
4. `.description.php` — `$arComponentDescription` (NAME, ICON, SORT, PATH-дерево, CACHE_PATH) для каталога компонентов в визуальном редакторе.
5. `.parameters.php` — `$arComponentParameters` (GROUPS + PARAMETERS): какие настройки показывать в окне параметров компонента.
6. `templates/.default/template.php` — вывод HTML из `$arResult`. Рядом — опциональные `result_modifier.php` (правка `$arResult` внутри кэша) и `component_epilog.php` (title/крошки вне кэша).
7. `lang/ru/.description.php`, `lang/ru/.parameters.php`, `templates/.default/lang/ru/template.php` — переводы через `Loc::loadMessages()`.
8. Подключите компонент на странице вызовом `$APPLICATION->IncludeComponent("<vendor>:<name>", ".default", [...])`.

Опирайтесь на готовый скелет: `shared/assets/component-skeleton`.

## Рабочий сниппет/конфиг

`/local/components/acme/news.feed/class.php` — логика и AJAX-экшен:

```php
<?php
if (!defined('B_PROLOG_INCLUDED') || B_PROLOG_INCLUDED !== true) die();

use Bitrix\Main\Loader;
use Bitrix\Main\Engine\Contract\Controllerable;
use Bitrix\Main\Localization\Loc;

class AcmeNewsFeedComponent extends CBitrixComponent implements Controllerable
{
    // Префильтры/постфильтры AJAX-экшенов (можно вернуть [])
    public function configureActions(): array
    {
        return [];
    }

    // Какие ключи $arParams подписать и безопасно отдать в экшен (HMAC)
    protected function listKeysSignedParameters(): array
    {
        return ['IBLOCK_ID', 'NEWS_COUNT'];
    }

    // Нормализация параметров (дефолты, типы). raw-значения берём из ~CODE
    public function onPrepareComponentParams($arParams): array
    {
        $arParams['IBLOCK_ID']  = (int)($arParams['IBLOCK_ID'] ?? 0);
        $arParams['NEWS_COUNT'] = (int)($arParams['NEWS_COUNT'] ?? 0) ?: 20;
        $arParams['CACHE_TYPE'] = $arParams['CACHE_TYPE'] ?? 'A';
        $arParams['CACHE_TIME'] = (int)($arParams['CACHE_TIME'] ?? 3600);
        return $arParams;
    }

    public function executeComponent(): void
    {
        if (!Loader::includeModule('iblock')) {
            ShowError(Loc::getMessage('ACME_FEED_NO_IBLOCK'));
            return;
        }

        // Управляемый кэш-блок: true — кэш-промах, надо считать данные
        if ($this->startResultCache()) {
            $items = [];
            $select = ['ID', 'NAME', 'PREVIEW_TEXT', 'DETAIL_PAGE_URL', 'ACTIVE_FROM'];
            $filter = [
                'IBLOCK_ID'         => $this->arParams['IBLOCK_ID'],
                'ACTIVE'            => 'Y',
                'ACTIVE_DATE'       => 'Y',
                'CHECK_PERMISSIONS' => 'Y',
            ];
            $rs = \CIBlockElement::GetList(
                ['ACTIVE_FROM' => 'DESC', 'ID' => 'DESC'],
                $filter,
                false,
                ['nTopCount' => $this->arParams['NEWS_COUNT']],
                $select
            );
            while ($item = $rs->GetNext()) {
                $items[] = $item;
            }

            if (empty($items)) {
                // Нет данных — не кэшируем пустой/ошибочный результат
                $this->abortResultCache();
            }

            $this->arResult['ITEMS'] = $items;
            // В кэш сохраняем только нужные ключи (экономия размера)
            $this->setResultCacheKeys(['ITEMS']);
            // includeComponentTemplate сам вызовет endResultCache()
            $this->includeComponentTemplate();
        }
    }

    // AJAX-экшен: метод с суффиксом ...Action.
    // Вызов с фронта: BX.ajax.runComponentAction('acme:news.feed', 'loadMore', {...})
    // ВАЖНО: внутри Controllerable-экшена $this->arParams ПУСТ — компонент не
    // проходит onPrepareComponentParams/executeComponent. Подписанные параметры
    // достаём только через getUnsignedParameters() (HMAC-проверка ядром); это
    // единственный устойчивый к подделке источник. Никакого fallback на $_REQUEST
    // для IBLOCK_ID — иначе посетитель сможет читать любой инфоблок.
    public function loadMoreAction(int $page = 1): array
    {
        Loader::includeModule('iblock');

        $p        = $this->getUnsignedParameters();
        $iblockId = (int)($p['IBLOCK_ID'] ?? 0);
        $count    = (int)($p['NEWS_COUNT'] ?? 0) ?: 20;

        // Тот же набор проверок, что и в executeComponent: эндпоинт независим,
        // повторяем ACTIVE_DATE/CHECK_PERMISSIONS, иначе через AJAX утекут
        // скрытые/недоступные по правам элементы.
        $rs = \CIBlockElement::GetList(
            ['ACTIVE_FROM' => 'DESC', 'ID' => 'DESC'],
            [
                'IBLOCK_ID'         => $iblockId,
                'ACTIVE'            => 'Y',
                'ACTIVE_DATE'       => 'Y',
                'CHECK_PERMISSIONS' => 'Y',
            ],
            false,
            ['iNumPage' => $page, 'nPageSize' => $count],
            ['ID', 'NAME', 'DETAIL_PAGE_URL']
        );
        $items = [];
        // GetNext() экранирует строковые поля; либо используйте Fetch() +
        // htmlspecialcharsbx() на каждом поле. Данные уходят в JSON — на фронте
        // вставляйте только через textContent, не innerHTML.
        while ($item = $rs->GetNext()) {
            $items[] = [
                'ID'              => (int)$item['ID'],
                'NAME'            => $item['NAME'],
                'DETAIL_PAGE_URL' => $item['DETAIL_PAGE_URL'],
            ];
        }
        return ['items' => $items, 'page' => $page];
    }
}
```

`/local/components/acme/news.feed/component.php` — тонкая точка входа (логика в классе):

```php
<?php
if (!defined('B_PROLOG_INCLUDED') || B_PROLOG_INCLUDED !== true) die();

/** @var AcmeNewsFeedComponent $this */
$this->executeComponent();
```

`/local/components/acme/news.feed/templates/.default/template.php` — только вывод:

```php
<?php
if (!defined('B_PROLOG_INCLUDED') || B_PROLOG_INCLUDED !== true) die();
/** @var array $arResult @var array $arParams @var CBitrixComponentTemplate $this */

$this->setFrameMode(true); // композитный кэш области
?>
<?php
// Fetch()/GetList отдают сырые данные; в шаблоне ВСЕГДА экранируй вывод (см. security/02).
// PREVIEW_TEXT с типом «текст» — htmlspecialcharsbx; если поле задумано как HTML,
// пропусти через CBXSanitizer вместо «голого» вывода.
$sanitizer = new \CBXSanitizer();
$sanitizer->SetLevel(\CBXSanitizer::SECURE_LEVEL_MIDDLE);
?>
<div class="acme-feed" id="<?= $this->GetEditAreaId('acme-feed') ?>">
    <?php foreach ($arResult['ITEMS'] as $item): ?>
        <article class="acme-feed__item">
            <a href="<?= htmlspecialcharsbx($item['DETAIL_PAGE_URL']) ?>"><?= htmlspecialcharsbx($item['NAME']) ?></a>
            <?php // PREVIEW_TEXT как обычный текст: ?>
            <div class="acme-feed__text"><?= htmlspecialcharsbx($item['PREVIEW_TEXT']) ?></div>
            <?php // ...или, если PREVIEW_TEXT — HTML-анонс, очисти санитайзером: ?>
            <?php // <div class="acme-feed__text"><?= $sanitizer->SanitizeHtml($item['PREVIEW_TEXT']) ?></div> ?>
        </article>
    <?php endforeach; ?>
</div>
```

`/local/components/acme/news.feed/templates/.default/component_epilog.php` — title/крошки ВНЕ кэша (на каждый хит):

```php
<?php
if (!defined('B_PROLOG_INCLUDED') || B_PROLOG_INCLUDED !== true) die();
/** @var array $arResult @var array $arParams @global CMain $APPLICATION */
global $APPLICATION;

if ($arParams['SET_TITLE'] ?? true) {
    $APPLICATION->SetTitle('Лента новостей');
}
$APPLICATION->AddChainItem('Новости', '/news/');
```

`/local/components/acme/news.feed/.description.php`:

```php
<?php
if (!defined('B_PROLOG_INCLUDED') || B_PROLOG_INCLUDED !== true) die();

use Bitrix\Main\Localization\Loc;
Loc::loadMessages(__FILE__);

$arComponentDescription = [
    'NAME'        => Loc::getMessage('ACME_FEED_NAME'),
    'DESCRIPTION' => Loc::getMessage('ACME_FEED_DESC'),
    'ICON'        => '/images/icon.gif',
    'SORT'        => 30,
    'CACHE_PATH'  => 'Y',
    'PATH'        => ['ID' => 'acme', 'NAME' => 'Acme'],
];
```

`/local/components/acme/news.feed/.parameters.php`:

```php
<?php
if (!defined('B_PROLOG_INCLUDED') || B_PROLOG_INCLUDED !== true) die();

use Bitrix\Main\Localization\Loc;
Loc::loadMessages(__FILE__);

$arComponentParameters = [
    'GROUPS'     => [],
    'PARAMETERS' => [
        'IBLOCK_ID' => [
            'PARENT'  => 'BASE',
            'NAME'    => Loc::getMessage('ACME_FEED_IBLOCK_ID'),
            'TYPE'    => 'STRING',
            'DEFAULT' => '',
        ],
        'NEWS_COUNT' => [
            'PARENT'  => 'BASE',
            'NAME'    => Loc::getMessage('ACME_FEED_COUNT'),
            'TYPE'    => 'STRING',
            'DEFAULT' => '20',
        ],
        'CACHE_TIME' => ['DEFAULT' => 3600],
    ],
];
```

Подключение на странице `/news/index.php` (между прологом и эпилогом):

```php
$APPLICATION->IncludeComponent('acme:news.feed', '.default', [
    'IBLOCK_ID'  => 1,
    'NEWS_COUNT' => 12,
    'CACHE_TYPE' => 'A',
    'CACHE_TIME' => 36000000,
], false);
```

Подпись параметров для фронта (в `template.php`). `signedParameters` — HMAC-подписанный набор ключей из `listKeysSignedParameters()`. Внутри экшена `$this->arParams` ПУСТ (компонент не инициализируется), поэтому `IBLOCK_ID`/`NEWS_COUNT` читаются ТОЛЬКО через `getUnsignedParameters()` — это единственный устойчивый к подделке источник; чтение тех же значений из `$_REQUEST` свело бы подпись на нет:

```php
<script>
BX.ajax.runComponentAction('acme:news.feed', 'loadMore', {
    mode: 'class',
    signedParameters: '<?= $this->__component->getSignedParameters() ?>',
    data: { page: 2 }
}).then(function (r) {
    // r.data.items — JSON; вставляй ТОЛЬКО через textContent, не innerHTML.
    r.data.items.forEach(function (it) {
        var a = document.createElement('a');
        a.href = it.DETAIL_PAGE_URL;
        a.textContent = it.NAME;
        document.querySelector('.acme-feed').appendChild(a);
    });
});
</script>
```

## Проверка

Режим «только файлы» (без живого Битрикса):

- Структура есть: `component.php`, `.description.php`, `.parameters.php`, `templates/.default/template.php`, lang-файлы.
- `php -l` для каждого `.php` проходит без ошибок.
- В каждом `.php` есть страж `B_PROLOG_INCLUDED`.
- HTML присутствует только в `template.php`; в `class.php`/`component.php` — нет разметки (соблюдено разделение логики и вывода).
- Выборка обёрнута в `startResultCache()`; есть `setResultCacheKeys()`; AJAX-методы оканчиваются на `Action`.

Режим «живой Битрикс»:

- Откройте страницу с `IncludeComponent` — список выводится, заголовок/крошки появляются.
- Очистите кэш (админка: «Настройки → Очистить кэш» или `CBitrixComponent::clearComponentCache('acme:news.feed', SITE_ID)`), повторно откройте страницу — данные пересобираются.
- AJAX: `BX.ajax.runComponentAction('acme:news.feed', 'loadMore', {mode:'class', signedParameters:'...', data:{page:2}})` в консоли возвращает `data.items` без ошибки подписи.
- Проверьте, что title/крошки меняются динамически (стоят в `component_epilog.php`), а не «застывают» из кэша.

## ⚠️ Риски

- ⚠️ **Не пишите HTML в логике.** Разметка только в `template.php`. Перенос вывода в `component.php`/`class.php` ломает кэширование и переносимость шаблона.
- ⚠️ **Title/крошки/счётчики — только в `component_epilog.php`** (вне кэша). Если поставить их внутри кэш-блока, при кэш-хите они «застынут» и покажут данные первого посетителя.
- **`$arParams['CODE']` HTML-экранирован, `$arParams['~CODE']` — сырой.** В логике/фильтрах/SQL берите `~`-версию, иначе значения со спецсимволами `&<>"` поломаются.
- **Ключ кэша зависит от всех `$arParams`.** Любой динамический параметр (например текущее время) делает кэш бесполезным — каждый запрос новый ключ.
- **`setResultCacheKeys()` урезает `$arResult`.** После кэш-хита в шаблоне будут доступны ТОЛЬКО перечисленные ключи. Не забудьте указать все, что нужны в `template.php`.
- **Composite/frameMode.** Если выводите персональные данные (имя пользователя, корзину) без `createFrame`, область «отравит» composite-кэш страницы. Динамику оборачивайте во фреймы или отключайте `setFrameMode(false)`.
- **AJAX-экшен на классе требует `class.php` и `implements Controllerable`.** Без интерфейса и суффикса `Action` метод не станет серверным экшеном. `signedParameters` берётся из `$this->__component->getSignedParameters()` в шаблоне.
- ⚠️ **`$this->arParams` ВНУТРИ Controllerable-экшена пуст.** Экшен не проходит `onPrepareComponentParams()`/`executeComponent()`, поэтому подписанные параметры доступны только через `$this->getUnsignedParameters()`. Чтение `IBLOCK_ID` из `$this->arParams` или из `$_REQUEST` — это либо «пустой инфоблок», либо обход подписи (INJ/AUTHZ): посетитель сам подставит любой `IBLOCK_ID`.
- ⚠️ **Каждый data-возвращающий AJAX-экшен — независимо достижимый эндпоинт.** Повторяй в нём те же проверки доступа, что и на рендере: `ACTIVE_DATE => 'Y'` и `CHECK_PERMISSIONS => 'Y'` в фильтре. Если их «потерять», через AJAX утекут неактивные/недоступные по правам элементы, даже когда основной список их прячет.
- ⚠️ **Экранируй и AJAX-ответ, и HTML-вывод.** `Fetch()` отдаёт сырые поля → stored XSS. В шаблоне оборачивай каждое поле в `htmlspecialcharsbx()` (HTML-анонс — через `CBXSanitizer`). В экшене используй `GetNext()` либо `htmlspecialcharsbx()` на каждой строке перед JSON; на фронте вставляй данные через `textContent`, не `innerHTML`. См. `security/02`.
- **Пустой/ошибочный результат не кэшируйте** — вызывайте `abortResultCache()`, иначе закэшируется «нет данных».

## Связано

- ../api-map.md
- 05-query-elements.md
- 06-output-on-page.md
- 07-customize-component-template.md
