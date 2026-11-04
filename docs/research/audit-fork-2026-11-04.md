# Fork audit: where the time actually goes (EN)

**Status:** code audit plus the customer's own measurements. Verdict: the bottleneck is
not in the GPU kernels but in delivering expert weights; the measured lever is the
prefill chunk size; moving the engine to upstream master is a no-go.

## Scope and method

Two halves of the fork were read: the engine `engine/` (branch `engine-on-master`) and the
llama.cpp fork `llama-master` (branch `h2d-hooks`, `2a7086597` = upstream master
`149f5641b` plus upload-stream, `GGML_SCHED_COPIES` and D2D tracing).

Three areas: decode and KV, prefill orchestration, the engine's own CUDA kernels. Plus a
separate pass over the MMQ dispatcher, the llama fork's patches, and the machine's
specifics.

Limits: read-only audit — no build, no GPU run, no change in anyone's tree. Every number
below is either measured by the customer (marked "measured") or computed from the code's
own formulas (marked "computed"). Full reports with anchors live outside the project:
`glm\2026-11-04_session\strata-master\`.

## Which code path actually runs

The "pp 568-584 on 96k" figures are **not** `src/prefill/prefill.cpp` but a separate
engine, `src/qwen35/q36_engine.cu` (`strata-q36`): `src/program/generate.cpp:3271-3283`
routes a file with architecture `qwen35moe` into `strata::qwen35::run()`.

- `src/prefill/prefill.cpp` serves a different family (geometry hard-coded at `:207`:
  `N = 2560, HC = 4, K = 10, NE = 512` — top-10, 512 experts);
- `src/split/*` is a third independent engine, `fnx` (multi-GPU);
- the `qwen4exp` branch (`src/core/*`, `src/spec/*`, paged KV `kv_q4.cu`/`kv_q8.cu`) is the
  path for Qwen3.8-Flash-Next: 37.6-54.8 GiB RAM+VRAM per `docs/MODELS.md:38-48`, so it
  does not fit 8 GiB VRAM and 32 GiB RAM.

Consequence for reading any report: findings about `prefill.cpp` and `split/*` do not
carry over to the 96k figures, and the `qwen4exp` branch never runs on this machine.

## Area 1: decode and KV

**Decode is bound by host RAM bandwidth, not by the GPU** (computed from
`q36_engine.cu:2623`): the CPU pool reads about 41 layers × 8 choices × (1−S/256) × 1.63 MiB
≈ **487 MiB of expert weights per token** — 26-35 ms of a ~45 ms token at 15-20 GiB/s of
RAM bandwidth. The GPU manages ~1-1.4 GiB of traffic in that time (2.5-3 ms) and idles. So
GPU-side decode optimizations yield single-digit percentages; the cure is more resident
slots, a cheaper host copy of the experts, or overlapping CPU and GPU.

| finding | where | expected | class |
| --- | --- | --- | --- |
| the MTP block claims slots, VRAM and RAM **even with `--mtp 0`**: 2.4 % of expert slots, ~0.4 GiB RAM, 1/11 of KV | `q36_engine.cu:1244-1245`, `:3181-3183`, `:3304-3305`, `:1548-1562` | direct headroom for experts | their machine only |
| the hybrid stack (attention + SSM) **disables the CUDA graph** — about 800 kernel launches per token | `q36_engine.cu:3271` | large, but needs analysis: can the graph be enabled for a hybrid stack? | universal |
| non-KV buffers eat expert slots: staging 834 MiB, `k16`/`v16` 201-268 MiB, score buffer 384 MiB, `router_ext` 86 MiB; every +8k of window ≈ 4.3 expert slots per layer | `q36_engine.cu:3275`, `:1400`+`:1637`, `:1638-1639`, `:1635`, `:1275-1279` | freed VRAM = more slots = fewer RAM reads | their machine only |
| split-K attention reads KV 8× more than needed because of GQA, and `q4_0` is dequantized byte by byte | `q36_engine.cu:2295-2300`, `:475`, `:344-386` | 1-3 ms/token on 96k | universal |
| GPU↔CPU-pool work is serialized per layer; busy-wait `cudaEventQuery` 41× per token; the activation is quantized twice (GPU `:1964` and host `:2617`) | `q36_engine.cu:2578-2639`, `:2596-2597` | no CPU/GPU overlap | universal |
| **no Walsh-Hadamard for `q4_0` KV**, although the code already exists in `kv_q4.cu:25-69` | `q36_engine.cu:294-386` | not a speedup but quality: measured `q4_0` degradation is 62 matching symbols against fp32 versus 471 for `q8_0` | universal |

Routing is not a problem: top-k and grouping are fused into one launch
(`q36_kernels.cuh:309-397`), and nothing is recomputed.

## Area 2: prefill orchestration

**About 806 GiB of H2D per prompt** (computed: 46 chunks × 16.34 GiB; at `h2d_gbps = 12.0`,
a project constant in `include/strata/program/prefill_plan.hpp:36`, that is 65-80 s of a
~160 s TTFT). The cause is chunk-major prefill: every chunk copies the whole expert set of
every layer into VRAM again (`q36_engine.cu:2418-2423` → `:2536`).

| finding | where | expected | class |
| --- | --- | --- | --- |
| the chunk rule is a hard ladder over free VRAM, 4096 is never chosen automatically | `q36_engine.cu:4275-4281` | measured, see below | universal |
| **there is no super-chunk pass**, although the neighbouring engine has one ("the layer's experts are staged ONCE for every sub-chunk of the super-chunk") | `q36_engine.cu:2418-2423` against `prefill.cpp:6585`, `:6595`, `:6619` | 4× fewer bytes over PCIe without bigger MMQ buffers; high risk (needs the state of all layers at once) | universal |
| on WDDM `cudaEventRecord`/wait cost ≈80/45 µs against ≈3/0 on Linux, one event per streamed expert (≈480k records and waits per prompt); `STRATA_PREFILL_COPY_EVENT_EVERY` and `STRATA_PREFILL_COPY_WAIT_DEDUPE` are **off by default** | `prefill.cpp:3702-3705`, `:3749-3756`, `:3806-3851`, `:3869-3881` | from single digits to tens of percent | Windows only |
| the planner model that accounts for H2D and page-cache misses is **not wired up** — the real scan looks at VRAM only | `include/strata/program/prefill_plan.hpp:81-128` (no callers) against `generate.cpp:9335-9400` | potentially large | universal |
| the expert blob is copied twice: `pread` into a pinned buffer, then DMA into VRAM; with 16.34 GiB of experts the set does not fit the page cache (32 GiB RAM), so every chunk re-reads it from disk | `expert_source.cpp:2053-2057`, `expert_cache.cpp:797` | the RAM tier on the q36 side already gave +73 % | their machine only |
| the "whole layer from host" branch recomputes the 23-37 experts that are already in VRAM slots; the code comment records the **opposite** measurement (whole 1970 against runs 1540) | `q36_engine.cu:2535-2553` | single-digit percent, needs a re-measure | universal |
| the per-layer barrier drags along `rmax` (needed for the MMQ tile choice) and `rcnt` (needed only for the routing count) | `q36_engine.cu:2339-2343` | small on hybrid; disappears entirely when everything sits in VRAM | universal |
| weight-stationary is compiled but `mode()` requires cc 6.0, so it is always off on their card | `src/prefill/moe_ws.cu:57-71` | no lever on a 3060 Ti | — |

## Area 3: the engine's own CUDA kernels

**None of the audited files executes in prompt mode** on their machine:

- `moe_ws*.cu` — `moe_ws.cu:57-67` requires cc 6.0 on every visible GPU, so `mode()` is
  always 0; moreover `CMakeLists.txt:2306` builds them only with `STRATA_EXPERIMENTAL_SM60`,
  and CUDA 13 cannot target sm_60;
- `moe_fused_iq.cu` — `gu_covered()` (`:1873-1881`) covers `Q4_K` and `Q5_K` only on HIP
  gfx11; on CUDA their pack is covered under no flag combination;
- `native_gdn.cu`, `fused_gdn.cu`, `native_bf16.cu` — the qwen35 engine computes GDN with its
  own `k_gdn_seq` and `k_gdn_seq_cols`, and `fused_gdn_conv_l2` is explicitly refused
  (`q36_engine.cu:2191`);
- `iq_kernels.cu` is alive but serves the qwen35 decode, not the prompt (the prompt goes
  through `MMQ::Context::run`).

That matches their own measurement in `docs/profile-q36.md`: 91 % of the time in MoE, 71 % of
it in the CPU pool, and the ×1.7 on prompt came from the pinned host arena, not from kernel
code.

What is genuinely on their path and checkable without rewriting code:

- `STRATA_KQ_SPLIT` is **not enabled** (`iq_kernels.cu:908-910`): their `Q4_K` and `Q5_K`
  experts in the qwen35 decode decode the weight per column instead of once per four. The
  flag is bit-neutral (verified by `iq_multi_parity`) and the sm_86 defaults table does not
  have it;
- `STRATA_OLD_IQ_MMVQ` (`iq_kernels.cu:3417`) keeps a deliberately worse path in the binary;
- the 2560/640/80 geometry is hard-coded: `row_dot_80_sub16`, `native_gu_swiglu_kernel`,
  `expdec`, S26 and S27 are unreachable at their 2048×512; `STRATA_GU_SWIGLU=1` is on by
  default but no code takes it (check with `cuobjdump` over the symbols);
- `native_gdn.cu` reads the state with a 24 KiB stride between lanes (`iq_kernels.cu:60`,
  `:62`, `:81-82`) — 8× traffic inflation; `fused_gdn.cu` reads the same state coalesced.

## MMQ dispatcher, the llama fork's patches, and the machine

- **The fused swiglu + quantization path is blocked by an architecture gate**:
  `moe_mmq.cu:152`, `:836`, `:846` require `STRATA_EXPERIMENTAL_SM60` (a Pascal/Volta build).
  On their card (cc 8.6) it is not compiled at all, although the engine knows the path and
  knows how to enable it (`prefill.cpp:5086`, `:5817`) — the condition is simply never true.
  The author's comment says the path is bit-identical. Effect: 1280 float read and 640 float
  written per row per group less, and one VRAM buffer (`H_g`) less.
- **Expert row width mismatch**: the engine uses 640 (`prefill.cpp:5302`, `:5311`;
  `moe_mmq.cu:111` — "codes [1280][640 B]"), the model card says
  `expert_feed_forward_length = 512`. If 640 is padding, MMQ computes 25 % more rows per
  layer. Checkable without edits: `mmq_expert_bench` prints `R` per shape.
- **RAM is at the limit**: 32 GiB = a 17-23 GiB model file in the Windows file cache + an
  8 GiB safety headroom on Windows (`ple_residency_test.cpp:80-87`), and only what is left
  goes to the arena. When it does not fit, the engine prints "Free RAM or lower
  STRATA_RESIDENT_HEADROOM_GIB" (`expert_source.cpp:4201-4204`) — that line means some
  experts come from disk. Candidates: `STRATA_UNBUFFERED_LOAD=1`, `--ram-keep-gib`,
  `STRATA_RESIDENT_HEADROOM_GIB`.
- **Their upload-stream on 8 GiB and PCIe 3.0 stalls the host**: the 64-slot ring is walked
  within one graph pass, so a slot is busy more often than the host can refill it;
  `GGML_SCHED_COPIES` is ruled out by memory (`n_copies=2` needed 25 777 MiB). Both patches
  are llama-profile only: the engine does not compile `ggml-cuda.cu` and does not use
  `ggml_backend_sched`.
- **Machine clarification**: the RTX 3060 Ti is GA104, i.e. **Ampere**, cc 8.6, 38 SM, 100 KiB
  of shared memory per block; int8 tensor cores (`mma.m16n8k32` with s8) and `cp.async` are
  present — visible in their own code (`src/prefill/moe_fused.cu:182-218`: the
  `__CUDA_ARCH__ >= 800` branch, while `>= 750` is marked Turing on their side).

## Measured: prefill chunk size

Customer's measurement on 96k (KAT IQ4_XS, 96k window, the same bench_dialog scenario):

| chunk | pp | tg | expert slots per layer |
| --- | ---: | ---: | ---: |
| 1024 (before) | 573.8 | 21.4 | 23 |
| **2048** | **1094.3** | 20.6-21.7 | 18 |
| 4096 | 1608 | 17.3-19.7 | 3 |

On 128k the ceiling is 2048: at 4096 no expert slot is left in VRAM ("0 of 256" in the log),
the whole MoE moves to the CPU, and 128k gives 586.2 pp against 648.3 at 2048.

Mechanism: what shrinks is not only the traffic but the **number of full passes over all 41
layers** — every chunk walks all layers again. The gain therefore does not add up with the
PCIe share, it multiplies by the layer count. The price is decode and the number of expert
slots: the freed VRAM is eaten by MMQ buffers for the larger chunk.

## Moving the engine to upstream master: no-go

| point | base `3cf03257` | `engine-on-master` | delta |
| --- | ---: | ---: | ---: |
| 96k bench | 573.8 / 21.4 | 587.7 / 22.4 | +2.4 % pp, +4.7 % tg |
| 128k live | 648.3 / 14.0 | 512.2 / 14.8 | **-21 % pp** |
| serve A/B decode | 26-28 tok/s | 24-27 tok/s | worse |

Reasons from the code: the move brings master's API (`J_best`, `prec_src1`) and its tile
choices, while the engine has its own expert layout (640 against 512, see above); on 128k,
where there are many layers and few chunks, that is what costs 21 %. Fusing gate/up in MMQ
gave nothing (586.4 against 587.7): the engine already computes gate and up in one launch,
while the llama path has two, and removing that second launch is what gives +7.2-8.5 % pp
there.

## What to do, in order

1. **Chunk size** — the only measured lever, no code needed: `STRATA_Q36_CHUNK` for 96k, and
   not above 2048 for 128k.
2. **Expert slots** — now the scarce resource: MTP with `--mtp 0` (2.4 % of slots),
   `STRATA_Q36_ATT_MB=64`, `--vram-reserve-mib 512`, dropping `k16`/`v16` for long windows.
   Every freed GiB ≈ 1.6 % of traffic.
3. **Super-chunk** — 4× fewer bytes over PCIe, high risk: needs the state of all layers at
   once.
4. **Fused swiglu + quantization** — drop the `STRATA_EXPERIMENTAL_SM60` gate from
   `moe_mmq.cu:152`, `:836`, `:846` and move the main prefill branch to the fused call
   (`prefill.cpp:5311-5315`, `:5391-5395`) where there is no Hadamard on `H_g`. The numbers
   should match.
5. **Expert row width** — read `R` in the `mmq_expert_bench` shapes: if it is 640 against
   512, that is 25 % more MMQ work, and the question is the codes format, not the code.
6. **WDDM events** — `STRATA_PREFILL_COPY_EVENT_EVERY=16` and
   `STRATA_PREFILL_COPY_WAIT_DEDUPE=1` (for the strata contour, not q36).
7. **KQ-split and the old MMVQ** — `STRATA_KQ_SPLIT=1` (K-quant decode), bit-neutrality
   verified by `iq_multi_parity`.

Touch points for this note: `docs/research/README.ru.md` and `README.md` (the index), this
file.
