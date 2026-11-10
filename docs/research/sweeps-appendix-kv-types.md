# Appendix to the full measurement report: `kv-types` family

One table over every record in the family: median and spread of pp, median tg, repeat count, prompt length and the primary-source path. Rows whose prompt is shorter than 1024 tokens are marked "non-canonical pp": such pp is not comparable with the grid.

Sources: `sweep-iq4xs-kv*.jsonl`, `sweep-iq4xs-q8*.jsonl` under `artifacts\benchmarks` — files: 3, records: 23, of them carrying pp/tg in JSONL: 23.

| window | model and parameters | median pp | pp spread | median tg | repeats | prompt tokens | source |
| --- | ---: | ---: | ---: | ---: | --- | --- | --- |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ctk=q4_0 ctv=q4_0 | 491.1 | — | 31.2 | 1 | prompt_n=4 · pp off-canon: prompt shorter than 1024 tokens | artifacts/benchmarks/sweep-iq4xs-kv3.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ctk=q4_0 ctv=q5_1 | 484.0 | — | 31.0 | 1 | prompt_n=4 · pp off-canon: prompt shorter than 1024 tokens | artifacts/benchmarks/sweep-iq4xs-kv3.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ctk=q4_0 ctv=q8_0 | 482.9 | — | 31.0 | 1 | prompt_n=4 · pp off-canon: prompt shorter than 1024 tokens | artifacts/benchmarks/sweep-iq4xs-kv3.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ctk=q5_1 ctv=q4_0 | 490.2 | — | 30.2 | 1 | prompt_n=4 · pp off-canon: prompt shorter than 1024 tokens | artifacts/benchmarks/sweep-iq4xs-kv3.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ctk=q5_1 ctv=q5_1 | 428.0 | — | 28.5 | 1 | prompt_n=4 · pp off-canon: prompt shorter than 1024 tokens | artifacts/benchmarks/sweep-iq4xs-kv.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ctk=q5_1 ctv=q5_1 | 499.7 | — | 30.3 | 1 | prompt_n=4 · pp off-canon: prompt shorter than 1024 tokens | artifacts/benchmarks/sweep-iq4xs-kv3.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ctk=q5_1 ctv=q8_0 | 279.6 | — | 27.4 | 1 | prompt_n=4 · pp off-canon: prompt shorter than 1024 tokens | artifacts/benchmarks/sweep-iq4xs-kv.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ctk=q5_1 ctv=q8_0 | 362.4 | — | 30.2 | 1 | prompt_n=4 · pp off-canon: prompt shorter than 1024 tokens | artifacts/benchmarks/sweep-iq4xs-kv3.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ctk=q8_0 ctv=q4_0 | 399.9 | — | 26.2 | 1 | prompt_n=4 · pp off-canon: prompt shorter than 1024 tokens | artifacts/benchmarks/sweep-iq4xs-kv.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ctk=q8_0 ctv=q4_0 | 480.8 | — | 29.1 | 1 | prompt_n=4 · pp off-canon: prompt shorter than 1024 tokens | artifacts/benchmarks/sweep-iq4xs-kv3.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ctk=q8_0 ctv=q5_1 | 317.9 | — | 28.3 | 1 | prompt_n=4 · pp off-canon: prompt shorter than 1024 tokens | artifacts/benchmarks/sweep-iq4xs-kv.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ctk=q8_0 ctv=q5_1 | 363.0 | — | 28.9 | 1 | prompt_n=4 · pp off-canon: prompt shorter than 1024 tokens | artifacts/benchmarks/sweep-iq4xs-kv3.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ctk=q8_0 ctv=q8_0 | 319.3 | — | 27.2 | 1 | prompt_n=4 · pp off-canon: prompt shorter than 1024 tokens | artifacts/benchmarks/sweep-iq4xs-kv.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ctk=q8_0 ctv=q8_0 | 356.9 | — | 27.8 | 1 | prompt_n=4 · pp off-canon: prompt shorter than 1024 tokens | artifacts/benchmarks/sweep-iq4xs-kv3.jsonl |
| 46k | Qwen3.6-35B-A3B-uncensored-HauhauC · ctk=q8_0 ctv=q8_0 | 262.7 | 51.0-407.6 | 22.1 | 9 | prompt_n=4 · pp off-canon: prompt shorter than 1024 tokens | artifacts/benchmarks/sweep-iq4xs-q8.jsonl |
