# 12. Файлы и медиа: CFile, ресайз с кэшем, свойства типа F

## Цель

Сохранять, отдавать, ресайзить и удалять файлы/изображения в 1С-Битрикс через
единственно рекомендованный для записи API `\CFile` (поверх таблицы `b_file`) и
через D7-фасад `\Bitrix\Main\File\Image` для пиксельной обработки. Покрывает:
импорт картинок из URL, миниатюры каталога с дисковым кэшем, привязку к
`PREVIEW_PICTURE`/`DETAIL_PICTURE` и свойству инфоблока типа `F`, водяные знаки,
безопасное удаление.

## Когда применять

- Импорт фото товаров/новостей из внешних фидов или с диска в инфоблок.
- Вывод миниатюр одинакового размера (сетки каталога) или «вписанных» (логотипы,
  баннеры) без повторного ресайза на каждом хите.
- Программная загрузка файлов из формы (счета, документы, вложения).
- Наложение водяного знака на фото.
- Чтение метаданных файла (путь, размеры, MIME) и контролируемая отдача приватных
  документов по HTTP вместо прямой ссылки в `/upload/`.

Запись в `b_file` — всегда через `\CFile`. Чтение допускается и через ORM
`\Bitrix\Main\FileTable` (read-only).

## Шаги

1. **Получить массив файла.** Из POST (`$_FILES`-формат), из URL/локального
   пути (`CFile::MakeFileArray`) либо собрать вручную с ключом `content`.
2. **Сохранить** через `CFile::SaveFile($arFile, "iblock")` → получить
   `b_file.ID`. Для полей инфоблока передавать сам массив в `PREVIEW_PICTURE` /
   `DETAIL_PICTURE` или в свойство типа `F` — модуль iblock сохранит сам.
3. **Привязать** к сущности: `CIBlockElement::Add/Update` или
   `SetPropertyValuesEx` для множественного свойства `F`.
4. **Выводить** миниатюру через `CFile::ResizeImageGet` (кэш на диске) или
   `CFile::ShowImage` (готовый `<img>`).
5. **Удалять** только через `CFile::Delete($id)` — он чистит `resize_cache`,
   учитывает дубли и квоту.

## Рабочий сниппет

Файл: `/local/php_interface/lib/Media/ImageImporter.php`

```php
<?php
namespace Local\Media;

use Bitrix\Main\Loader;

/** Импорт изображения из URL/пути в инфоблок + получение миниатюры. */
final class ImageImporter
{
    /** Скачать/прочитать картинку и сохранить в b_file. Вернёт ID или null. */
    public static function importToFile(string $source, string $module = 'iblock'): ?int
    {
        // MakeFileArray: ID, локальный путь или http(s)/ftp URL (скачает сам).
        $arFile = \CFile::MakeFileArray($source);
        if (!$arFile) {
            return null;
        }
        // Валидация картинки (тип/MIME/расширение/габариты): "" или null = ок.
        $error = \CFile::CheckImageFile($arFile, 0, 0, 0);
        if ($error) {
            return null;
        }
        // Контроль дублей (main.control_file_duplicates=Y) отсечёт повторы сам.
        $fileId = \CFile::SaveFile($arFile, $module);
        return ($fileId && $fileId !== 'NULL') ? (int)$fileId : null;
    }

    /**
     * Привязать картинку к элементу инфоблока: PREVIEW_PICTURE/DETAIL_PICTURE
     * + множественное свойство типа F (MORE_PHOTO).
     */
    public static function attachToElement(int $elementId, int $iblockId, string $detailUrl, array $galleryUrls = []): void
    {
        if (!Loader::includeModule('iblock')) {
            return;
        }
        // В поля инфоблока передаётся МАССИВ MakeFileArray — SaveFile вызовет iblock.
        $detail = \CFile::MakeFileArray($detailUrl);
        if ($detail) {
            $el = new \CIBlockElement();
            $el->Update($elementId, ['DETAIL_PICTURE' => $detail]);
        }

        // Свойство типа F (множественное): значение — массив файловых массивов.
        $values = [];
        foreach ($galleryUrls as $i => $url) {
            $ar = \CFile::MakeFileArray($url);
            if ($ar) {
                $values['n' . $i] = ['VALUE' => $ar, 'DESCRIPTION' => ''];
            }
        }
        if ($values) {
            \CIBlockElement::SetPropertyValuesEx($elementId, $iblockId, ['MORE_PHOTO' => $values]);
        }
    }

    /**
     * Миниатюра с дисковым кэшем. $file — b_file.ID или массив GetFileArray().
     * EXACT — обрезка под целевое соотношение (сетки); PROPORTIONAL — вписать.
     */
    public static function thumb($file, int $w, int $h, bool $crop = true): array
    {
        $type = $crop ? BX_RESIZE_IMAGE_EXACT : BX_RESIZE_IMAGE_PROPORTIONAL;
        $res = \CFile::ResizeImageGet(
            $file,
            ['width' => $w, 'height' => $h],
            $type,
            true,    // $bInitSizes: вернуть реальные width/height
            false,   // $arFilters: по умолчанию добавится sharpen
            false,
            85       // $jpgQuality: 80–85 экономит вес против дефолтных 95
        );
        return $res ?: ['src' => '', 'width' => 0, 'height' => 0];
    }
}
```

