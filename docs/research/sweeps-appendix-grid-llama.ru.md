# Приложение к сводному отчёту: семейство `grid-llama`

Единая таблица по всем записям этого семейства: медиана и разброс pp, медиана tg, число повторов, длина промпта и путь первичника. Строки, где промпт короче 1024 токенов, помечены «pp неканон»: такой pp не сравнивается со значениями сетки.

Первичники: `grid-heretic-q4km-2026-11-10.jsonl`, `grid-hauhaucs-iq4xs-2026-11-10.jsonl` в `artifacts\benchmarks` — файлов: 2, записей: 20, из них с pp/tg в JSONL: 20. Модель в этом семействе в JSONL не записана — она различима по имени первичника (последняя колонка).

| окно | модель и параметры | медиана pp | разброс pp | медиана tg | повторов | промпт, токенов | первичник |
| --- | ---: | ---: | ---: | ---: | --- | --- | --- |
| 128k | hauhaucs-iq4xs-128k-p1 · ncmoe=33 ub=8192 tb=8 np=1 grid | 856.4 | — | 18.6 | 1 | prompt_n=121777 | artifacts/benchmarks/grid-hauhaucs-iq4xs-2026-11-10.jsonl |
| 128k | hauhaucs-iq4xs-128k-p2 · ncmoe=33 ub=8192 tb=8 np=1 grid | 854.8 | — | 18.8 | 1 | prompt_n=121777 | artifacts/benchmarks/grid-hauhaucs-iq4xs-2026-11-10.jsonl |
| 128k | heretic-q4km-128k-p1 · ncmoe=33 ub=8192 tb=8 np=1 grid | 793.7 | — | 18.0 | 1 | prompt_n=121777 | artifacts/benchmarks/grid-heretic-q4km-2026-11-10.jsonl |
| 128k | heretic-q4km-128k-p2 · ncmoe=33 ub=8192 tb=8 np=1 grid | 792.7 | — | 18.9 | 1 | prompt_n=121777 | artifacts/benchmarks/grid-heretic-q4km-2026-11-10.jsonl |
| 160k | hauhaucs-iq4xs-160k-p1 · ncmoe=33 ub=8192 tb=8 np=1 grid | 832.7 | — | 18.1 | 1 | prompt_n=139262 | artifacts/benchmarks/grid-hauhaucs-iq4xs-2026-11-10.jsonl |
| 160k | hauhaucs-iq4xs-160k-p2 · ncmoe=33 ub=8192 tb=8 np=1 grid | 830.0 | — | 17.9 | 1 | prompt_n=139262 | artifacts/benchmarks/grid-hauhaucs-iq4xs-2026-11-10.jsonl |
| 160k | heretic-q4km-160k-p1 · ncmoe=33 ub=8192 tb=8 np=1 grid | 766.1 | — | 18.2 | 1 | prompt_n=139262 | artifacts/benchmarks/grid-heretic-q4km-2026-11-10.jsonl |
| 160k | heretic-q4km-160k-p2 · ncmoe=33 ub=8192 tb=8 np=1 grid | 766.4 | — | 17.9 | 1 | prompt_n=139262 | artifacts/benchmarks/grid-heretic-q4km-2026-11-10.jsonl |
| 64k | hauhaucs-iq4xs-64k-p1 · ncmoe=33 ub=2048 tb=8 np=1 grid | 963.5 | — | 20.5 | 1 | prompt_n=64641 | artifacts/benchmarks/grid-hauhaucs-iq4xs-2026-11-10.jsonl |
| 64k | hauhaucs-iq4xs-64k-p2 · ncmoe=33 ub=2048 tb=8 np=1 grid | 975.8 | — | 19.8 | 1 | prompt_n=64641 | artifacts/benchmarks/grid-hauhaucs-iq4xs-2026-11-10.jsonl |
| 64k | heretic-q4km-64k-p1 · ncmoe=33 ub=2048 tb=8 np=1 grid | 874.5 | — | 18.4 | 1 | prompt_n=64641 | artifacts/benchmarks/grid-heretic-q4km-2026-11-10.jsonl |
| 64k | heretic-q4km-64k-p2 · ncmoe=33 ub=2048 tb=8 np=1 grid | 879.0 | — | 19.9 | 1 | prompt_n=64641 | artifacts/benchmarks/grid-heretic-q4km-2026-11-10.jsonl |
| 80k | hauhaucs-iq4xs-80k-p1 · ncmoe=33 ub=2048 tb=8 np=1 grid | 936.9 | — | 19.4 | 1 | prompt_n=77350 | artifacts/benchmarks/grid-hauhaucs-iq4xs-2026-11-10.jsonl |
| 80k | hauhaucs-iq4xs-80k-p2 · ncmoe=33 ub=2048 tb=8 np=1 grid | 936.8 | — | 19.2 | 1 | prompt_n=77350 | artifacts/benchmarks/grid-hauhaucs-iq4xs-2026-11-10.jsonl |
| 80k | heretic-q4km-80k-p1 · ncmoe=33 ub=2048 tb=8 np=1 grid | 855.7 | — | 19.3 | 1 | prompt_n=77350 | artifacts/benchmarks/grid-heretic-q4km-2026-11-10.jsonl |
| 80k | heretic-q4km-80k-p2 · ncmoe=33 ub=2048 tb=8 np=1 grid | 853.7 | — | 19.5 | 1 | prompt_n=77350 | artifacts/benchmarks/grid-heretic-q4km-2026-11-10.jsonl |
| 96k | hauhaucs-iq4xs-96k-p1 · ncmoe=33 ub=8192 tb=8 np=1 grid | 909.5 | — | 19.2 | 1 | prompt_n=86558 | artifacts/benchmarks/grid-hauhaucs-iq4xs-2026-11-10.jsonl |
| 96k | hauhaucs-iq4xs-96k-p2 · ncmoe=33 ub=8192 tb=8 np=1 grid | 908.9 | — | 19.2 | 1 | prompt_n=86558 | artifacts/benchmarks/grid-hauhaucs-iq4xs-2026-11-10.jsonl |
| 96k | heretic-q4km-96k-p1 · ncmoe=33 ub=8192 tb=8 np=1 grid | 840.0 | — | 19.7 | 1 | prompt_n=86558 | artifacts/benchmarks/grid-heretic-q4km-2026-11-10.jsonl |
| 96k | heretic-q4km-96k-p2 · ncmoe=33 ub=8192 tb=8 np=1 grid | 845.1 | — | 19.7 | 1 | prompt_n=86558 | artifacts/benchmarks/grid-heretic-q4km-2026-11-10.jsonl |
