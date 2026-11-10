# Stock (upstream) vs fork on an RTX 3060 Ti 8 GiB laptop: what the fork actually buys (EN)

Russian twin: [stock-vs-fork-2026-11-08.ru.md](stock-vs-fork-2026-11-08.ru.md). Written 2026-11-08;
the structure was re-cut the same day at the request of the person who is capturing the stock grid.
English is the base file, per that request. Note the divergence: the neighbouring report
`2026-11-07-strata-q36-full-report.md` uses the opposite convention (base = Russian, `.en.md` =
English). Renaming either side is a one-command change.

Status of this document: **structure + verified numbers only**. Everything the author has not
measured yet is `{{no measurement}}`, every command line not confirmed yet is `{{command}}`, every
claim still needing a code or file check is `{{verify}}`. No number below is invented: each one is
copied verbatim from a first-hand artifact and the source line is cited.

## 1. What was measured and why

Hardware: one laptop, RTX 3060 Ti 8 GiB, 32 GiB RAM, 4 CPU cores. Model of record:
KAT-Coder-V2.5-Dev-35B-A3B MoE, IQ4_XS weights (17.86 GiB; the routed experts alone are 16.34 GiB
in host memory, `docs/archive/2026-11-02_session/pr2-optimizations.md:23`). Two engines:

- **stock Strata** = upstream build at HEAD `146df3c4`, `engine-stock\build-stock\strata-q36.exe`.
  Subject of that commit: "setup.py run(): the app's installer also runs the bundled Mac preparation
  tools in metal/tools (metal_repack.py, stream_experts.py); a fresh Mac Terminal or app install of
  UD-Q4_K_XL or UD-IQ4_XS-v31 stopped with "only runs its bundled preparation tools" since af1ffd913.
  Test: they run, and -m, another interpreter and other folders are still refused". `146df3c4` is an
  ancestor of our HEAD `72fd5013` (`git merge-base --is-ancestor`), so the two trees differ by our
  commits only - there is no third-party drift to control for. Three flags the fork drives its q36
  path with are not parsed by the stock q36 engine: a grep over `engine-stock/src/qwen35/` finds no
  `--kv-type`, `--vram-reserve-mib` or `--att-mb` there, the built binary carries no literal for them
  (positive controls `--native` and `--prefill` are found, a made-up flag is not; measure
  `glm/scripts/probe_exe_flags.py`), and our build parses all three inside the q36 engine itself
  (`engine/src/qwen35/q36_engine.cu:4385`, `:4384`, `:4357`). Over the whole stock tree the first and
  third flags appear nowhere in its C++ - fork-only. The reserve is different and the difference
  matters for how this claim should be read: it is an upstream flag that simply lives in the *other*
  engine mains (`engine-stock/src/program/generate.cpp:3539`, target `strata` at `engine-stock/CMakeLists.txt:936`,
  and `engine-stock/sycl/src/program/generate.cpp:1938`), the serve layer exposes it as a config key
  (`engine-stock/serve/runconfig.py:42-43`, "engine default 700") and passes it to the engine only
  from a `vision.gpu` config (`engine-stock/serve/server.py:3836-3837`). The model of record runs on
  q36 here, so on this machine the reserve is a fork addition, but "upstream has no reserve flag"
  would be wrong. KV is fp32 in stock.
- **fork Strata** = our tree (`engine/build/strata-q36.exe`) with FA (`STRATA_Q36_FA_LAYER=all`),
  super-chunk (`STRATA_Q36_SUPER_CHUNK=4`), KV q4_0 and VRAM reserve; capture conditions in
  `docs/measurements/grid-2026-11-07.md:4-5`.

Two grids exist and they are **not** the same grid:

- the **fork grid**, 64k-160k, captured 2026-11-07, first-hand artifact
  `docs/measurements/grid-2026-11-07.md`;
- the **stock grid**, 2k-32k Strata plus two llama.cpp branches, captured 2026-11-08 and **still
  running** while this file is being written; its artifacts are
  `glm/2026-11-08_session/stock-<engine>-<ctx>-<tag>.jsonl`.

What each fork patch is shown to contribute, with the line that proves it:

