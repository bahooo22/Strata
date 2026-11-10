# Приложение к сводному отчёту: семейство `by-model`

Единая таблица по всем записям этого семейства: медиана и разброс pp, медиана tg, число повторов, длина промпта и путь первичника. Строки, где промпт короче 1024 токенов, помечены «pp неканон»: такой pp не сравнивается со значениями сетки.

Первичники: `sweep-coder30b*.jsonl`, `sweep-heretic-q4km.jsonl`, `sweep-hauhau-q4km.jsonl` в `artifacts\benchmarks` — файлов: 4, записей: 8, из них с pp/tg в JSONL: 8.

| окно | модель и параметры | медиана pp | разброс pp | медиана tg | повторов | промпт, токенов | первичник |
| --- | ---: | ---: | ---: | ---: | --- | --- | --- |
| 46k | Huihui-Qwen3-Coder-30B-A3B-Instruc · ub=512 b=2048 ncmoe=26 | 83.4 | — | 6.6 | 1 | prompt_n=1 · pp неканон: промпт короче 1024 токенов | artifacts/benchmarks/sweep-coder30b.jsonl |
| 46k | Huihui-Qwen3-Coder-30B-A3B-Instruc · ub=512 b=2048 ncmoe=32 | 225.0 | — | 17.7 | 1 | prompt_n=1 · pp неканон: промпт короче 1024 токенов | artifacts/benchmarks/sweep-coder30b.jsonl |
| 46k | Huihui-Qwen3-Coder-30B-A3B-Instruc · ub=512 b=2048 ncmoe=36 | 480.0 | — | 16.6 | 1 | prompt_n=1 · pp неканон: промпт короче 1024 токенов | artifacts/benchmarks/sweep-coder30b40.jsonl |
| 46k | Huihui-Qwen3-Coder-30B-A3B-Instruc · ub=512 b=2048 ncmoe=40 | 443.6 | — | 15.0 | 1 | prompt_n=1 · pp неканон: промпт короче 1024 токенов | artifacts/benchmarks/sweep-coder30b40.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ub=512 b=2048 ncmoe=26 | 48.8 | — | 13.5 | 1 | prompt_n=4 · pp неканон: промпт короче 1024 токенов | artifacts/benchmarks/sweep-hauhau-q4km.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ub=512 b=2048 ncmoe=32 | 382.9 | — | 25.3 | 1 | prompt_n=4 · pp неканон: промпт короче 1024 токенов | artifacts/benchmarks/sweep-hauhau-q4km.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-heretic · ub=512 b=2048 ncmoe=28 | 325.0 | — | 28.4 | 1 | prompt_n=4 · pp неканон: промпт короче 1024 токенов | artifacts/benchmarks/sweep-heretic-q4km.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-heretic · ub=512 b=2048 ncmoe=32 | 377.4 | — | 25.3 | 1 | prompt_n=4 · pp неканон: промпт короче 1024 токенов | artifacts/benchmarks/sweep-heretic-q4km.jsonl |