Вывод в шаблоне (миниатюра + готовый `<img>` через ShowImage):

```php
<?php
$img = \Local\Media\ImageImporter::thumb($arItem['PREVIEW_PICTURE'], 400, 400, true);
if ($img['src']) {
    echo '<img src="', htmlspecialcharsbx($img['src']),
         '" width="', (int)$img['width'], '" height="', (int)$img['height'],
         '" loading="lazy" alt="">';
}
// Альтернатива: готовый тег с alt из DESCRIPTION, $strImage = ID/URL/массив.
echo \CFile::ShowImage($arItem['DETAIL_PICTURE'], 600, 600);
```

Водяной знак через D7 (`\Bitrix\Main\File\Image`):

```php
<?php
use Bitrix\Main\File\Image;

// GetPath даёт URL /upload/.../x.jpg; физический путь = DOCUMENT_ROOT + URL.
$physical = $_SERVER['DOCUMENT_ROOT'] . \CFile::GetPath($fileId);
$image = new Image($physical);
$image->load();
$wm = Image\Watermark::createFromArray([
    'type' => 'image',
    'file' => $_SERVER['DOCUMENT_ROOT'] . '/local/assets/wm.png',
    'position' => 'br', 'alpha_level' => 60, 'fill' => 'resize',
]);
$image->drawWatermark($wm);
$image->save(90);
```

## Выбор API

| Задача | API | Примечание |
|---|---|---|
| Запись файла в `b_file` | `CFile::SaveFile` / `SaveForDB` | Единственный путь записи; внутри уже использует D7 |
| Импорт из URL/пути | `CFile::MakeFileArray` | Скачивает http(s)/ftp; блокирует `phar://`, приватные IP |
| Миниатюра с кэшем | `CFile::ResizeImageGet` | Кэш в `/upload/resize_cache/`; повторы бесплатны |
| Низкоуровневый ресайз файл→файл | `CFile::ResizeImageFile` | EXIF-автоповорот, фильтры, водяные знаки |
| Готовый `<img>` | `CFile::ShowImage` | alt из `DESCRIPTION`, опц. поп-ап |
| Путь / массив / MIME | `CFile::GetPath` / `GetFileArray` / `GetContentType` | Чтение |
| Чтение через ORM | `\Bitrix\Main\FileTable::getList/getById` | ⚠️ только чтение |
| Пиксельная обработка | `\Bitrix\Main\File\Image` (+ `Gd`/`Imagick`) | Поворот, blur, фильтры, WebP, водяные знаки |
| Удаление | `CFile::Delete` | Чистит кэш, учитывает дубли и квоту |
| Отдача приватного файла | `\Bitrix\Main\Engine\Response\BFile::createByFileId` | Права + Range вместо прямой ссылки |

