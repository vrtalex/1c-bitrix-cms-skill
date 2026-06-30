# Шаблоны компонентов: переопределение, хук-файлы, кэш-границы

## Цель
Переопределить вывод штатного компонента (например `bitrix:news.list`) под свой
дизайн так, чтобы кастомизация переживала обновления ядра и корректно работала с
кэшем. Разобрать роли всех файлов шаблона компонента (`template.php`,
`result_modifier.php`, `component_epilog.php`, `.description.php`,
`.parameters.php`, `lang/`) и понять главную границу — что выполняется ВНУТРИ
кэша, а что на КАЖДОМ запросе.

## Когда применять
- Нужно изменить разметку компонента, не трогая файлы в `/bitrix/`.
- `SetTitle()`, хлебные крошки или мета-теги из компонента «пропадают» после
  включения кэша компонента.
- Нужно подготовить/перебрать `$arResult` до рендера без правки `component.php`.
- Скопированному шаблону нужны собственные настройки в визуальном редакторе.

## Шаги
1. **Найдите шаблон по иерархии разрешения.** Ядро ищет папку шаблона по приоритету
   `/local` → `/bitrix`, и при отсутствии указанного имени откатывается на
   `.default`. Порядок поиска (от высшего приоритета):
   `/local/templates/<id>/components/<ns>/<component>/<tpl>/` →
   `/local/components/<ns>/<component>/templates/<tpl>/` →
   `/bitrix/components/<ns>/<component>/templates/<tpl>/`, а если папки `<tpl>` нет —
   `.default` в тех же местах. Размещение в шаблоне САЙТА
   (`/local/templates/<id>/components/...`) — корректный путь для рестайла вывода,
   привязанного к дизайну конкретного шаблона сайта.
2. **Переопределяйте копированием ВСЕЙ папки, а не правкой `/bitrix`.** В режиме
   правки выберите «Скопировать шаблон компонента» (или скопируйте папку вручную)
   в путь шаблона сайта выше. `/local` приоритетнее `/bitrix`, поэтому копия
   замещает штатный шаблон, а обновления ядра не трогают `/local` — кастомизация
   не снимается на апдейте.
3. **Распределите логику по файлам по их роли** (см. таблицу ниже): подготовка
   данных — в `result_modifier.php`, разметка — в `template.php`, действия «на
   каждый хит» (заголовок, мета, крошки, поздние ассеты) — в `component_epilog.php`.
4. **Зарегистрируйте ключи `$arResult` для эпилога** через `SetResultCacheKeys()`,
   если эпилогу нужны данные из модификатора (кэш хранит только эти ключи).
5. **Подключайте CSS/JS компонента через менеджер ассетов**, а не литеральными
   тегами в разметке (файлы `style.css`/`script.js` рядом с `template.php` ядро
   подключает само).
6. **Локализацию шаблона** держите в `lang/<LANG_ID>/template.php` (подключается
   автоматически), а для эпилога — отдельно в `lang/<LANG_ID>/component_epilog.php`
   с явной загрузкой.

### Роли файлов шаблона компонента

| Файл | Когда выполняется | Назначение |
|---|---|---|
| `result_modifier.php` | ПЕРЕД `template.php`, ВНУТРИ кэша (1 раз) | подготовить/перебрать `$arResult`/`$arParams`; результат кэшируется |
| `template.php` | рендер, ВНУТРИ кэша (пропускается при кэш-хите) | только разметка; не делать здесь «на каждый хит» действий |
| `component_epilog.php` | ПОСЛЕ шаблона, ВНЕ кэша, на КАЖДОМ хите | `SetTitle()`, мета, крошки, поздние ассеты, динамика |
| `.description.php` | визуальный редактор | имя/описание шаблона (`$arTemplateDescription` через `Loc`) |
| `.parameters.php` | визуальный редактор | СОБСТВЕННЫЕ параметры шаблона; в обычном рантайме НЕ грузится |
| `lang/<lang>/...` | при подключении соответствующего файла | строки `Loc::getMessage()` |

## Рабочий сниппет (путь в /local)

