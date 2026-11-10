# Full measurement report on an RTX 3060 Ti 8 GiB: two forks, five windows, before and after (EN)

Russian twin: [full-measurement-report.ru.md](full-measurement-report.ru.md).
Per-fork reports: [Strata](strata-fork-report.md),
[llama.cpp](llama-fork-report.md). Raw sweeps live in the per-family appendices
(`sweeps-appendix-*.md`).

Document status: **measured only**. No number here was invented: the tables are printed by the
generator `glm\scripts\report_tables_2026-11-11.py` from the registry
`glm\2026-11-10_session\evolution-data.json` and the primary sources `artifacts\benchmarks\*.jsonl`,
and the same generator requires this document to contain every printed line exactly as printed (the
`--verify` gate). Percentages and ratios in the prose are arithmetic over the numbers of these very
tables; no other quantities appear in the text. The prose around the tables summarises what those
lines mean; where a figure is absent the text says plainly "not measured".

## 1. What is measured and how to read it

<!-- GLOSSARY -->
## What is measured

For a reader with an RTX 5080 new to these words. One machine produced everything: eight gigabytes of video memory, four CPU cores, models on a SATA SSD. Engines: llamaStrata («Страта», Russian for "the stratum") and llama.cpp pinned at ggml 3cf03257f.

### `pp` — prefill

Prompt tokens read per second while the KV cache fills; the engine prints the figure.

**Fake when:** a cold page cache — the line then describes the SATA drive, not the GPU; short prompts too.

### `tg` — decode

Answer tokens per second after the prompt; it falls as the window grows.

**Fake when:** averaged over a very short answer, whose opening runs on a small cache and looks brisker.

### TTFT

Wait from request to first token; on a long prompt, nearly all prefill.

**Fake when:** server startup is folded in and minutes of disk waiting read as model speed.

### Context window (64k/80k/96k/128k/160k)

Tokens the model holds per conversation; the rungs are set by memory, not taste.

**Fake when:** a 160k row whose KV pool spilled into system RAM, or a truncated prompt that read half the text.

### KV quant (`q4_0`/`q5_0`/`q5_1`/`q8_0`/`fp32`)

Precision of the attention keys and values: `fp32` is hungriest, `q4_0` buys room with bits, and rounding moves answers off the reference.

**Fake when:** memory saved by `q4_0` is booked as engine speed beside an `fp32` row.

### MoE and `--n-cpu-moe` (`ncmoe`)

Many experts per layer, a few active per token; the rest computes on the CPU, which `ncmoe` governs.

**Fake when:** one step of `ncmoe` and `pp` collapses by a factor of several — a profile setting, not the model.

### `-b` and `-ub`

`-b` is the logical batch, `-ub` what one kernel pass really processes.

**Fake when:** `-ub` is pushed up for `pp`: the expert slots lose that memory and the next window never starts.

### Pinned arena, CPU expert pool

RAM locked to the driver so expert weights reach the card directly; the CPU pool computes the rest.

**Fake when:** a large pinned allocation fails on Windows and drops to pageable in silence: same command, slower number.

### `super-chunk` (N=1/4/8)

The prompt is read in chapters; at N=4 a layer loads its experts every few chapters, sparing PCIe.

**Fake when:** N=4 against N=1 is called "the engine got faster" though only a profile switched; "bit-exact" holds inside one N.

### Flash attention (`FA`), tile

Attention without a score matrix for the whole prompt; the tile sets shared memory and occupancy.

**Fake when:** FA loses to the plain path on short prompts while only long rows are tabled; "bit-identical to cuBLAS" is unsayable.

### MTP drafts and the acceptance alpha

A draft head proposes tokens ahead, the model verifies them in one pass; alpha is the share accepted.

**Fake when:** drafted `tg` sits beside drafts-off `tg`, though the MTP block occupies KV and costs prefill: `tg` up, `pp` down.

### Needle («игла»)

Words and a number buried in the prompt, asked for at the end; the number alone is a partial, not a hit. A gate on quality, not speed.

**Fake when:** one lucky query stands for a series across depths and repeats.

### VRAM reserve `--vram-reserve-mib`

Memory held back so the KV allocation, the CUDA context and staging buffers stop fighting over the last megabytes.

**Fake when:** the reserve is squeezed: the check passes, the long run dies halfway — a coin toss, not an engine.

### `att-mb`

A megabyte ceiling on the attention buffers allowed for one prompt length.

**Fake when:** turned with reserve and slots: freed memory goes to experts, `tg` moves, and reads like a faster kernel.

### `draft-vocab`

Limits the vocabulary a draft proposes from; tokens outside it are refused, so the answer stands and the draft is cheaper.

**Fake when:** credited with a gain in a row where drafting is off: without MTP it does nothing.

### Greedy, temperature 0, determinism