- **KV q4_0** (`-ctk/-ctv q4_0` equivalent, our `--kv-type`): the single change that moves the
  memory ceiling, so the whole 64k-160k band is a consequence of it plus the reserve. The fp32 cost
  per token is fixed in upstream code, not estimated: stock
  `engine-stock/src/qwen35/q36_engine.cu:3837` and ours `engine/src/qwen35/q36_engine.cu:4478` both
  carry `const double kv_one = 45056.0, kv_shared = 5120.0` - the same declaration at the same place
  in that file, but at different line numbers, because our branch has grown above it.
  The allocation that constant describes is `(n_head_kv * head_dim * 2 * 4) * ctx * n_attn` bytes per
  session - stock `:1457`, ours `:1755`. The model of record closes that arithmetic exactly: its GGUF
  header has `block_count 41`, `full_attention_interval 4`, `attention.head_count_kv 2`,
  `attention.key_length 256`, `nextn_predict_layers 1`, so 10 attention layers + the MTP block = 11
  layers carrying KV, and 2 x 2 x 256 x 4 = 4096 B per token per layer, 11 x 4096 = 45 056 B per token
  (measure `glm/scripts/probe_kv_geometry_2026_11_08.py`). Upstream's own comment five lines above
  that constant, stock `:3832` and ours `:4473`, rounds the same number to "50 KB per cell and
  session". Our q4_0 path puts
  those same values in 18 bytes per 32 (`engine/src/qwen35/q36_engine.cu:265`) - 576 B per layer,
  6 336 B per token, so one session's KV at 128k is 5.5 GiB upstream against 792 MiB with q4_0. That
  7.1x, not a speedup, is what opens the band on 8 GiB.
- **IQ4_XS in the 1-D `ssm_alpha` / `ssm_beta` slot**: upstream's loader refuses the model of record
  before any measurement is possible. `engine-stock/src/qwen35/q36_engine.cu:951` prints
  "blk.0.ssm_alpha.weight is IQ4_XS, expected F32, BF16, F16 or Q8_0" and exits 1; the rejection is in
  `glm/2026-11-08_session/stock-strata-iq4xs.log`, discussed at `second-grid-sources.md:91-111`. Our
  tree adds the IQ4_XS branch at `engine/src/qwen35/q36_engine.cu:1160-1163`. Consequence for this
  report: the stock Strata ladder had to be captured on KAT Q5_K_S (24.57 GiB) - a different model -
  which is precisely why the stock columns of section 2 stay empty instead of being filled across
  quants.
- **Flash attention (mma path) and the buffer sizing around it**: `att_rows = H * kGemmT` instead of
  `H * min(tmax, 64)` because split-K runs only in the decode/verify windows - the old 64-row sizing
  wasted 336 MiB at 96k and 448 MiB at 128k, and the freed VRAM became 6 more expert slots at 96k
  (23 vs 17), `docs/archive/2026-11-02_session/pr2-optimizations.md:32-35`.
- **L2-ordered split-K grid**: `dim3(nt*H, nc)` instead of `dim3(nc, nt*H)`, so the 8 q-heads of one
  KV-head run adjacently and reuse the K/V chunk from L2, same file `:36-37`.
