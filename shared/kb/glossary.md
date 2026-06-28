# Глоссарий: 1С-Битрикс: Управление сайтом (ядро 26.x)

> Краткие определения ключевых терминов платформы. Помечено: [D7] современный API / [legacy] рабочий API (для ряда задач — основной). Две поддерживаемые версии API сосуществуют; D7 — для нового кода, legacy — рабочий и обязательный для title/SEO/крошек и многих подсистем.
> Документация: dev.1c-bitrix.ru, docs.1c-bitrix.ru.

## Контент и данные

- **Инфоблок (iblock)** — основная универсальная EAV-модель структурированного контента сайта (новости, каталоги, услуги, FAQ). На инфоблоках строятся готовые публичные компоненты и кэш по тегам. Таблица `b_iblock`.
- **Тип инфоблока** — верхний уровень группировки инфоблоков (`b_iblock_type`, `CIBlockType` / `\Bitrix\Iblock\TypeTable`). Примеры: `news`, `catalog`, `lists`.
- **Элемент** — единица контента инфоблока (`b_iblock_element`, `CIBlockElement` / `\Bitrix\Iblock\ElementTable`); ID элемента = ID товара в каталоге.
- **Раздел** — иерархическая категория внутри инфоблока (`b_iblock_section`, nested set, `CIBlockSection` / `SectionTable`).
- **Свойство** — дополнительное поле элемента (`b_iblock_property`, `CIBlockProperty`). Типы: `S` строка, `N` число, `F` файл, `L` список, `E` привязка к элементу, `G` к разделу; user-type: `HTML`, `Date`, `directory` (справочник на HL-блоке) и др.
- **VERSION инфоблока (v1/v2)** — схема хранения значений свойств. v1 — общая таблица `b_iblock_element_property`; v2 (рекомендуется) — персональные `b_iblock_element_prop_s<ID>`/`_m<ID>`, быстрее и масштабируемее.
- **API_CODE** — латинский символьный код инфоблока, обязательный для D7-ORM. legacy-API (`CIBlock*`) работает и без него.
- **Highload-блок** — кастомная плоская ORM-таблица (модуль `highloadblock`), без разделов и EAV; поля добавляются как пользовательские поля. Для справочников и произвольных данных. `HighloadBlockTable`.
- **Торговое предложение / SKU** — вариант товара (цвет/размер). Родитель — товар `TYPE_SKU(3)`, предложения — `TYPE_OFFER(4)` в отдельном инфоблоке-предложений, связанном свойством-привязкой; связка в `CatalogIblockTable.SKU_PROPERTY_ID`.
- **Пользовательское поле (UF)** — произвольное поле к любой сущности с `ENTITY_ID` (раздел ИБ, HL-элемент, заказ, пользователь). Имя `UF_*`. Менеджер `$USER_FIELD_MANAGER` (`CUserTypeManager`), типы `\Bitrix\Main\UserField\Types\*`. Хранение: `b_uts_*` / `b_utm_*`.

## ORM и ядро

