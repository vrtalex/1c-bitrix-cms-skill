<?php
if (!defined('B_PROLOG_INCLUDED') || B_PROLOG_INCLUDED !== true) die();

/** @var CBitrixComponent $this */
/** @var array $arParams */
/** @var array $arResult */

if (!\Bitrix\Main\Loader::includeModule('iblock')) {
    ShowError('Не установлен модуль iblock');
    return;
}

// Нормализация входных параметров
$arParams['IBLOCK_ID'] = (int)($arParams['IBLOCK_ID'] ?? 0);
$cacheTime = (int)($arParams['CACHE_TIME'] ?? 3600);

if ($this->startResultCache($cacheTime)) {
    $arResult['ITEMS'] = [];
    // TODO: наполнить выборкой — см. recipe 05-query-elements

    // объявляет, какие ключи $arResult сохраняются в кэше и восстанавливаются
    // на каждом хите (включая попадание в кэш) — их и читает component_epilog.php.
    // Сам title/хлебные крошки ставятся в component_epilog.php, чтобы выполняться
    // на каждом хите, вне закэшированного результата.
    $this->setResultCacheKeys(['ITEMS']);
    $this->includeComponentTemplate();
}
