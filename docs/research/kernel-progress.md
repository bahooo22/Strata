# Strata kernel progress: two baselines and the working 64k-160k grid (2026-11-09)

Purpose: make the gap between "before our changes" and "what works now" readable as a number rather
than an adjective. Both baselines sit in one table next to the working series: the fork point
`146df3c4` (stock, before our edits) and our own 2026-11-01 start (`170.5 pp` at 64k). The chart is
`docs/assets/kernel-progress.svg`.

## 1. What each row was measured with

All rows come from one bench (RTX 3060 Ti 8 GB unlocked, 31.87 GiB RAM, models on SSD), one prompt
(`master.txt`), temperature 0, greedy, 256 answer tokens unless the row says otherwise.

| series | build | base / flags |
| --- | --- | --- |
| Strata stock | `engine-stock` build | `146df3c4`, KV stays fp32 |
| Strata fork 2026-11-01 | `engine/build/strata-q36.exe` | KV q4_0, no super-chunk, no FA |
| Strata fork 2026-11-05 | same tree + super-chunk | `STRATA_Q36_SUPER_CHUNK=4`, MTP 0 |
| Strata fork 2026-11-07 | `engine/build/strata-q36.exe` | main with FA + super-chunk |
| llama fork (control) | `llama-master` build | head `9f0e5098a` |
| llama stock (control) | `llama-3cf` build | `3cf03257`, stock flags |

## 2. One table: baselines and working series

Every row uses KAT Coder IQ4_XS with KV q4_0; prompt length given in tokens.

| series | window | prompt_tokens | pp, tok/s | tg, tok/s |
| --- | ---: | ---: | ---: | ---: |
| Strata stock `146df3c4` | 2048 | 1 749 | 109.6 | 19.94 |
| Strata stock | 4096 | 3 517 | 125.9 | 19.49 |
| Strata stock | 8192 | 6 677 | 124.8 | 17.62 |
| Strata stock | 16384 | 12 293 | 123.2 | 15.05 |
| Strata stock | 24576 | 18 526 | 123.2 | 12.45 |
| **Strata stock (ceiling)** | 32768 | 24 483 | **123.1** | 11.34 |
| **Strata fork 2026-11-01 (baseline)** | 64k | 64 660 | **170.5** | 33.4 |
| Strata fork super N=4 (2026-11-05) | 64k | 64 660 | 913.8 | 19.4 |
| Strata fork super N=4 | 96k | 86 589 | 1 024.0 | 17.2 |
| Strata fork super N=4 | 128k | 121 808 | 813.4 | 15.7 |
| **Strata fork super N=4 + FA (working kernel)** | 64k | 64 660 | **1 504.0** | 18.1 |
| Strata fork super N=4 + FA | 80k | 77 378 | 1 253.6 | 16.6 |
| Strata fork super N=4 + FA | 96k | 86 589 | 1 308.9 | 15.3 |
| Strata fork super N=4 + FA | 128k | 121 808 | 1 091.9 | 14.6 |
| Strata fork super N=4 + FA | 160k | 139 293 | 959.9 | 13.6 |
| llama fork (control) | 64k | 64 651 | 1 050.5 | 24.2 |
| llama fork | 80k | 77 360 | 1 025.1 | 24.3 |
| llama fork | 96k | 86 568 | 987.3 | 23.3 |
| llama fork | 128k | 121 787 | 890.8 | 20.2 |
| llama stock (control, 64 answer tokens) | 64k | 64 651 | 639.3 | 7.65 |
| llama stock | 96k | 86 568 | 619.9 | 7.51 |
| llama stock | 128k | 121 787 | 598.3 | 7.05 |
| llama stock | 160k | 139 272 | 573.7 | 6.71 |

One line: prefill 123.1 (stock, and that is its 32k ceiling) → 170.5 (our 2026-11-01 start at 64k) →
1504.0 (working kernel at 64k); the window ceiling moved from 32k to 160k (139 293 tokens).

Comparability footnote: both stock ladders (Strata and llama) were taken with a 64-token answer, the
working series with 256. So stock `tg` is not comparable with working `tg`; `pp` is comparable, and
re-shooting stock llama at 256 answer tokens showed that the speed gap is not an artifact of answer
length.

## 3. Where the gain came from

- **KV q4_0 instead of fp32 buys the window, not the speed.** Stock KV is fp32 (~45 KB/token), so
  8 GB runs out exactly at 32k. q4_0 removes that boundary: the same 8 GB hold 160k. Stock `pp`
  barely moves along its ladder (109.6-125.9), so the window was not paid for with prefill.
- **Chunk prefill 2048** against the default: 170.5 → 1026.8 pp at 64k. Caveat: that run carried MTP 2
  and 21.7 tg against 33.4, so compare `pp`, not everything at once.
- **super-chunk N=4** against N=1: +25 % pp at 64k, +28 % at 96k, +21-22 % at 128k, checked on two
  models; details in [super-chunk.md](super-chunk.md).
- **Flash attention** on top of super-chunk: 913.8 → 1504.0 (+64.6 % at 64k), 1024.0 → 1308.9
  (+27.8 % at 96k), 813.4 → 1091.9 (+34.2 % at 128k); gates in [fa-attention.md](fa-attention.md).
- **The price of MTP 2** shows up inside one series: at 64k, 1504.0 → 1350.9/1352.6 pp at 16.4/16.9
  tg. The 80k point of the working row (1253.6) was taken by a profile with MTP 2, which is why it sits
  below 96k - it is not window degradation.
- **160k** existed before FA only as a needle series (TTFT 246-248 s at a ~150k prompt); now it is a
  measured prefill point, 959.9 pp / 13.6 tg.
- llama fork did not reach 160k on 8 GB, so the Strata row is the only line with five windows.

## 4. Quality on the large windows

The large windows are backed by more than speed: with FA on by default, needle runs give 7/7 full and
7/7 number at 96k and at 160k, and 5/7 full at 128k with 7/7 number. FA did not degrade needle recall
on any window.

## 5. Route caveat: the window is not available to every quant

UD-IQ3_S at 64k reads its prompt in Strata through the native grouped kernels: 64 660 tokens in
1 276 073 ms = 50.7 tok/s, with decode at 17.8 tok/s. llama on the same model and window gives
1106.49 pp on 64 641 tokens - a factor of 21.8, while decode stays at parity (17.8 against 17.29 tg).
So "160k is available" does not mean "for any model": for IQ3-class quants the Strata prompt path runs
on slow kernels, and a per-model grid has to show that in numbers.

## 6. The chart

- `docs/assets/kernel-progress.svg` (10 977 bytes);
- the generator lives outside this repository and anchors every series to the raw measurement files
  named inside the SVG; before writing the file it rejects DTDs and entity declarations and parses the
  assembled text as XML;
- the figure appears in the fork README and in the measurements showcase "Dynamics" section.

Raw grid tables live in the fork's measurements archive on the bench machine (they are not published in
this repository); this note is the published summary of the same numbers.
