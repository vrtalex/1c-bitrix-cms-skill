# api-map — мастер-таблица «задача → класс/компонент → способ» (БУС, ядро 26.x)

> **Version-validity:** карта валидна для ядра 24.x–26.x на платформенном baseline (PHP ≥ 8.2.0, MySQL ≥ 8.0/utf8mb4, только UTF-8) и с учётом снятых на 25.x+ legacy-API (`CAll*`, `core_fx`/`core_ls`, прямой `LAST_ERROR`, `iblock.field-selector`). Полный baseline и decay-матрица — в conventions.md, §5.0–5.1.
> Две поддерживаемые версии API: **D7** (`\Bitrix\…`, для нового кода) и **legacy** (`C*`-классы / процедурные функции — рабочий слой, для ряда задач основной).
> Колонка «когда D7 / когда legacy» — выбор **по контексту задачи**, не «D7 по умолчанию». Для части подсистем (form, обмен 1С, агенты, title/SEO) legacy и есть рекомендованный путь — D7-обёртки нет.
> Слои переплетены: «чистого D7» в рантайме нет. Новый код пишем на D7 и кладём в `/local`; для title/meta/крошек/подключения компонентов на публичной странице используем `$APPLICATION` (legacy, обязательно).

---

## 1. Модули, конфиг, окружение

| Задача | D7 | legacy | Когда что |
|---|---|---|---|
| Подключить модуль | `\Bitrix\Main\Loader::includeModule('iblock')`; `requireModule()` бросает `LoaderException` | `CModule::IncludeModule('iblock')` | **D7** — для всего нового кода (канонический способ; поднимает namespace и сервисы модуля). legacy — правка старого кода |
| Сервисы / DI | `ServiceLocator::getInstance()->get($code)` (PSR-11); регистрация в `.settings.php` секцией `services` | — | **D7** всегда. Переопределение сервиса проекта — глобальный `/local/.settings.php` (побеждает помодульный) |
| Файловые настройки окружения | `\Bitrix\Main\Config\Configuration::getValue($name)` / `getInstance($moduleId)` (читает `.settings.php`, `/local` приоритетнее) | — | **D7** для `.settings.php` (SMTP, кэш-движок, services) |
| Настройки модуля в БД (из админки) | `\Bitrix\Main\Config\Option::get($mod,$name,$def,$siteId)` / `Option::set(...)` | `COption::GetOptionString/SetOptionString` | **D7** `Option` для нового кода; legacy `COption` — в старом. Это БД-настройки, не файловые |

⚠️ Кастом кладём только в `/local` — `/bitrix` затирается обновлениями ядра.

> **Класс присутствует в дистрибутиве ≠ модуль установлен.** Наличие файла с классом в `/bitrix/modules/` не гарантирует, что модуль активирован в конкретной установке. Перед использованием любого модульного API вызывать `\Bitrix\Main\Loader::includeModule('<id>')` и явно обрабатывать `false` (модуль недоступен): выбрасывать исключение, возвращать ошибку или использовать альтернативный путь. Примеры модулей, которые могут отсутствовать: `highloadblock`, `seo`, `security`, `search`, `mail`, `iblock` на отдельных редакциях. Не вызывать API модуля до успешного `includeModule`.

## 2. Сайт и шаблон сайта

