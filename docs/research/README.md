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
| [llama-h2d-overlap.md](llama-h2d-overlap.md) | closed | Overlap expert H2D copies with compute in llama.cpp | Ceiling +3-7 % pp (no layer look-ahead); upstream master already gives +8.5 %/+5.5 %, and 128k has no VRAM for a second staging slot |
| [rejected-levers.md](rejected-levers.md) | measurement | Flags and kernels that were tried and were slower | Numbers so nobody repeats them |

The applied optimizations are in `engine/docs/profile-q36.md` and in the commit history
(`pacc` under T ≤ 8, L2-ordered split-K, per-layer pinned arena, `--att-mb`,
profiler, route count+scan, llama pinned/expert profile).

Measurement conventions used in every note: one GPU run at a time, full GGUF (KAT IQ4_XS),
memory clock +1003 MHz, medians of three bench passes, first pass of a series discarded
as warm-up noise.