`/local/templates/main/components/bitrix/news.list/my_list/result_modifier.php`
— готовит данные ВНУТРИ кэша и регистрирует ключ для эпилога:
```php
<?php
if (!defined('B_PROLOG_INCLUDED') || B_PROLOG_INCLUDED !== true) die();

// $arResult/$arParams доступны; объект шаблона — $template, компонент — $this->__component.
foreach ($arResult['ITEMS'] as &$item) {
    // CODE экранирован движком, ~CODE — сырое исходное значение.
    $item['SAFE_NAME'] = htmlspecialcharsbx($item['~NAME']);
}
unset($item);

// Чтобы данные дошли до component_epilog.php через кэш-границу — зарегистрировать ключ.
$this->__component->SetResultCacheKeys(['ITEMS', 'NAV_TITLE']);
```

`.../my_list/template.php` — только разметка, экранированный вывод:
```php
<?php
if (!defined('B_PROLOG_INCLUDED') || B_PROLOG_INCLUDED !== true) die();

use Bitrix\Main\Page\Asset;

// CSS/JS компонента — через менеджер ассетов, не литеральным <link>/<script>.
Asset::getInstance()->addCss($this->GetFolder() . '/extra.css');
?>
<ul class="news-list">
<?php foreach ($arResult['ITEMS'] as $item): ?>
    <li><?= htmlspecialcharsbx($item['~NAME']) ?></li>
<?php endforeach; ?>
</ul>
<?php
// Передать вычисленное значение в эпилог через кэшируемый $templateData.
$templateData['LAST_TITLE'] = $arResult['NAV_TITLE'] ?? '';
```

`.../my_list/component_epilog.php` — выполняется на КАЖДОМ хите (в т.ч. при
кэш-хите), поэтому свойства страницы/мета ставим здесь:
```php
<?php
if (!defined('B_PROLOG_INCLUDED') || B_PROLOG_INCLUDED !== true) die();

use Bitrix\Main\Localization\Loc;

// В эпилоге язык НЕ грузится сам — подключить явно (файл lang/<lang>/component_epilog.php).
Loc::loadLanguageFile(__FILE__);

global $APPLICATION;
// $arResult здесь содержит только ключи из SetResultCacheKeys(); $templateData — из шаблона.
$title = $templateData['LAST_TITLE'] ?? Loc::getMessage('MY_LIST_DEFAULT_TITLE');
$APPLICATION->SetTitle(htmlspecialcharsbx($title));
$APPLICATION->AddChainItem($title);
```

`.../my_list/.description.php` — метаданные шаблона для редактора:
```php
<?php
if (!defined('B_PROLOG_INCLUDED') || B_PROLOG_INCLUDED !== true) die();

use Bitrix\Main\Localization\Loc;

$arTemplateDescription = [
    'NAME' => Loc::getMessage('MY_LIST_TPL_NAME'),
    'DESCRIPTION' => Loc::getMessage('MY_LIST_TPL_DESC'),
];
```

`.../my_list/.parameters.php` — собственные параметры шаблона (в визуальном
редакторе, отдельно от параметров компонента; в обычном рантайме не грузится):
```php
<?php
if (!defined('B_PROLOG_INCLUDED') || B_PROLOG_INCLUDED !== true) die();

use Bitrix\Main\Localization\Loc;

$arTemplateParameters = [
    'SHOW_DATE' => [
        'NAME' => Loc::getMessage('MY_LIST_PARAM_SHOW_DATE'),
        'TYPE' => 'CHECKBOX',
        'DEFAULT' => 'Y',
    ],
];
```

## Выбор API
Кэш-граница — главное правило выбора файла:

| Что нужно сделать | Файл | Почему |
|---|---|---|
| Подготовить/перебрать данные до рендера | `result_modifier.php` | внутри кэша, выполняется 1 раз, результат кэшируется |
| Нарисовать разметку | `template.php` | внутри кэша; при кэш-хите пропускается |
| `SetTitle()` / мета / крошки / поздние ассеты | `component_epilog.php` | вне кэша, на каждом хите — иначе «пропадёт» под кэшем |
| Протащить данные модификатор → эпилог | `SetResultCacheKeys([...])` | кэш хранит только зарегистрированные ключи |
| Протащить данные шаблон → эпилог | `$templateData[...]` | кэшируется и доступен в эпилоге |