| Задача | D7 | legacy | Когда что |
|---|---|---|---|
| Создать сайт-сущность | `\Bitrix\Main\SiteTable::add([...])` + `\Bitrix\Main\Localization\CultureTable::add()` | `(new CSite)->Add(['LID'=>'s1','ACTIVE'=>'Y','DEF'=>'Y','DIR'=>'/',...])` | **legacy** надёжнее для создания (совпадает с установщиком); D7 `SiteTable` — для чтения/выборок |
| Сайт vs язык vs культура | `SiteTable`(`b_lang`) / `b_language` / `b_culture` | — | `SITE_ID ≠ LANGUAGE_ID`. Мультиязычность = несколько сайтов + привязка ИБ к сайту (`b_iblock_site`); контент сам не переводится |
| Шаблон сайта (файлы) | папка `/local/templates/<id>/`: `header.php`+`footer.php`+`description.php` | — | Всегда файлы в `/local`. `.default` — не выбирается, только fallback |
| Привязать шаблон к сайту | условия в `.settings`/`Option` | `CSite::Update(['TEMPLATE'=>[...]])` | legacy `CSite::Update` для привязки в БД |
| `<head>` / CSS / JS шаблона | `Asset::getInstance()->addJs/addCss`; `\Bitrix\Main\UI\Extension::load(['ui.buttons',…])`; `template_styles.css`/`styles.css` подключаются автоматически | `$APPLICATION->ShowHead()`, `SetTemplateCSS()`, `AddHeadString/AddHeadScript` | **D7** Asset/Extension для своих ассетов. `$APPLICATION->ShowHead()` обязателен в `<head>`, `ShowTitle()` в `<title>`, `ShowPanel()` после `<body>` — здесь альтернативы нет |
| Подключить UI-расширение | `\Bitrix\Main\UI\Extension::load(['ui.bootstrap4'])` (имя ≥ 2 частей через `.`) | `CJSCore::Init(['fx'])` | **D7** Extension для `ui.*`; `CJSCore::Init` — для legacy-расширений с однословным именем. (на 25.x+: `core_fx`/`core_ls` удалены в main 25.900.0 — анимация и localStorage перенесены в `core`; вместо `iblock.field-selector` использовать `ui.field-selector`) |
| Title / meta / robots / canonical | **аналога нет** | `$APPLICATION->SetTitle($t)`; `SetPageProperty('keywords'\|'description'\|'robots'\|'canonical', …)` | **только legacy** — единственный путь для title/SEO публичной страницы |
| Хлебные крошки | **аналога нет** | `$APPLICATION->AddChainItem($title,$url)` + компонент `bitrix:breadcrumb` | **только legacy** |
| Включаемые области (логотип, телефон, копирайт) | компонент `bitrix:main.include` (`AREA_FILE_SHOW=file/page/sect`, `PATH`) | `$APPLICATION->IncludeFile($rel,$arParams,$fnParams)` | **`bitrix:main.include`** рекомендуется (правка из публички + sect/page + кэш); legacy `IncludeFile` — простой инклюд |

Резолв шаблона компонента (приоритет `/local`→`/bitrix`): `/local/templates/<site_tpl>/components/...` → `/bitrix/templates/<site_tpl>/components/...` → `/local/components/...` → `/bitrix/components/...`. Кастом-вывод кладём как переопределённый `template.php` в шаблоне сайта, а не правим `/bitrix/components`.

## 3. Инфоблоки (основной способ хранения контента сайта)

Инфоблоки — центральная EAV-модель контента (новости, каталог, услуги, FAQ). Под них есть готовые компоненты, кэш по тегам, права, SEO, ЧПУ. Моделируем контент через инфоблоки, если данные не требуют иной схемы.

| Задача | D7 | legacy | Когда что |
|---|---|---|---|
| Тип ИБ | `\Bitrix\Iblock\TypeTable::add()` | `CIBlockType::Add()` | **legacy** для создания структуры (миграции — совпадает с мастером); D7 Table — чтение |
| Инфоблок | `\Bitrix\Iblock\IblockTable::add()` | `(new CIBlock)->Add([...,'API_CODE'=>'news','VERSION'=>2])` | **legacy** создание; задавать `API_CODE` (латиница) + `VERSION=2`. `API_CODE` обязателен для D7-ORM элементов |
| Свойство ИБ | `\Bitrix\Iblock\PropertyTable::add()` | `(new CIBlockProperty)->Add()` | legacy создание. Типы `PROPERTY_TYPE`: `S/N/F/L/E/G`; user-type: `HTML/Date/FileMan/directory/Money/…` |
| Раздел | `\Bitrix\Iblock\SectionTable` (nested set) | `CIBlockSection::Add()` | legacy запись; D7 Table — выборки |
| Элемент (запись) | `IblockTable::compileEntity('news')->getDataClass()::add([...])` | `CIBlockElement::Add(['IBLOCK_ID'=>..,'NAME'=>..,'PROPERTY_VALUES'=>['AUTHOR'=>'..'],'IBLOCK_SECTION'=>[$sec]])` | **legacy** для надёжной записи со свойствами/привязками; D7 — когда есть `API_CODE` и нужны объекты |
| Чтение элементов (backend) | `\Bitrix\Iblock\IblockTable::compileEntity('news')->getDataClass()::getList(['select'=>['ID','NAME','MY_PROP','SECTIONS'],'filter'=>['=ACTIVE'=>'Y']])->fetchCollection()` | `CIBlockElement::GetList()` (2 прохода: ID, затем `SetUrlTemplates`+`GetNext`), свойства через `PROPERTY_<CODE>` | **D7 compileEntity** для нового backend-кода (свойства = ORM-поля). legacy `GetList` — без `API_CODE` и в старом коде |
| Справочник для свойства | свойство `S` + `USER_TYPE='directory'` + `USER_TYPE_SETTINGS['TABLE_NAME']='b_hlbd_…'` (на HL-блоке) | — | **HL-блок + directory** для цветов/брендов/городов. Значение = `UF_XML_ID`, выводится как `UF_NAME` |
| SEO meta товаров/разделов | `\Bitrix\Iblock\InheritedProperty\*` (наследуемые свойства, шаблоны title/keywords/description, alt/title картинок по дереву разделов) | — | **D7** InheritedProperty — основной механизм SEO-мета ИБ |

