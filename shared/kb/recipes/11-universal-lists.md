# 11. Универсальные списки (модуль `lists`)

## Цель

Создать управляемый контент-тип «список + карточка» средствами модуля `lists` —
тонкой надстройки над `iblock`. Контент хранится в обычном инфоблоке
(`b_iblock_element`), а «поля списка» — это системные поля элемента ИБ и/или
свойства ИБ. Модуль даёт контент-менеджеру дружелюбный интерфейс редактирования
без админки инфоблоков и готовую привязку к бизнес-процессам, а программисту —
не плодить отдельный модуль. Типовые сценарии: FAQ, вакансии, реестры,
документы, отзывы, заявки с согласованием.

## Когда применять

Берите `lists`, если:

- контентом управляет обычный пользователь/контент-менеджер через интерфейс
  «список + карточка» (компоненты `lists.list`, `lists.element.edit`), без
  захода в админку инфоблоков;
- нужны бизнес-процессы согласования «из коробки» (заявки, заказы услуг,
  согласование договоров) — тип ИБ `bitrix_processes` либо `lists` с `BIZPROC=Y`
  и автозапуском БП на Create/Edit;
- справочник/реестр нужно переносить между сайтами одним пакетом
  (`Importer::export` / `import`);
- контент живёт в интранете/группах соц.сети (тип ИБ `lists_socnet`).

Берите чистый `iblock` (+ `catalog`), а не `lists`, если:

- это каталог товаров магазина (цены, торговые предложения SKU, остатки) —
  `lists` намеренно исключает тип свойства `SKU` и `directory` из доступных,
  то есть для коммерческой витрины не предназначен;
- нужна публичная витрина с умным фильтром, сортировкой, SEO-ЧПУ — это
  компоненты `bitrix:catalog` / `bitrix:news`, не `lists.*`;
- ожидается высокая нагрузка/кэш на публичной части — публичные компоненты
  iblock рассчитаны на витрину.

> Запомните: компоненты `lists.*` ориентированы на интранет-интерфейс
> редактирования. Маркетинговую витрину поверх того же ИБ собирают штатными
> `bitrix:news.list` / `bitrix:news.detail` (данные лежат в обычном инфоблоке).

## Шаги

1. Подключить модуль: `\Bitrix\Main\Loader::includeModule('lists')` (он сам
   требует `iblock`). Типы ИБ `lists` / `bitrix_processes` создаются при
   установке модуля; отдельно создавать тип обычно не нужно.
2. Создать список (инфоблок) через `\Bitrix\Lists\Entity\Iblock(Param)->add()`.
   Внутри жёстко задаются `WORKFLOW='N'`, `RIGHTS_MODE='E'` (расширенные права
   на элемент), `SITE_ID = CSite::getDefSite()`.
3. Добавить поля: системные (NAME, SORT, PREVIEW_TEXT…) уже есть; собственные
   поля заводятся как свойства ИБ через `\Bitrix\Lists\Entity\Field(Param)->add()`.
   Тип поля после создания изменить нельзя — продумайте структуру заранее.
4. (Опц.) Настроить URL детальной страницы элемента через `b_lists_url`
   (`CList::getUrlByIblockId`, `CList::OnGetDocumentAdminPage`).
5. (Опц.) Привязать бизнес-процесс: тип документа bizproc — строка
   `iblock_<IBLOCK_ID>`. Поля доступны в дизайнере БП как `PROPERTY_<CODE>`
   (см. `BizprocDocumentLists::getDocumentFields`).
6. Наполнять элементы: `\Bitrix\Lists\Entity\Element->add()` либо REST
   `lists.element.add` (например из веб-формы). При включённом БП с автозапуском
   на Create процесс стартует сам.
7. Выводить: на интранет-странице — компонент `bitrix:lists.list`; на публичной
   витрине — `bitrix:news.list` / `CIBlockElement::GetList(...)` по `IBLOCK_ID`.

## Рабочий сниппет

Файл: `/local/php_interface/lists_setup.php` (разовый запуск, например из
командного скрипта или `init.php` с защитой от повторного выполнения).

