# Overlap expert H2D copies with compute (llama.cpp)

**Status:** design. Requires a planner change; not a parameter.

## Where

- `llama.cpp/ggml/src/ggml-backend.cpp:1693-1793`: for a `MUL_MAT_ID` whose weights are in
  a host buffer, only the used experts are copied, grouped by consecutive ids. Before the
  copies the scheduler calls `ggml_backend_synchronize(input_backend)` (1705); the copies
  use `ggml_backend_tensor_set_async` into the target backend.
- `ggml-backend.cpp:1401-1412`: one copy buffer per backend (`cur_copy`) — a single
  staging area.
- `llama.cpp/ggml/src/ggml-cuda/ggml-cuda.cu:2445-2450`: `set_tensor_async` issues the H2D
  into the backend's compute stream.
- `llama.cpp/src/llama-context.cpp:247, 3436-3439`: the graph is sliced into ubatches;
  the planner copies each node's inputs right before the node runs.

Consequence: copies and MMQ kernels share one stream and one buffer, so H2D of a layer
cannot run while the previous layer computes.

## Design

1. A dedicated copy stream in the CUDA backend (`cudaStreamCreateWithFlags(nonBlocking)`).
2. A second staging buffer for `MUL_MAT_ID` weights (double buffering); `+0.9 GiB` VRAM for
   this model (0.42 GiB per layer).
3. Overlap inside a layer. The ids of a layer arrive only after its router, so the
   gate/up copies of that layer cannot start earlier. What can overlap is the down-expert
   copy, which may run on the copy stream while the gate/up MMQ is busy (about a third of
   the layer's traffic). A look-ahead to layer L+1 is impossible without reordering: the
   ids of L+1 depend on layer L's output.
4. Ids themselves are device tensors; a D2H of the tiny ids tensor can go on the copy
   stream with its own event (today it is a synchronous get, `ggml-backend.cpp:1725-1728`).
5. Keep the current path as a fallback when the buffer cannot be allocated or when graphs
   are disabled (`ggml-cuda.cu:2569-2580` disables graphs for the synchronous fallback).

## Expected effect

The prompt path copies ~0.42 GiB per layer; at 22–26 GB/s (pinned) that is ~17 ms per
layer, ~450 ms per 26 layers, against a ~140 s 128k prefill — the win comes from removing
the per-layer synchronize and from overlapping the down copy with the gate/up MMQ, not from
bandwidth alone. Upper bound in measurement terms: **pp +8–20 %** (the earlier +15–35 %
assumed a one-layer look-ahead, which the ids dependency rules out).

**8 GB note.** The second staging buffer costs ~0.9 GiB. On this card 128k already uses
~7.5 GiB, so the overlap can only run with a smaller window (96k), with `ncmoe` lowered by
1–2 layers (~0.4 GiB each), or with a smaller `-ub`. Measure the VRAM headroom first;
otherwise the patch turns an OOM into a feature.

## Measured on the reference machine (03.11)

With `GGML_MOE_TRACE=1` on a 128k run (fill 117 753, pinned, `-ub 8192`, `ncmoe 30`):
5220 expert-copy calls across 90 nodes, **660.8 GiB** copied; at 22–26 GB/s that is
**27–32 s of H2D inside a 142 s prefill (~20 %)**. A full overlap can therefore return at
most about 20 % pp; a realistic target for the design above is +8–15 %.

## Verification

- `bench_dialog.py` 128k (pinned): first pass pp/TTFT, passes 2–4 tg; compare with the
  current 831.7/20.4/141 s.
- Outputs must match the plain path on a short prompt (`/completion`, temperature 0).
- Build against both the vendored tree and the git clone; keep the patch in
  `engine-upstream` so upstream can take it separately.

## Risks

- Stream ordering bugs are silent and data-dependent; events must guard every buffer reuse.
- CUDA graphs capture streams and events; the patched path may need graph capture support
  or must run without graphs.
- Extra VRAM can push a tight placement into OOM; keep the fallback.

## Outcome 04.11.2026: closed as research

Measured on upstream master `149f5641b` with the same flags (`--load-mode none`,
`-ub 4096` at 96k, `-ub 8192` at 128k, `ncmoe 30`, pinned):

| lever | result |
|---|---|
| upstream master, no code | pp **923.7-934.7** at 96k (+7.2...+8.5 % over 861.8), **890.7-890.9** at 128k (+7.1 % over 831.7), tg in the noise; output SHA is identical with and without the upload-stream patch |
| `GGML_SCHED_COPIES=2` | `n_copies>1` marks every input copy `OUTPUT` and adds it to the graph leafs (`ggml-backend.cpp:1787-1797`, 1971-1996), so all MoE staging buffers live for the whole graph: 26 000 MiB requested at 128k and 25 777 MiB at 96k (measured on master, 04.11) |
| second staging buffer | ~0.4-0.9 GiB; 128k has ~0.5 GiB free, 96k ~1 GiB |
| `--moe-cache-mib` | measured worse on 8 GB: pp/tg 913/15.4-16.3 (64 MiB), 912/15.4-16.1 (128 MiB) at 96k, tg 15.0-15.4 at 128k |

Why the ceiling is lower than this document first assumed: the ids of layer L+1 are
produced by the router of layer L, so no layer look-ahead exists. Only the down-expert
copy (about one third of a layer's H2D) can overlap with the gate/up MMQ. With 27-32 s
of H2D in a 142 s 128k prefill, that is **+3-7 % pp**, below the +8.5 % already obtained
by updating the tree, and it needs VRAM that 128k does not have plus disabled CUDA
graphs for the MoE splits. Decision: do not build the ring buffer; run on upstream
master, keep the upload-stream and `GGML_SCHED_COPIES` patches as diagnostics only
(`h2d-hooks` branch, env-off is the old path).