Sampling is off, the likeliest token wins, so a repeated profile must return the same text.

**Fake when:** "deterministic" is claimed across engines with different tokenizers, or a logit shift is called "dumber" while the same token wins.

## How to read the tables

A generator writes the numbers; here is how to trust them.

### The prompt canon

One master prompt file, filled to a per-window character canon: 64k → 190 000, 80k → 230 000, 96k → 260 000, 128k → 380 000, 160k → 440 000. Answers are 256 tokens, greedy; the canon counts characters, because the engine decides the token count.

### Off-canon points are dropped

A point whose prompt token count misses its window's canon does not enter the grid, and no median blends it back: 83 were dropped, since an average over unequal prompts measures nothing.

### Points are re-shot

Each point runs again and the published figure is the pass matching the window's tuned profile; the ranking rule in the primary records can be re-checked.

### One engine at a time

One run alive, nothing else on the card, models on the SSD. A series aimed at the HDD reported "server did not start": a weights read timing out, not an out-of-memory; confuse them and the report gains a phantom OOM.

### Two axes are never multiplied

The code axis is an expert-routing fix measured with the profile frozen; the profile axis is other tuning flags on the same build. Ratios stay per axis: their product as "the speed-up of the fix" is a lie.

### TTFT is not separately measured

TTFT is the prefill duration printed in the line that produced `pp`, so they cannot disagree; it is no second quantity.

### The stock llama row is a reference

It reached the working windows with a 64-token answer against a canon of 256: an order of magnitude, not a same-condition baseline.

### Foreign data stays foreign

Results under `engine\bench\results` come from P100, V100, 5090 and 3090 boxes, not this machine; they are quoted as foreign, never as ours.

## 2. Capture methodology

One rig, one machine, one queue. The rig: RTX 3060 Ti 8 GiB with the ga102 unlock (sm_86), 4 CPU
cores, 31.87 GiB RAM, Windows 11, CUDA 13.3, MSI enabled, HAGS off; the models sit on a SATA SSD on
`D:` (`docs/measurements/grid-2026-11-10.md:13`). Two engines: the Strata fork at commit `60b3aca9`
and the llama.cpp fork with the ggml pin `3cf03257f`.

Prompt and answer canon. Every grid point was captured on one prompt file filled to the canonical
character count, and on 256 answer tokens at temperature 0; the prompt length in tokens the engine
returned is recorded in the primary source and checked. A point whose prompt came out shorter or
longer than the canon does not enter the grid — it enters the rejection table below. 83 points were
rejected in total.

One GPU series at a time. A second run on the same card changes both figures: this is not caution but
a measured effect — a series on HDD reported "server did not start" with perfectly healthy VRAM,
because the timeout did not cover reading 19 GiB of weights; on SSD the same flag set starts and
captures fine (`docs/measurements/grid-2026-11-08.md:538`).

A point is re-captured. If the first capture does not match the tuned profile of the window, the
repeat is published, and the priority is written into the primary source, so the choice is checked
rather than remembered. A window here is `n_ctx`, not the prompt length: the prompt must fill the
window, otherwise a fast `pp` only means "half of it was never read".

### 2.1 What was dropped and why

<!-- OFFPROMPT -->
| drop reason | points |
| --- | --- |
| prompt 15 tokens instead of canon 77378 | 28 |
| prompt 53968 tokens instead of canon 64660 | 11 |
| prompt 44446 tokens instead of canon 77378 | 6 |
| prompt 92627 tokens instead of canon 86589 | 6 |
| prompt 92594 tokens instead of canon 86589 | 5 |
| prompt 15 tokens instead of canon 86589 | 5 |
| prompt 73756 tokens instead of canon 77378 | 3 |
| prompt 53950 tokens instead of canon 64660 | 3 |
| prompt 15 tokens instead of canon 64660 | 3 |
| prompt 89555 tokens instead of canon 86589 | 2 |
| prompt 117753 tokens instead of canon 121808 | 1 |
| prompt 15 tokens instead of canon 121808 | 1 |
| prompt 117786 tokens instead of canon 121808 | 1 |
| prompt 362411 characters instead of canon 380000 | 1 |
| prompt 524288 characters instead of canon 440000 | 1 |
| prompt 6554 characters instead of canon 190000 | 1 |
| prompt 172492 characters instead of canon 190000 | 1 |
| prompt 130506 characters instead of canon 190000 | 1 |
| prompt 220712 characters instead of canon 230000 | 1 |
| prompt 6554 characters instead of canon 260000 | 1 |
| prompt 273733 characters instead of canon 260000 | 1 |
| total | 83 |

## 3. Master table: eight lines, five windows

This is the entire grid. The "Strata stock" row is not left blank by accident: fp32 KV cache gives it
no working windows, see §8.