`Fetch()` отдаёт сырые данные, `GetNext()` — с HTML-конвертацией и URL. `CHECK_PERMISSIONS=>'Y'` меняет выборку по правам.

## 4. Кастомные данные и HL-блоки

| Задача | D7 | legacy | Когда что |
|---|---|---|---|
| Своя таблица данных (заявки, бронь, логи) | `class XxxTable extends \Bitrix\Main\ORM\Data\DataManager` (`getTableName()`+`getMap()`); запись `Xxx::add([...])` с проверкой `isSuccess()` | `$DB->Query($sql)` | **D7 ORM** для всех новых сущностей. Прямой SQL — только при отсутствии ORM-аналога |
| HL-блок (плоская таблица/справочник) | `\Bitrix\Highloadblock\HighloadBlockTable::add(['NAME'=>'Colors','TABLE_NAME'=>'b_hlbd_colors'])`; `compileEntity($id)->getDataClass()` | — | **только D7 ORM**. Поля — через UserField (`UF_*`). Нет разделов/EAV — для справочников и данных без иерархии и компонентов |
| Доп. поля к любой сущности (UF) | типы `\Bitrix\Main\UserField\Types\*` | `$USER_FIELD_MANAGER` (`CUserTypeManager`); `CUserTypeEntity::Add(['ENTITY_ID'=>'HLBLOCK_'.$id,'FIELD_NAME'=>'UF_NAME','USER_TYPE_ID'=>'string'])` | legacy `CUserTypeManager` для добавления UF (D7-типов недостаточно для CRUD метаданных). Имя `UF_…`, `[0-9A-Z_]`, 4–50 |
| Выборка (общий ORM) | Array-API `Xxx::getList(['select','filter','order','cache'=>['ttl'=>3600]])`; Query-builder `Xxx::query()->where('ID','>',5)->fetchCollection()`; объекты `createObject()/save()` | array-фильтр с префиксами: `'>ID'`,`'!ID'`(≠),`'%NAME'`(LIKE),`'@ID'=>[...]`(IN),`'><ID'=>[a,b]`(BETWEEN) | **D7** для нового кода. legacy-префиксы фильтра рабочие и совместимы с `setFilter()` |

⚠️ `add/update/delete` ORM не бросают исключение при ошибке валидации — всегда проверять `$r->isSuccess()` и `$r->getErrorMessages()`. ⚠️ JOIN нескольких множественных UF/полей даёт декартово произведение — выбирать отдельными запросами.

## 5. Вывод на страницах (IncludeComponent)

