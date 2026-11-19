# MMQ was removed by upstream, and 160k prefill died with it

Date: 2026-11-19. Stand: RTX 3060 Ti 8 GiB. Cell `kat-iq4xs` 160k: ctx 163 840, prompt
139 293 tokens, `--att-mb 256`, super-chunk 8, `--kv-type q4_0`, `--vram-reserve-mib 512`,
`--mtp 0`, `--prefill 2048`, model `D:\Strata\models\katcoder\KAT-Coder-V2.5-Dev-35B-A3B-MTP-ABLITERATED.i1-IQ4_XS.gguf`
(D: SSD, as required). Full command lines of both legs: lines 92 and 101 of
`glm/2026-11-19_session/grid16-kat-iq4xs-160k-t1-strata.log`.

## The pair, back to back in one machine state

Both numbers come from the engine's own summary line, 6 minutes apart, same carrier settings:

| carrier | engine commit | prompt-experts banner | expert batch | prompt staging | warmup | prefill 139 293 tokens | pp | tg |
|---|---|---|---|---|---|---|---|---|
| `F:\tmp\sync1622-build-strata` (pin) | `c930ed15d` | `prompt experts on MMQ (int8)` | `<= 128 rows on 4 CPU threads` | `0.80 GiB` | 4,0 s | 233 533 ms | **596,5** | 8,1 |
| `F:\tmp\sync1911-build-strata` (merged main) | `c8f9562ed` | `prompt experts on the native grouped kernels` | `<= 2048 rows on 4 CPU threads` | `0.00 GiB` | 38,4 s | 2 588 018 ms | **53,8** | 9,8 |

Ratio: prefill is 11,1x slower, pp **-91,0 %**, decode (tg) did not regress. The 160k grid also
pinned 7 of 256 experts per layer in VRAM (0,45 GiB) against 22 of 256 (1,40 GiB) in the new build.

Both carriers are Release builds with the compiler flags in place: `build.ninja` of
`sync1622-build-strata` has 316 `/O2` occurrences and 0 `/Od` over 417 CUDA/CXX build
statements, `sync1911-build-strata` has 259 `/O2` and 0 `/Od` over 339 statements, and both
`CMakeCache.txt` say `CMAKE_BUILD_TYPE:STRING=Release`. So the gap is not a flag-parity artefact
(the trap that made the 18.11 r1/r2 pair uninterpretable).

What does differ in configuration, and it is exactly the thing under test: the pin's cache carries
6 MMQ keys (`STRATA_MMQ:BOOL=ON`, `STRATA_MMQ_KQUANTS:BOOL=ON`, `STRATA_MMQ_TAB:BOOL=OFF`,
`STRATA_MMQ_TQ_OVERLAY:BOOL=ON`), the new cache carries **zero** `STRATA_*MMQ*` keys - the options
themselves are gone from the tree.

Both engines were built against the same ggml pin `3cf03257f219afbe7334045ff7c6a06ac68c627d`
(`GGML_PIN` at `engine/.github/workflows/kit-build.yml:65`), so this is not a ggml difference
either. Repeat noise for this cell is +1,19 % pp; an 11x gap needs no statistics.

## Why the second carrier has no MMQ

Upstream deleted the whole path, not a flag:

```
3e26b4e15 [Engine] remove llama.cpp's MMQ build path and the vendored ggml-cuda (own-stack step 10)
128 files changed, 107 insertions(+), 34510 deletions(-)
    "No release build compiled MMQ any more (x86 since 0.2.14 ...) ... MMQ comparison builds
     come from the v0.2.15 tag from now on."
```

The merge of 0.2.16 into our `main` (`c8f9562ed`, 19.11 05:17) brought that deletion in. After it
the CMake options `STRATA_MMQ`, `STRATA_PREFILL_MMQ`, `STRATA_MMQ_TAB`, `STRATA_MMQ_TQ_OVERLAY`,
`STRATA_ORCA_Q4KS_MMQ`, `STRATA_MMQ_KQUANTS` no longer exist, and the source moved from
`engine/` to `engine/engine/` (`CMAKE_HOME_DIRECTORY` proves which tree each build came from).

The banner names the replacement mechanism: without MMQ the expert products of the prompt go to
the native grouped kernels with batches of up to 2048 rows placed on 4 host threads, and the
prompt-chunk staging that MMQ used to feed the GPU drops to 0,00 GiB. Warmup grew 4,0 s -> 38,4 s.

## Verdict

- On this card, for a MoE model at a 139k prompt, MMQ is not a micro-optimization: it is the only
  path that keeps prompt experts on the GPU. 900+ pp is unreachable in the merged tree. The
  fastest clean 160k number to date (928,1 pp / 15,2 tg, 18.11 09:56) belongs to the pre-merge
  pin `c930ed15d`.
- Caveat that keeps the ratio honest but not the absolutes: the pin's own 596,5 pp here sits below
  its best 928,1 pp - the depressed-state effect of task #33 is still unexplained. The pair is
  valid because both legs were taken 6 minutes apart in the same state; the state penalty is
  inside both numbers, and an 11x gap is far outside the +1,19 % repeat band.
- The fallback the user named (return to MMQ) is the only option the numbers support: build from
  the `v0.2.15` tag - the tag upstream itself points at for MMQ comparison builds - plus our own
  patches, or revert `3e26b4e15` on top of main. The revert replays a 34 510-line deletion
  backwards across the 0.2.16 layout moves, so `v0.2.15` as the carrier is the cheaper of the two.

## Not measured, deliberately left open

GPU clocks during the two legs are **not** evidence in this note: the clocks probe recorded 3
samples and exited rc=1 with `ОТКАЗ: записи в журнале нет`, its duration assumption is ~155 s
against a 2 588 s run. Until that probe is fixed (task #40) no statement about util, SM clock or
power belongs to this pair.

## Measurement hygiene, fixed on the way

- `serve.server` moved to `engine/terminal` in 0.2.16 and `gguf_reader` to `engine/terminal/tools`;
  the carriers still launched `-m serve.server` and `from gguf_reader import ...` from the old
  paths, which killed whole points with `WinError 10061` and made `--selftest` die with
  `ModuleNotFoundError`. Fixed in `harness/scripts/live_strata.py`, `harness/scripts/grid_sweep.py`,
  `harness/gateway/launcher.py` (commit `0b63895`, 19.11 06:32, working tree clean) and in
  `glm/scripts/grid16_run_2026-11-16.py`; `--selftest` there is now rc=0 with 104 checks all True
  (`glm/2026-11-19_session/grid16-run-selftest-2026-11-19.txt`).
- The same carrier refused the next point 2 seconds after the previous one because a leftover
  engine still held port 8186 for 46 minutes. Port and VRAM availability is now a bounded wait
  (`wait_gpu_free`, timeout 3600 s), the way the RAM gate already worked; sabotaged by a live
  socket and by a stubbed `vram_used_mib`.
- The point the runner lost (the background command was cut by the tool's own 1800 s limit while
  the engine finished) was recovered from the engine log by
  `glm/scripts/point_from_engine_log_2026-11-19.py`, which rebuilds a full journal record from the
  primary summary line plus the point's tmp config. The journal now carries 53,8 / 9,8 with a note
  naming its origin: 17 records in `glm/2026-11-19_session/grid16-2026-11-19.jsonl`.