### 3.1 Prompt processing, tokens per second

<!-- MASTER_PP -->
| line | 64k | 80k | 96k | 128k | 160k |
| --- | ---: | ---: | ---: | ---: | --- |
| Strata fork, UD-IQ3_S (q3) | 1240.3 | 1153.9 | 1099.8 | 945.1 | 869.7 |
| Strata fork, heretic Q4_K_M (q4) | 1338.8 | 1225.0 | 1178.0 | 1005.0 | 914.0 |
| Strata fork, HauhauCS IQ4_XS (reference) | 1499.7 | 1092.5 | 1303.5 | 906.8 | 985.8 |
| llama fork, UD-IQ3_S (q3) | 1113.8 | 1083.4 | 1052.6 | 973.1 | 937.9 |
| llama fork, heretic Q4_K_M (q4) | 879.0 | 853.7 | 845.1 | 792.7 | 766.4 |
| llama fork, HauhauCS IQ4_XS | 975.8 | 936.8 | 908.9 | 854.8 | 830.0 |
| llama stock (3cf03257), KAT IQ4_XS | 639.3 | 632.3 | 619.9 | 598.3 | 573.7 |
| Strata stock (146df3c4), KAT Q5_K_S, fp32 KV | — | — | — | — | — |

### 3.2 Generation, tokens per second

<!-- MASTER_TG -->
| line | 64k | 80k | 96k | 128k | 160k |
| --- | ---: | ---: | ---: | ---: | --- |
| Strata fork, UD-IQ3_S (q3) | 14.7 | 15.5 | 14.2 | 13.3 | 12.5 |
| Strata fork, heretic Q4_K_M (q4) | 16.6 | 17.0 | 16.6 | 14.8 | 13.9 |
| Strata fork, HauhauCS IQ4_XS (reference) | 17.3 | 18.0 | 13.6 | 14.8 | 13.8 |
| llama fork, UD-IQ3_S (q3) | 17.2 | 17.0 | 16.5 | 16.6 | 16.5 |
| llama fork, heretic Q4_K_M (q4) | 19.9 | 19.5 | 19.7 | 18.9 | 17.9 |
| llama fork, HauhauCS IQ4_XS | 19.8 | 19.2 | 19.2 | 18.8 | 17.9 |
| llama stock (3cf03257), KAT IQ4_XS | 7.7 | 7.7 | 7.5 | 7.0 | 6.7 |
| Strata stock (146df3c4), KAT Q5_K_S, fp32 KV | — | — | — | — | — |

### 3.3 Time to first token

Three rows measured, five computed, and every cell carries its own label. The split is mandatory: the
Strata `serve` line prints `ttft_ms` straight into the primary source, and a TTFT column already
exists in the 07.11 grid (`docs/measurements/grid-2026-11-07.md:8`), while a llama record gives only
the wall time of the request and `pp` — there TTFT is computed as `prompt / pp` and is not a
measurement (`artifacts/benchmarks/grid-ud-iq3s-2026-11-10.jsonl:1`).

<!-- MASTER_TTFT -->
| line | 64k | 80k | 96k | 128k | 160k |
| --- | ---: | ---: | ---: | ---: | --- |
| Strata fork, UD-IQ3_S (q3) | 52.1 s (measured) | 67.1 s (measured) | 78.7 s (measured) | 128.9 s (measured) | 160.2 s (measured) |
| Strata fork, heretic Q4_K_M (q4) | 48.3 s (measured) | 63.2 s (measured) | 73.5 s (measured) | 121.2 s (measured) | 152.4 s (measured) |
| Strata fork, HauhauCS IQ4_XS (reference) | 43.1 s (measured) | 70.8 s (measured) | 66.4 s (measured) | 134.3 s (measured) | 141.3 s (measured) |
| llama fork, UD-IQ3_S (q3) | 58.0 s (computed) | 71.4 s (computed) | 82.2 s (computed) | 125.1 s (computed) | 148.5 s (computed) |
| llama fork, heretic Q4_K_M (q4) | 73.5 s (computed) | 90.6 s (computed) | 102.4 s (computed) | 153.6 s (computed) | 181.7 s (computed) |
| llama fork, HauhauCS IQ4_XS | 66.2 s (computed) | 82.6 s (computed) | 95.2 s (computed) | 142.5 s (computed) | 167.8 s (computed) |
| llama stock (3cf03257), KAT IQ4_XS | 101.1 s (computed) | 122.3 s (computed) | 139.6 s (computed) | 203.6 s (computed) | 242.8 s (computed) |
| Strata stock (146df3c4), KAT Q5_K_S, fp32 KV | — | — | — | — | — |

### 3.4 How to read this

