# Local changes of this fork

Upstream: `https://github.com/Niko1221/Strata` (version 0.2.10, base `ffa80d73`).
The fork's branch is `main`. Local commits on top of upstream:

| Commit | What |
| --- | --- |
| `86200712` | the out-of-VRAM error suggests `--mtp 0` and `STRATA_MMQ_KQ=0` |
| `b8d4b58d` | the `qwen35moe` guard no longer requires the MTP key: third-party GGUFs load |
| `143d5be4` | the q36 loader accepts IQ4_XS in `ssm_alpha/beta` |
| `414b9cde` | the VRAM reserve is the `--vram-reserve-mib` flag |
| `91725ec7` | the quantized q8_0 KV cache behind `--kv-type` |
| `28f39156` | KV types q4_0, q5_0, q5_1 (ggml layouts, one byte buffer) |
| `912ea835` | fork notes: the `q8-kv` branch, the `STRATA_GGML_DIR` build, `build-verify.bat` |
| `4af27c19` | `strata verify` logs the residency prior at start |
| `8852b327` | `/v1/models` reports `chat_template_caps` in meta |
| `976226a9` | serve: start-failure hints — VRAM, CUDA, layout, flags, crash |
| `2e1c2a04` | q36: OOM diagnostics for the expert buffers |
| `2fe24691` | serve: a rejected batch admission is an error, not a finished request (#3040) |
| `2033a9dc` | q36: OOM diagnostics for the expert slots and staging |
| `4f0b1248` | serve: read the engine output with `errors="replace"` |
| `59855142` | q36: the attention/GDN/MoE profiler and its report (pool, reserve, hybrid-rows, attention buffer) |
| `3ae7d409` | q36: per-request determinism — an expert-placement snapshot (#4604) |
| `aea22e2f` | serve: a test of the `strata_deterministic` flag in `sampling_keys` |
| `efec68e7` | q36: the attention buffer size is the `STRATA_Q36_ATT_MB` env flag |
| `c9ca876d` | q36: the request profile in serve-DONE; fork notes in two languages |
| `a00ab004` | q36: the `--att-mb` flag — the attention buffer size without a rebuild |
| `bbc034d4` | q36: pacc for T ≤ 8 and L2-ordered split-K — 96k tg +28 % |
| `227ba006` | q36: the request profile — total, head, quant and the MTP phases |

## Build

`..\harness\scripts\build_strata.bat` builds `strata` and `strata-q36` into `build\`, taking `ggml`
from the sibling git clone `..\llama.cpp` (`-DSTRATA_GGML_DIR`). `build-verify.bat` performs
a clean check build (25 targets).

## Python and `.venv`

One interpreter for the build, the tests and `setup.py` — the system
`C:\Program Files\Python314` (Python 3.14.5); the `.venv` in the engine root is created on it
only (packages from `requirements.txt` and `requirements-build.txt`, cmake 4.4.3 and ninja 1.13.2
inside). Tests — `.venv\Scripts\python.exe -m unittest`. The Qoder runtime (3.15) and PyManager
are not used by the project.

## Two llama.cpp copies

- `third_party\llama.cpp` — a vendored snapshot of upstream `3cf03257` without `.git`, untracked
  (`.gitignore`); `build\bin\llama-server.exe` is built from it.
- `..\llama.cpp` — the same commit with git history; it supplies `ggml` for the engine build.

Both are needed; removing the clone breaks reproducibility (CMake fetches it again).

## KV and MTP additions

- `--kv-type fp32|q8_0|q5_1|q5_0|q4_0`; on 48k q4_0 gives +72 % over fp32 (20.5 → 35.3 tok/s);
- `--mtp 2 --draft-vocab 8192` is the best MTP profile (42.1 tok/s on 16k, 38.9 on 48k);
- a Q5 file whose `ssm` tensors are Q5_K must be repacked to Q8_0 (`harness\..\artifacts\glm\scripts\repack_ssm_q8.py`).

## Measurements and launch profiles

The final 16/64/80/96/128k profiles (Strata and llama.cpp), the `ncmoe` grid, `--prefill/--ub`,
the q36 profile and the KV comparison live in `..\docs\measurements\` and `..\harness\reports\`.
The quick documentation catalog is `..\docs\index.html` (opens locally, no server).

Details — `..\harness\docs\kv-quantization.md`, `..\harness\docs\mtp-vs-not.md`.
