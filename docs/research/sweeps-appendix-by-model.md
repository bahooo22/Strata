# Appendix to the full measurement report: `by-model` family

One table over every record in the family: median and spread of pp, median tg, repeat count, prompt length and the primary-source path. Rows whose prompt is shorter than 1024 tokens are marked "non-canonical pp": such pp is not comparable with the grid.

Sources: `sweep-coder30b*.jsonl`, `sweep-heretic-q4km.jsonl`, `sweep-hauhau-q4km.jsonl` under `artifacts\benchmarks` — files: 4, records: 8, of them carrying pp/tg in JSONL: 8.

| window | model and parameters | median pp | pp spread | median tg | repeats | prompt tokens | source |
| --- | ---: | ---: | ---: | ---: | --- | --- | --- |
| 46k | Huihui-Qwen3-Coder-30B-A3B-Instruc · ub=512 b=2048 ncmoe=26 | 83.4 | — | 6.6 | 1 | prompt_n=1 · pp off-canon: prompt shorter than 1024 tokens | artifacts/benchmarks/sweep-coder30b.jsonl |
| 46k | Huihui-Qwen3-Coder-30B-A3B-Instruc · ub=512 b=2048 ncmoe=32 | 225.0 | — | 17.7 | 1 | prompt_n=1 · pp off-canon: prompt shorter than 1024 tokens | artifacts/benchmarks/sweep-coder30b.jsonl |
| 46k | Huihui-Qwen3-Coder-30B-A3B-Instruc · ub=512 b=2048 ncmoe=36 | 480.0 | — | 16.6 | 1 | prompt_n=1 · pp off-canon: prompt shorter than 1024 tokens | artifacts/benchmarks/sweep-coder30b40.jsonl |
| 46k | Huihui-Qwen3-Coder-30B-A3B-Instruc · ub=512 b=2048 ncmoe=40 | 443.6 | — | 15.0 | 1 | prompt_n=1 · pp off-canon: prompt shorter than 1024 tokens | artifacts/benchmarks/sweep-coder30b40.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ub=512 b=2048 ncmoe=26 | 48.8 | — | 13.5 | 1 | prompt_n=4 · pp off-canon: prompt shorter than 1024 tokens | artifacts/benchmarks/sweep-hauhau-q4km.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ub=512 b=2048 ncmoe=32 | 382.9 | — | 25.3 | 1 | prompt_n=4 · pp off-canon: prompt shorter than 1024 tokens | artifacts/benchmarks/sweep-hauhau-q4km.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-heretic · ub=512 b=2048 ncmoe=28 | 325.0 | — | 28.4 | 1 | prompt_n=4 · pp off-canon: prompt shorter than 1024 tokens | artifacts/benchmarks/sweep-heretic-q4km.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-heretic · ub=512 b=2048 ncmoe=32 | 377.4 | — | 25.3 | 1 | prompt_n=4 · pp off-canon: prompt shorter than 1024 tokens | artifacts/benchmarks/sweep-heretic-q4km.jsonl |
