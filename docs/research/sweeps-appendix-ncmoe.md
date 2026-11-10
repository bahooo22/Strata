# Appendix to the full measurement report: `ncmoe` family

One table over every record in the family: median and spread of pp, median tg, repeat count, prompt length and the primary-source path. Rows whose prompt is shorter than 1024 tokens are marked "non-canonical pp": such pp is not comparable with the grid.

Sources: `sweep-iq4xs-ncmoe*.jsonl` under `artifacts\benchmarks` — files: 1, records: 9, of them carrying pp/tg in JSONL: 9.

| window | model and parameters | median pp | pp spread | median tg | repeats | prompt tokens | source |
| --- | ---: | ---: | ---: | ---: | --- | --- | --- |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ncmoe=24 ub=512 b=2048 | 48.3 | — | 14.2 | 1 | prompt_n=4 · pp off-canon: prompt shorter than 1024 tokens | artifacts/benchmarks/sweep-iq4xs-ncmoe3.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ncmoe=26 ub=512 b=2048 | 484.6 | — | 30.9 | 1 | prompt_n=4 · pp off-canon: prompt shorter than 1024 tokens | artifacts/benchmarks/sweep-iq4xs-ncmoe3.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ncmoe=28 ub=512 b=2048 | 462.2 | — | 29.0 | 1 | prompt_n=4 · pp off-canon: prompt shorter than 1024 tokens | artifacts/benchmarks/sweep-iq4xs-ncmoe3.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ncmoe=30 ub=512 b=2048 | 430.5 | — | 27.2 | 1 | prompt_n=4 · pp off-canon: prompt shorter than 1024 tokens | artifacts/benchmarks/sweep-iq4xs-ncmoe3.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ncmoe=32 ub=512 b=2048 | 410.8 | — | 25.1 | 1 | prompt_n=4 · pp off-canon: prompt shorter than 1024 tokens | artifacts/benchmarks/sweep-iq4xs-ncmoe3.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ncmoe=34 ub=512 b=2048 | 401.2 | — | 24.5 | 1 | prompt_n=4 · pp off-canon: prompt shorter than 1024 tokens | artifacts/benchmarks/sweep-iq4xs-ncmoe3.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ncmoe=36 ub=512 b=2048 | 384.9 | — | 23.4 | 1 | prompt_n=4 · pp off-canon: prompt shorter than 1024 tokens | artifacts/benchmarks/sweep-iq4xs-ncmoe3.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ncmoe=38 ub=512 b=2048 | 243.7 | — | 21.3 | 1 | prompt_n=4 · pp off-canon: prompt shorter than 1024 tokens | artifacts/benchmarks/sweep-iq4xs-ncmoe3.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ncmoe=40 ub=512 b=2048 | 235.1 | — | 20.7 | 1 | prompt_n=4 · pp off-canon: prompt shorter than 1024 tokens | artifacts/benchmarks/sweep-iq4xs-ncmoe3.jsonl |
