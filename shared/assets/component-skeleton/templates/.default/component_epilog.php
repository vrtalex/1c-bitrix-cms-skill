<?php
if (!defined('B_PROLOG_INCLUDED') || B_PROLOG_INCLUDED !== true) die();

/** @var array $arResult */
/** @var CMain $APPLICATION */

// Выполняется на КАЖДОМ хите, даже при включённом кэше компонента.
// Сюда — заголовок страницы, хлебные крошки, счётчики.
// Доступны только поля, помеченные через setResultCacheKeys() в component.php.
// Пример:
// $APPLICATION->SetTitle($arResult['NAME'] ?? '');
