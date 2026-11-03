# MTP-only prompt through MMQ + staging (q36)

**Status:** idea, not implemented. Unreachable on the reference machine (experts do not fit).

## Where

`engine/src/qwen35/q36_engine.cu`:

- `E.main_hybrid = !mtp_only` (q36:3266); in the `mtp_only` placement the main layers hold
  every expert in VRAM and only the MTP block is hybrid.
- `hy_rows = lhy(li) && (T <= hybrid_t || !main_hybrid)` (q36:2307): `!main_hybrid` makes
  **every** batch of the MTP layer take the slots + CPU-pool path, prompt chunks included.
- Staging is allocated only `E.use_mmq && E.main_hybrid` (q36:3271-3272), and
  `stream_begin` for the MTP layer is gated on `main_hybrid` (q36:2442).

## Effect

A 32768-token prompt chunk of the MTP block is computed by the CPU pool. In the hybrid
runs measured on this machine the pool took 6–8.6 s per 32768 chunk across all layers; for
one MTP layer the same code path is the whole prompt cost. A streamed MMQ path would read
the MTP layer's experts once over PCIe (a few hundred MiB) and run on the GPU.

## Design

1. Allocate the staging pair when `E.use_mmq` (not only `main_hybrid`); size as today,
   `2 * (max_layer + kMmqTail)` (q36:3271).
2. In the `hy_rows` condition drop `|| !main_hybrid` when staging exists, so
   `T > hybrid_t` prompt chunks of the MTP layer take the MMQ path; `T <= hybrid_t`
   batches keep the GPU+CPU split.
3. Extend `stream_begin` (q36:2438-2452) to the MTP layer sequence when it is the only
   hybrid layer; `stream_take`/`stream_done` already handle `lhy(li)` (q36:2330, 2344).
4. Keep `mtp_only` without staging when VRAM cannot hold it (fallback to today's path).

## Verification

- Bit-identical MTP drafts: `--mtp 2 --draft-vocab 8192` and `--tokens … --n 64`, compare
  outputs with and without the change; drafts accepted must match.
- `--bench-pp` on a small model where main experts fit (the only setup that reaches
  `mtp_only`), then a full GGUF dialog run.
- Watch VRAM: staging is 2 × the largest layer; on a card that just fit the experts this
  may need `--vram-reserve-mib` headroom.

## Risks

- The MTP block's drafts feed the speculative window; a changed path must be bit-identical
  or the accept rate changes silently.
- Adding staging can push a tight placement into OOM; keep the fallback.
