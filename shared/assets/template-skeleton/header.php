<?php
if (!defined('B_PROLOG_INCLUDED') || B_PROLOG_INCLUDED !== true) die();
/** @var CMain $APPLICATION */
?><!DOCTYPE html>
<html lang="<?= LANGUAGE_ID ?>">
<head>
    <?php $APPLICATION->ShowHead(); ?>
    <title><?php $APPLICATION->ShowTitle(); ?></title>
</head>
<body>
<?php $APPLICATION->ShowPanel(); ?>
<header><!-- шапка сайта --></header>
<main>
<!-- начало рабочей области страницы -->
