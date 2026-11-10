# The llama.cpp fork on an RTX 3060 Ti 8 GiB: tuning, patches and five windows (EN)

Russian twin: [llama-fork-report.ru.md](llama-fork-report.ru.md). The common
report: [full-measurement-report.md](full-measurement-report.md); the other
engine: [strata-fork-report.md](strata-fork-report.md).

Subject: llama.cpp with our ggml pin and the edits on top of it, on the same 8 GiB machine. The grid
was captured on the build `llama-master\build-master\bin\llama-server.exe` (head `a0039832b`,
`docs/measurements/grid-2026-11-10.md:36`); the stock base is `llama-3cf\build-stock` at `3cf03257`
(`docs/measurements/grid-2026-11-10.md:37`). Anchor paths point at the same primary-source lines as
the Russian twin, because the notes around the captures are kept in that corpus.

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

## 2. Why this fork is a separate line at all

An MoE model on 8 GiB in llama.cpp survives because of `--n-cpu-moe`: part of the experts stay in RAM
and are completed by the CPU. Everything else — tuning and patches — is around that: how to fit into
VRAM without losing `pp`. In Strata the same profile is done by its own `q36` engine, and on `pp` it is
ahead (§5).

## 3. The five-window grid

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

For the rows of this fork TTFT is a computation: the primary source holds `seconds` (the request wall
time) and `pp`, while the prefill lines with `ttft_ms` are printed by Strata's serve. That is why the
cells are labelled "computed" (`artifacts/benchmarks/grid-ud-iq3s-2026-11-10.jsonl:1`).

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

## 4. Tuning by window: what was picked

### 4.1 `--n-cpu-moe`

The 96k series (llama, KAT IQ4_XS) with the control point at 30
(`docs/measurements/vram-audit-ncmoe-2026-11-09.md:29`):

- `ncmoe 30` — 60.65 pp / 13.52 tg (the evening run of 08.11);
- `ncmoe 31` — 794.44 pp / 19.96 tg (`docs/measurements/vram-audit-ncmoe-2026-11-09.md:30`);
- `ncmoe 32` — 858.10 pp / 20.04 tg (`docs/measurements/vram-audit-ncmoe-2026-11-09.md:31`);
- `ncmoe 33` — 843.41 pp / 19.81 tg at 6985 MiB (`docs/measurements/vram-audit-ncmoe-2026-11-09.md:32`).

The difference between 32 and 33 is within noise, but the VRAM remainder differs, and it is the
remainder that decides whether the next window starts.

### 4.2 `-b` and `-ub`

The 96k profile: `ncmoe 30` with `-ub 8192` gives 831.7…834.7 pp and 20.3…20.5 tg against 643.8 pp /
19.91 tg at `-ub 2048` (`harness/reports/profiles.md:86`). An important correction found during the
review: `-ub 8192` under `-b 2048` does nothing — the ubatch is clamped by the batch
(`llama.cpp/src/llama-context.cpp:247`), so the pair "`-ub 2048` against `-ub 8192`" on the old batch
never existed at all (`docs/measurements/grid-2026-11-08.md:438`).

### 4.3 The window threshold and the false "collapse"

The 96k point at `ncmoe 30` is unstable: 894.9 pp in the morning, 60.7 in the evening with the same
code and prompt — that was the false "window threshold": the threshold is not the prompt length but the
video-memory remainder at launch (`harness/reports/profiles.md:262`). Separately, the collapse on
Q4_K_M is documented: 128k starts at 314.6 tok/s against 1089.4 at 96k with the same
`-b 2048 -ub 8192 --n-cpu-moe 30` (`docs/measurements/grid-2026-11-08.md:471`), and the llmfan Q5_K_S
series of 08.11 with 55–59 pp at 96k on `ncmoe 30`
(`docs/measurements/grid-2026-11-08.md:511`). It is cured not by a window flag but by a `ncmoe` step
and a VRAM-remainder check.

## 5. Patches and edits: accepted, rejected, given upstream

- **H2D overlap and event lifetime** (our ggml patch; branch `pr-h2d-event-lifetime`, commit
  `86b90698e`, `docs/research/pr-acceptance-2026-11-05.md:40`). Published as PR #31850; the
  upload-stream test as published failed before the first copy (`ggml_new_object: not enough space in
  the context's memory pool`), fixed by raising `mem_size` to `*8` and giving the leak loop its own
  context: 200 copies of 4 MiB, `200 copies verified, no leak` (commit `9d3a6cc06`,
  `docs/reports/2026-11-07-strata-q36-full-report.md:230`).
