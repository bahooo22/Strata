# MMVQ vs MMQ at small MoE batches (measured 04.11)

**Status:** research, not applied. The working profile has no batches in 9..32.

## Why this matters

`get_mmvq_mmid_max_batch` sends `MUL_MAT_ID` with `n <= 8` to MMVQ and `n > 8` to MMQ
(Turing+ default 8, `ggml/src/ggml-cuda/mmvq.cu:150-188`; dispatch
`ggml/src/ggml-cuda/ggml-cuda.cu:1824`). The hybrid 35B-A3B workload decodes at n=1 and
prefills at n=4096/8192, so the threshold is irrelevant here. Small local models and
agent turns with short batches can sit exactly in 9..32, where the choice is untested.

## Method

- Clean worktree `3cf03257`; `test-backend-ops perf -o MUL_MAT_ID -b CUDA0 -p "n_mats=256"`.
- Shape: `n_mats=256`, `n_used=8`, gate/up `m=512, k=2048`, types IQ4_XS and Q4_0,
  `n = 8, 9, 12, 16, 24, 32`.
- Three runs, median. Test patch: `glm/2026-11-04_session/test-crossover.patch`.
- Caveat: `test-backend-ops` reports one measured run per case; the median is across
  three process runs.

## Results (median of three runs)

| type | n | us/run | TFLOPS | us per 1k tokens |
| --- | ---: | ---: | ---: | ---: |
| IQ4_XS | 8 (MMVQ) | 116.19 | 1.160 | 14.52 |
| IQ4_XS | 9 (MMQ) | 188.99 | 0.799 | 21.00 |
| IQ4_XS | 12 | 235.46 | 0.855 | 19.62 |
| IQ4_XS | 16 | 274.35 | 0.978 | 17.15 |
| IQ4_XS | 24 | 414.01 | 0.973 | 17.25 |
| IQ4_XS | 32 | 517.85 | 1.040 | 16.18 |
| Q4_0 | 8 (MMVQ) | 84.62 | 1.590 | 10.58 |
| Q4_0 | 9 (MMQ) | 153.55 | 0.983 | 17.06 |
| Q4_0 | 12 | 253.61 | 0.794 | 21.13 |
| Q4_0 | 16 | 233.78 | 1.150 | 14.61 |
| Q4_0 | 24 | 347.91 | 1.160 | 14.50 |
| Q4_0 | 32 | 445.92 | 1.200 | 13.94 |

## Reading

- MMVQ at n=8 is 1.63× (IQ4_XS) and 1.81× (Q4_0) faster in total time than MMQ at n=9,
  and stays better per token up to n=32; MMQ efficiency only slowly recovers.
- Raising the threshold to 16 or 32 would help a workload with short batches by roughly
  10–20 %, but it changes the MMQ tile choice (`src/prefill/moe_mmq.cu`, tile selection)
  and needs an A/B on the target model.
- Not applied: decode is n=1, prefill 2048/4096/8192 on this machine, so the patch would
  be dead code. The numbers and the patch are here for configurations that do use
  9–32-token batches.
