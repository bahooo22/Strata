# The Strata fork on an RTX 3060 Ti 8 GiB: 25 commits, five windows, and what of them is measured (EN)

Russian twin: [strata-fork-report.ru.md](strata-fork-report.ru.md). The common
report over both engines:
[full-measurement-report.md](full-measurement-report.md); the other fork:
[llama-fork-report.md](llama-fork-report.md).

Subject: the `Niko1221/Strata` fork (base `ffa80d73`, branch `main`) and its `q36` engine on a machine
with 8 GiB of video memory. The grid was captured at commit `60b3aca9`; the rig and the prompt canon
are described in the common report, here only what concerns Strata. Anchor paths point at the primary
sources themselves, regardless of the language the note around them was written in.

## 1. Terms and reading rules

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

## 2. What the fork contains, grouped by meaning

The list of local commits is kept by `engine/LOCAL.ru.md:6` — 25 entries on top of upstream. The
groups that matter for the numbers of this report:

- **quant routing.** `143d5be4` (IQ4_XS in `ssm_alpha/beta`) and the later fix that is the reason the
  q3 line exists at all: in UD-IQ3_S 39 of the 41 expert layers are IQ2_S, and before `d797be8b` they
  ran the common path without MMQ (`docs/measurements/grid-2026-11-10.md:74`). The second half of the
  cause surfaced later: Q2_K was missing from the whitelist, which switched MMQ off on all 41 layers.
- **memory and launch.** `414b9cde` (`--vram-reserve-mib`), `efec68e7` and `a00ab004` (the attention
  buffer first as an env flag, then as a flag without a rebuild), `2e1c2a04`/`2033a9dc` (OOM
  diagnostics on expert buffers and slots), `976226a9` (startup hints).
- **KV cache.** `91725ec7` (q8_0) and `28f39156` (q4_0, q5_0, q5_1 in one byte buffer).
- **kernels and weight access.** `bbc034d4` (pacc under T≤8 and L2-ordered split-K), `4b679a76` (pinned
  host arena per layer), `4569b243` (count+scan routing in a single block), `53a8f8ca` (pinned share as
  a flag).