- **Super-chunk prefill + FA, same-window before/after** (the fork's own numbers, without them):
  64k 913.8 -> 1504.0, 96k 1024.0 -> 1308.9, 128k 813.4 -> 1091.9 pp,
  `docs/measurements/grid-2026-11-07.md:29-31`.
- **Split-K partials**: `pacc` + `pm` + `pl` cost 51 MiB at 96k and 68 MiB at 128k
  (`q36_engine.cu:1695-1699`, table row in
  `docs/archive/2026-11-04_session/strata-master/audit-decode-kv.md:78`), and the same audit records
  the price: split-K attention reads 8x more KV than needed because of GQA
  (finding K6, same file `:407`).
- **Pinned expert arenas**: one `cudaHostAlloc` for the whole 16.34 GiB fails on Windows and falls
  back to pageable memory; a per-layer allocation of ~400 MiB pins 37 of 41 layers and raised hybrid
  prefill by 73 % (96k pp 326 -> 562-565), `pr2-optimizations.md:38-40`. The earlier memory census is
  the other half of the story: experts in host RAM 18.75 GiB pageable, "pinned did not fit in 32 GB",
  `docs/archive/2026-10-28_session/strata-measurements.md:23`.

Question for upstream: how much of the long-context behaviour on this class of GPU is a property of
the engine and how much is a property of the hardware - would an upstream user with 8 GiB of VRAM see
the same wall we removed, and at what cost.

## 2. Upstream vs fork, by window

Metric definitions, identical on both sides: `pp` = prompt-eval tokens/s from the engine's own line,
`tg` = generation tokens/s, `TTFT` = time to the first token. Greedy (temperature 0).

The fork columns are taken verbatim from the first-hand artifact
`docs/measurements/grid-2026-11-07.md:10-14` (rows 10-14 of that table). The stock columns are
`{{no measurement}}` here on purpose, and the 08.11 work made the reason stronger than "not captured
yet": the stock engine cannot load the model of record at all (IQ4_XS in the 1-D `ssm_alpha` slot,
section 1), so no stock row can exist at these windows on this model. What stock does run here - the
KAT Q5_K_S ladder on fp32 KV - stops at 32k for the memory reason spelled out in section 4, and its
rows are listed in section 3 rather than in this table, so that nobody computes a speedup from
mismatched rows. See section 6, note 1.

| window | stock pp | stock tg | stock TTFT | fork pp | fork tg | fork TTFT | delta | capture conditions |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| 64k | {{no measurement}} | {{no measurement}} | {{no measurement}} | 1504.0 | 18.1 | 43.0 s | {{no measurement}} | fork: `grid-2026-11-07.md:10`, profile `strata-kat-iq4xs-64k-super`, prompt 64 660 tok, KV q4_0, FA + super N=4, MTP 0, `--att-mb 64`, reserve 512, 256 tok answer |
| 80k | {{no measurement}} | {{no measurement}} | {{no measurement}} | 1253.6 | 16.6 | 61.7 s | {{no measurement}} | fork: `:11`, `strata-kat-iq4xs-80k`, prompt 77 378 tok, same but MTP 2 (`--att-mb 64`, reserve 512) |
| 96k | {{no measurement}} | {{no measurement}} | {{no measurement}} | 1308.9 | 15.3 | 66.2 s | {{no measurement}} | fork: `:12`, `strata-kat-iq4xs-96k-super-main-fa`, prompt 86 589 tok, KV q4_0, FA + super N=4, MTP 0, 256 tok |
| 128k | {{no measurement}} | {{no measurement}} | {{no measurement}} | 1091.9 | 14.6 | 111.6 s | {{no measurement}} | fork: `:13`, `-128k-super-main-fa`, prompt 121 808 tok, as 96k |
| 160k | {{no measurement}} | {{no measurement}} | {{no measurement}} | 959.9 | 13.6 | 145.1 s | {{no measurement}} | fork: `:14`, `strata-kat-iq4xs-160k`, prompt 139 293 tok, as 96k |

Every fork row was captured with `reused = 0` (the raw engine lines are in the same file, `:19-23`),
so `pp` is a real full-prompt prefill rate, not a cache hit. End-to-end request seconds (256 answer
tokens + server load) are in `:33`: 64k 130.0 / 80k 203.0 / 96k 214.4 / 128k 254.1 / 160k 290.1.

Windows below 64k are absent from this table because the 07.11 fork grid does not contain them; they
will be added only when both engines have a row captured on the same model and the same request
length. The captured stock Strata points in the meantime are listed in section 3, not here, so that
nobody computes a speedup from mismatched rows.

`delta` is intentionally empty everywhere. A ratio between these columns would be a fabricated
number.

## 3. The "pp around 100, tg around 3" claim

We were asked to test the hypothesis that a stock engine on this GPU settles at roughly 100 tok/s
prefill **and** roughly 3 tok/s decode. Our conclusion of 2026-11-08, from
`glm/2026-11-08_session/second-grid-sources.md:313-337`: **the pair was never measured together in
any of our data, and the two halves come from different regimes.**

- The prefill half is roughly right *for stock Strata*: `pp` holds 109.6-125.9 across 2k-32k
  (the rows below), so the ~100 order is real for prompt processing there.
- The decode half does not reproduce on stock Strata: `tg` falls from 19.94 to 11.34 as the window
  grows and never approaches 3 at any window captured so far.
