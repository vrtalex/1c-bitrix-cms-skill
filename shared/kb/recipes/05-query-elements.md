# Рецепт 05 — Выборка элементов инфоблока (query-elements)

> Основан на изучении ядра «1С-Битрикс: Управление сайтом» (модуль iblock, ядро 26.x) и официальной документации вендора.

## Цель

Получить список элементов инфоблока (новости, товары, услуги и т.п.) с нужными полями
и значениями свойств — для вывода на странице, в API-обработчике или в скрипте миграции/обработки.

## Когда применять

- Нужна выборка элементов, которую не закрывает готовый компонент (`bitrix:news.list`, `bitrix:catalog.section`).
- Пишется бэкенд-логика: REST-эндпоинт, экспорт, агрегат, импорт, кастомный AJAX.
- Нужно отфильтровать по свойствам (`PROPERTY_*`), разделам, активности и т.д.

Если задача — просто показать список на сайте, начните с готового компонента (см. рецепт 06);
прямой `GetList` оправдан, когда нужен контроль над выборкой или вывод вне публичной страницы.

## Шаги

1. Подключить модуль: `\Bitrix\Main\Loader::includeModule('iblock')`.
2. Собрать четыре массива: `$order`, `$filter`, `$select`, `$nav`.
   - В `$filter` всегда указывать `IBLOCK_ID` (или `IBLOCK_CODE`) и обычно `ACTIVE => 'Y'`.
   - В `$select` перечислить только нужные поля; для свойств добавить `PROPERTY_<CODE>`.
3. Выполнить `CIBlockElement::GetList($order, $filter, false, $nav, $select)` → `CIBlockResult`.
4. Прочитать результат:
   - простой случай — `while ($row = $res->Fetch())` (сырые данные);
   - с подстановкой URL/HTML — `SetUrlTemplates(...)` + `while ($row = $res->GetNext())`;
   - двухпроходное чтение через объект элемента — `while ($ob = $res->GetNextElement())`,
     затем `$ob->GetFields()` и (при необходимости) `$ob->GetProperties()`.
5. Свойства для уже выбранного массива элементов эффективнее догрузить пакетно через
   `CIBlockElement::GetPropertyValuesArray()`, а не вызывать `GetProperties()` в цикле.

## Рабочий сниппет

Файл: `/local/php_interface/lib/Content/NewsRepository.php`
(или любой автозагружаемый класс проекта; для разовой выборки — инлайн в `/local/...`).

```php
<?php
namespace Local\Content;

use Bitrix\Main\Loader;

final class NewsRepository
{
    /**
     * Список активных новостей раздела со свойством AUTHOR.
     *
     * @return array<int, array<string, mixed>>
     */
    public static function getList(int $iblockId, int $limit = 20, ?int $sectionId = null): array
    {
        Loader::includeModule('iblock');

        $order = ['ACTIVE_FROM' => 'DESC', 'SORT' => 'ASC', 'ID' => 'DESC'];

        $filter = [
            'IBLOCK_ID'         => $iblockId,
            'ACTIVE'            => 'Y',
            'ACTIVE_DATE'       => 'Y',   // учитывать даты начала/окончания активности
            'CHECK_PERMISSIONS' => 'Y',   // уважать права доступа текущего пользователя
        ];
        if ($sectionId !== null) {
            $filter['SECTION_ID']          = $sectionId;
            $filter['INCLUDE_SUBSECTIONS'] = 'Y';
        }

        // Перечисляем только нужное. PROPERTY_AUTHOR вытащит свойство сразу в выборке.
        $select = [
            'ID', 'NAME', 'CODE', 'PREVIEW_TEXT', 'PREVIEW_PICTURE',
            'ACTIVE_FROM', 'DETAIL_PAGE_URL',
            'PROPERTY_AUTHOR',
        ];

        $nav = ['nTopCount' => $limit];   // или ['iNumPage' => $page, 'nPageSize' => $limit]

        $res = \CIBlockElement::GetList($order, $filter, false, $nav, $select);
        $res->SetUrlTemplates('/news/#ELEMENT_ID#/');   // заполнит DETAIL_PAGE_URL для GetNext()

        $items = [];
        while ($row = $res->GetNext()) {   // GetNext(): HTML-преобразование + подстановка URL
            $items[] = $row;
        }

        return $items;
    }

    /**
     * Двухпроходный вариант через объект элемента — когда нужны ВСЕ свойства разом.
     * ⚠️ GetProperties() — отдельный запрос на КАЖДЫЙ элемент (N+1). Для больших списков
     *    предпочтительнее GetPropertyValuesArray() (см. ниже) или PROPERTY_<CODE> в $select.
     */
    public static function getWithAllProps(int $iblockId, int $limit = 20): array
    {
        Loader::includeModule('iblock');

        $res = \CIBlockElement::GetList(
            ['SORT' => 'ASC'],
            ['IBLOCK_ID' => $iblockId, 'ACTIVE' => 'Y'],
            false,
            ['nTopCount' => $limit],
            ['ID', 'NAME', 'IBLOCK_ID']
        );

        $items = [];
        while ($ob = $res->GetNextElement()) {
            $fields = $ob->GetFields();
            $fields['PROPERTIES'] = $ob->GetProperties();   // см. предупреждение выше
            $items[] = $fields;
        }

        return $items;
    }

    /**
     * Пакетная догрузка свойств для уже выбранного списка — без N+1.
     * $items индексируется по ID элемента (как в news.list/component.php).
     */
    public static function attachProperties(array &$items, int $iblockId): void
    {
        Loader::includeModule('iblock');
        \CIBlockElement::GetPropertyValuesArray(
            $items,                       // by-ref: добавит ['PROPERTIES'] в каждый элемент
            $iblockId,
            ['ID' => array_keys($items)]  // фильтр по уже полученным ID
        );
    }
}
```

