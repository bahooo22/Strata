# Appendix to the full measurement report: `stock` family

One table over every record in the family: median and spread of pp, median tg, repeat count, prompt length and the primary-source path. Rows whose prompt is shorter than 1024 tokens are marked "non-canonical pp": such pp is not comparable with the grid.

Sources: `stock-llama-*.jsonl` under `artifacts\benchmarks` — files: 7, records: 8, of them carrying pp/tg in JSONL: 8. The model is not recorded in JSONL for this family — it is distinguishable only by the source file name (last column).

| window | model and parameters | median pp | pp spread | median tg | repeats | prompt tokens | source |
| --- | ---: | ---: | ---: | ---: | --- | --- | --- |
| 128k | stock-gpu | 598.3 | — | 7.0 | 1 | prompt_n=— | artifacts/benchmarks/stock-llama-131072-stock-gpu.jsonl |
| 160k | stock-gpu | 573.7 | — | 6.7 | 1 | prompt_n=— | artifacts/benchmarks/stock-llama-163840-stock-gpu.jsonl |
| 32k | stock-cpu | 344.5 | — | 7.4 | 1 | prompt_n=— | artifacts/benchmarks/stock-llama-32768-stock-cpu.jsonl |
| 64k | stock-gpu | 641.8 | 639.3-644.2 | 7.9 | 2 | prompt_n=— | artifacts/benchmarks/stock-llama-65536-stock-gpu.jsonl |
| 80k | stock-gpu | 632.3 | — | 7.7 | 1 | prompt_n=— | artifacts/benchmarks/stock-llama-81920-stock-gpu.jsonl |
| 8k | stock-cpu | 350.7 | — | 7.8 | 1 | prompt_n=— | artifacts/benchmarks/stock-llama-8192-stock-cpu.jsonl |
| 96k | stock-gpu | 619.9 | — | 7.5 | 1 | prompt_n=— | artifacts/benchmarks/stock-llama-98304-stock-gpu.jsonl |