- Where `tg` 2-4 does appear in our records it is the **first, cold** llama.cpp answer with all
  experts on CPU (`--n-cpu-moe 99`, `docs/research/long-context-2026-10-28.md`, captured 28.10-29.10,
  summarised at `second-grid-sources.md:22-26`): 32k first answer pp 5.0 / tg 2.1, 40k first answer
  pp 6.0 / tg 3.9. In those rows `pp` is 5-6, not 100 - the weights were still being read from SSD
  into the page cache. Warmed, the same points give pp 12.4 / 87.5 with tg 18.2 / 19.3.
- All three stock branches are now measured, and none of them lands on the pair: stock Strata
  109.6-125.9 / 11.34-19.94, stock llama.cpp with normal flags 573.7-639.3 / 6.71-7.65, stock
  llama.cpp launched as shipped 317.9-350.7 / 7.00-7.75 (cold first answer 31.7-36.9 / 4.57-5.94).
  "pp 100" lies between the cold and the warmed CPU reading, and "tg ~3" is below every one of
  them, so the baseline matches neither engine as it actually runs on this machine.

Honest framing: the rows below are the actual measurements. Nothing is fitted to the hypothesis.

### Stock Strata points captured so far

`build-stock`, KV fp32, no FA, no super-chunk. One slot per point, greedy, 64 answer tokens, prompt
auto-scaled to 0.90 of the window. Artifacts: `glm/2026-11-08_session/stock-strata-<ctx>-grid.jsonl`.

| window | pp tok/s | tg tok/s | TTFT | prompt tok | artifact |
| ---: | ---: | ---: | ---: | ---: | --- |
| 2048 | 109.6 | 19.94 | 15.95 s | 1 749 | `stock-strata-2048-grid.jsonl` |
| 8192 | 124.8 | 17.62 | 53.5 s | 6 677 | `stock-strata-8192-grid.jsonl` |
| 16384 | 123.2 | 15.05 | 99.8 s | 12 293 | `stock-strata-16384-grid.jsonl` |
| 24576 | 123.2 | 12.45 | 150.3 s | 18 526 | `stock-strata-24576-grid.jsonl` |

The same ladder also holds 4096 (pp 125.9 / tg 19.49 / TTFT 27.94 s / prompt 3 517) and 32768
(pp 123.1 / tg 11.34 / TTFT 198.88 s / prompt 24 483), from `stock-strata-4096-grid.jsonl` and
`stock-strata-32768-grid.jsonl`. All six were captured on **KAT Q5_K_S ssm-q8** (24.57 GiB), not on
the IQ4_XS model of record. The re-capture bat for the model of record exists
(`harness/scripts/run-stock-strata-iq4xs.bat`, windows 2048..40960, port 8093, tag `iq4xs`) and it
wrote no JSONL at all: every start dies in the loader with "blk.0.ssm_alpha.weight is IQ4_XS, expected
F32, BF16, F16 or Q8_0" (four restart attempts in
`glm/2026-11-08_session/stock-strata-iq4xs.log`, engine line `engine-stock/src/qwen35/q36_engine.cu:951`).
So this column is not pending - on `146df3c4` it cannot be filled, and the 40k window that bat queues
was never reached.

### Stock llama.cpp, branch (a) "as shipped"

No `-ngl`, no `--n-cpu-moe`, i.e. CPU inference. Captured 2026-11-08 with ctx 8192 / 32768 / 65536 /
98304, 6 554 characters of prompt (2 928 tokens), 8 answer tokens, `-t 4`
(`harness/scripts/run-stock-llama-cpu.bat`; the port each row records is 8096, which is that bat's -
the older `glm/2026-11-08_session/run-stock-llama-cpu.bat` copy sits on 8093 and was not what produced
these rows). Artifacts
`glm/2026-11-08_session/stock-llama-<ctx>-stock-cpu.jsonl`; every point carries both the cold `warm`
pair (77 tokens) and the main answer. That the run is on the CPU is visible in the recorded command
line (no `-ngl`, hence 0 layers offloaded) and in the server log: `llama threadpool init, n_threads =
4` plus `tensor overrides to CPU are used with mmap enabled`; on 98 304 the log also reports
`n_slots = 4, n_ctx_slot = 98304`.