D7-опция (если у инфоблока задан `API_CODE`, например `news`) — типобезопасная ORM-коллекция:

```php
<?php
use Bitrix\Main\Loader;
use Bitrix\Iblock\IblockTable;

Loader::includeModule('iblock');

// Скомпилировать ORM-сущность элементов инфоблока с API_CODE = 'news'
// compileEntity() возвращает объект Entity; имя data-класса берём через getDataClass()
$dataClass = IblockTable::compileEntity('news')->getDataClass();   // -> 'Bitrix\Iblock\Elements\ElementNewsTable'

$collection = $dataClass::getList([
    'select' => ['ID', 'NAME', 'AUTHOR', 'SECTIONS'],   // свойства = обычные ORM-поля
    'filter' => ['=ACTIVE' => 'Y'],
    'order'  => ['ID' => 'DESC'],
    'limit'  => 20,
])->fetchCollection();

foreach ($collection as $element) {
    $name = $element->getName();
    // доступ к свойству и привязанным разделам — через объектную модель
}
```

## Выбор API (для ЭТОЙ задачи)

Битрикс предоставляет две поддерживаемые версии API. Для выборки элементов:

- `CIBlockElement::GetList(...)` — основной выбор для legacy-экосистемы. На нём написаны все
  публичные компоненты (`news.list`, `catalog.section`); работает и без `API_CODE`; поддерживает
  фильтры по свойствам `PROPERTY_*`, `SetUrlTemplates`, штатную пагинацию (`GetPageNavStringEx`).
  Рекомендуется, когда: правите/расширяете шаблон компонента, нужен фильтр по свойствам «из коробки»,
  у инфоблока не заполнен `API_CODE`, или важна совместимость с остальным кодом проекта.
- `Element<ApiCode>Table::getList()->fetchCollection()` (D7/ORM) — для нового бэкенд-кода: REST,
  сервисы, типизированный доступ. ⚠️ Требует заполненного `API_CODE` у инфоблока, иначе
  `getEntityDataClass()` выдаёт предупреждение `API_CODE required for DataClass of iblock #...`.
  Рекомендуется, когда: пишете изолированный сервис/контроллер с нуля и нужна объектная модель.

Практическое правило: расширяете вывод сайта или нужен фильтр по свойствам — `CIBlockElement::GetList`;
строите отдельный сервис на чистом D7 и `API_CODE` есть — ORM-коллекция.

## Проверка

Проверка рендера и структуры — по общему паттерну: [verification](../operations.md) (CLI для структуры, браузер/preview для рендера; на dev-стенде).

Режим «только файлы» (без запущенного Битрикса):
- PHP-синтаксис: `php -l /local/php_interface/lib/Content/NewsRepository.php`.
- Глазами: в `$filter` присутствует `IBLOCK_ID`; в `$select` нет `*` и перечислены реальные поля;
  свойства запрашиваются как `PROPERTY_<CODE>`; внутри `while` нет `GetProperties()` без необходимости.
- Сигнатуры: порядок аргументов `GetList($order, $filter, $groupBy=false, $nav, $select)`,
  парный вызов `GetNextElement()` → `GetFields()`/`GetProperties()`.

Режим «живой Битрикс»:
- Из CLI ядра: `php -r "define('NO_KEEP_STATISTIC',true); ... require '.../bitrix/modules/main/include/prolog_before.php';"`
  и вызвать `\Local\Content\NewsRepository::getList($iblockId)` — проверить, что массив непустой
  и в элементах есть `PROPERTY_AUTHOR_VALUE` / `DETAIL_PAGE_URL`.
- Сверить число элементов с админкой: «Контент → <инфоблок> → Элементы» (с тем же фильтром по активности).
- Проверить количество SQL-запросов в режиме отладки — рост числа запросов пропорционально количеству
  элементов сигнализирует о N+1 (выносите свойства в `$select` или в `GetPropertyValuesArray`).

## ⚠️ Риски

- ⚠️ **N+1 на свойствах.** `GetProperties()`/`GetProperty()` в цикле — отдельный запрос на каждый
  элемент. Для списков указывайте `PROPERTY_<CODE>` в `$select` или используйте пакетный
  `CIBlockElement::GetPropertyValuesArray()`.
- ⚠️ **Пустой `$select` тянет всё.** Без явного `$select` выбираются все поля (и тяжёлые
  `DETAIL_TEXT`). Всегда перечисляйте только нужные поля.
- **Права доступа.** `CHECK_PERMISSIONS => 'Y'` меняет состав выборки под текущего пользователя;
  в фоновых/cron-скриптах под нужды задачи может потребоваться `'N'` (осознанно).
- **`Fetch()` vs `GetNext()`.** `Fetch()` — сырые данные; `GetNext()` — с HTML-конвертацией и
  подстановкой URL (нужен предварительный `SetUrlTemplates`). Выбирайте по назначению вывода.
- **Кэшируйте выборки.** В компонентах — через `startResultCache()/endResultCache()`; в сервисах —
  через `\Bitrix\Main\Data\Cache` или управляемый кэш с тегами инфоблока, чтобы не бить БД на каждый запрос.

## Связано

- ../api-map.md — модель инфоблоков, сигнатуры `GetList`, версии хранилища свойств (V1/V2), `API_CODE`.
- recipes/06-output-on-page.md — как `news.list` строит выборку (два прохода, `GetPropertyValuesArray`, кэш).
- Рецепт 09 (вывод через готовые компоненты) — когда не нужен прямой `GetList`.
