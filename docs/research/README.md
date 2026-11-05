# Research notes: designs measured and not applied

These notes collect engine changes that were analysed and (where possible) measured on
this fork's reference machine: an 8 GB RTX 3060 Ti, 32 GiB RAM, a 35B-A3B MoE model whose
16.34 GiB of routed experts live in host memory (hybrid mode). Some ideas were rejected
here but are useful on other configurations; others are full designs left for whoever
wants to finish them.

| File | Kind | Summary | Why it is here |
| --- | --- | --- | --- |
| [routing-sync.md](routing-sync.md) | idea | Remove the per-layer `cudaStreamSynchronize` that reads `rmax` | Only helps when every expert fits in VRAM; on a hybrid placement the same sync also carries `rcnt` for the slot score |
| [mtp-only-prompt.md](mtp-only-prompt.md) | idea | Run the MTP block's prompt through MMQ + staging instead of the CPU pool | Needs main layers fully in VRAM, i.e. a model whose experts fit; not reachable with 16.34 GiB of experts in 8 GB |
| [llama-h2d-overlap.md](llama-h2d-overlap.md) | closed | Overlap expert H2D copies with compute in llama.cpp | Ceiling +3-7 % pp (no layer look-ahead); upstream master already gives +7.2-8.5 %/+7.1 %, and 128k has no VRAM for a second staging slot |
| [mmvq-crossover.md](mmvq-crossover.md) | closed | MMVQ/MMQ crossover for `MUL_MAT_ID` at 9-32 tokens | n=9 takes 1.63-1.81x the n=8 time, but the profile runs n=1 (decode) and n=2048/8192 (prefill), so the threshold is untouched; `test-crossover.patch` is next to it |
| [rejected-levers.md](rejected-levers.md) | measurement | Flags and kernels that were tried and were slower | Numbers so nobody repeats them |
| [super-chunk.md](super-chunk.md) | applied | Layer-major prefill: stage each layer's experts once per N chunks | N=4 gives +25/+28/+21 % pp at 64k/96k/128k; bit-identical at N=1 |
| [fa-attention.md](fa-attention.md) | pilot | Prompt attention on mma.m16n8k16: no score buffer, one launch per layer per chunk | Replaces ~45 000 cuBLAS launches at 96k; gated by G1-G5 |
| [audit-fork-2026-11-04.md](audit-fork-2026-11-04.md) | audit | Where the time goes in the fork: expert weight delivery, not GPU kernels | The measured lever is the prefill chunk size (96k: 573.8 -> 1094.3 pp at 2048); moving the engine to upstream master is a no-go |

The applied optimizations are in `engine/docs/profile-q36.md` and in the commit history
(`pacc` under T ≤ 8, L2-ordered split-K, per-layer pinned arena, `--att-mb`,
profiler, route count+scan, llama pinned/expert profile; super-chunk in
[super-chunk.md](super-chunk.md)).

Measurement conventions used in every note: one GPU run at a time, full GGUF (KAT IQ4_XS),
memory clock +1003 MHz, medians of three bench passes, first pass of a series discarded
as warm-up noise.
