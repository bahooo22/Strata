# Portable inference kit for long context (Strata + llama.cpp)

One build of both engines that inspects your machine and picks the context window and the
launch parameters itself. Every number in it comes from measurements taken on one specific
bench (RTX 3060 Ti 8 GB, 4 cores, 31.87 GiB RAM, models on an SSD), not from general advice;
where a measurement does not exist the kit says so out loud - "this is a formula estimate".

The archive contains no models. The kit never writes outside its own folder.

## Quick start

1. Unpack the archive anywhere (a path without non-ASCII characters is preferable, not required).
2. Double-click `START.bat`.
3. When asked, paste the path to a `.gguf` file (you can also drag the file onto `START.bat`).

The kit shows four steps and asks for confirmation before launching:

| step | what it does | file |
|---|---|---|
| 1 | reads the hardware: GPU, VRAM, architecture, CPU cores, RAM, media type under the model, HAGS, MSI | `kit\detect.py` |
| 2 | compares the machine with our bench and states what will not work on it | `kit\classify.py` |
| 3 | from the `.gguf` header and the machine class, computes the largest window and the parameters | `kit\recommend.py` |
| 4 | starts the server and opens the address in a browser (`-NoBrowser` skips it) | `kit\start.ps1` |

Other ways to run it:

```
START.bat model.gguf                    same, without asking for the path
START.bat model.gguf -DryRun            print the launch line, start nothing
START.bat model.gguf -Yes               start without asking
START.bat -FakeConfig 16g.json -Gguf model.gguf -DryRun
                                        tuning for someone else's hardware, without switching it
```

It is worth checking the kit before the first real run:

```
python kit\detect.py --selftest
python kit\classify.py --selftest
python kit\recommend.py --selftest
```

Python 3 is required (we tested on 3.14); there are no external dependencies - standard library
only. If Python is available as `py`, use `py kit\detect.py --selftest`. Each of the three files
also works on its own: `--out file.json` writes the result, `--json` prints machine-readable
output.

## What gets tuned

For Strata: context window, `--att-mb`, `--vram-reserve-mib`, super-chunk N, KV cache type, MTP.
For llama.cpp: window, `--n-cpu-moe`, `-ub`, `-b`, `-fa`, thread count. Strata listens on port
8082, llama on 8081.

The window is computed from VRAM terms: KV cache (bytes per token taken from the `.gguf` header)
plus the attention buffer, plus the reserve, plus the linear-attention state, plus (for llama)
weights on the GPU at the given `--n-cpu-moe`. A ladder step (64k, 80k, 96k, 128k, 160k) passes
if the sum fits.

Honesty control: on our bench the formula must reproduce the measured ladder within one step -
that is one of the assertions in `recommend.py --selftest`.

## The model the parameters were tuned for

`kit\models.json` holds six measured models. Every entry carries a download link (`hf_url`),
verified with a HEAD request and an exact size match, and the primary source of the measurement
(`src` - a file and a line in a results table). If your model is not in the list, the kit tunes
by formula and says so: "this model is not in the measured registry".

## How to read the warnings

Return code of any step:

- `0` - verdict reached, nothing to add;
- `1` - verdict reached with warnings (printed; the run is possible, expect a slower start or a
  smaller window);
- `2` - the check did not happen: broken input, no GPU, GGUF without metadata. This is not
  "everything is fine", it is "there was nothing to measure".

Machine classes (`classify.py`), relative to our bench:

| verdict | meaning |
|---|---|
| above our bench | at least 1.5x headroom in memory; you can try a window above the measured one |
| not below our bench | within 5%; every profile transfers one to one |
| below our bench | one axis is clearly smaller; some windows will not fit |
| far below our bench | the kit warns and lists what will be missing |

The warning texts and what they mean:

- "long windows (128k+) and MoE with CPU experts do not fit into this memory" - VRAM bound;
- "part of the experts will stay on disk; model load and prompt processing will be slower" - low RAM;
- "CPU experts (--n-cpu-moe) will become the bottleneck" - too few cores;
- "loading the model from an HDD was measured only as a degradation, not as a profile" - the model
  sits on an HDD: our profiles were taken from an SSD, start-up time will differ;
- "no prebuilt cubin for this architecture is in the kit" - your GPU architecture is not among the
  built ones; execution would fall back to PTX JIT (slow start, unverified result). This list comes
  from `elf-proof.json` next to `kit\` - proof taken from the actual binary, not from a constant.

## Supported configurations

- Windows 10/11 x64, PowerShell 5.1 (the kit uses the shell that ships with Windows; pwsh 7 is not
  needed);
- NVIDIA GPUs with architecture `sm_86`, `sm_89` or `sm_120` - that is Ampere (3060 Ti and kin),
  Ada (4090, 4060 Ti 16G) and Blackwell (5080, 5090). The exact set of built architectures is in
  `elf-proof.json`, and it is the basis of the warning above;
- a driver able to run the CUDA 13 runtime (shipped inside the kit: `cublas64_13.dll`,
  `cublasLt64_13.dll`);
- a GGUF model that fits into RAM together with the KV cache of the selected window.

## Weight

The full build (with the CUDA runtime) and the thin one (`-NoCudaRuntime`, cuBLAS not shipped)
differ by roughly 488 MiB - that is `cublas64_13.dll` plus `cublasLt64_13.dll`. The measured sizes
of the folder and of the archive are in `kit-weight.json` next to this file; the packer writes it
on every archive build, so the numbers there always describe this archive.

## Building the kit yourself

You need pwsh 7, CMake, Ninja, MSVC and a CUDA 13.3 toolkit. From the root of the bench:

```
pwsh -File harness\scripts\build_kit.ps1 -Engines strata,llama -Arch "86;89;120"
pwsh -File harness\scripts\pack_kit.ps1                      # full build
pwsh -File harness\scripts\pack_kit.ps1 -NoCudaRuntime       # thin build
```

Quote the architecture list: without quotes the shell splits the argument on the semicolons.

`build_kit.ps1` writes three measurement files into `dist\gpu-infer-kit`: `build-measure.json`
(configuration and build time and exit code per engine), `elf-proof.json` (which cubins are
actually inside the binaries, read with `cuobjdump --list-elf`) and `runtime-deps.json` (dependency
closure, from `dumpbin /imports`). Before calling an archive ready, `pack_kit.ps1` checks that
every required file exists, that no foreign machine's absolute paths remain in the text files of
the tree, that the measurement files parse as JSON without a BOM, that the built architectures
cover the declared ones, that the dependency closure is empty, that the archive opens, and that no
model is inside. Every control fails with a stated reason; a missing control is a failure too, not
a success.

`-SelfTest` on both scripts runs the controls without building anything and without touching
hardware.

## What is not here

- models (the archive contains no `.gguf` file);
- Linux and macOS;
- measurements on hardware other than our bench: a "below / far below" verdict is the honest
  boundary of profile transfer, not a promise of the same speeds;
- MTP at windows of 64k and above (measured as a regression, so it is not enabled), and every other
  rejected lever - their list with numbers is in the bench report `docs\reports`.

Russian version: `README.ru.md`.
