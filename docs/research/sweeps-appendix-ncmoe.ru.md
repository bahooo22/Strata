# Приложение к сводному отчёту: семейство `ncmoe`

Единая таблица по всем записям этого семейства: медиана и разброс pp, медиана tg, число повторов, длина промпта и путь первичника. Строки, где промпт короче 1024 токенов, помечены «pp неканон»: такой pp не сравнивается со значениями сетки.

Первичники: `sweep-iq4xs-ncmoe*.jsonl` в `artifacts\benchmarks` — файлов: 1, записей: 9, из них с pp/tg в JSONL: 9.

| окно | модель и параметры | медиана pp | разброс pp | медиана tg | повторов | промпт, токенов | первичник |
| --- | ---: | ---: | ---: | ---: | --- | --- | --- |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ncmoe=24 ub=512 b=2048 | 48.3 | — | 14.2 | 1 | prompt_n=4 · pp неканон: промпт короче 1024 токенов | artifacts/benchmarks/sweep-iq4xs-ncmoe3.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ncmoe=26 ub=512 b=2048 | 484.6 | — | 30.9 | 1 | prompt_n=4 · pp неканон: промпт короче 1024 токенов | artifacts/benchmarks/sweep-iq4xs-ncmoe3.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ncmoe=28 ub=512 b=2048 | 462.2 | — | 29.0 | 1 | prompt_n=4 · pp неканон: промпт короче 1024 токенов | artifacts/benchmarks/sweep-iq4xs-ncmoe3.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ncmoe=30 ub=512 b=2048 | 430.5 | — | 27.2 | 1 | prompt_n=4 · pp неканон: промпт короче 1024 токенов | artifacts/benchmarks/sweep-iq4xs-ncmoe3.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ncmoe=32 ub=512 b=2048 | 410.8 | — | 25.1 | 1 | prompt_n=4 · pp неканон: промпт короче 1024 токенов | artifacts/benchmarks/sweep-iq4xs-ncmoe3.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ncmoe=34 ub=512 b=2048 | 401.2 | — | 24.5 | 1 | prompt_n=4 · pp неканон: промпт короче 1024 токенов | artifacts/benchmarks/sweep-iq4xs-ncmoe3.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ncmoe=36 ub=512 b=2048 | 384.9 | — | 23.4 | 1 | prompt_n=4 · pp неканон: промпт короче 1024 токенов | artifacts/benchmarks/sweep-iq4xs-ncmoe3.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ncmoe=38 ub=512 b=2048 | 243.7 | — | 21.3 | 1 | prompt_n=4 · pp неканон: промпт короче 1024 токенов | artifacts/benchmarks/sweep-iq4xs-ncmoe3.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ncmoe=40 ub=512 b=2048 | 235.1 | — | 20.7 | 1 | prompt_n=4 · pp неканон: промпт короче 1024 токенов | artifacts/benchmarks/sweep-iq4xs-ncmoe3.jsonl |