| Задача | Компонент / способ | Когда что |
|---|---|---|
| Вставить компонент | `$APPLICATION->IncludeComponent("bitrix:news.list", "шаблон", [параметры], $parentComponent)` (метод `CMain`) | **единственный API** вывода — это и есть основной путь (не legacy-vs-D7) |
| Список / детальная (контент) | `bitrix:news.list` / `bitrix:news.detail` (или комплексный `bitrix:news`) | готовые компоненты вместо своего SQL |
| Каталог-витрина | `bitrix:catalog.section` + `bitrix:catalog.smart.filter` + `bitrix:catalog.element` (или комплексный `bitrix:catalog`) | D7-ядро внутри; параметры через arParams |
| Меню | файл `.<type>.menu.php` (позиционный `$aMenuLinks`) + `bitrix:menu` (`CMenu`); динамика — `.<type>.menu_ext.php` + `bitrix:menu.sections`, `USE_EXT=Y` | legacy-ядро `CMenu`, но это рабочий и единственный путь |
| Кастом-вывод под дизайн | копия шаблона компонента в `/local/templates/<tpl>/components/<vendor>/<comp>/<tpl>/template.php` | правка `template.php`/`result_modifier.php` рядом, не `/bitrix/components` |
| Лёгкая правка данных (внутри кэша) | `result_modifier.php` — выполнится один раз и закэшируется | вычисляемые поля |
| Title / крошки / счётчики (вне кэша) | `component_epilog.php` — на каждый хит | ⚠️ `SetTitle`/`AddChainItem` в кэш класть нельзя — «застынут» |
| AJAX-экшен компонента | **D7**: `class.php implements \Bitrix\Main\Engine\Contract\Controllerable`, методы `…Action`; вызов `BX.ajax.runComponentAction('bitrix:…','action',{mode:'class',signedParameters,data})` | **D7** для нового кода. legacy `CComponentAjax` (`AJAX_MODE=Y`) — конфликтует с composite, для старого кода |
| Подпись параметров для экшена | `protected function listKeysSignedParameters(){return ['IBLOCK_ID'];}` → `getSignedParameters()` в DOM, `unsignParameters()` на сервере | D7, HMAC через `Signer` |

`IncludeComponent` возвращает `false` при неразрешённом пути (молчаливый провал) — проверять имя/путь. Параметры: в логике/SQL — raw `$arParams['~CODE']`, в HTML — экранированный `$arParams['CODE']`.

Параметры и кастомизация ходовых штатных компонентов (`news.*`, `catalog.*`, `menu`/`breadcrumb`, корзина/заказ, формы/вход, поиск) — каталог карточек `components/00-index.md` (читать нужную карточку, не весь каталог).

## 6. Кэш

| Задача | D7 | legacy | Когда что |
|---|---|---|---|
| Кэш произвольных данных | `\Bitrix\Main\Data\Cache::createInstance()`; `initCache($ttl,$id,$dir)`/`getVars()` ↔ `startDataCache()`/`endDataCache([...])` | `CPHPCache` (`InitCache/GetVars/StartDataCache/EndDataCache`) | **D7** для нового кода; legacy `CPHPCache` — полная обёртка над тем же |
| Кэш компонента | `$this->startResultCache($time,$addId,$path)` / `endResultCache()` / `abortResultCache()` (404) / `setResultCacheKeys([...])`; параметр `CACHE_TYPE='A'`, `CACHE_TIME` | — | встроенный механизм компонента |
| Инвалидация по тегам | `\Bitrix\Main\Application::getInstance()->getTaggedCache()`: `startTagCache($path)`→`registerTag('iblock_id_5')`→`endTagCache()`; сброс `clearByTag('iblock_id_5')` | `$CACHE_MANAGER->ClearByTag()` | **D7** TaggedCache. Требует `SITE_ID`. Так инвалидируется HTML-кэш компонентов при изменении ИБ |
| Кэш в ORM | ключ `cache` в `getList`: `['cache'=>['ttl'=>3600,'cache_joins'=>true]]` | — | обязателен для часто читаемых каталожных данных |
| Composite (вся страница) | `\Bitrix\Main\Composite\Engine::setEnable()`; динамику оборачивать `$this->createFrame()` / `StaticArea::startDynamicArea()` | — | ⚠️ один компонент с `frameMode=false` выключает composite всей страницы |
| Сброс кэша при деплое контента | `clearByTag('iblock_id_X')` (точечно) | `BXClearCache(true)` (файловый); composite — `cron_html_pages.php` | точечный сброс по тегу предпочтителен |

