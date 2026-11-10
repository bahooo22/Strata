# Приложение к сводному отчёту: семейство `kv-types`

Единая таблица по всем записям этого семейства: медиана и разброс pp, медиана tg, число повторов, длина промпта и путь первичника. Строки, где промпт короче 1024 токенов, помечены «pp неканон»: такой pp не сравнивается со значениями сетки.

Первичники: `sweep-iq4xs-kv*.jsonl`, `sweep-iq4xs-q8*.jsonl` в `artifacts\benchmarks` — файлов: 3, записей: 23, из них с pp/tg в JSONL: 23.

| окно | модель и параметры | медиана pp | разброс pp | медиана tg | повторов | промпт, токенов | первичник |
| --- | ---: | ---: | ---: | ---: | --- | --- | --- |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ctk=q4_0 ctv=q4_0 | 491.1 | — | 31.2 | 1 | prompt_n=4 · pp неканон: промпт короче 1024 токенов | artifacts/benchmarks/sweep-iq4xs-kv3.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ctk=q4_0 ctv=q5_1 | 484.0 | — | 31.0 | 1 | prompt_n=4 · pp неканон: промпт короче 1024 токенов | artifacts/benchmarks/sweep-iq4xs-kv3.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ctk=q4_0 ctv=q8_0 | 482.9 | — | 31.0 | 1 | prompt_n=4 · pp неканон: промпт короче 1024 токенов | artifacts/benchmarks/sweep-iq4xs-kv3.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ctk=q5_1 ctv=q4_0 | 490.2 | — | 30.2 | 1 | prompt_n=4 · pp неканон: промпт короче 1024 токенов | artifacts/benchmarks/sweep-iq4xs-kv3.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ctk=q5_1 ctv=q5_1 | 428.0 | — | 28.5 | 1 | prompt_n=4 · pp неканон: промпт короче 1024 токенов | artifacts/benchmarks/sweep-iq4xs-kv.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ctk=q5_1 ctv=q5_1 | 499.7 | — | 30.3 | 1 | prompt_n=4 · pp неканон: промпт короче 1024 токенов | artifacts/benchmarks/sweep-iq4xs-kv3.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ctk=q5_1 ctv=q8_0 | 279.6 | — | 27.4 | 1 | prompt_n=4 · pp неканон: промпт короче 1024 токенов | artifacts/benchmarks/sweep-iq4xs-kv.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ctk=q5_1 ctv=q8_0 | 362.4 | — | 30.2 | 1 | prompt_n=4 · pp неканон: промпт короче 1024 токенов | artifacts/benchmarks/sweep-iq4xs-kv3.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ctk=q8_0 ctv=q4_0 | 399.9 | — | 26.2 | 1 | prompt_n=4 · pp неканон: промпт короче 1024 токенов | artifacts/benchmarks/sweep-iq4xs-kv.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ctk=q8_0 ctv=q4_0 | 480.8 | — | 29.1 | 1 | prompt_n=4 · pp неканон: промпт короче 1024 токенов | artifacts/benchmarks/sweep-iq4xs-kv3.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ctk=q8_0 ctv=q5_1 | 317.9 | — | 28.3 | 1 | prompt_n=4 · pp неканон: промпт короче 1024 токенов | artifacts/benchmarks/sweep-iq4xs-kv.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ctk=q8_0 ctv=q5_1 | 363.0 | — | 28.9 | 1 | prompt_n=4 · pp неканон: промпт короче 1024 токенов | artifacts/benchmarks/sweep-iq4xs-kv3.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ctk=q8_0 ctv=q8_0 | 319.3 | — | 27.2 | 1 | prompt_n=4 · pp неканон: промпт короче 1024 токенов | artifacts/benchmarks/sweep-iq4xs-kv.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ctk=q8_0 ctv=q8_0 | 356.9 | — | 27.8 | 1 | prompt_n=4 · pp неканон: промпт короче 1024 токенов | artifacts/benchmarks/sweep-iq4xs-kv3.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ctk=q8_0 ctv=q8_0 | 262.7 | 51.0-407.6 | 22.1 | 9 | prompt_n=4 · pp неканон: промпт короче 1024 токенов | artifacts/benchmarks/sweep-iq4xs-q8.jsonl |
