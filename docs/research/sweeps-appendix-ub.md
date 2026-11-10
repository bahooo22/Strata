# Appendix to the full measurement report: `ub` family

One table over every record in the family: median and spread of pp, median tg, repeat count, prompt length and the primary-source path. Rows whose prompt is shorter than 1024 tokens are marked "non-canonical pp": such pp is not comparable with the grid.

Sources: `sweep-matrix*.jsonl` under `artifacts\benchmarks` — files: 2, records: 100, of them carrying pp/tg in JSONL: 100.

| window | model and parameters | median pp | pp spread | median tg | repeats | prompt tokens | source |
| --- | ---: | ---: | ---: | ---: | --- | --- | --- |
| 16k | Huihui-Qwen3-Coder-30B-A3B-Instruc · ub=512 b=2048 ncmoe=32 | 545.6 | 507.0-563.2 | 17.8 | 16 | prompt_n=1 · pp off-canon: prompt shorter than 1024 tokens | artifacts/benchmarks/sweep-matrix-qwen3moe.jsonl |
| 16k | Qwen3.6-35B-A3B-uncensored-HauhauC · ub=512 b=2048 ncmoe=26 | 486.2 | 470.0-502.6 | 30.8 | 20 | prompt_n=4 · pp off-canon: prompt shorter than 1024 tokens | artifacts/benchmarks/sweep-matrix.jsonl |
| 24k | Huihui-Qwen3-Coder-30B-A3B-Instruc · ub=512 b=2048 ncmoe=32 | 538.0 | 252.3-558.8 | 17.3 | 16 | prompt_n=1 · pp off-canon: prompt shorter than 1024 tokens | artifacts/benchmarks/sweep-matrix-qwen3moe.jsonl |
| 24k | Qwen3.6-35B-A3B-uncensored-HauhauC · ub=512 b=2048 ncmoe=26 | 487.3 | 483.9-500.7 | 30.8 | 16 | prompt_n=4 · pp off-canon: prompt shorter than 1024 tokens | artifacts/benchmarks/sweep-matrix.jsonl |
| 32k | Huihui-Qwen3-Coder-30B-A3B-Instruc · ub=512 b=2048 ncmoe=32 | 448.6 | 74.2-543.5 | 16.8 | 16 | prompt_n=1 · pp off-canon: prompt shorter than 1024 tokens | artifacts/benchmarks/sweep-matrix-qwen3moe.jsonl |
| 32k | Qwen3.6-35B-A3B-uncensored-HauhauC · ub=512 b=2048 ncmoe=26 | 487.8 | 481.3-497.9 | 30.9 | 16 | prompt_n=4 · pp off-canon: prompt shorter than 1024 tokens | artifacts/benchmarks/sweep-matrix.jsonl |
