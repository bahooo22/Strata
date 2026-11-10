# Appendix to the full measurement report: `grid-llama` family

One table over every record in the family: median and spread of pp, median tg, repeat count, prompt length and the primary-source path. Rows whose prompt is shorter than 1024 tokens are marked "non-canonical pp": such pp is not comparable with the grid.

Sources: `grid-heretic-q4km-2026-11-10.jsonl`, `grid-hauhaucs-iq4xs-2026-11-10.jsonl` under `artifacts\benchmarks` — files: 2, records: 20, of them carrying pp/tg in JSONL: 20. The model is not recorded in JSONL for this family — it is distinguishable only by the source file name (last column).

| window | model and parameters | median pp | pp spread | median tg | repeats | prompt tokens | source |
| --- | ---: | ---: | ---: | ---: | --- | --- | --- |
| 128k | hauhaucs-iq4xs-128k-p1 · ncmoe=33 ub=8192 tb=8 np=1 grid | 856.4 | — | 18.6 | 1 | prompt_n=121777 | artifacts/benchmarks/grid-hauhaucs-iq4xs-2026-11-10.jsonl |
| 128k | hauhaucs-iq4xs-128k-p2 · ncmoe=33 ub=8192 tb=8 np=1 grid | 854.8 | — | 18.8 | 1 | prompt_n=121777 | artifacts/benchmarks/grid-hauhaucs-iq4xs-2026-11-10.jsonl |
| 128k | heretic-q4km-128k-p1 · ncmoe=33 ub=8192 tb=8 np=1 grid | 793.7 | — | 18.0 | 1 | prompt_n=121777 | artifacts/benchmarks/grid-heretic-q4km-2026-11-10.jsonl |
| 128k | heretic-q4km-128k-p2 · ncmoe=33 ub=8192 tb=8 np=1 grid | 792.7 | — | 18.9 | 1 | prompt_n=121777 | artifacts/benchmarks/grid-heretic-q4km-2026-11-10.jsonl |
| 160k | hauhaucs-iq4xs-160k-p1 · ncmoe=33 ub=8192 tb=8 np=1 grid | 832.7 | — | 18.1 | 1 | prompt_n=139262 | artifacts/benchmarks/grid-hauhaucs-iq4xs-2026-11-10.jsonl |
| 160k | hauhaucs-iq4xs-160k-p2 · ncmoe=33 ub=8192 tb=8 np=1 grid | 830.0 | — | 17.9 | 1 | prompt_n=139262 | artifacts/benchmarks/grid-hauhaucs-iq4xs-2026-11-10.jsonl |
| 160k | heretic-q4km-160k-p1 · ncmoe=33 ub=8192 tb=8 np=1 grid | 766.1 | — | 18.2 | 1 | prompt_n=139262 | artifacts/benchmarks/grid-heretic-q4km-2026-11-10.jsonl |
| 160k | heretic-q4km-160k-p2 · ncmoe=33 ub=8192 tb=8 np=1 grid | 766.4 | — | 17.9 | 1 | prompt_n=139262 | artifacts/benchmarks/grid-heretic-q4km-2026-11-10.jsonl |
| 64k | hauhaucs-iq4xs-64k-p1 · ncmoe=33 ub=2048 tb=8 np=1 grid | 963.5 | — | 20.5 | 1 | prompt_n=64641 | artifacts/benchmarks/grid-hauhaucs-iq4xs-2026-11-10.jsonl |
| 64k | hauhaucs-iq4xs-64k-p2 · ncmoe=33 ub=2048 tb=8 np=1 grid | 975.8 | — | 19.8 | 1 | prompt_n=64641 | artifacts/benchmarks/grid-hauhaucs-iq4xs-2026-11-10.jsonl |
| 64k | heretic-q4km-64k-p1 · ncmoe=33 ub=2048 tb=8 np=1 grid | 874.5 | — | 18.4 | 1 | prompt_n=64641 | artifacts/benchmarks/grid-heretic-q4km-2026-11-10.jsonl |
| 64k | heretic-q4km-64k-p2 · ncmoe=33 ub=2048 tb=8 np=1 grid | 879.0 | — | 19.9 | 1 | prompt_n=64641 | artifacts/benchmarks/grid-heretic-q4km-2026-11-10.jsonl |
| 80k | hauhaucs-iq4xs-80k-p1 · ncmoe=33 ub=2048 tb=8 np=1 grid | 936.9 | — | 19.4 | 1 | prompt_n=77350 | artifacts/benchmarks/grid-hauhaucs-iq4xs-2026-11-10.jsonl |
| 80k | hauhaucs-iq4xs-80k-p2 · ncmoe=33 ub=2048 tb=8 np=1 grid | 936.8 | — | 19.2 | 1 | prompt_n=77350 | artifacts/benchmarks/grid-hauhaucs-iq4xs-2026-11-10.jsonl |
| 80k | heretic-q4km-80k-p1 · ncmoe=33 ub=2048 tb=8 np=1 grid | 855.7 | — | 19.3 | 1 | prompt_n=77350 | artifacts/benchmarks/grid-heretic-q4km-2026-11-10.jsonl |
| 80k | heretic-q4km-80k-p2 · ncmoe=33 ub=2048 tb=8 np=1 grid | 853.7 | — | 19.5 | 1 | prompt_n=77350 | artifacts/benchmarks/grid-heretic-q4km-2026-11-10.jsonl |
| 96k | hauhaucs-iq4xs-96k-p1 · ncmoe=33 ub=8192 tb=8 np=1 grid | 909.5 | — | 19.2 | 1 | prompt_n=86558 | artifacts/benchmarks/grid-hauhaucs-iq4xs-2026-11-10.jsonl |
| 96k | hauhaucs-iq4xs-96k-p2 · ncmoe=33 ub=8192 tb=8 np=1 grid | 908.9 | — | 19.2 | 1 | prompt_n=86558 | artifacts/benchmarks/grid-hauhaucs-iq4xs-2026-11-10.jsonl |
| 96k | heretic-q4km-96k-p1 · ncmoe=33 ub=8192 tb=8 np=1 grid | 840.0 | — | 19.7 | 1 | prompt_n=86558 | artifacts/benchmarks/grid-heretic-q4km-2026-11-10.jsonl |
| 96k | heretic-q4km-96k-p2 · ncmoe=33 ub=8192 tb=8 np=1 grid | 845.1 | — | 19.7 | 1 | prompt_n=86558 | artifacts/benchmarks/grid-heretic-q4km-2026-11-10.jsonl |
