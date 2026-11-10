# Приложение к сводному отчёту: семейство `stock`

Единая таблица по всем записям этого семейства: медиана и разброс pp, медиана tg, число повторов, длина промпта и путь первичника. Строки, где промпт короче 1024 токенов, помечены «pp неканон»: такой pp не сравнивается со значениями сетки.

Первичники: `stock-llama-*.jsonl` в `artifacts\benchmarks` — файлов: 7, записей: 8, из них с pp/tg в JSONL: 8. Модель в этом семействе в JSONL не записана — она различима по имени первичника (последняя колонка).

| окно | модель и параметры | медиана pp | разброс pp | медиана tg | повторов | промпт, токенов | первичник |
| --- | ---: | ---: | ---: | ---: | --- | --- | --- |
| 128k | stock-gpu | 598.3 | — | 7.0 | 1 | prompt_n=— | artifacts/benchmarks/stock-llama-131072-stock-gpu.jsonl |
| 160k | stock-gpu | 573.7 | — | 6.7 | 1 | prompt_n=— | artifacts/benchmarks/stock-llama-163840-stock-gpu.jsonl |
| 32k | stock-cpu | 344.5 | — | 7.4 | 1 | prompt_n=— | artifacts/benchmarks/stock-llama-32768-stock-cpu.jsonl |
| 64k | stock-gpu | 641.8 | 639.3-644.2 | 7.9 | 2 | prompt_n=— | artifacts/benchmarks/stock-llama-65536-stock-gpu.jsonl |
| 80k | stock-gpu | 632.3 | — | 7.7 | 1 | prompt_n=— | artifacts/benchmarks/stock-llama-81920-stock-gpu.jsonl |
| 8k | stock-cpu | 350.7 | — | 7.8 | 1 | prompt_n=— | artifacts/benchmarks/stock-llama-8192-stock-cpu.jsonl |
| 96k | stock-gpu | 619.9 | — | 7.5 | 1 | prompt_n=— | artifacts/benchmarks/stock-llama-98304-stock-gpu.jsonl |