| window | window fill | prompt tok | pp tok/s | tg tok/s | TTFT | wall | cold pp / tg (77 tok) |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 8 192 | 36 % | 2 928 | 350.7 | 7.75 | 8.35 s | 9.3 s | 36.9 / 4.88 |
| 32 768 | 8.9 % | 2 928 | 344.5 | 7.42 | 8.50 s | 9.4 s | 33.2 / 4.83 |
| 65 536 | 4.5 % | 2 928 | 334.8 | 7.17 | 8.74 s | 9.7 s | 32.7 / 5.94 |
| 98 304 | 3.0 % | 2 928 | 317.9 | 7.00 | 9.21 s | 10.2 s | 31.7 / 4.57 |

Consequence for the hypothesis: the out-of-the-box CPU run does not produce "pp ~100 / tg ~3"
either. The main answer reads 318-351 tok/s prefill and 7.0-7.75 tok/s decode; the cold first answer
on 77 tokens reads 31.7-36.9 and 4.6-5.9. "pp 100" sits between those two readings and "tg ~3" is
below both, so the baseline nobody measured is not reproducible by the default llama.cpp launch, by
stock Strata, or by stock llama.cpp with normal flags. These four points use a short prompt
(2 928 tokens), unlike the 64 651-139 272 token ladder of branch (b), so they are not comparable to
the fork grid; they answer only the question "what does the default launch actually do".

### Stock llama.cpp, branch (b) normal upstream flags

`-ngl 99 --n-cpu-moe 30 -ctk q4_0 -ctv q4_0 -fa on -b 2048 -ub 2048 -t 6 -tb 8`, IQ4_XS, 64 answer
tokens (`harness/scripts/run-stock-llama-gpu.bat`; the `glm/2026-11-08_session/` copy of the same bat
is the earlier pilot - four windows from 48k, with the old `--fill 0.88` prompt lengths baked in as
`--chars` at 3.2 x ctx, which is why its 48k and first 64k rows are excluded below). Captured
2026-11-08, artifacts
`glm/2026-11-08_session/stock-llama-<ctx>-stock-gpu.jsonl`. Prompt length is given in characters of
the same `master.txt` used by the fork grid of 2026-11-07 (window → characters: 65536 → 190 000,
81920 → 230 000, 98304 → 260 000, 131072 → 380 000, 163840 → 440 000), so `prompt tok` in the table
matches the fork points one-to-one and the stock/fork ratio is comparable:

| window | pp tok/s | tg tok/s | TTFT | prompt tok | window fill |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 65536 | 639.3 | 7.65 | 101.13 s | 64 651 | 99 % |
| 81920 | 632.3 | 7.66 | 122.35 s | 77 360 | 94 % |
| 98304 | 619.9 | 7.51 | 139.64 s | 86 568 | 88 % |
| 131072 | 598.3 | 7.05 | 203.54 s | 121 787 | 93 % |
| 163840 | 573.7 | 6.71 | 242.78 s | 139 272 | 85 % |

