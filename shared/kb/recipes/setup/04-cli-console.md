# 04. CLI и консольные команды (Symfony Console)

## Цель

Запустить консольный слой «1С-Битрикс: Управление сайтом» (ядро 26.x) и
использовать встроенные команды `make:*`, `orm:annotate`, `update:*`,
`messenger:consume` для scaffolding кастомной логики, генерации ORM-аннотаций и
обновлений модулей из скриптов CI/деплоя.

## Когда применять

- Нужно сгенерировать каркас своего модуля, компонента, ORM Table-класса или
  AJAX/REST-контроллера, не выписывая бойлерплейт вручную.
- Нужны PHPDoc-аннотации ORM-сущностей для автокомплита в IDE.
- Деплой/CI: детерминированная установка точных версий модулей и пересборка
  аннотаций после изменения схемы.
- Запуск воркера шины сообщений (Messenger) как отдельного процесса.

Не применять для настройки контента (инфоблоки, страницы, компоненты на
странице) — это делается через штатные средства, а не через CLI.

## Шаги

1. **Убедиться, что настроен Composer + Symfony Console.**
   Консольный слой Bitrix построен на Symfony Console; точка входа —
   `bitrix/modules/main/cli/bitrix.php`. Без установленного Symfony Console
   точка входа выводит «Symfony Console is not installed» и завершается.
   В «чистом» дистрибутиве без настроенного composer команды недоступны.
   Настройка composer описана в официальной документации:
   https://docs.1c-bitrix.ru/pages/get-started/composer.html

2. **Создать CLI-обёртку `bitrix/bitrix.php`.** Сам исполняемый файл —
   `bitrix/modules/main/cli/bitrix.php`, но команды запускают через тонкую
   обёртку `bitrix/bitrix.php`. Её создаёт настройка Composer (`docs.1c-bitrix`
   выше) либо её делают вручную одной строкой:
   ```php
   <?php // DOCUMENT_ROOT/bitrix/bitrix.php
   require __DIR__ . '/modules/main/cli/bitrix.php';
   ```
   Сниппет обёртки приведён и в рецепте `../update/04-apply-update.md`. Без этого файла
   `php bitrix.php` не найдёт точку входа.

3. **Определить способ запуска.** Команды вызываются из каталога
   `DOCUMENT_ROOT/bitrix` (тогда `php bitrix.php`) либо из корня документа
   (`php bitrix/bitrix.php`) — это один и тот же обёрточный файл:
   ```bash
   php bitrix.php list
   ```
   Пути генераторов (`make:component`, `make:tablet`) зависят от текущего
   каталога и опции `--root`; запуск из другого места даст другие пути.

4. **Посмотреть список доступных команд** (`php bitrix.php list`). Кроме команд
   модуля main, в список попадают команды любых модулей, объявивших их в секции
   `console` своего `.settings.php` (например, `bizproc`, `translate`).

5. **Запускать нужную команду** с её опциями (см. сниппеты ниже). Большинство
   команд поддерживают:
   - интерактивный режим (задают вопросы по недостающим параметрам);
   - `-n` / `--no-interaction` (стандарт Symfony) — отключить вопросы;
   - `--show` — вывести результат в консоль без записи файла.

6. **При необходимости добавить свою команду.** Свой класс-наследник
   `Symfony\Component\Console\Command\Command` регистрируется в секции
   `console.commands` файла `.settings.php` своего модуля — после этого команда
   автоматически попадает в `php bitrix.php list`.

## Рабочий сниппет/конфиг

Встроенные команды модуля main (по результату `php bitrix.php list`):

| Команда | Назначение |
|---------|-----------|
| `orm:annotate` | PHPDoc-аннотации ORM-сущностей (Table) для автокомплита |
| `make:component` | Компонент (класс + шаблон + lang) |
| `make:controller` | Контроллер AJAX/REST, опционально CRUD-экшены |
| `make:tablet` | ORM Table-класс (наследник `DataManager`) |
| `make:entity` | Простой entity-класс бизнес-логики (DTO-подобный) |
| `make:module` | Каркас папки модуля (include, install, version, lang) |
| `make:request` / `make:service` | Объект запроса / класс сервисного слоя |
| `make:event` / `make:eventhandler` | Класс события / обработчика |
| `make:message` / `make:messagehandler` | Сообщение / обработчик для Messenger |
| `make:agent` | Класс агента (фоновой задачи) |
| `dev:module-skeleton` | Скелет структуры внутри `module/lib` |
| `dev:locator-codes` | Генерация метаданных для автокомплита ServiceLocator |
| `update:modules` | Установка обновлений модулей (поддержка expert-mode JSON) |
| `update:languages` | Обновление языковых файлов |
| `update:versions` | Показ доступных версий обновлений |
| `messenger:consume` | Воркер шины сообщений (CLI) |