```php
<?php
// /local/php_interface/lists_setup.php — создание списка «Вакансии»
use Bitrix\Main\Loader;
use Bitrix\Lists\Service\Param;
use Bitrix\Lists\Entity\Iblock;
use Bitrix\Lists\Entity\Field;
use Bitrix\Lists\Entity\Element;

Loader::includeModule('lists');

// 0) ⚠️ Тип ИБ `lists` НЕ создаётся при установке модуля — он появляется при первом списке.
//    Создаём тип один раз, иначе add() инфоблока упадёт на несуществующем типе.
//    (проверено на живой 26.x: по умолчанию есть только rest_entity).
if (!CIBlockType::GetByID('lists')->Fetch()) {
    (new CIBlockType)->Add([
        'ID' => 'lists', 'SECTIONS' => 'N',
        'LANG' => [
            'ru' => ['NAME' => 'Списки', 'ELEMENT_NAME' => 'Элементы', 'SECTION_NAME' => 'Разделы'],
            'en' => ['NAME' => 'Lists', 'ELEMENT_NAME' => 'Elements', 'SECTION_NAME' => 'Sections'],
        ],
    ]);
}

// 1) Список (инфоблок типа lists)
$iblockParam = new Param([
    'IBLOCK_TYPE_ID' => 'lists',
    'IBLOCK_CODE'    => 'vacancies',
    'FIELDS'         => ['NAME' => 'Вакансии', 'SORT' => 100],
    // 'SOCNET_GROUP_ID' => ... — для списка внутри группы соц.сети
]);
$iblockEntity = new Iblock($iblockParam);
$iblockId = $iblockEntity->isExist() ? false : $iblockEntity->add(); // int|false

// 2) Поле-свойство «Город» (список значений, тип L)
$cityParam = new Param([
    'IBLOCK_TYPE_ID' => 'lists',
    'IBLOCK_CODE'    => 'vacancies',
    'IBLOCK_ID'      => $iblockId,
    'FIELDS' => [
        'NAME'             => 'Город',
        'CODE'             => 'CITY',
        'TYPE'             => 'L',          // S | N | L | F | G | E + UF-типы
        'MULTIPLE'         => 'N',
        'IS_REQUIRED'      => 'Y',
        'SORT'             => 100,
        // enum-значения: построчно (модуль развернёт в LIST сам)
        'LIST_TEXT_VALUES' => "Москва\nСПб\nКазань",
    ],
]);
(new Field($cityParam))->add(); // -> CList->addField()

// 3) Элемент списка
$elementParam = new Param([
    'IBLOCK_TYPE_ID' => 'lists',
    'IBLOCK_ID'      => $iblockId,
    'FIELDS' => [
        'NAME'           => 'PHP-разработчик',
        'PREVIEW_TEXT'   => 'Описание вакансии…',
        // свойства — через PROPERTY_<CODE>; enum L передаётся ID значения
        'PROPERTY_VALUES' => ['CITY' => /* ID enum-значения */ 0],
    ],
]);
// add() сам стартует БП, если у типа ИБ включён bizproc и есть автозапуск на Create
(new Element($elementParam))->add();
```

Реальные сигнатуры (из research):
`Entity\Iblock`: `__construct(Param)`, `isExist()`, `add()`, `get(array $navData=[])`,
`update()`, `delete()`.
`Entity\Field`: `add()` (→ `CList->addField`), `get()`, `update()` (TYPE менять
нельзя), `delete()`, `getAvailableTypes()`.
`Entity\Element`: `add()`, `get()`, `update()`, `delete()`, `getFileUrl()`,
`getAvailableFields()`.

## Выбор API

В модуле две поддерживаемые версии API; обе рабочие, выбор по задаче.

- **D7 (`\Bitrix\Lists\...`) — рекомендуемый путь для нового кода.** Паттерн
  `Service\Param` (нормализация входных параметров) → Entity-класс
  (`Iblock` / `Field` / `Element` / `Section`). Все entity реализуют
  `Controllable, Errorable` — ошибки читаются через интерфейс ошибок, а не
  через `$APPLICATION->GetException()`. Ручной запуск БП по элементу —
  `\Bitrix\Lists\Workflow\Starter->run()`.
- **Legacy (`CLists` / `CList` / `CListField*`) — основной рабочий слой ядра.**
  Entity-классы внутри вызывают именно его. Часть операций доступна только
  здесь: enum-значения свойства (`CList::UpdatePropertyList`), URL детальной
  (`CList::getUrlByIblockId`, `CList::OnGetDocumentAdminPage`), листинг
  доступных списков (`CLists::GetIBlocks`), копирование (`CLists::copyIblock`),
  проверка прав (`CLists::GetIBlockPermission`).
- **REST (`scope lists`).** Для интеграций/веб-форм: `lists.add/get/update/delete`,
  `lists.field.*`, `lists.element.add/get/update/delete`,
  `lists.element.get.file.url`, `lists.section.*`. Все методы идут через те же
  `Entity` + `Param`.