Экранирование данных `$arResult`:
- `$item['NAME']` — значение, уже экранированное движком (готово к выводу);
- `$item['~NAME']` — сырое исходное значение; при выводе ОБЯЗАТЕЛЬНО оборачивать
  в `htmlspecialcharsbx()`.

Безопасность кэша:
- если компонент не должен закэшировать ошибочный/невалидный запрос (например
  несуществующий `ID`), вызовите `$this->AbortResultCache()` в `component.php` ДО
  `$this->IncludeComponentTemplate()` — иначе пустой/ошибочный результат осядет в
  кэше и заполнит диск. Для штатных компонентов это уже сделано; правило важно при
  собственной логике подготовки данных.
- `$this->StartResultCache()` / `$this->EndResultCache()` / `$this->AbortResultCache()`
  — методы класса компонента (`CBitrixComponent`), не шаблона; в шаблоне доступен
  `$this->__component` для `SetResultCacheKeys()`.

## Проверка
Режим «только файлы» (без запущенного Битрикс):
- Папка скопированного шаблона лежит в `/local/...`, оригинал в `/bitrix/` не
  тронут.
- `SetTitle()` / `AddChainItem()` / мета вызываются в `component_epilog.php`, а не
  в `template.php` или `result_modifier.php`.
- Сырые ключи `~CODE`/`~NAME` при выводе обёрнуты в `htmlspecialcharsbx()`.
- CSS/JS подключены через `Asset`/`$this->addExternalCss()`, а не литеральными
  тегами в разметке.
- Если эпилог использует `Loc::getMessage()` — есть `Loc::loadLanguageFile(__FILE__)`
  и файл `lang/<lang>/component_epilog.php`.

Режим «живой Битрикс»:
- Включить кэш компонента, открыть страницу дважды: заголовок/мета/крошки должны
  оставаться корректными на повторном (кэш-)хите.
- Проверить, что данные из `result_modifier.php` видны в эпилоге (ключи
  зарегистрированы через `SetResultCacheKeys`).
- Убедиться, что параметры из `.parameters.php` шаблона появились в настройках
  компонента в визуальном редакторе.

## ⚠️ Риски
- ⚠️ `SetTitle()` / крошки / мета в `template.php` или `result_modifier.php` под
  включённым кэшем не выполнятся при кэш-хите — заголовок «пропадёт». Их место —
  `component_epilog.php`.
- ⚠️ `$arResult` в эпилоге «пустой»: в него попадают только ключи из
  `SetResultCacheKeys()`. Нужные данные регистрируйте из `result_modifier.php`
  или передавайте через `$templateData`.
- ⚠️ Языковые фразы в эпилоге без `Loc::loadLanguageFile(__FILE__)` и файла
  `lang/<lang>/component_epilog.php` возвращаются пустыми.
- ⚠️ Вывод сырого `~CODE` без `htmlspecialcharsbx()` — XSS.
- ⚠️ Отсутствие `AbortResultCache()` при невалидном запросе в собственной логике
  компонента: ошибочный результат кэшируется и заполняет диск.
- ⚠️ Правка шаблона прямо в `/bitrix/components/bitrix/...` снимается при
  обновлении ядра; всегда копируйте в `/local`.

## Источники

- `$APPLICATION->IncludeComponent` и переопределение шаблона компонента (api_help вендора): https://dev.1c-bitrix.ru/api_help/main/reference/cmain/includecomponent.php

## Связано
- [api-map](../../api-map.md) — классы `CBitrixComponent`, `CBitrixComponentTemplate`, `Asset`.
- [00-overview](../../00-overview.md) — жизненный цикл страницы и шаблона.
- [04. Подключение CSS/JS](./04-assets.md) — ассеты внутри шаблона компонента.
- [06. Вывод заголовка/мета на странице](../06-output-on-page.md) — `SetTitle` / `SetPageProperty`.
- [11. Подводные камни + Монитор качества](./11-troubleshooting-quality.md) — диагностика «шаблон не применяется», кэш, целостность HTML.
- Создание собственного компонента (когда кастомизации одного шаблона мало) — `../16-custom-component.md`.
- [Каталог компонентов](../../components/00-index.md) — карточки ходовых компонентов (назначение, `arParams`, что копировать в `/local`).