Two earlier captures are deliberately not in this table: 48k (35 133 tok) and the second 64k row
(45 954 tok). They were taken by the `--fill 0.88` auto-calibration, which - because tokens per
character was overestimated - stopped at 70-72 % of the window instead of the 92-99 % of the fork
grid. Mediating across different fills produced a row that never existed ("65536: pp 641.8 at
55 302 tokens"), so the method was fixed and those two points stay only as a pilot in
`glm/2026-11-08_session/second-grid-sources.md`, section 11a.

Ratios against fork llama.cpp on the same window and prompt (`grid-2026-11-07.md`): pp ×1.49…×1.64
(639.3 against 1050.5 at 64k; 598.3 against 890.8 at 128k), tg ×2.87…×3.17 (7.65 against 24.2; 7.05
against 20.2). There is no comparable fork llama point at 160k - that window was never brought up on
llama - so 573.7 / 6.71 is only comparable with fork Strata there (959.9 / 13.6).

Consequence for the hypothesis: on stock llama.cpp with normal upstream flags neither half holds -
`pp` is 574-639, not ~100, and `tg` is 6.7-7.7, not ~3. `pp` ~100 / `tg` ~3 is not an engine
property; it is a cold-cache, CPU-expert reading, and quoting it as the expected stock performance on
8 GiB of VRAM would be wrong.

## 4. What the fork can do that stock cannot reach

- **Windows above ~32k on stock Strata.** Stock keeps KV in fp32, so 32k already costs 198.88 s of
  TTFT for a 24 483-token prompt (`stock-strata-32768-grid.jsonl`). A 40k stock point was never
  captured and never queued: the ladder bat stops at 32768 by construction
  (`glm/2026-11-08_session/run-stock-strata.bat:23-28`), so the honest statement is "no measurement",
  not "does not fit". What can be said without a run is the memory side of it: fp32 KV for this model
  is 1408 MiB at 32k, 2816 MiB at 64k and 7040 MiB at 160k - the last one on an 8 GiB card with the
  weights still to fit - while the same windows cost 198 / 396 / 990 MiB in q4_0 (measure
  `glm/scripts/probe_kv_geometry_2026_11_08.py`, output
  `glm/2026-11-08_session/kv-geometry-2026-11-08.txt:9-14`). 64k-160k is not available upstream on
  this machine at an acceptable runtime; the fork reaches 160k at pp 959.9 / TTFT 145.1 s
  (`grid-2026-11-07.md:14`). 256k loads only with `NO_MMQ` and was rejected on time, not on memory:
  about 88 minutes per run.
- **KV quantization** is the change that moves the memory ceiling; everything in section 2's fork
  column follows from it plus the reserve.
- **FA + super-chunk prefill** are worth the same-window factor recorded in `grid-2026-11-07.md:29-31`
  (64k 913.8 -> 1504.0, 96k 1024.0 -> 1308.9, 128k 813.4 -> 1091.9 pp).
- **VRAM reserve** (`--vram-reserve-mib`) so the KV allocation does not fight the CUDA context for the
  last megabytes. Checked in the stock tree rather than assumed: the flag is upstream's, but not on
  the q36 path - stock reads it only in its other engine mains (`src/program/generate.cpp:3539`,
  `sycl/src/program/generate.cpp:1938`), its `src/qwen35/` has no such parse and the stock q36 binary
  has no such literal (section 1), while the serve layer adds it only for a `vision.gpu` config
  (`serve/server.py:3836-3837`, key documented at `serve/runconfig.py:42-43`). Our q36 engine parses
  it at `engine/src/qwen35/q36_engine.cu:4384`, which is what makes a per-window reserve (512/768/1024
  MiB in the grid profiles) usable here at all.
- **MTP is orthogonal here**: of the fork's five points only 80k was captured with MTP 2, the rest with
  MTP 0 (`grid-2026-11-07.md:27-28`). That is what puts 80k (1253.6) below 96k (1308.9) despite the
  smaller window - on the same 64k window MTP 2 measures 1350.9 and 1352.6 pp against 1504.0 at MTP 0
  (engine start lines `:62` and `:71` versus `:17` in `harness/logs/strata-kat-iq4xs-64k-super.log`).
  Not a stock-vs-fork difference.
- **Stock llama.cpp is a third case, not a stock Strata case**: with `-ctk/-ctv q4_0 -fa on` upstream
  llama reaches 163840 on this GPU (pp 573.7 / TTFT 242.78 s, section 3, branch (b)), while stock
  Strata's ladder stops at 32k. Answered from code and header arithmetic rather than a new run, because
  the two candidates separate cleanly: the knob is the **KV path**, which upstream llama has as a
  documented flag and stock q36 does not have at all (section 1). On the model's own geometry the KV
  bytes are the whole story at that window - 7040 MiB fp32 for the model of record with its MTP block,
  against 990 MiB in q4_0 (`kv-geometry-2026-11-08.txt:14`); strip the MTP block to the 10 attention
  layers alone and the same arithmetic gives 6400 MiB fp32 / 900 MiB q4_0, which is the row the
  heretic header produces at 163840 (`:28`). The MoE layout is a real second difference
  (`--n-cpu-moe 30` in llama against the q36 expert arena and its slots), but it moves expert
  weights, not KV bytes, so it is not what puts the ceiling on the stock ladder.

Every claim in this section that needs a stock run at the same window on the same model is marked; the
honest framing is "stock cannot get there", not "stock is X times slower".

## 5. How to reproduce

Every command below was re-read from the file it names on 2026-11-08; none of them takes an argument
unless stated. All of them start the server themselves, wait for `/health`, send one request and write
one JSONL record per point.

- Stock Strata ladder, Q5_K_S (source of the section 3 stock points): bat
  `glm/2026-11-08_session/run-stock-strata.bat`, run with no arguments; it calls its own `:point`
  macro for 2048, 4096, 8192, 16384, 24576, 32768 in order, port 8092, config
  `harness/config/stock-strata.json`, `--max-tokens 64 --busy-wait 600 --boot-budget 900 --tag grid
  --model stock-strata`, artifacts `stock-strata-<ctx>-grid.jsonl`.
- Stock Strata ladder, IQ4_XS model of record: bat `harness/scripts/run-stock-strata-iq4xs.bat`, no
  arguments, windows 2048..40960, port 8093, config `harness/config/stock-strata-iq4xs.json`, tag
  `iq4xs`, artifacts `stock-strata-<ctx>-iq4xs.jsonl`. On `146df3c4` it writes nothing - the loader
  refuses the quant (section 3) - and that is itself the result worth reproducing.
- Stock Strata smoke point (the one that failed with HTTP 400): bat
  `glm/2026-11-08_session/smoke-stock-strata.bat`, no arguments; ctx 2048, 6 554 characters, 32 answer
  tokens, port 8092, tag `smoke`, artifact `stock-strata-2048-smoke.jsonl`.
- Stock llama.cpp, branch (a) "as shipped": bat `harness/scripts/run-stock-llama-cpu.bat` (older copy
  `glm/2026-11-08_session/run-stock-llama-cpu.bat`), no arguments; four points 8192 / 32768 / 65536 /
  98304, 6 554 characters, `--max-tokens 8 --boot-budget 1200 --tag stock-cpu`, port 8096, server
  command `llama-server -m <KAT IQ4_XS> -c <ctx> --host 127.0.0.1 --port 8096 -t 4` - no `-ngl`, no
  `--n-cpu-moe`, which is the whole point of the branch.
- Stock llama.cpp, branch (b) normal upstream flags: bat `harness/scripts/run-stock-llama-gpu.bat`
  (older copy `glm/2026-11-08_session/run-stock-llama-gpu.bat`, which stops at 128k and has no 160k
  row). No arguments runs the five ladder points 65536/190000, 81920/230000, 98304/260000,
  131072/380000, 163840/440000; `run-stock-llama-gpu.bat <ctx> <chars>` runs exactly one, because the
  ladder is not restarted for a single window. `MAXT` and `TAG` come from the environment (defaults 64
  and `stock-gpu`; the 256-token re-shoot writes a separate tag instead of overwriting the primary).
  Port 8094, `--reserve 128`, and before each point `gate_ram.ps1 24` must pass. Server command:
  `llama-server -m <KAT IQ4_XS> -c <ctx> --host 127.0.0.1 --port 8094 -ngl 99 --n-cpu-moe 30 -ctk q4_0
  -ctv q4_0 -fa on -b 2048 -ub 2048 -t 6 -tb 8` - every one of those flags is upstream's.
- Fork 64k-160k grid (source of the fork column in section 2): the five `live_strata.py` lines and the
  four `llama_smoke.py` lines are printed verbatim in the artifact itself, `grid-2026-11-07.md:61-73`.
  The same windows through the profile harness are `python harness/scripts/grid_run.py --family
  <heretic-q4km|llmfan-q5|hauhaucs-iq4xs> [--passes N] [--windows 64k,80k,96k,128k,160k]`; profiles
  come from `harness/config/strata-<family>-<window>.json` and the ports from the profiles themselves,
  so the bat cannot drift from the config (`grid_run.py:5-6,38-42`).
- Measurer used by all stock points: `glm/scripts/stock_point.py`; it writes one JSONL record per point
  with `cmd`, `config`, `log` and the measured fields. Prompt `E:\tmp\master.txt`, temperature 0, 64
  answer tokens for Strata and branch (b), 8 for branch (a). Prompt length: `--fill` defaults to 0.90
  (`stock_point.py:153`); with no `--chars` the script calibrates tokens-per-character on a 512..4096
  character slice (`:201`), then takes `chars = int((ctx * fill - reserve - max_tokens) / ratio)`
  (`:204-205`), which is why the ladder rows show 74-86 % of the window rather than 90 % - the
  subtracted reserve is the chat template plus the answer. Branch (b) passes `--chars` explicitly for
  exactly that reason (`run-stock-llama-gpu.bat:6-12`), so its fills match the fork grid's 92-99 %.
- Summary table over the artifacts: `glm/scripts/stock_grid_table.py` (`--engine strata|llama|all`,
  `--tag`, `--out <file.md>`, `--selftest`). It prints median and min..max per point, the repeat count
  as `n/n`, the window fill, and classifies failures from the recorded error text only. The 08.11 run
  of it is kept as `glm/2026-11-08_session/stock-grid-table-2026-11-08.md`; `--selftest` passes 5
  controls (a deleted repeat, a broken line, a refusal row, a mixed-fill split, an empty directory).

## 6. Caveats a reader must not skip

1. **Different capture conditions across the two engines.** The fork column of section 2 is 07.11:
   IQ4_XS, 256 answer tokens, `glm/scripts/live_strata.py`, KV q4_0, FA + super-chunk. The stock
   Strata rows of section 3 are 08.11: Q5_K_S (24.57 GiB), 64 answer tokens, `stock_point.py`, KV
   fp32, no FA. The llama branch (b) rows are 08.11 on IQ4_XS with upstream `-ctk/-ctv q4_0 -fa on`.
   These are comparable as orders of magnitude, not as a ratio. Do not compute a speedup from any pair
   of rows in this file until the same-window, same-model re-capture exists.
2. **One slot per row** in the stock tables - a single bench run, not a distribution. This is checked
   rather than assumed: `stock_grid_table.py` prints a `n/n` repeats column and, on the 2026-11-08
   re-run, it is `1/1` on all 17 successful rows (6 Strata ladder rows, 4 llama branch (a), 7 llama
   branch (b)); the 18th record is the failed smoke row and lands in the "not captured" table
   (`glm/2026-11-08_session/stock-grid-table-2026-11-08.md`). The branch (b) table above has no repeats
   column because its last column is window fill. Where a source did keep repeats we print `median
   (min..max)`; such a source is the fork grid of 2026-11-07.
3. **Timing gate.** Any capture projected above 30 minutes was discarded rather than reported, which is
   why 256k appears as "rejected", not as a number, and why the heretic llama 160k point is absent. It is
   not why the stock Strata ladder stops at 32k: that stop is the ladder script's own construction plus
   the fp32 KV memory cost (section 4), and the empty 160k llama cell is there because that window was
   never brought up on 8 GiB (`grid-2026-11-07.md:47`).
4. **Shared machine noise.** Long runs happened while the IDE and other processes were active: RAM and
   CPU were shared, and in the early series `tg` moved by up to 40 % between repeats of the same bench
   (`second-grid-sources.md:59-60`, bench 0/1/2). The branch (b) rows cannot show this: they are 1/1,
   and the 71.34 s / 101.13 s pair at 64k is not two repeats of one command but two different fills
   (70 % and 99 % of the window), which is why the 70 % point is excluded from the table.
5. **Old points are not reusable as stock points.** The 28.10-29.10 upstream rows use a different
   model, `--n-cpu-moe 99`, `-t 4`, KV q8_0 and short prompts, so they belong to the cold-cache
   discussion in section 3 and not to the table in section 2.
6. **Internal paths.** `glm/...` paths and `E:\tmp\master.txt` are ours, not an upstream user's; they
   must be replaced by a self-contained repro script before this file is sent outward. **That scrub has
   not been done and this file is not sendable yet:** 25 lines of it cite `glm/scripts/...`,
   `glm/2026-11-08_session/...` or `E:\tmp\master.txt` as the location of the measure, the bat or the
   artifact, and no self-contained repro exists in the tree (`harness/scripts/` has no
   `repro*`/`standalone*` script, `docs/guides/` has no repro page). A reader without our disk layout
   can follow the method from section 5 but cannot re-run it as written.