- **Чтение контента.** Отдельного `*Table`-ORM поверх контента списков нет:
  элементы читаются как обычный ИБ — `CIBlockElement::GetList(...)` по `IBLOCK_ID`.
- **Лимиты.** Ограничения числа списков/процессов относятся только к
  Битрикс24-облаку; в коробочном «Бизнес 26.x» `CLists::isFeatureEnabled`
  всегда `true`, лимитов нет.

## Проверка

Проверка рендера и структуры — по общему паттерну: [verification](../operations.md) (CLI для структуры, браузер/preview для рендера; на dev-стенде).

**Режим «только файлы» (без запущенного Битрикс):**

- PHP-синтаксис скрипта: `php -l /local/php_interface/lists_setup.php`.
- Грепом убедиться, что используются реальные namespace и классы:
  `Bitrix\Lists\Service\Param`, `Bitrix\Lists\Entity\{Iblock,Field,Element}`.
- Проверить, что у поля типа `L` задан `LIST_TEXT_VALUES` либо `LIST`, а у
  каждого поля есть `CODE` (для обращения как `PROPERTY_<CODE>`).
- Проверить, что для свойств запись идёт через `PROPERTY_VALUES`, а системные
  поля (NAME, PREVIEW_TEXT…) — прямыми ключами.

**Режим «живой Битрикс»:**

- Выполнить скрипт; `Iblock->add()` должен вернуть `int` (ID списка), не `false`.
  При `false` читать ошибки entity (Errorable), не игнорировать.
- В админке: «Контент → Списки» (или раздел списков) — список «Вакансии» виден,
  поле «Город» с тремя значениями присутствует.
- Создать тестовый элемент через `Entity\Element->add()` и проверить выборкой
  `CIBlockElement::GetList([], ['IBLOCK_ID'=>$iblockId], false, false, ['ID','NAME','PROPERTY_CITY'])`.
- (Если настроен БП) добавить элемент и убедиться, что процесс стартовал
  (журнал БП / `data['workflowIds']` от `Workflow\Starter->run()`).
- Публичный вывод: вывести тот же ИБ компонентом `bitrix:news.list` и сверить
  данные с админкой.

## ⚠️ Риски

- ⚠️ **Тип поля нельзя изменить после создания.** `Entity\Field::update()` через
  `canChangeField()` запрещает смену `TYPE`. Смена типа = удалить и пересоздать
  поле, что означает **потерю данных** в этом поле у всех элементов.
  Продумывайте структуру до наполнения.
- ⚠️ **`RIGHTS_MODE='E'` (права на уровне элемента) задаётся при создании списка.**
  Это влияет на производительность выборок при больших объёмах и на логику прав.
  Учитывайте при выводе на публичную часть.
- ⚠️ **`lists` не для каталога магазина.** Типы свойств `SKU`, `directory`,
  `EAutocomplete`, `SectionAuto` намеренно исключены. Не стройте на `lists`
  коммерческую витрину — для товаров нужен `iblock` + `catalog`.
- **Поля — два разных мира.** Системные поля элемента ИБ (`CListElementField`,
  ключи NAME/SORT/PREVIEW_TEXT…) пишутся прямыми ключами в `CIBlockElement::Add`;
  свойства (`CListPropertyField`, `PROPERTY_<CODE>`/`PROPERTY_<ID>`) — через
  `PROPERTY_VALUES`. Не путайте при программной записи/чтении.
- **Bizproc обязателен для процессов.** Класс bizproc-документа списка завершает
  работу, если модуль `bizproc` не подключён. Привязка к БП — через тип
  документа `iblock_<ID>`, а не по типу ИБ.
- **Кэш-теги при ручных правках полей.** Модуль сам чистит тег
  `lists_list_<iblockId>` после изменения полей. При собственных манипуляциях
  полями в обход entity повторяйте
  `$CACHE_MANAGER->clearByTag("lists_list_<id>")`.

## Связано

- `../00-overview.md` — модули, `/local`, D7 vs legacy.
- `02-create-iblock.md` / каталоговые рецепты — когда нужен чистый `iblock` +
  `catalog` вместо `lists`.
- Рецепты по `bizproc` — дизайнер процессов, document type `iblock_<ID>`,
  автозапуск и `Workflow\Starter`.
- Рецепты по компонентам `bitrix:news.*` — публичный вывод контента списка на
  витрину.
- Источник: модуль `lists` — dev.1c-bitrix.ru.
