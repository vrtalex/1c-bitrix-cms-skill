<?php
if (!defined('B_PROLOG_INCLUDED') || B_PROLOG_INCLUDED !== true) die();

/** @var array $arResult */
/** @var array $arParams */
?>
<div class="sk-list">
<?php foreach ($arResult['ITEMS'] as $item): ?>
    <div class="sk-item"><?= htmlspecialcharsbx($item['NAME'] ?? '') ?></div>
<?php endforeach; ?>
</div>
