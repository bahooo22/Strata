# Super-chunk prefill: layer-major traversal (q36)

Reference machine: RTX 3060 Ti 8 GB, 32 GiB RAM, i7-4790K, KAT IQ4_XS (qwen35moe),
q4_0 KV, memory clock +1003 MHz. Branch `super-chunk` (0d20f0f5), base `main` 529f29c2.

## Why

On a 96k prompt the engine moves 805.9 GiB of expert bytes over PCIe: every prefill
chunk of 2048 tokens reloads the experts of all 41 layers. With `--prefill 2048` a 96k
prompt is ~43 chunks, so each layer's experts are staged ~43 times. The bytes, not the
matmuls, dominate prefill on a hybrid MoE placement.

## What

`STRATA_Q36_SUPER_CHUNK=N` (1..64, default 1 = the old path) groups N chunks into one
super-chunk and walks the model **layer-major**:

1. embed all T = N×2048 rows into `xsuper`, run `k_rms` into `hsuper`;
2. for each layer: `stream_take` once, then for each sub-chunk copy `hsuper[off] → h`,
   run `layer(T=2048)` and copy `h → hsuper[off]`, then `stream_done`;
3. positions of sub-chunks come from a device array `pos_super` (not `hpin`: an async
   copy would race with the host write);
4. MTP runs over the same sub-chunks: row seeds q are `hsuper[q−1]`, the first one is
   `hlast`; the super path is allowed with `mtp_d > 0` (stage 2);
5. `on_chunk` and window rebalancing happen only on super-chunk boundaries.

The only change inside `layer` is a new parameter `stream_base`: when set, the experts
of the layer are already staged by the caller and `stream_take`/`stream_done` are not
called. Buffers stay chunk-sized; only `hsuper` grows by 16 MiB per 2048 tokens.

## Gates

| Gate | Result |
| --- | --- |
| Compile | `build-sc`, 0 errors |
| N=1 bit-identical (4k, 100..900 tokens × 8, full logits) | `fc /b` against base `sha_base2.logits` → **fc_rc=0**, 7 946 240 bytes; `gen: 1020 198 220 16 15 15 15 15` |
| MTP 0 vs MTP 2, 96k N=4 | MTP path works; greedy output matches, 911.1 pp / 18.4 tg |
| Quality at the window | needle on the base build: q4_0 finds the fact at 96k (1/1) and 128k (3/3) |

## Measurements

Prompt 86 589 tokens at 96k (ctx 98 304), 111 831 at 128k (ctx 131 072), prefill 2048,
MTP 0, att 256:

| window | N=1 pp | N=4 pp | delta | tg N=1 → N=4 | TTFT, s | slots |
| --- | ---: | ---: | ---: | --- | --- | --- |
| 64k | 728.6 | **913.8** | +25 % | 18.7 → 19.4 | 84.4 → 67.3 | — |
| 96k | 800.9 | **1024.0** | +28 % | 16.7 → 17.2 | 108.1 → 84.6 | 19 → 17 |
| 128k | 671.6 | **813.4** | +21 % | 15.5 → 15.7 | 166.5 → 137.5 | 7 → 5 |

N=1 matches the base build within noise at every window (128k: 671.6 vs 673.0), so the
wrapper itself is neutral.

## Profile at 96k (STRATA_Q36_PROFILE=1)

| component | N=1, ms | N=4, ms | delta |
| --- | ---: | ---: | --- |
| total | 127 021.8 | 103 174.2 | −18.8 % |
| attn | 61 372.3 | 60 958.8 | 0 |
| gdn | 15 393.1 | 15 408.7 | 0 |
| moe | 49 518.9 | 23 336.6 | −52.9 % |

MoE splits into ~35 s of copies + ~15 s of CPU matmul at N=1, and ~8.7 s of copies at
N=4. The remaining floor at N→∞ is attn 61 + gdn 15.4 + matmul 14.6 ≈ 93 s
(≈930–950 pp): H2D is now spent, and prefill-attention (60 % of the time) is the next
lever.

## Costs and limits

- Cancel and window changes are deferred to a super-chunk boundary: up to ~36 s at
  96k, N=4.
- Memory: `hsuper` +16 MiB per 2048 tokens; at 128k the slot count drops 7 → 5.
- MTP on a super-chunk costs ~11 % pp (1024 → 911 at 96k): the MTP block runs over all
  rows. Prefer MTP 0 when prefill speed matters.
- The design expected 2130–3020 pp at N=4; measured is 1024. The copy share of prefill
  is lower than the model assumed (p≈0.25), and the CPU matmul and attention dominate.

## How to run

```
set STRATA_Q36_SUPER_CHUNK=4
strata-q36.exe --native <model> --max-context 98304 --prefill 2048 --mtp 0 ...
```

Without the variable (or with 1) the old path runs bit-for-bit; the rollback is
removing the env variable.
