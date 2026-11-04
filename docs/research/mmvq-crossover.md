# MMVQ/MMQ crossover at small batch sizes

**Status:** measurement. Verdict for step 3.3: the threshold of 8 stays, and nothing is
changed in this profile.

## Where the threshold is

- `ggml/src/ggml-cuda/mmvq.cuh:3`: `#define MMVQ_MAX_BATCH_SIZE 8`.
- `ggml/src/ggml-cuda/mmvq.cu:285`: `get_mmvq_mmid_max_batch(type, cc)`. On NVIDIA with
  compute capability >= Turing (this card is 8.6) the table at `mmvq.cu:177-188` returns 8
  for both IQ4_XS and Q4_0, because neither type is listed and the default is
  `MMVQ_MAX_BATCH_SIZE`. On Pascal and older the table at `mmvq.cu:150-175` gives IQ4_XS 5
  and Q4_0 6.
- The dispatch: `ggml/src/ggml-cuda/ggml-cuda.cu:1933-1937`. For `MUL_MAT_ID`, when
  `ne2 <= MMVQ_MAX_BATCH_SIZE` and `ne2 <= get_mmvq_mmid_max_batch(type, cc)`, the op goes
  to `ggml_cuda_mul_mat_vec_q` (the MMVQ path); above the threshold it takes the MMQ path.
  `ne2` is `dst->ne[2]`, which for `MUL_MAT_ID` is the number of tokens in the batch
  (`ggml/src/ggml.c:3407`: `ne = {as->ne[1], ids->ne[0], b->ne[2]}`).

So the crossover sits at 8 tokens: up to 8 tokens the vector kernel runs, above it the
tiled kernel runs.

## What was measured

A clean worktree at the pinned commit `3cf03257`, no local patches. The cases come from a
patch to `tests/test-backend-ops.cpp` (kept next to this note as `test-crossover.patch`):
`test_mul_mat_id(type_a, F32, n_mats=256, n_used=8, b=false, m=512, n, k=2048)` for
`n` in {8, 9, 12, 16, 24, 32} and `type_a` in {IQ4_XS, Q4_0}. The bench is
`test-backend-ops perf`; the machine is an RTX 3060 Ti, 8191 MiB, compute capability 8.6
("Device 0: NVIDIA GeForce RTX 3060 Ti", run logs).

The table holds medians of three passes over us/run and TFLOPS. Per-case work grows with
`n` (`op_flops = 2*m*k*n*n_used`, `test-backend-ops.cpp:5127`): 134.22 MFLOP at n=8 and
150.99 MFLOP at n=9, so n=9 does 12.5 % more work than n=8.

| type | n=8 | n=9 | n=12 | n=16 | n=24 | n=32 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| IQ4_XS, us/run | 116.19 | 188.99 | 235.46 | 274.35 | 414.01 | 517.85 |
| IQ4_XS, TFLOPS | 1.160 | 0.799 | 0.855 | 0.978 | 0.973 | 1.040 |
| Q4_0, us/run | 84.62 | 153.55 | 253.61 | 233.78 | 347.91 | 445.92 |
| Q4_0, TFLOPS | 1.590 | 0.983 | 0.794 | 1.150 | 1.160 | 1.200 |

## Reading

- n=8 is the MMVQ path and n=9 and above is the MMQ path, by the dispatch rule quoted
  above, so the step from n=8 to n=9 is the threshold crossing itself.
- IQ4_XS: 116.19 us / 1.160 TFLOPS at n=8 against 188.99 us / 0.799 at n=9 — 1.63x more
  time for 12.5 % more work, so throughput falls to 0.69 of the n=8 value.
- Q4_0: 84.62 us / 1.590 against 153.55 us / 0.983 — 1.81x more time, same work growth,
  throughput 0.62 of the n=8 value.

  Note on the ratios: the summary file prints "1.63x time, 0.61x speed", where the speed
  number is the inverted time ratio (116.19 / 188.99). Compared by TFLOPS the drop is
  0.799 / 1.160 = 0.69 for IQ4_XS and 0.983 / 1.590 = 0.62 for Q4_0, since n=9 does more
  work per call.
- Above the threshold the curve climbs back: IQ4_XS reaches 0.978 TFLOPS at n=16 and 1.040
  at n=32; Q4_0 reaches 1.150 at n=16, 1.160 at n=24 and 1.200 at n=32.
- In this profile the threshold is never in play: decode runs at n=1 (MMVQ) and prefill at
  n=2048/8192 (MMQ), with no batch sizes between 9 and 32. There is nothing to change
  here; the numbers matter for configurations that do use batches of 9 to 32.

## Caveats

- The split is indirect: `GGML_CUDA_FORCE_MMQ` was not enabled, so the same path could not
  be run at both n=8 and n=9. The n=8/n=9 difference mixes the path change and the work
  growth, and it does not say what MMVQ would have cost at n=9.
- One measurement per case per pass, and the pass-to-pass spread reaches ~18 %
  (Q4_0 n=12: 191.35 to 257.65 us/run), hence medians of three.
- These numbers belong to this card (compute capability 8.6) and to these two quant
  types. On Pascal the threshold itself is lower (IQ4_XS 5, Q4_0 6), so the crossover
  moves with it.

## Verification

- Rebuild the bench in a clean worktree at `3cf03257`, apply `test-crossover.patch`, and run
  three passes: `test-backend-ops perf -o MUL_MAT_ID`. The medians must reproduce the
  table above.
- Recompute the medians with `python glm/scripts/sum_moe_perf.py run1.txt run2.txt
  run3.txt`; it prints the same rows as the summary file.
- Which path a case took follows from the dispatch rule (`ne2` against the threshold); to
  see it directly, print `ne2` and the branch taken in `ggml_cuda_mul_mat_id`.

## Outcome

Step 3.3 is closed as research: the threshold of 8 stays, because this profile never
runs batches of 9 to 32. The measurement shows the cost of the MMQ path above the
threshold, not that 8 is the optimal crossover; MMVQ was not run at n=9. The numbers and
the test patch stay in the research notes for configurations that do use such batches.
