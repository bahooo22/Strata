# Appendix to the full measurement report: `windows-ladder` family

One table over every record in the family: median and spread of pp, median tg, repeat count, prompt length and the primary-source path. Rows whose prompt is shorter than 1024 tokens are marked "non-canonical pp": such pp is not comparable with the grid.

Sources: `stock-strata-*.jsonl` under `artifacts\benchmarks` — files: 6, records: 6, of them carrying pp/tg in JSONL: 6. The model is not recorded in JSONL for this family — it is distinguishable only by the source file name (last column).

| window | model and parameters | median pp | pp spread | median tg | repeats | prompt tokens | source |
| --- | ---: | ---: | ---: | ---: | --- | --- | --- |
| 16k | grid | 123.2 | — | 15.1 | 1 | prompt_n=— | artifacts/benchmarks/stock-strata-16384-grid.jsonl |
| 24k | grid | 123.2 | — | 12.4 | 1 | prompt_n=— | artifacts/benchmarks/stock-strata-24576-grid.jsonl |
| 2k | grid | 109.6 | — | 19.9 | 1 | prompt_n=— | artifacts/benchmarks/stock-strata-2048-grid.jsonl |
| 32k | grid | 123.1 | — | 11.3 | 1 | prompt_n=— | artifacts/benchmarks/stock-strata-32768-grid.jsonl |
| 4k | grid | 125.9 | — | 19.5 | 1 | prompt_n=— | artifacts/benchmarks/stock-strata-4096-grid.jsonl |
| 8k | grid | 124.8 | — | 17.6 | 1 | prompt_n=— | artifacts/benchmarks/stock-strata-8192-grid.jsonl |