The Strata fork leads on `pp` in every closed window and on all three models; the llama fork keeps
`tg` higher (17.2…19.9 against 12.5…18.0) and degrades on `pp` more slowly: on UD-IQ3_S the drop from
64k to 160k is 15.8 %, while Strata on the same model drops 29.9 %. The "llama stock" row was captured
with a 64-token answer instead of the canonical 256, so it is an order-of-magnitude reference, not a
same-conditions comparison; the re-capture on 256 tokens fails the prompt canon (59,080 tokens
against 64,660) and did not enter the grid.

## 4. Before and after: two axes, and they must not be multiplied

The code axis is the quant-routing fix inside the engine with an unchanged launch profile. The profile
axis is a different set of tuning flags on the same build. The ratios are computed separately, and the
product x24.5 × x1.80 will not appear in this document once as "the speedup of the fix": that would
credit to the code what a flag did.

### 4.1 The code axis (UD-IQ3_S, profile unchanged)

<!-- DELTA_CODE -->
| window | before fix | after fix | code speed-up | in grid |
| --- | ---: | ---: | ---: | --- |
| 64k | 50.7 | 1240.3 | x24.5 | 1240.3 |
| 80k | 55.3 | 1076.8 | x19.5 | 1153.9 |
| 96k | 51.2 | 1099.8 | x21.5 | 1099.8 |
| 128k | 51.0 | 523.8 | x10.3 | 945.1 |
| 160k | 51.1 | 869.7 | x17.0 | 869.7 |

The "in grid" column is needed because the "after" points at 80k and 128k were captured before the
final profile tuning: the master table carries later repeats there, while the ratio is computed over
the pair where only the build tree changed. The contribution of the commits at 96k over the measured
pairs is in [waterfall-96k.svg](../assets/waterfall-96k.svg); there are no per-commit deltas over the
25 commits, so the diagram draws no "commit → percent" steps.

### 4.2 The profile axis (same tree, different flags)

<!-- DELTA_PROFILE -->
| window | before | after | profile speed-up | profile change |
| --- | ---: | ---: | --- | --- |
| 80k | 1076.8 | 1153.9 | x1.07 | mtp: 2>0 |
| 128k | 523.8 | 945.1 | x1.80 | att-mb: off>256, draft-vocab: off>8192, super-chunk: off>4x2048 |

Both points are about profiles, not code: at 80k MTP drafts were switched on, at 128k `att-mb 256`,
`draft-vocab 8192` and super-chunk 4×2048. Each lever separately:
[dep-profile-axis.svg](../assets/dep-profile-axis.svg),
[dep-mtp.svg](../assets/dep-mtp.svg), [dep-superchunk.svg](../assets/dep-superchunk.svg).

### 4.3 Fork against stock of the same engine

<!-- DELTA_STOCK -->
| line | stock | 64k | 80k | 96k | 128k | 160k |
| --- | ---: | ---: | ---: | ---: | --- | --- |
| llama fork, UD-IQ3_S (q3) | llama stock (3cf03257), KAT IQ4_XS | x1.74 | x1.71 | x1.70 | x1.63 | x1.63 |
| llama fork, heretic Q4_K_M (q4) | llama stock (3cf03257), KAT IQ4_XS | x1.37 | x1.35 | x1.36 | x1.32 | x1.34 |
| llama fork, HauhauCS IQ4_XS | llama stock (3cf03257), KAT IQ4_XS | x1.53 | x1.48 | x1.47 | x1.43 | x1.45 |

The base is stock llama.cpp with ggml `3cf03257f` on KAT IQ4_XS; the model in the base row differs
from the model in the numerator, so this is an order of magnitude, not a clean same-model A/B. The
even "stock against fork" pair on an identical flag set is in
[stock-vs-fork-2026-11-08.md](stock-vs-fork-2026-11-08.md) and on
[dep-stock-fork.svg](../assets/dep-stock-fork.svg).

## 5. Needles: quality at a long window

A needle is a quality gate, not a speed gate: a rare code made of words and digits is hidden in the
prompt and must be recited at the end. Only the full code counts; a partial hit (digits only) goes
into the denominator but not the numerator.