- **ORM / DataManager** [D7] — слой над SQL. Сущность = класс `XxxTable extends \Bitrix\Main\ORM\Data\DataManager` с `getTableName()` + `getMap()`. Три уровня: Array-API (`getList/add/...`), Query-builder (`Table::query()`), объектный API (`createObject()->save()`).
- **Result** [D7] — объект-результат CRUD: `add/update/delete` не бросают исключение, а возвращают `Result`; всегда проверять `isSuccess()` и `getErrorMessages()`.
- **Loader** [D7] — `\Bitrix\Main\Loader::includeModule('iblock')` — канонический способ подключить модуль (поднимает namespace и сервисы); legacy-аналог `CModule::IncludeModule()`.
- **ServiceLocator / DI** [D7] — PSR-11 контейнер синглтонов; регистрация в `.settings.php` секцией `services`. Глобальный конфиг переопределяет помодульный.
- **Configuration / `.settings.php`** [D7] — файловый конфиг окружения (`Configuration::getValue`). Не путать с `\Bitrix\Main\Config\Option` (`Option::get/set`) — это БД-настройки модулей из админки.
- **Событие (event)** — две шины над общим хранилищем `b_module_to_module`: [D7] `\Bitrix\Main\EventManager` + `Event` (обработчик получает объект `Event`); [legacy] `AddEventHandler` / `RegisterModuleDependences` (позиционные аргументы). Сигнатура обработчика обязана совпадать со способом регистрации.
- **Агент** [legacy] — отложенная/периодическая PHP-задача (`CAgent::AddAgent`, таблица `b_agent`). D7-обёртки нет. На проде запускать по cron (`tools/cron_events.php`, `agents_use_crontab`).
- **Кэш** — многослойный: `\Bitrix\Main\Data\Cache` (базовый), `ManagedCache` (привязан к таблице), `TaggedCache` (инвалидация по тегам, напр. `registerTag('iblock_id_5')`), HTML-кэш компонентов, composite.

## Компоненты и представление

- **Компонент 2.0** — инкапсуляция логики (выборка данных в `$arResult`) с отделением от представления (HTML в шаблоне). Подключение: `$APPLICATION->IncludeComponent($name, $template, $arParams)`.
- **Комплексный компонент** — компонент-роутер (`bitrix:news`, `bitrix:catalog`, флаг `"COMPLEX"=>"Y"`): сам не выбирает данные, по URL определяет страницу (sub-component) и передаёт переменные (SEF через `CComponentEngine`).
- **Шаблон компонента** — папка `templates/<name>/` с обязательным `template.php` (вывод HTML); `style.css`/`script.js` автоподключаются. Переопределяют в шаблоне сайта, не в `/bitrix`.
- **result_modifier.php** — выполняется внутри кэша, до `template.php`, один раз и кэшируется. Сюда — вычисляемые поля `$arResult`.
- **component_epilog.php** — выполняется вне кэша, на каждый хит. Сюда — `SetTitle`, `AddChainItem`, счётчики. ⚠️ Установку title/крошек в кэш (через result_modifier) класть нельзя — «застынут».
- **AJAX class-actions** [D7] — современный AJAX: `class.php` реализует `Controllerable`, методы с суффиксом `Action`; вызов `BX.ajax.runComponentAction(...)`. legacy-аналог — `CComponentAjax` (`AJAX_MODE=Y`).
- **Шаблон сайта** — папка `templates/<id>/` с парой `header.php`+`footer.php`, оборачивающей контент. `styles.css`/`template_styles.css` автоподключаются ядром. Приоритет `/local/templates` над `/bitrix/templates`.
- **Включаемая область** — переиспользуемый фрагмент (логотип, телефон, копирайт). Вывод: `bitrix:main.include` (`AREA_FILE_SHOW=page|sect|file`) [рекомендуется] или legacy `$APPLICATION->IncludeFile(...)`. Правится из публички «карандашом».
- **Меню** [legacy-ядро `CMenu`] — источник: файлы `.<type>.menu.php` (статика, позиционный массив `$aMenuLinks`) и `.<type>.menu_ext.php` (динамика, при `USE_EXT=Y`). Вывод — `bitrix:menu` / `bitrix:menu.sections`.
- **Asset / Extension** [D7] — менеджер ассетов `\Bitrix\Main\Page\Asset` (`addCss/addJs`, таргеты `TEMPLATE`/`PAGE`) и Extension API `\Bitrix\Main\UI\Extension::load(['ui.buttons', ...])` (имя ≥ 2 частей через точку). legacy-регистратор — `CJSCore`.
- **Design Tokens** [D7] — CSS-переменные дизайн-системы модуля `ui`: `ui.design-tokens` и новые `ui.design-tokens.air` (Б24-стиль, префикс `--ui-color-*`). Смешивать поколения без адаптации нельзя.

