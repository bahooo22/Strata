# Приложение к сводному отчёту: семейство `windows-ladder`

Единая таблица по всем записям этого семейства: медиана и разброс pp, медиана tg, число повторов, длина промпта и путь первичника. Строки, где промпт короче 1024 токенов, помечены «pp неканон»: такой pp не сравнивается со значениями сетки.

Первичники: `stock-strata-*.jsonl` в `artifacts\benchmarks` — файлов: 6, записей: 6, из них с pp/tg в JSONL: 6. Модель в этом семействе в JSONL не записана — она различима по имени первичника (последняя колонка).

| окно | модель и параметры | медиана pp | разброс pp | медиана tg | повторов | промпт, токенов | первичник |
| --- | ---: | ---: | ---: | ---: | --- | --- | --- |
| 16k | grid | 123.2 | — | 15.1 | 1 | prompt_n=— | artifacts/benchmarks/stock-strata-16384-grid.jsonl |
| 24k | grid | 123.2 | — | 12.4 | 1 | prompt_n=— | artifacts/benchmarks/stock-strata-24576-grid.jsonl |
| 2k | grid | 109.6 | — | 19.9 | 1 | prompt_n=— | artifacts/benchmarks/stock-strata-2048-grid.jsonl |
| 32k | grid | 123.1 | — | 11.3 | 1 | prompt_n=— | artifacts/benchmarks/stock-strata-32768-grid.jsonl |
| 4k | grid | 125.9 | — | 19.5 | 1 | prompt_n=— | artifacts/benchmarks/stock-strata-4096-grid.jsonl |
| 8k | grid | 124.8 | — | 17.6 | 1 | prompt_n=— | artifacts/benchmarks/stock-strata-8192-grid.jsonl |
