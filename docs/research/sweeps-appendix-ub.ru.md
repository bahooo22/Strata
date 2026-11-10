# Приложение к сводному отчёту: семейство `ub`

Единая таблица по всем записям этого семейства: медиана и разброс pp, медиана tg, число повторов, длина промпта и путь первичника. Строки, где промпт короче 1024 токенов, помечены «pp неканон»: такой pp не сравнивается со значениями сетки.

Первичники: `sweep-matrix*.jsonl` в `artifacts\benchmarks` — файлов: 2, записей: 100, из них с pp/tg в JSONL: 100.

| окно | модель и параметры | медиана pp | разброс pp | медиана tg | повторов | промпт, токенов | первичник |
| --- | ---: | ---: | ---: | ---: | --- | --- | --- |
| 16k | Huihui-Qwen3-Coder-30B-A3B-Instruc · ub=512 b=2048 ncmoe=32 | 545.6 | 507.0-563.2 | 17.8 | 16 | prompt_n=1 · pp неканон: промпт короче 1024 токенов | artifacts/benchmarks/sweep-matrix-qwen3moe.jsonl |
| 16k | Qwen3.6-35B-A3B-uncensored-HauhauC · ub=512 b=2048 ncmoe=26 | 486.2 | 470.0-502.6 | 30.8 | 20 | prompt_n=4 · pp неканон: промпт короче 1024 токенов | artifacts/benchmarks/sweep-matrix.jsonl |
| 24k | Huihui-Qwen3-Coder-30B-A3B-Instruc · ub=512 b=2048 ncmoe=32 | 538.0 | 252.3-558.8 | 17.3 | 16 | prompt_n=1 · pp неканон: промпт короче 1024 токенов | artifacts/benchmarks/sweep-matrix-qwen3moe.jsonl |
| 24k | Qwen3.6-35B-A3B-uncensored-HauhauC · ub=512 b=2048 ncmoe=26 | 487.3 | 483.9-500.7 | 30.8 | 16 | prompt_n=4 · pp неканон: промпт короче 1024 токенов | artifacts/benchmarks/sweep-matrix.jsonl |
| 32k | Huihui-Qwen3-Coder-30B-A3B-Instruc · ub=512 b=2048 ncmoe=32 | 448.6 | 74.2-543.5 | 16.8 | 16 | prompt_n=1 · pp неканон: промпт короче 1024 токенов | artifacts/benchmarks/sweep-matrix-qwen3moe.jsonl |
| 32k | Qwen3.6-35B-A3B-uncensored-HauhauC · ub=512 b=2048 ncmoe=26 | 487.8 | 481.3-497.9 | 30.9 | 16 | prompt_n=4 · pp неканон: промпт короче 1024 токенов | artifacts/benchmarks/sweep-matrix.jsonl |