<!-- NEEDLES -->
| line | hits | prompt tokens | measured | source line |
| --- | ---: | --- | --- | --- |
| heretic-q4km-128k | 4/4 | 117 000 | 2026-11-10 | artifacts/benchmarks/needle-strata-heretic-q4km-128k-2026-11-10.jsonl |
| heretic-q4km-96k | 3/4 | 78 000 | 2026-11-10 | artifacts/benchmarks/needle-strata-heretic-q4km-96k-2026-11-10.jsonl |
| kat-iq4xs-128k | 5/7 | 127 000 | 2026-11-05 | artifacts/benchmarks/needle-end-128k.jsonl |
| kat-iq4xs-160k | 7/7 | 159 000 | 2026-11-05 | artifacts/benchmarks/needle-end-160k.jsonl |
| kat-iq4xs-96k-base | 7/7 | 96 000 | 2026-11-05 | artifacts/benchmarks/needle-end-96k.jsonl |
| needle-128k-base | 1/2 | 127 000 | 2026-11-05 | artifacts/benchmarks/needle-128k-base.jsonl |
| needle-128k-control | 1/2 | 127 000 | 2026-11-05 | artifacts/benchmarks/needle-128k-control.jsonl |
| needle-128k-nofa | 1/2 | 127 000 | 2026-11-05 | artifacts/benchmarks/needle-128k-nofa.jsonl |
| needle-160k | 1/4 | 159 000 | 2026-11-05 | artifacts/benchmarks/needle-160k.jsonl |
| needle-16k-control | 2/2 | 16 000 | 2026-11-05 | artifacts/benchmarks/needle-16k-control.jsonl |
| needle-256k | 1/2 | 255 000 | 2026-11-05 | artifacts/benchmarks/needle-256k.jsonl |
| needle-96k-control | 1/2 | 96 000 | 2026-11-05 | artifacts/benchmarks/needle-96k-control.jsonl |
| ud-iq3s-128k | 12/12 | 117 000 | 2026-11-09, 2026-11-10 | artifacts/benchmarks/needle-strata-ud-iq3s-128k-2026-11-09.jsonl, artifacts/benchmarks/needle-strata-ud-iq3s-128k-2026-11-10.jsonl, artifacts/benchmarks/needle-strata-ud-iq3s-128k-aligned-2026-11-10.jsonl |
| ud-iq3s-96k | 8/8 | 78 000 | 2026-11-09, 2026-11-10 | artifacts/benchmarks/needle-strata-ud-iq3s-96k-2026-11-09.jsonl, artifacts/benchmarks/needle-strata-ud-iq3s-96k-2026-11-10.jsonl |

### 5.1 Hit rate by depth in the prompt

<!-- NEEDLE_POS -->
| position | hits | share |
| --- | ---: | ---: |
| end | 23/31 | 74 % |
| end90 | 8/9 | 89 % |
| mid | 23/25 | 92 % |

The dash on the llama fork in the registry is not accidental: needles were never captured on that
fork, and §9 lists this as a hole.

## 6. Levers that did not work

Thirteen attempts, each with a number and a primary source. This is not a list of "we did not do it",
it is a list of "we did it and got a minus".