Scaffolding кастомного модуля (пример сценария корп-сайта):

```bash
# 1. Каркас своего модуля (по умолчанию пишется в local/modules/<id>)
php bitrix.php make:module partner.corp --name="Corp logic"

# 2. ORM Table-класс под форму/заявку
php bitrix.php make:tablet b_corp_request partner.corp

# 3. AJAX-контроллер для формы (один экшен add)
php bitrix.php make:controller feedback -m partner.corp --actions=add

# 4. Свой компонент для блока
php bitrix.php make:component partner:corp.feedback.form --local

# 5. Метаданные автокомплита ServiceLocator для IDE
php bitrix.php dev:locator-codes partner.corp
```

ORM-аннотации (сигнатура `orm:annotate`):

```bash
# Аннотировать один модуль и сохранить файл внутри него
php bitrix.php orm:annotate -m partner.corp --inside

# Пересобрать аннотации по всем модулям (после изменения схемы)
php bitrix.php orm:annotate -m all
```
Опции: `-m, --modules` (список через запятую, `all` — все), `-c, --clean`
(пересоздать карту с нуля), `--inside` (сохранить внутри папки модуля, только
при одном модуле).

Обновления из CLI (для CI/деплоя):

```bash
# Детерминированная установка точных версий (expert-mode)
php bitrix.php update:modules -i updates.json

# Показать доступные обновления
php bitrix.php update:versions
```
`update:modules` без опций обновляет все доступные; `-m main,iblock` — только
указанные (с авто-добором зависимостей); `-i` импортирует точный список версий
из JSON. Команда интерактивно запрашивает подтверждение установки.

## Проверка

- `php bitrix.php list` выводит список команд (а не сообщение об отсутствии
  Symfony Console) — значит окружение настроено.
- После `make:module` команда возвращает список созданных файлов в
  `local/modules/<id>`.
- После `make:component` выводится готовый сниппет вызова
  `$APPLICATION->IncludeComponent('ns:name', '', [])`.
- После `orm:annotate` в файле аннотаций появляются блоки с маркером аннотации;
  IDE начинает подсказывать поля Table-сущностей.
- `messenger:consume` запускается воркером только при `messenger.run_mode = 'cli'`
  в `.settings.php`; иначе выводит предупреждение и выходит.

## ⚠️ Риски

- ⚠️ **`update:modules` меняет код установленных модулей.** Это запись в боевой
  кодовой базе. Перед запуском в CI/проде — резервная копия и тест на стенде;
  expert-mode (`-i updates.json`) фиксирует точные версии и снижает риск
  расхождения окружений.
- ⚠️ **`orm:annotate` инклюдит php-файлы проекта** (`include_once` каждого
  `.php` при сканировании). Исполняемый код на верхнем уровне таких файлов
  выполнится как побочный эффект — держите в `lib/` только определения классов.
  Есть стоп-лист исключаемых файлов.
- **Два разных «Command», не путать namespace.** `Bitrix\Main\Cli\Command\*` —
  консольные команды Symfony Console (тема этого рецепта).
  `Bitrix\Main\Command\AbstractCommand` / `CommandInterface` — отдельный
  Command-pattern доменного слоя (валидация + `execute()`, возвращает `Result`),
  вызывается из контроллеров/сервисов, а не из консоли.
- **`make:entity` создаёт НЕ ORM-сущность**, а простой класс со
  свойствами-строками. Для ORM-таблицы (наследник `DataManager`) нужен
  `make:tablet`.
- **`make:module` пишет в `local/modules`** по умолчанию — так кастом не
  перетирается обновлениями ядра; для этого `local/` должен быть задействован
  в проекте.
- **Список команд модуля `readonly`.** Секцию `console` модуля нельзя
  переопределить из UI-настроек; свои команды добавляются только правкой
  `.settings.php` своего модуля.

## Связано

- [../../00-overview.md](../../00-overview.md) — обзор скилла и карта поддоменов.
- [../../operations.md](../../operations.md) — операционные процедуры (деплой, обновления, CI).
- [../../conventions.md](../../conventions.md) — соглашения (namespace, две поддерживаемые версии API, структура `local/`).
- [../01-introspect-project.md](../01-introspect-project.md) — интроспекция проекта перед запуском команд.