`\CFile` и `\Bitrix\Main\File\Image` — две поддерживаемые версии API для разных
слоёв: `\CFile` для записи/привязки/кэша миниатюр, `Image` — для пиксельных
операций. `Image::RESIZE_PROPORTIONAL/EXACT` (0/1/2) численно совпадают с
`BX_RESIZE_IMAGE_*`.

## Проверка

**Режим «только файлы» (без запущенного Битрикса):**

- `php -l` по файлу `/local/php_interface/lib/Media/ImageImporter.php` — синтаксис.
- Грепом убедиться, что запись в `b_file` идёт только через `CFile::SaveFile`/
  `SaveForDB`, а не через `FileTable::add/update/delete`.
- Проверить, что в полях инфоблока (`PREVIEW_PICTURE`/`DETAIL_PICTURE`/свойство
  `F`) передаётся массив `MakeFileArray`, а не голый ID при добавлении нового
  файла.
- Проверить наличие удаления через `CFile::Delete`, а не `unlink`.

**Режим «живой Битрикс»:**

- Через консоль (`bitrix/php_interface` или CLI с подключённым `prolog`):
  `$id = \CFile::MakeFileArray($url); var_dump(\CFile::SaveFile($id, 'iblock'));`
  — должен вернуться числовой ID.
- `\CFile::GetPath($id)` возвращает URL вида `/upload/<subdir>/<name>`.
- `\CFile::ResizeImageGet($id, ['width'=>400,'height'=>400], BX_RESIZE_IMAGE_EXACT, true)`
  — `src` указывает в `/upload/resize_cache/...`; повторный вызов отдаёт тот же файл.
- В админке (Контент → элемент инфоблока) картинка отображается в
  `DETAIL_PICTURE` и в галерее свойства `F`.
- `\CFile::Delete($id)` — запись и кэш ресайзов исчезают; квота пересчитана.

## ⚠️ Риски

1. ⚠️ **Удаление только через `CFile::Delete`.** Прямой `unlink` оставит запись в
   `b_file` и весь `resize_cache`, а при включённом контроле дублей может удалить
   файл, на который ещё ссылаются другие записи (потеря данных у соседних
   элементов).
2. ⚠️ **`FileTable` — read-only.** `add/update/delete` намеренно бросают
   `NotImplementedException("Use CFile class.")`. Любая запись в `b_file` мимо
   `\CFile` — ошибка by design.
3. ⚠️ **`MakeFileArray` с пользовательским URL — внешняя загрузка.** Метод
   скачивает по http(s)/ftp; принимайте URL только из доверенных источников.
   Встроенная защита блокирует `phar://`/`php://` (кроме `php://input`) и
   приватные IP, но валидируйте источник на своём уровне.
4. **Нет апскейла.** В режиме `PROPORTIONAL` картинка меньше запрошенного размера
   возвращается как оригинал (с исходными `width/height`). Фиксируйте контейнер
   через CSS, не полагайтесь на то, что `src` всегда из `resize_cache`.
5. **`EXACT` обрезает по центру** — для товаров с важными краями (упаковка с
   текстом) часть кадра потеряется; используйте `PROPORTIONAL`.
6. **`resize_cache` разрастается.** Каждый уникальный набор (W, H, type, filters)
   = отдельный файл. Стандартизируйте набор размеров миниатюр в шаблонах.
7. **Качество JPEG по умолчанию 95** (`main.image_resize_quality`) — тяжёлые
   файлы. Для каталога с сотнями фото передавайте `$jpgQuality` 80–85.
8. **Контроль дублей меняет физический путь.** При `control_file_duplicates=Y`
   новый `b_file.ID` может указывать на файл уже существующего оригинала —
   ещё одна причина не трогать диск вручную.

## Связано

- Свойства инфоблока типа `F`, `PREVIEW_PICTURE`/`DETAIL_PICTURE` — рецепт по
  инфоблокам и `CIBlockElement::Add/Update`, `SetPropertyValuesEx`.
- Контроллеры и отдача файлов по HTTP — рецепт по `Engine\Response`.
- Настройки: `main.control_file_duplicates`, `main.image_resize_quality`,
  квоты `disk_space` — рецепт по настройкам модуля main.