⚠️ Любой динамический параметр в `$arParams` (текущее время и т.п.) делает кэш бесполезным. После прямой правки таблицы обработчиков событий managed-кэш держит её 3600 с — сбросить кэш.

## 7. События и агенты

| Задача | D7 | legacy | Когда что |
|---|---|---|---|
| Подписка на событие (на хит) | `\Bitrix\Main\EventManager::getInstance()->addEventHandler($from,$type,$cb,$incFile,$sort)`; обработчик получает один аргумент `\Bitrix\Main\Event` (v2) | `AddEventHandler($from,$msg,$cb,$sort)`; обработчик получает позиционные аргументы (v1) | в `/local/php_interface/init.php`. **D7** для нового кода; legacy для старых обработчиков. ⚠️ Сигнатура обработчика обязана совпадать со способом регистрации (объект vs позиционные) |
| Постоянная подписка (между хитами) | `registerEventHandler($from,$type,$toModule,$toClass,$toMethod,…)` / `unRegisterEventHandler(...)` | `RegisterModuleDependences(...)` | пишет в `b_module_to_module`; постоянные модульные — в `install` модуля |
| Рассылка своего события | `(new \Bitrix\Main\Event('mymod','OnAfterX',['ID'=>$id]))->send();` → `$event->getResults()` | `GetModuleEvents()`+`ExecuteModuleEventEx()` | **D7** для нового кода |
| Периодическая/отложенная задача | **аналога нет** | `CAgent::AddAgent("MyClass::run();", "mymod", "N"\|"Y", $interval)` / `RemoveAgent` | **только legacy** `CAgent`. Строка `NAME` — PHP, обязана заканчиваться `;`. Возврат своего имени → перепланирование; пустой строки → ⚠️ агент удаляется |
| Запуск агентов на проде | — | cron: `bitrix/modules/main/tools/cron_events.php` + опция `agents_use_crontab='Y'` | **cron** на проде (режим «на хитах» тормозит хиты). Внутри агента `$USER=null` |
| Отложить необязательную работу | `Application::getInstance()->addBackgroundJob($cb,$args,JOB_PRIORITY_LOW)` (после отправки ответа) | — | **D7** для фоновых задач одного запроса |

⚠️ `CEvent` (`classes/general/event.php`) — это почтовые рассылки, НЕ межмодульные события.

## 8. Файлы и медиа (CFile)

| Задача | D7 | legacy | Когда что |
|---|---|---|---|
| Сохранить файл | — | `CFile::SaveFile($fileArray,$module)` → возвращает `b_file.ID` | **legacy `CFile`** — единственный путь записи. `\Bitrix\Main\FileTable` — read-only |
| Получить путь / массив | `\Bitrix\Main\FileTable::getById()` (чтение) | `CFile::GetPath($id)`, `CFile::GetFileArray($id)` | legacy `CFile` для путей/вывода |
| Ресайз картинки (с кэшем) | `\Bitrix\Main\File\Image` (`Image\Gd`/`Image\Imagick`, `Watermark`) | `CFile::ResizeImageGet($id,['width'=>300,'height'=>300],BX_RESIZE_IMAGE_PROPORTIONAL)` | **legacy `CFile::ResizeImageGet`** рабочая лошадка (ресайз с кэшем); D7 `File\Image` — низкоуровневая обработка |
| Вывести / проверить / удалить | — | `CFile::ShowImage()`, `CFile::CheckImageFile()`, `CFile::Delete($id)` | legacy. ⚠️ Файловые UF и значения свойств `F` удалять через `CFile::Delete()` |
| Медиабиблиотека | — | `\CMedialib*` (модуль fileman) | legacy |

Облачные хранилища прозрачны через события `OnFileSave`/`OnMakeFileArray`/`OnGetFileSRC`.

## 9. Формы и заявки