<!-- REJECTS -->
| lever | what was tried | measurement | verdict | source |
| --- | --- | --- | --- | --- |
| Flash attention on q4_0 KV | read attention straight from quantized K/V instead of converting to fp16 | attention 80.7 s against 41.5 s at 96k, pp −37 % | no-go: in-kernel dequant costs more than the traffic it saves | docs/research/fa-q4_0.md:4 |
| Lazy att_s/att_p16 buffers | defer the attention buffers to free expert slots | +384 MiB and +6 slots, pp/tg within noise | no-go: the slot plateau is already above 9 | docs/reports/2026-11-07-strata-q36-full-report.en.md:216 |
| MTP drafts on 64k/80k | multi-token drafts on the working windows | tg +4…16 %, but pp −9 %: with --mtp>0 the MTP block warms its KV over the whole prompt | no-go: request time grows; at 4k D=4 the +11.6 % tg stands | docs/research/mtp-long-context.md:45 |
| --hybrid-rows 256 | move more prompt rows onto the hybrid path | 1305.6/15.6 and 1304.5/15.4 against the 1307.7/15.3 control | no-go: tg +1.3 %, pp within noise | docs/research/cpu-pool.md:46 |
| Pinned host layers | STRATA_Q36_PINNED_LAYERS=0 against pinning all 41 layers | 37 of 41 layers are pinned by default too, 1307.1/15.3 | no lever: the driver pins 37 of 41 either way, the gap is run noise | docs/research/pinning-host-layers.md:13 |
| --pool-workers 4/8 | more CPU threads on the expert pool than the default 3 | 4 workers: 309–339 pp / 22.5–26.3 tg; 8: 306–312 / 14.8–16.9 against 336.9–345.9 | no-go: the pool is DRAM-bound; extra workers only add contention on 4 cores | docs/research/rejected-levers.md:15 |
| Large pages / AWE | place the expert arena on 2 MiB pages | 0 % on decode, prompt and load (primary #5238, rig 5080 + 9950X3D) | no-go: never measured on this rig; zero on the upstream author's rig | docs/research/research-candidates-4pct-2026-11-05.md:18 |
| cold-store arena | survive a service restart so the model is not re-read | 18.94 GiB in 94.2 s and 18.55 GiB in 92.8 s on every serve start | a real lever, but it moves start time, not the grid's pp/tg | docs/research/re-read-factor.md:37 |
| -ub 1024 (llama) | a small physical batch as a way to hold VRAM | 532.17 pp / 20.26 tg / 7892 MiB at 96k with ncmoe 30 | no-go: pp below 858 and VRAM did not drop | docs/measurements/vram-audit-ncmoe-2026-11-09.md:52 |
| -nkvo (llama) | move the V cache to system RAM to free VRAM for experts | 691.11 pp / 5.16 tg / 6368 MiB at 96k | no-go: VRAM was freed, tg dropped fourfold | docs/measurements/vram-audit-ncmoe-2026-11-09.md:53 |
| --ctx-checkpoints 0 (llama) | disable context checkpoints to drop their overhead | 848.98 pp / 20.32 tg against the 843.41/19.81 control | no effect: the difference is within noise | docs/measurements/vram-audit-ncmoe-2026-11-09.md:54 |
| super-chunk N=8 | raise the fused prefill chunk count from 4 to 8 | median 1328.9 against 1308.9 = +1.5 % over 6 repeats | no-go: below the 4 % gate, tg under control in five of six repeats | docs/measurements/grid-2026-11-08.en.md:304 |
| FA tile 8x16 with kPad = 0 | shrink the attention tile to fit 2 blocks per SM | 741.5 pp / 15.5 tg against 1311.8 / 16.0 for the 4x32 control | no-go: -43.5 % pp | docs/research/rejected-levers.md:29 |

## 7. The machine ceiling and the answer by task class

The numbers of this section come from the "PC ceiling" summary and the "answer by task class" section
in `docs/measurements/grid-2026-11-08.md:220` (table) and `docs/measurements/grid-2026-11-08.md:241`
(classes); they are retold here because they were captured outside the eight-line grid.

- Long prompt, short answer — the Strata fork: 64k 1504.0 against 1050.5 for the llama fork (+43.2 %),
  96k 1308.9 against 987.3 (+32.6 %), 128k 1091.9 against 890.8 (+22.6 %)
  (`docs/measurements/grid-2026-11-08.md:244`). The top window of this class in those runs is 160k on
  KAT IQ4_XS (959.9 pp / 13.6 tg, `docs/measurements/grid-2026-11-08.md:224`) and 192k on heretic
  Q4_K_M by allocation, with 139k by actual fill (`docs/measurements/grid-2026-11-08.md:225`).
- Chat over a warmed history — llama: decode 17.2…19.9 tok/s against 12.5…18.0 for Strata, and turns
  on an already warm window come with a TTFT under a second
  (`docs/measurements/grid-2026-11-08.md:241`).
- Highest `pp` on this machine — 1504.0 tok/s (Strata, 64k); highest `tg` in the grid — 19.9 tok/s
  (llama, heretic Q4_K_M, 64k).
- Stocks as the "without a fork" ceiling: llama stock on default flags — 573.7 pp / 6.71 tg at 160k
  (`docs/measurements/grid-2026-11-08.md:232`); llama stock on CPU — 317.9…350.7 pp
  (`docs/measurements/grid-2026-11-08.md:231`); Strata stock on fp32 KV — 123.1 pp / 11.34 tg, but
  only up to 32k (`docs/measurements/grid-2026-11-08.md:233`).
- Closed directions: 256k fits in Strata memory in `NO_MMQ` mode, but the prefill takes 88 minutes at
  45 pp; prefill 4096 (lazy buffers) fits and leaves 0 free slots
  (`docs/measurements/grid-2026-11-08.md:235`).

## 8. What these numbers do not contain

<!-- HOLES -->
- Strata stock (146df3c4), KAT Q5_K_S, fp32 KV — not covered: 64k, 80k, 96k, 128k, 160k — this is the machine ceiling, not a hole: ladder taken on the short shelf 2k (109.6), 4k (125.9), 8k (124.8), 16k (123.2), 24k (123.2), 32k (123.1)

The line about Strata stock is a ceiling, not a gap: fp32 KV cache eats the memory before 64k, and pp
at 32k is already 123.1 — there is nothing left to capture beyond that.

## 9. Charts: how metrics depend on the ideas and patches

Twelve new diagrams are produced by `glm\scripts\make_report_charts_2026-11-11.py` from the same
registry as the tables, and pass the same XML gate as the previous seven
(`docs/measurements/kernel-progress-2026-11-09.en.md:110`). All files live in `docs\assets\`.

| chart | which dependency |
| --- | --- |
| [dep-tg-window.svg](../assets/dep-tg-window.svg) | `tg` against the window for all eight lines |
| [dep-ncmoe.svg](../assets/dep-ncmoe.svg) | `pp` and `tg` against `--n-cpu-moe` (llama, 96k) |
| [dep-superchunk.svg](../assets/dep-superchunk.svg) | super-chunk N=1 / 4 / 8 across windows |
| [dep-fa.svg](../assets/dep-fa.svg) | Flash attention on and off, including the q4_0 no-go |
| [dep-mtp.svg](../assets/dep-mtp.svg) | MTP 0/1/2/4: `pp` and `tg`, 4k against working windows |
| [dep-answer-len.svg](../assets/dep-answer-len.svg) | answer length 8 / 64 / 256 tokens |
| [dep-needle.svg](../assets/dep-needle.svg) | needles: hit rate by window and by position |
| [dep-ttft.svg](../assets/dep-ttft.svg) | TTFT and request wall time against the window, measured and computed separately |
| [dep-stock-fork.svg](../assets/dep-stock-fork.svg) | stock against fork by window (delta) |
| [dep-profile-axis.svg](../assets/dep-profile-axis.svg) | the q3 profile axis: 80k and 128k |
| [waterfall-96k.svg](../assets/waterfall-96k.svg) | accumulated contribution of the measured steps to `pp` at 96k |
| [dep-days.svg](../assets/dep-days.svg) | `pp` by capture day, both forks against the upstreams |

## 10. Primary-source map

Every number in the master table is a line in a JSONL. The list below is printed by the generator, so
it cannot silently go stale: a divergence is caught by the gate.

<!-- SOURCEMAP -->
| line | pp, tok/s | tg, tok/s | measured | source |
| --- | ---: | --- | --- | --- |
| Strata fork, UD-IQ3_S (q3) / 64k | 1240.3 | 14.7 | 2026-11-10 | artifacts/benchmarks/grid-udiq3s-2026-11-10.jsonl:17 |
| Strata fork, UD-IQ3_S (q3) / 80k | 1153.9 | 15.5 | 2026-11-10 | artifacts/benchmarks/grid-udiq3s-2026-11-10.jsonl:41 |
| Strata fork, UD-IQ3_S (q3) / 96k | 1099.8 | 14.2 | 2026-11-10 | artifacts/benchmarks/grid-udiq3s-2026-11-10.jsonl:23 |
| Strata fork, UD-IQ3_S (q3) / 128k | 945.1 | 13.3 | 2026-11-10 | artifacts/benchmarks/grid-udiq3s-2026-11-10.jsonl:35 |
| Strata fork, UD-IQ3_S (q3) / 160k | 869.7 | 12.5 | 2026-11-10 | artifacts/benchmarks/grid-udiq3s-2026-11-10.jsonl:29 |
| Strata fork, heretic Q4_K_M (q4) / 64k | 1338.8 | 16.6 | 2026-11-10 | artifacts/benchmarks/grid-hereticq4km-2026-11-10.jsonl:17 |
| Strata fork, heretic Q4_K_M (q4) / 80k | 1225.0 | 17.0 | 2026-11-10 | artifacts/benchmarks/grid-hereticq4km-2026-11-10.jsonl:20 |
| Strata fork, heretic Q4_K_M (q4) / 96k | 1178.0 | 16.6 | 2026-11-10 | artifacts/benchmarks/grid-hereticq4km-2026-11-10.jsonl:23 |
| Strata fork, heretic Q4_K_M (q4) / 128k | 1005.0 | 14.8 | 2026-11-10 | artifacts/benchmarks/grid-hereticq4km-2026-11-10.jsonl:26 |
| Strata fork, heretic Q4_K_M (q4) / 160k | 914.0 | 13.9 | 2026-11-10 | artifacts/benchmarks/grid-hereticq4km-2026-11-10.jsonl:29 |
| Strata fork, HauhauCS IQ4_XS (reference) / 64k | 1499.7 | 17.3 | 2026-11-08 | artifacts/benchmarks/grid-hauhaucsiq4xs-2026-11-08.jsonl:11 |
| Strata fork, HauhauCS IQ4_XS (reference) / 80k | 1092.5 | 18.0 | 2026-11-10 | artifacts/benchmarks/grid-hauhaucsiq4xs-2026-11-10.jsonl:8 |
| Strata fork, HauhauCS IQ4_XS (reference) / 96k | 1303.5 | 13.6 | 2026-11-08 | artifacts/benchmarks/grid-hauhaucsiq4xs-2026-11-08.jsonl:14 |
| Strata fork, HauhauCS IQ4_XS (reference) / 128k | 906.8 | 14.8 | 2026-11-10 | artifacts/benchmarks/grid-hauhaucsiq4xs-2026-11-10.jsonl:11 |
| Strata fork, HauhauCS IQ4_XS (reference) / 160k | 985.8 | 13.8 | 2026-11-08 | artifacts/benchmarks/grid-hauhaucsiq4xs-2026-11-08.jsonl:17 |
| llama fork, UD-IQ3_S (q3) / 64k | 1113.8 | 17.2 | 2026-11-10 | artifacts/benchmarks/grid-ud-iq3s-2026-11-10.jsonl:1 |
| llama fork, UD-IQ3_S (q3) / 80k | 1083.4 | 17.0 | 2026-11-10 | artifacts/benchmarks/grid-ud-iq3s-2026-11-10.jsonl:2 |
| llama fork, UD-IQ3_S (q3) / 96k | 1052.6 | 16.5 | 2026-11-10 | artifacts/benchmarks/grid-ud-iq3s-2026-11-10.jsonl:3 |
| llama fork, UD-IQ3_S (q3) / 128k | 973.1 | 16.6 | 2026-11-10 | artifacts/benchmarks/grid-ud-iq3s-2026-11-10.jsonl:4 |
| llama fork, UD-IQ3_S (q3) / 160k | 937.9 | 16.5 | 2026-11-10 | artifacts/benchmarks/grid-ud-iq3s-2026-11-10.jsonl:5 |
| llama fork, heretic Q4_K_M (q4) / 64k | 879.0 | 19.9 | 2026-11-10 | artifacts/benchmarks/grid-heretic-q4km-2026-11-10.jsonl:2 |
| llama fork, heretic Q4_K_M (q4) / 80k | 853.7 | 19.5 | 2026-11-10 | artifacts/benchmarks/grid-heretic-q4km-2026-11-10.jsonl:4 |
| llama fork, heretic Q4_K_M (q4) / 96k | 845.1 | 19.7 | 2026-11-10 | artifacts/benchmarks/grid-heretic-q4km-2026-11-10.jsonl:6 |
| llama fork, heretic Q4_K_M (q4) / 128k | 792.7 | 18.9 | 2026-11-10 | artifacts/benchmarks/grid-heretic-q4km-2026-11-10.jsonl:8 |
| llama fork, heretic Q4_K_M (q4) / 160k | 766.4 | 17.9 | 2026-11-10 | artifacts/benchmarks/grid-heretic-q4km-2026-11-10.jsonl:10 |
| llama fork, HauhauCS IQ4_XS / 64k | 975.8 | 19.8 | 2026-11-10 | artifacts/benchmarks/grid-hauhaucs-iq4xs-2026-11-10.jsonl:2 |
| llama fork, HauhauCS IQ4_XS / 80k | 936.8 | 19.2 | 2026-11-10 | artifacts/benchmarks/grid-hauhaucs-iq4xs-2026-11-10.jsonl:4 |
| llama fork, HauhauCS IQ4_XS / 96k | 908.9 | 19.2 | 2026-11-10 | artifacts/benchmarks/grid-hauhaucs-iq4xs-2026-11-10.jsonl:6 |
| llama fork, HauhauCS IQ4_XS / 128k | 854.8 | 18.8 | 2026-11-10 | artifacts/benchmarks/grid-hauhaucs-iq4xs-2026-11-10.jsonl:8 |
| llama fork, HauhauCS IQ4_XS / 160k | 830.0 | 17.9 | 2026-11-10 | artifacts/benchmarks/grid-hauhaucs-iq4xs-2026-11-10.jsonl:10 |
| llama stock (3cf03257), KAT IQ4_XS / 64k | 639.3 | 7.7 | 2026-11-08 | artifacts/benchmarks/stock-llama-65536-stock-gpu.jsonl:2 |
| llama stock (3cf03257), KAT IQ4_XS / 80k | 632.3 | 7.7 | 2026-11-08 | artifacts/benchmarks/stock-llama-81920-stock-gpu.jsonl:1 |
| llama stock (3cf03257), KAT IQ4_XS / 96k | 619.9 | 7.5 | 2026-11-08 | artifacts/benchmarks/stock-llama-98304-stock-gpu.jsonl:1 |
| llama stock (3cf03257), KAT IQ4_XS / 128k | 598.3 | 7.0 | 2026-11-08 | artifacts/benchmarks/stock-llama-131072-stock-gpu.jsonl:1 |
| llama stock (3cf03257), KAT IQ4_XS / 160k | 573.7 | 6.7 | 2026-11-08 | artifacts/benchmarks/stock-llama-163840-stock-gpu.jsonl:1 |
| outside repo: 0 |  |  |  |  |

## 11. How to reproduce

The Strata build — `harness\scripts\build_strata.bat:21`, the fast 96k run —
`harness\scripts\run_strata_fast_96k.bat:4`, the window profiles — `harness\config\*.json`
(`harness\README.md:88`). The llama-fork profiles and the levers collected in them —
`harness\reports\profiles.md:261`. The table generator is invoked as:

```
python -X utf8 glm\scripts\report_tables_2026-11-11.py --verify docs\reports\2026-11-11-full-measurement-report.md --lang en
```

An empty answer from the measure counts as a failed check, not as "no divergences": the generator
prints how many lines it verified.