- **quality and predictability.** `3ae7d409` (per-request determinism of expert placement, #4604),
  `aea22e2f` (a test for the `strata_deterministic` flag), `b8d4b58d` (the guard no longer requires the
  MTP key), `2fe24691` (a refused batch admission is an error, not a completed request, #3040).
- **observability.** `59855142` and `227ba006` (the attention/GDN/MoE profiler and the MTP phases),
  `c9ca876d` (request profile in serve-DONE), `4af27c19` (residency prior in the log), `8852b327`
  (`chat_template_caps`).

## 3. The five-window grid: which rows are Strata

The number blocks are printed by one measure for both engines, so the tables also carry llama rows:
they are there as the neighbour in the same window, so that the Strata difference is visible in place.
The Strata rows are the first three.

### 3.1 Prompt processing

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

### 3.2 Generation

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

For the Strata rows every cell is a measurement: `serve` prints `ttft_ms` itself into the run line
(`docs/measurements/grid-2026-11-07.md:8`). For the llama rows the same block prints the computed
`prompt / pp`, because their primary source only holds the request wall time; the llama fork report
unpacks this in detail.

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

## 4. Two acceleration axes

### 4.1 The code axis: the quant-routing fix with an unchanged profile

<!-- DELTA_CODE -->
| window | before fix | after fix | code speed-up | in grid |
| --- | ---: | ---: | ---: | --- |
| 64k | 50.7 | 1240.3 | x24.5 | 1240.3 |
| 80k | 55.3 | 1076.8 | x19.5 | 1153.9 |
| 96k | 51.2 | 1099.8 | x21.5 | 1099.8 |
| 128k | 51.0 | 523.8 | x10.3 | 945.1 |
| 160k | 51.1 | 869.7 | x17.0 | 869.7 |

The before/after pair was built on one set of levers; only the build tree changes. The "before" point
is not "stock": stock Strata on fp32 KV does not survive to the working windows, see §8. What exactly
the fix does is visible in the 96k profile:
`att-mb=256 draft-vocab=8192 kv-type=q4_0 mtp=0 native=yes`
(`docs/measurements/grid-2026-11-10.md:111`).

### 4.2 The profile axis: same code, different flags

<!-- DELTA_PROFILE -->
| window | before | after | profile speed-up | profile change |
| --- | ---: | ---: | --- | --- |
| 80k | 1076.8 | 1153.9 | x1.07 | mtp: 2>0 |
| 128k | 523.8 | 945.1 | x1.80 | att-mb: off>256, draft-vocab: off>8192, super-chunk: off>4x2048 |

The product of the two axes is not published in this report: x24.5 is code, x1.80 is flags.

## 5. What the profile is made of: measured levers

- **super-chunk N=4.** At 96k the grid profile uses chunk merging; in the profile the MoE phase shrank
  from 49,518.9 ms to 23,336.6 ms (−52.9 %), attention did not change (61,372.3 → 60,958.8)
  (`docs/research/super-chunk.ru.md:85`). N=8 was tried and rejected: +1.5 % against a 4 % gate
  (`harness/reports/profiles.md:353`).
- **Flash attention.** Tile 4x32 on fp16 KV: 1341.1 tok/s against the 1019.1 control without FA on the
  same 86,589-token prompt (`docs/research/fa1-status-2026-11-05.md:124`). The 8x16 tile with
  `kPad=0` gave 741.5 against 1311.8
  (`docs/reports/2026-11-07-strata-q36-full-report.md:80`) — that one is in §7. FA computed directly on
  q4_0 KV is also in §7.
- **attention buffer.** `--att-mb 512` returns +5.5 % pp at 96k with super N=4 (1018.4 → 1074.0)
  (`docs/research/fa-attention.ru.md:12`); the default is 256 MB (`engine/docs/profile-q36.md:201`).
- **pinned arena.** Revision 2.2: pp +73 % at tg −10 % (326.2 → 564.6 on a 32768 prefill), TTFT from
  ~100 to ~58 s (`engine/docs/profile-q36.md:139`). The pinned share is the flag
  `STRATA_Q36_PINNED_LAYERS`, and on this rig 37 of 41 layers pin by default
  (`engine/LOCAL.ru.md:31`).
- **pacc + split-K and the route kernels.** `bbc034d4` gave +28 % tg at 96k
  (`engine/docs/profile-q36.md:112`), the count+scan merge — pp 567–569
  (`engine/docs/profile-q36.md:115`).
- **MTP.** The working point is short windows: D=4 at 4k gives +11.6 % tg at alpha 0.766
  (`docs/research/mtp-long-context.ru.md:25`), at 16k — 42.1 tok/s
  (`docs/measurements/mtp-16k-2026-11-01.md:43`), at 48k — 38.9 against 35.3 without MTP
  (`docs/measurements/mtp-16k-2026-11-01.md:64`). At 64k and 80k it is a no-go, see §7; the grid runs
  mtp=0 (`docs/measurements/grid-2026-11-10.md:111`).
- **KV quantization.** At 48k q4_0 gives 35.3 tok/s against 20.5 for fp32 (+72 %), the quant spread is
  +65…74 % (`docs/measurements/kv-types-q36-2026-11-01.md:99`). In the working windows of the grid
  q4_0 stays in the profile (`docs/measurements/grid-2026-11-10.md:111`), but attention computed
  directly on it costs more: see §7 and `docs/research/fa-q4_0.md:4`.

## 6. Needles

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

### 6.1 By depth in the prompt

<!-- NEEDLE_POS -->
| position | hits | share |
| --- | ---: | ---: |
| end | 23/31 | 74 % |
| end90 | 8/9 | 89 % |
| mid | 23/25 | 92 % |

Needles are a quality gate, not a speed gate: they check that a long window did not lose the answer.
The `kat-iq4xs-*` points were captured on KAT IQ4_XS (the model on which the Strata grid is not
closed), `ud-iq3s-*` and `heretic-q4km-*` on the grid models.

## 7. What failed specifically in Strata

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

The rows about `-ub`, `-nkvo` and `--ctx-checkpoints` belong to the llama fork and stay here because
the block is printed once: in this engine they were never applied.

## 8. Why the stock Strata row is dashes

The "Strata stock" row in the master tables is closed only on the short shelf: fp32 KV eats the memory
before 64k, and pp at 32k is already 123.1 — beyond that there is nothing to capture
(`docs/measurements/grid-2026-11-08.md:233`).

<!-- HOLES -->
- Strata stock (146df3c4), KAT Q5_K_S, fp32 KV — not covered: 64k, 80k, 96k, 128k, 160k — this is the machine ceiling, not a hole: ladder taken on the short shelf 2k (109.6), 4k (125.9), 8k (124.8), 16k (123.2), 24k (123.2), 32k (123.1)

## 9. How to build and how to reproduce

The build — `harness\scripts\build_strata.bat:21` (targets `strata` and `strata-q36`, `ggml` from the
neighbouring llama.cpp clone); the portability check — `engine\build-verify.bat` (25 targets,
`engine/LOCAL.ru.md:38`). The fast 96k run — `harness\scripts\run_strata_fast_96k.bat:4`, the window
profiles — `harness\config\strata-kat-iq4xs-96k-super-main-fa.json:15`, the general harness
description — `harness\README.md:88`.

## 10. Primary-source map

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