| Задача | D7 | legacy | Когда что |
|---|---|---|---|
| Веб-форма (обратная связь, заявка) | единственный D7-класс `\Bitrix\Form\SenderConnectorForm` (интеграция рассылок) | `CForm`, `CFormField`, `CFormResult`, `CFormStatus`, `CFormValidator`; вывод — компонент `bitrix:form` | **legacy — рекомендованный путь** (D7-обёрток нет). Данные в `b_form*`, не в инфоблоках. Это не CRM-формы Б24 |
| Поток обработки | — | POST → `CForm::Check()` (валидация, капча) → `CFormResult::Add()` → события `onBeforeResultAdd`/`onAfterResultAdd` → `CEvent::Send` (письмо) | legacy |
| Транзакционное письмо | `\Bitrix\Main\Mail\Event`, `EventMessageTable`, `EventMessageCompiler` | `CEvent::Send('EVENT','s1',$fields)` (отложенно) / `SendImmediate(...)` (синхронно) | **legacy `CEvent::Send`** — основной API. Тип `b_event_type` → шаблон `b_event_message` (плейсхолдеры `#FIELD#`). SMTP в `.settings.php` |
| Справочник/реестр контента в админке | — | модуль `lists` над iblock (типы ИБ `lists`, поля `b_lists_field`) | legacy `lists` — справочники (вакансии, FAQ, филиалы) без своего модуля, с привязкой к bizproc |
| Вход через соцсети | хранилище связок `\Bitrix\Socialservices\UserTable` (токены в `CryptoField`) | `CSocServAuthManager`, `CSocServAuth::AuthorizeUser()`, провайдеры `CSocServVKontakte`/`CSocServGoogleOAuth`/… | **legacy-доминантный**. Свой провайдер — событие `OnAuthServicesBuildList`; redirect `/bitrix/tools/oauth/<provider>.php`. Регистрация требует И `main:new_user_registration` И `socialservices:allow_registration` |

## 10. Заказы и коммерция (Order)

| Задача | D7 | legacy | Когда что |
|---|---|---|---|
| Собрать/сохранить заказ | `\Bitrix\Sale\Order::create($siteId,$userId)`; `Basket`/`BasketItem`, `Payment`+`PaymentCollection`, `Shipment`+`ShipmentCollection`; `$order->save()` → `\Bitrix\Sale\Result` | `CSaleOrder::DoSaveOrder` | **D7 — рекомендованный путь**. Заказ собирается в памяти и сохраняется одним `$order->save()` |
| Реестр сущностей | `\Bitrix\Sale\Registry::getInstance(Registry::REGISTRY_TYPE_ORDER)->getOrderClassName()` | — | **D7** всегда: ⚠️ никогда `new Order` — только `Order::create()`/Registry |
| Корзина | `\Bitrix\Sale\Basket::loadItemsForFUser(\Bitrix\Sale\Fuser::getId(),$siteId)` | — | D7. Корзина на FUSER ≠ USER |
| Скидки/купоны | `Bitrix\Sale\Discount` (`buildFromOrder`); `DiscountCouponsManager::init(MODE_CLIENT,['userId'=>$uid])` | — | D7. ⚠️ купон инициализировать ДО `doFinalAction` |
| Управление готовым заказом | `$payment->setPaid('Y')`; `$shipment->allowDelivery()`/`tryShip()`; `$order->setField('STATUS_ID','F')` — каждый раз `$order->save()` | — | D7. Статусы: `OrderStatus::getInitialStatus()` (N) → `getFinalStatus()` (F) |
| Витрина магазина | компоненты `bitrix:sale.basket.basket.line`/`.basket`, `bitrix:sale.order.ajax` (одностраничный мастер) или `bitrix:sale.order.checkout` (React), `bitrix:sale.personal.*` | — | `sale.order.ajax` — рабочая лошадка; `checkout` — на `\Bitrix\Main\Engine\Controller` |
| Платёжная система / доставка | хендлеры `handlers/paysystem/<code>/` и `handlers/delivery/<code>/` (`handler.php`+`.description.php`); конфиг через Business Value; кассы 54-ФЗ `\Bitrix\Sale\Cashbox\*` | — | D7-структура хендлеров |
| Каталог / цены / валюты | `\Bitrix\Catalog\*`, `\Bitrix\Currency\*` | `CCatalogGroup::Add()` | **D7** для нового кода; legacy в старом |

