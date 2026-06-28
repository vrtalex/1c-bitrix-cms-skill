<?php
require($_SERVER['DOCUMENT_ROOT'] . '/bitrix/header.php');
/** @var CMain $APPLICATION */
$APPLICATION->SetTitle('Заголовок страницы');
?>

<!-- Контент страницы. Пример вывода списка из инфоблока: -->
<?php
$APPLICATION->IncludeComponent('bitrix:news.list', '.default', [
    'IBLOCK_TYPE' => 'content',
    'IBLOCK_ID'   => '#IBLOCK_ID#',
    'NEWS_COUNT'  => 20,
    'CACHE_TYPE'  => 'A',
    'CACHE_TIME'  => 3600,
]);
?>

<?php require($_SERVER['DOCUMENT_ROOT'] . '/bitrix/footer.php'); ?>
