# Levers tested and rejected (with numbers)

Reference machine: RTX 3060 Ti 8 GB, 32 GiB RAM, KAT IQ4_XS (qwen35moe), memory clock
+1003 MHz. q36 measurements at 96k unless stated; llama at 128k/96k with pinned host memory.

| Lever | What was tried | Result | Verdict |
| --- | --- | --- | --- |
| `quantize_scatter` for MoE activations | T embeds quantized once and scattered by `rinv` instead of T·Kp quantized copies | 96k pp 285.6–311.7, tg 20.6–22.3, CPU pool 5062 ms vs pp 325.1–326.2, tg 23.3–23.7, pool 4597 ms | slower: the scatter pass costs more than the 8× re-read it removes |
| `swiglu_quant` (fused SwiGLU + q8) | use the fused kernel instead of swiglu + quantize | compiled only in `STRATA_EXPERIMENTAL_SM60` builds | unavailable on sm_86 |
| `GGML_OP_OFFLOAD_MIN_BATCH=1` (llama) | run MoE on the GPU even for 1-token decode | pp 825.6 (better), tg 14.0 vs 18.9 (pinned `-ub 4096`) | rejected: PCIe latency per token beats the CPU path |
| `-ub 128` / `-ub 64` (llama) | fewer experts per ubatch to shrink H2D | prefill 133 tok/s vs 654–800 | rejected: MMQ efficiency dominates |
| `-ub 8192` at 96k (llama) | larger ubatch | pp 870.4 (+1 %), tg 20.7–20.8 vs 21.2–21.9 | use only at 128k (831.7/20.4 vs 800.5/18.9 at 4096) |
| `ext` router product for T > 8 (q36) | fused router + shared-gate row for prompt chunks | pp 569 (+1 %), tg 17.7–19.2 vs 18.6–21.1, GPU expert share 11.8 % vs 25.6 % | rejected: the fused product changes borderline top-k choices, routing shifts |
| `--hybrid-rows 1024` (q36) | move a prompt chunk from PCIe streaming to slots + CPU pool | prefill 8192 did not finish in ~5 min (default 128: ~30 s) | rejected: 4 CPU threads cannot feed it |
| `--pool-workers 4` / `8` (q36) | more CPU threads than the default 3 | 4: 309–339 pp / 22.5–26.3 tg; 8: 306–312 pp / 14.8–16.9 tg vs 336.9–345.9 / 25.5–26.0 | keep default 3 (4 physical cores, hyper-threading hurts) |
| `--vram-reserve-mib 512` at 80k (q36) | smaller reserve for more expert slots | 256.7 pp / 16.9 tg vs 275.7 / 16.4 at 768 | 80k/96k keep 768; 16k uses 512 (36 slots vs 32) |
| attention buffer 32M floats (q36) | smaller scores buffer for more expert slots | pp 243–308, tg 17.3–22.7 vs 289–312 / 19.0–20.4 | keep 64M (now `--att-mb 256`) |
| `STRATA_Q36_ATT_MB=128` after `pacc` (q36) | +3 slots at 96k before the `pacc` fix | 20 slots, pp 289–301, tg 17.9–19.1; after `pacc` the slot count is set by the arena, not this buffer | re-measure only when slots are the limit |

| RoPE cos/sin table per step (q36 patch B2) | fill a `[T][3][half]` table once per step instead of `powf`/`sincosf` per element | SHA diverges (tokens `198 220 220…` vs `1020 198 220…`), 96k pp 743.8/tg 17.3 vs 800.9/16.7, 128k 673.3/14.8 vs 673.0/15.5 | rejected: not bit-identical and slower |
| CUDA graphs (llama, `GGML_CUDA_GRAPH_NODES` counter) | count graph nodes/chunks to see if the decode graph is split | the counter never fires: `ggml_cuda_graph_check_compability` disables CUDA graphs whenever `MUL_MAT_ID` needs a stream sync, which is the case with `--n-cpu-moe` (PR #18958) | lever unavailable with CPU-offloaded MoE |

Rule of thumb from these runs: on a hybrid MoE placement, moving bytes over PCIe or
reordering work inside the CPU pool rarely pays; removing VRAM waste (slots) and making
host memory pinned paid the most.
