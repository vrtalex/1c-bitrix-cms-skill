---
name: 1c-bitrix-cms-seo
description: "SEO для сайтов на «1С-Битрикс: Управление сайтом» — sitemap.xml, robots.txt (+ Clean-param), мета-шаблоны (наследуемые SEO-свойства инфоблоков), ЧПУ/SEF, 301-редиректы, canonical, Open Graph, schema.org, дубли страниц и коды ответа (soft-404, noindex), SEO умного фильтра, скорость и Core Web Vitals (композит, сжатие, версии окружения), пагинация, hreflang/мультиязычность/мультирегиональность. Используй для SEO-задач на сайте Битрикс (не на портале Битрикс24)."
---
# 1c-bitrix-cms-seo

SEO сайта на Битрикс. Гейты оркестратора: код в `/local`, ядро не трогать, перед сдачей — `check-conventions`.

Важно: SEO распределён по нескольким модулям — **sitemap/robots** это модуль `seo`; **мета-теги (title/description/keywords) товаров и разделов** — это `iblock` (наследуемые свойства), вывод и микроразметка — шаблоны компонентов; **коды ответа/404 и композит** — модуль `main`; **умный фильтр** — `catalog`/`iblock`. Неочевидные грабли вынесены в рецепты 06–09.

## Среда
- «только файлы» → создавай файлы/код + инструкцию; «живой Битрикс» → можно выполнить и проверить.

## Задача → рецепт (читай из `../../shared/kb/recipes/seo/`)
- карта сайта `sitemap.xml` → `seo/01-sitemap.md`
- `robots.txt` → `seo/02-robots.md`
- мета-шаблоны (title/description/keywords разделов и элементов) → `seo/03-meta-templates.md`
- ЧПУ/SEF, 301-редиректы, canonical → `seo/04-sef-redirects-canonical.md`
- Open Graph + микроразметка schema.org (Product, FAQPage, Organization, LocalBusiness, Article) → `seo/05-opengraph-schema.md`
- дубли страниц, soft-404 и коды ответа, Clean-param, noindex/X-Robots-Tag → `seo/06-duplicates-response-codes.md`
- SEO умного фильтра (catalog.smart.filter: SEF, посадочные, индексация) → `seo/07-smart-filter-seo.md`
- скорость и Core Web Vitals (композит, кэш, CDN, картинки, perfmon) → `seo/08-speed-core-web-vitals.md`
- пагинация (canonical-стратегия, ЧПУ страниц, rel next/prev) → `seo/09-pagination.md`
- hreflang, мультиязычность и мультирегиональность (языки vs города, x-default) → `seo/10-hreflang-multilang.md`

## База знаний
SEO-строки в `../../shared/kb/api-map.md`; общая модель — `../../shared/kb/00-overview.md`. ЧПУ компонента настраивается в `1c-bitrix-cms-content` (рецепт комплексного компонента).

## Завершение
`../../shared/scripts/check-conventions.sh <каталог_проекта>`
