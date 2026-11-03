# Remove the per-layer `rmax` wait (q36)

**Status:** idea, not implemented. Measured as not applicable to a hybrid placement.

## Where

`engine/src/qwen35/q36_engine.cu`, the MMQ prompt path of `layer()`:

- `cudaMemcpyAsync(hpin + 10, rmax, 4, cudaMemcpyDeviceToHost, st)` and, for hybrid
  layers, `cudaMemcpyAsync(h_cnt …)`, followed by `cudaStreamSynchronize(st)`
  (q36:2324-2326 in this tree).
- `rmax` is `k_route_scan`'s `max_rows` (q36:680-691), consumed as `Product::max_rows`
  for both expert products (q36:2334, 2342); MMQ picks its tile `J` from it
  (`src/prefill/moe_mmq.cu`, tile selection `mmq:349-375`).

## Why it was not applied here

- The same `cudaStreamSynchronize` that delivers `rmax` also delivers `rcnt`
  (per-expert counts) for `hy[li].score` (q36:2336-2339). With 16.34 GiB of routed
  experts on an 8 GB card every prompt layer is hybrid, so the sync is needed anyway.
- The idea only pays off when the main layers are fully in VRAM (small model, or the
  `mtp_only` placement where only the MTP block is hybrid — see
  [mtp-only-prompt.md](mtp-only-prompt.md)).

## Design for an all-in-VRAM placement

1. `max_rows` upper bound: set `Product::max_rows = n_ent` (or `min(n_ent, tmax*Kp)`)
   and drop the D2H+sync. The MMQ grid becomes wider than necessary; the tile pick may
   choose a different `J`, which can cost more than the saved barrier. Measure both.
2. Device-side `rmax`: keep the value in device memory and let the MMQ launcher read it;
   today the API takes a host `int`, so this needs an MMQ API change (a device pointer
   field in `Product`).
3. Deferred `rcnt`: when the score is only needed per request (non-hybrid does not use
   it), copy `rcnt` once per `forward` instead of per layer. `rmax` still needs a
   per-layer host value under option 1 only.

## Verification

- A/B 16k and 96k (`--bench-pp 32768 --bench-tg 64`), full GGUF; accept pp +5 %, decode −2 %.
- Compare outputs token-for-token (`--tokens 1,2,3 --n 24`), because a wrong `max_rows`
  would truncate expert rows silently.
- Check the tile pick in the MMQ log; a smaller `J` can show up as slower prefill.

## Risks

- A too-small `max_rows` drops rows (wrong answer, no error); the upper bound must be
  exact or larger.
- A larger grid costs launch overhead on short prompts (16k), where MoE is already 91 %.
