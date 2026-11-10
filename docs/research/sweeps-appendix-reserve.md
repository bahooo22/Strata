# Appendix to the full measurement report: `reserve` family

One table over every record in the family: median and spread of pp, median tg, repeat count, prompt length and the primary-source path. Rows whose prompt is shorter than 1024 tokens are marked "non-canonical pp": such pp is not comparable with the grid.

Sources: `strata-window-*.jsonl` under `artifacts\benchmarks` — files: 16, records: 38, of them carrying pp/tg in JSONL: 38. The model is not recorded in JSONL for this family — it is distinguishable only by the source file name (last column).

| window | model and parameters | median pp | pp spread | median tg | repeats | prompt tokens | source |
| --- | ---: | ---: | ---: | ---: | --- | --- | --- |
| 16k | reserve=768 | 173.1 | — | 32.7 | 1 | prompt_n=— | artifacts/benchmarks/strata-window-reserve768.jsonl |
| 16k | reserve=768 fp32 mtp0 | 169.8 | — | 34.2 | 1 | prompt_n=— | artifacts/benchmarks/strata-window-reserve768-fp32-mtp0-KAT-Coder-V2.5-Dev-3.jsonl |
| 16k | reserve=768 mtp0 q4_0 | 170.8 | — | 39.8 | 1 | prompt_n=— | artifacts/benchmarks/strata-window-reserve768-q4_0-mtp0-KAT-Coder-V2.5-Dev-3.jsonl |
| 16k | reserve=768 mtp0 q5_0 | 166.3 | — | 38.3 | 1 | prompt_n=— | artifacts/benchmarks/strata-window-reserve768-q5_0-mtp0-KAT-Coder-V2.5-Dev-3.jsonl |
| 16k | reserve=768 mtp0 q5_1 | 164.3 | — | 38.1 | 1 | prompt_n=— | artifacts/benchmarks/strata-window-reserve768-q5_1-mtp0-KAT-Coder-V2.5-Dev-3.jsonl |
| 16k | reserve=768 mtp0 q8_0 | 154.0 | 121.2-175.0 | 31.9 | 3 | prompt_n=— | artifacts/benchmarks/strata-window-reserve768-q8_0-mtp0-KAT-Coder-V2.5-Dev-3.jsonl |
| 16k | reserve=768 mtp0 q8_0 | 129.6 | — | 27.6 | 1 | prompt_n=— | artifacts/benchmarks/strata-window-reserve768-q8_0-mtp0-Qwen3.6-35B-A3B-unce.jsonl |
| 16k | reserve=768 mtp0 q8_0 | 157.9 | — | 25.9 | 1 | prompt_n=— | artifacts/benchmarks/strata-window-reserve768-q8_0-mtp0.jsonl |
| 16k | reserve=768 mtp1 q4_0 | 175.3 | — | 40.8 | 1 | prompt_n=— | artifacts/benchmarks/strata-window-reserve768-q4_0-mtp1-KAT-Coder-V2.5-Dev-3.jsonl |
| 16k | reserve=768 mtp2 q4_0 | 175.2 | 175.1-176.1 | 42.0 | 3 | prompt_n=— | artifacts/benchmarks/strata-window-reserve768-q4_0-mtp2-KAT-Coder-V2.5-Dev-3.jsonl |
| 16k | reserve=768 mtp2 q8_0 | 155.6 | — | 33.9 | 1 | prompt_n=— | artifacts/benchmarks/strata-window-reserve768-q8_0-mtp2-KAT-Coder-V2.5-Dev-3.jsonl |
| 16k | reserve=768 mtp2 q8_0 | 124.3 | — | 26.0 | 1 | prompt_n=— | artifacts/benchmarks/strata-window-reserve768-q8_0-mtp2-Qwen3.6-35B-A3B-unce.jsonl |
| 16k | reserve=768 mtp2 q8_0 | 150.5 | — | 27.7 | 1 | prompt_n=— | artifacts/benchmarks/strata-window-reserve768-q8_0-mtp2.jsonl |
| 16k | reserve=768 mtp3 q4_0 | 174.0 | — | 41.0 | 1 | prompt_n=— | artifacts/benchmarks/strata-window-reserve768-q4_0-mtp3-KAT-Coder-V2.5-Dev-3.jsonl |
| 16k | reserve=768 q8_0 | 170.8 | — | 29.8 | 1 | prompt_n=— | artifacts/benchmarks/strata-window-reserve768-q8_0.jsonl |
| 24k | reserve=768 | 162.8 | — | 28.5 | 1 | prompt_n=— | artifacts/benchmarks/strata-window-reserve768.jsonl |
| 24k | reserve=768 mtp0 q4_0 | 127.3 | — | 27.9 | 1 | prompt_n=— | artifacts/benchmarks/strata-window-reserve768-q4_0-mtp0-Qwen3.6-35B-A3B-unce.jsonl |
| 24k | reserve=768 mtp2 q4_0 | 175.4 | — | 41.3 | 1 | prompt_n=— | artifacts/benchmarks/strata-window-reserve768-q4_0-mtp2-KAT-Coder-V2.5-Dev-3.jsonl |
| 2k | reserve=768 | 124.4 | — | 33.0 | 1 | prompt_n=— | artifacts/benchmarks/strata-window-reserve768.jsonl |
| 32k | reserve=768 | 168.7 | — | 27.6 | 1 | prompt_n=— | artifacts/benchmarks/strata-window-reserve768.jsonl |
| 32k | reserve=768 mtp0 q4_0 | 133.7 | — | 28.3 | 1 | prompt_n=— | artifacts/benchmarks/strata-window-reserve768-q4_0-mtp0-Qwen3.6-35B-A3B-unce.jsonl |
| 32k | reserve=768 mtp2 q4_0 | 168.4 | — | 39.7 | 1 | prompt_n=— | artifacts/benchmarks/strata-window-reserve768-q4_0-mtp2-KAT-Coder-V2.5-Dev-3.jsonl |
| 32k | reserve=768 q8_0 | 167.1 | — | 32.8 | 1 | prompt_n=— | artifacts/benchmarks/strata-window-reserve768-q8_0.jsonl |
| 46k | reserve=768 fp32 mtp0 | 151.6 | — | 20.5 | 1 | prompt_n=— | artifacts/benchmarks/strata-window-reserve768-fp32-mtp0-KAT-Coder-V2.5-Dev-3.jsonl |
| 46k | reserve=768 mtp0 q4_0 | 150.2 | 137.3-163.1 | 30.8 | 2 | prompt_n=— | artifacts/benchmarks/strata-window-reserve768-q4_0-mtp0-KAT-Coder-V2.5-Dev-3.jsonl |
| 46k | reserve=768 mtp0 q4_0 | 136.5 | — | 28.2 | 1 | prompt_n=— | artifacts/benchmarks/strata-window-reserve768-q4_0-mtp0-Qwen3.6-35B-A3B-unce.jsonl |
| 46k | reserve=768 mtp0 q5_0 | 168.5 | — | 35.6 | 1 | prompt_n=— | artifacts/benchmarks/strata-window-reserve768-q5_0-mtp0-KAT-Coder-V2.5-Dev-3.jsonl |
| 46k | reserve=768 mtp0 q5_1 | 163.3 | — | 33.6 | 1 | prompt_n=— | artifacts/benchmarks/strata-window-reserve768-q5_1-mtp0-KAT-Coder-V2.5-Dev-3.jsonl |
| 46k | reserve=768 mtp0 q8_0 | 161.6 | — | 33.9 | 1 | prompt_n=— | artifacts/benchmarks/strata-window-reserve768-q8_0-mtp0-KAT-Coder-V2.5-Dev-3.jsonl |
| 46k | reserve=768 mtp2 q4_0 | 174.2 | — | 38.9 | 1 | prompt_n=— | artifacts/benchmarks/strata-window-reserve768-q4_0-mtp2-KAT-Coder-V2.5-Dev-3.jsonl |
| 46k | reserve=768 q8_0 | 168.6 | — | 33.2 | 1 | prompt_n=— | artifacts/benchmarks/strata-window-reserve768-q8_0.jsonl |
| 4k | reserve=768 | 163.0 | — | 32.4 | 1 | prompt_n=— | artifacts/benchmarks/strata-window-reserve768.jsonl |
| 64k | reserve=768 mtp0 q4_0 | 170.5 | — | 33.4 | 1 | prompt_n=— | artifacts/benchmarks/strata-window-reserve768-q4_0-mtp0-KAT-Coder-V2.5-Dev-3.jsonl |