## Структура, URL, страница

- **document root / /bitrix / /local** — три зоны на диске. `/bitrix` — ядро (затирается обновлениями); `/local` — кастом (не затирается, приоритетнее `/bitrix`). Весь кастом класть в `/local`.
- **$APPLICATION (CMain)** [legacy] — фасад HTML-страницы; единственный путь для `SetTitle`, `SetPageProperty` (keywords/description/canonical/robots), `AddChainItem`, `IncludeComponent`, `ShowHead`. D7-аналога нет.
- **ЧПУ / SEF** — человекопонятные URL. Включается у компонента флагом `SEF_MODE=Y` + `SEF_FOLDER`; генерируется автоматически, не пишется руками.
- **urlrewrite.php** [legacy] — корневой массив `$arUrlRewrite` (regexp `CONDITION` → `PATH`+`RULE`); на нём держатся ЧПУ всех штатных компонентов. Управление — `\Bitrix\Main\UrlRewriter` (`add/reindexAll/reindexFile`). ⚠️ Ручная правка файла затрётся при реиндексации.
- **Routing** [D7] — `\Bitrix\Main\Routing` (`routing_index.php`, `/local/routes/*.php`, `$routes->get('/path/{id}', $controller)`) — для своих API/контроллеров. Приоритет: физ. файлы → `urlrewrite.php` → D7-роутинг.
- **Композит (composite)** — кэш HTML всей страницы целиком с динамическими «дырами» (`StaticArea::startDynamicArea()`). Может отдать статический HTML, минуя PHP. Один компонент с `frameMode=false` выключает composite для всей страницы.
- **Монитор качества** — встроенный чек-лист требований к сайту (производительность, безопасность, дизайн, поддержка) перед сдачей проекта; влияет на оценку и сертификацию.

## Коммерция и сервисы

- **catalog** — товарный каталог как надстройка над инфоблоком: товар = элемент ИБ + строка `b_catalog_product` + цены `b_catalog_price`. Запись через Model-слой `\Bitrix\Catalog\Model\Product`/`Price` [D7]. Связь ИБ с каталогом — `b_catalog_iblock`.
- **sale / заказ** [D7] — объектная модель `\Bitrix\Sale\Order`/`Basket`/`Payment`/`Shipment`. ⚠️ Заказ создавать только через `Order::create()`/`Registry`, не `new`; перед `save()` обязателен `doFinalAction(true)` (пересчёт скидок/налогов).
- **Business Value** — механизм сопоставления свойств заказа значениям, нужным платёжной системе/доставке (через какие поля заказа ПС получает сумму, email, ИНН и т. п.). Конфигурируется для handlers ПС и доставки.
- **landing (Сайты24)** [D7] — no-code конструктор: Site → Page → Block; контент хранится как готовый HTML в БД (`b_landing_block.CONTENT`), рендер через `bitrix:landing.pub`. Правка контента — `updateNodes()` по селекторам манифеста, не правкой `block.php`.
- **Веб-форма (form)** [legacy] — классический механизм заявок/обратной связи (`CForm`, `CFormResult`, данные в `b_form*`). Встраивание — `bitrix:form`. Это НЕ CRM-формы Б24 и не landing-формы.
- **search** [legacy] — модуль индексации и поиска (`CSearch::Index`, документ = `(MODULE_ID, ITEM_ID)` в `b_search_content`). D7 API нет.
- **CommerceML** [legacy] — двусторонний обмен 1С ↔ сайт (XML, точки входа `1c_import.php`/`1c_exchange.php`; `CIBlockCMLImport`/`Export`, `CSaleExport`). D7-обёртки нет — legacy и есть рекомендованный путь.
- **CLI / Symfony Console** — консоль `php bitrix/modules/main/cli/bitrix.php` (команды `make:*`, `orm:annotate`, `update:*`). Требует Composer (см. docs.1c-bitrix.ru/pages/get-started/composer.html).