⚠️ Порядок обязателен: `doFinalAction(true)` перед `save()`; `save()` возвращает `Result`, не bool; persontype задавать до свойств; без `PRODUCT_PROVIDER_CLASS` позиция не свяжется с каталогом; legacy `CSaleOrder::DoSaveOrder` и D7 `Order::save()` нельзя смешивать в одной транзакции.

## 11. Обмен с 1С (CommerceML)

| Задача | D7 | legacy | Когда что |
|---|---|---|---|
| Импорт каталога из 1С | — | `CIBlockCMLImport`; оркестрация — `bitrix:catalog.import.1c`; точка входа `1c_import.php`/`1c_exchange.php` | **legacy — рекомендованный путь** (D7-обёртки нет). CommerceML 2.x (XML, по умолчанию `windows-1251`) |
| Экспорт каталога в 1С | — | `CIBlockCMLExport`; `bitrix:catalog.export.1c` | legacy |
| Экспорт заказов в 1С | вспом. `\Bitrix\Sale\Exchange\*` (схемы 2.10/3.1) | `CSaleExport::ExportOrders2Xml()`; точка входа `1c_exchange.php?type=sale` | legacy `CSaleExport` для экспорта; приём заказов — `CSaleOrderLoader` + D7 `Exchange\*` |

HTTP-диалог обмена идёт по протоколу `success`/`progress`/…

## 12. Роутинг и ЧПУ

| Задача | D7 | legacy | Когда что |
|---|---|---|---|
| ЧПУ штатного компонента | `\Bitrix\Main\UrlRewriter` (`getList/add/update/delete`, `reindexAll($maxTime,$ns)`, `reindexFile()`) | массив `$arUrlRewrite` в корневом `/urlrewrite.php` (`CONDITION`/`RULE`/`ID`/`PATH`/`SORT`) | **SEF/urlrewrite** — основной механизм ЧПУ. Вставить компонент с `SEF_MODE=Y`+`SEF_FOLDER` → `UrlRewriter::reindexAll()` (или админка «ЧПУ → Реиндексация»). ⚠️ Ручная правка `/urlrewrite.php` затрётся реиндексацией |
| Точечное правило | `UrlRewriter::add($siteId,['CONDITION'=>'#^/blog/#','RULE'=>'','ID'=>'bitrix:blog','PATH'=>'/blog/index.php'])` | `CUrlRewriter::Add()` | D7 `UrlRewriter::add` для нового кода |
| Свой URL / API-маршрут | `\Bitrix\Main\Routing`: `/local/routes/*.php`, `$routes->get('/path/{id}', $controller)` | — | **D7 Routing** для своих контроллеров/API |
| Приоритет резолва | физические файлы → правила `urlrewrite.php` → D7 Routing (фолбэк) | — | для штатных ЧПУ — urlrewrite (приоритетнее); для своих маршрутов — D7 Routing. На корне нужны `/urlrewrite.php` и `/404.php` |

⚠️ `SEF_FOLDER` должен совпадать с реальным путём страницы, иначе деталка молча не отрисуется (`guessComponentPath()` вернёт `false`). Порядок правил по `SORT`, затем по длине `CONDITION` (длиннее выше): общее `#^/catalog/#` ниже специфичных.

---

### Правило выбора версии API (резюме)

- **Новый backend-код, своя бизнес-логика, выборки** → D7 ORM (`\Bitrix\…`), `/local`.
- **Создание структуры ИБ, запись элементов со свойствами** → legacy `C*` (надёжно, совпадает с мастером), либо D7 при наличии `API_CODE`.
- **Title / SEO / крошки / IncludeComponent / меню / CFile** → legacy `$APPLICATION`/`C*` — единственный или основной путь.
- **Формы, обмен 1С, агенты, соцсети, транзакционная почта** → legacy — рекомендованный путь (D7-обёрток нет).
- **Заказы, скидки, каталог-ядро, sitemap/robots, роутинг своих API** → D7.

CLI-генерация кода (`make:*`, `orm:annotate`) — Symfony Console, точка входа `bitrix/modules/main/cli/bitrix.php`; требует настроенного Composer (см. https://docs.1c-bitrix.ru/pages/get-started/composer.html).