- **upload-stream and `n_copies`.** Master validation: build 160/160 rc=0, the 96k control pp 932.43 /
  tg 22.57–23.43 at SHA `f3499b0a5b888991` — the bits matched the base, the speed was within noise
  (`docs/reports/master-validation-2026-11-04.md:50`). The `GGML_SCHED_COPIES` mechanism was confirmed
  as the source of the extra memory: 25,777 MiB compute at 96k
  (`docs/reports/control-runs-2026-11-04.md:53`).
- **VRAM cache of hot experts (`--moe-cache-mib`) — rejected on 8 GiB.** At 96k the control is 934.8 pp
  against 913/15.4–16.3 with the cache, at 128k 877.5 against 883/15.0–15.5, and 64k with a 512 MiB
  cache did not start at all (`docs/reports/control-runs-2026-11-04.md:57`). The cause was measured:
  the top-16 experts hold only ~37 % of routings
  (`docs/research/llama-master-analysis-2026-11-04.md:141`).
- **updating the tree instead of code.** Upstream master without our code gives +7.2…8.5 % pp at 96k
  and +7.1 % at 128k (`docs/reports/wave3-decision-2026-11-04.md:10`) — the cheapest lever on the list.
- **upstream fixes #29941 and #30449 — not taken.** Separately #29941 is a correctness fix (861.6 pp /
  20.8–21.7 tg, `docs/reports/upstream-highlights-measurements-2026-11-04.md:113`); #30449 (the 4 GiB
  pinned limit) drops tg by 20…30 % on our configuration, and together they give pp −2.4 % and a bit
  divergence (`docs/reports/upstream-highlights-measurements-2026-11-04.md:104`).
- **the ggml pin `3cf03257f` against `6c01da62`.** The pin was chosen for Strata's q3 route: in
  `6c01da62` the MoE-copy was rewritten, and the edit our `q36` needs is absent there. The branch was
  rebased onto `origin/master 6c01da62` and checked: 4/4 commits landed
  (`docs/research/llama-h2d-overlap.md:112`), with the master control points — 987.3 pp / 23.3 tg at
  96k without upload-stream and 986.7 / 23.8 at 128k with it
  (`docs/research/llama-h2d-overlap.md:118`).

## 6. Fork against stock

<!-- DELTA_STOCK -->
| line | stock | 64k | 80k | 96k | 128k | 160k |
| --- | ---: | ---: | ---: | ---: | --- | --- |
| llama fork, UD-IQ3_S (q3) | llama stock (3cf03257), KAT IQ4_XS | x1.74 | x1.71 | x1.70 | x1.63 | x1.63 |
| llama fork, heretic Q4_K_M (q4) | llama stock (3cf03257), KAT IQ4_XS | x1.37 | x1.35 | x1.36 | x1.32 | x1.34 |
| llama fork, HauhauCS IQ4_XS | llama stock (3cf03257), KAT IQ4_XS | x1.53 | x1.48 | x1.47 | x1.43 | x1.45 |

The base is stock llama.cpp at `3cf03257` on KAT IQ4_XS, and the series was captured with a 64-token
answer instead of the canonical 256: 639.3 pp / 7.65 tg at 64k and 573.7 / 6.71 at 160k
(`docs/reports/2026-11-08-stock-vs-fork.ru.md:222`). Hence the ratios are an order of magnitude. The
stock re-capture on 256 tokens did not enter the grid: the prompt came out at 59,080 tokens instead of
the canonical 64,660 (`docs/measurements/kernel-progress-2026-11-09.md:54`).

## 7. Needles

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

Not a single row of this block belongs to the llama fork: needles were never captured on it. That is a
hole, not a result, and §9 lists it separately. Without needles the quality of a long window in llama is
confirmed only by speed and by greedy-SHA equality, not by retrieval from the prompt.

### 7.1 By depth in the prompt

<!-- NEEDLE_POS -->
| position | hits | share |
| --- | ---: | ---: |
| end | 23/31 | 74 % |
| end90 | 8/9 | 89 % |
| mid | 23/25 | 92 % |

## 8. What did not work

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

The rows about the FA tile, the pinned arena, super-chunk, MTP at 64k and lazy buffers belong to
Strata: the rejection block is printed once for both engines so that the list does not drift apart
across documents.

## 9. Grid holes

<!-- HOLES -->
- Strata stock (146df3c4), KAT Q5_K_S, fp32 KV — not covered: 64k, 80k, 96k, 128k, 160k — this is the machine ceiling, not a hole: ladder taken on the short shelf 2k (109.6), 4k (125.9), 8k (124.8), 16k (123.2), 24k (123.2), 32k (123.1)

## 10. How to reproduce

The window configurations and profiles — `harness\reports\profiles.md:261` (including the `-ub`
breakdown), the run scripts — `harness\scripts\`. The llama build: ggml comes from the clone at the pin
`3cf03257f`, and Strata builds its `q36` from the same source (`harness\README.md:88`).

## 11. Primary-source map

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
