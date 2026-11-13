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
every required file exists, that no absolute path with a drive letter remains in the text files of
the tree - neither the "letter, forward slash, tree" form nor the "letter, backslash, tree" one
(JSON and CMake emit both, the second as an escaped double backslash before the file name), that
the measurement files parse as JSON without a BOM, that the built architectures cover the declared
ones, that the dependency closure is empty, that the archive opens, and that no model is inside.
Every control fails with a stated reason; a missing control is a failure too, not a success.

`-SelfTest` on both scripts runs the controls without building anything and without touching
hardware.

## Automation: what GitHub Actions builds and publishes

The CI variants of the same scripts live in `packaging\kit\ci\` and are called with parameters only
(`-StrataSrc`, `-LlamaSrc`, `-GgmlDir`, `-Cuda`, `-Out`): a run knows nothing about the bench and
cannot accidentally build something that works at home and fails in Actions. A missing mandatory
parameter is a refusal with exit code 2, not a half-finished build.

The entry point of these self-checks is pwsh 7 - the same one Actions calls them with: on it
`pack_kit.ps1 -SelfTest` reports `ok=73 bad=0` (taken on 12.11). The same run under Windows
PowerShell 5.1 reports `ok=69 bad=4` (it used to be `ok=63 bad=3`; the seven extra controls come
from the portability fix, and both pairs were measured on one tree). The four FAILs sit on an entry
that did not happen, not on packing: the test tree is never created because
`Set-Content -Encoding utf8NoBOM` only exists from PowerShell 6 on, and `install_cuda_redist.ps1`
does not parse in 5.1 at all (its source is UTF-8 without a BOM, which 5.1 reads as OEM). Red on
that entry means "the check did not happen", and green there means nothing: two of the new controls
wait for ZERO findings and pass idly on a tree that was never built. One more difference between the
entries is a JSON round-trip: `ConvertTo-Json` writes the Double `3321.0` as `3321`, and
`ConvertFrom-Json` returns Int32 in 5.1 where pwsh returns Double; `Chk` in `build_kit.ps1`
compares fractional values as numbers under any types and prints the types in the FAIL line, so
equal values are never compared as strings. The real packing path does not depend on the shell:
measures are written with `[System.IO.File]::WriteAllText` and `UTF8Encoding($false)`, not
`-Encoding`.

- `kit-build.yml` (this fork, a push to `main` touching `src/`, `include/`, `cmake/`,
  `CMakeLists.txt` or `packaging/kit/`). The first job runs five controls without a toolchain and
  without sources: `-SelfTest` of build_kit, pack_kit and install_cuda_redist, plus
  `patch_markers.py --selftest` and `verify_zip.sh --selftest`. The second job builds CUDA 13.3.1
  from redist archives (a pinned sha256 per archive, the download folder in actions/cache), compiles
  `strata.exe` and `strata-q36.exe` for architecture 86 and gates the markers byte-wise in both
  executables.
- `kit-build-cuda.yml` (the llama.cpp fork, a push to `kit-all-sync`) does the same for the llama
  leg: the scripts and the marker registry are checked out from this fork, because a copy would
  diverge at the first edit; `-Engines llama`, then the gate over ggml-base.dll, ggml-cuda.dll and
  llama.dll.
- `kit-release.yml` (this fork, a published release by tag or a manual run with a tag) is the whole
  kit: both engines in ONE run (`-Engines 'strata;llama'`) for `86;89;120`, because only the paired
  run writes the merged build-measure.json and elf-proof.json that the packer reads; then the marker
  gate for both legs, the native dependency registry over six binaries, packaging, a byte-level
  format gate on the archive bytes (the PK header and the EOCD) and the upload as an asset of an
  already existing release. Without a tag it stays a run artifact. The upload runs `gh`, which does
  NOT inherit the automatic run token: the step must receive `GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}`
  (the workflow already declares `contents: write`). Without that line the LAST step dies - after a
  two-hour build - with "set the GH_TOKEN environment variable"; an empty token is caught by a
  separate guard that returns rc=2 with its own reason, so the refusal reads as "the publication did
  not happen" rather than as "our patches are missing".

Before any push, acceptance stays an offline measure made of two parts. The first is the `ci-gates`
job on a clean tree export (`git archive main packaging/kit | tar -x`, with no `.git` and no stand
paths): `build_kit` 116/116 controls, `pack_kit` 73/0, `install_cuda_redist` 27/0,
`patch_markers --selftest` 28/0, `verify_zip --selftest` 6/0 (measured 13.11). The second is the
marker gate over the stand's binaries: 24/24 Strata markers across 12 commits and 5/5 in the llama
leg across 3. Add to them a static audit of the three workflows: it catches GH_TOKEN-class defects
before a long run starts, its own sabotage control (six buried failures plus a false-alarm
control) gives 7/7, and over the three files it is clean except one warning - the llama leg takes
the CI scripts at a floating `ref: main`, which is the price of one source of truth, not a forgotten
pin.

Log-line formatting is a class a green build never notices: `-f` binds tighter than `+`, so
`"template {0}" + "tail {1}" -f a, b` substitutes into the second piece only. The live run of
12.11 (`build-strata.log` of the kit378 rehearsal) printed literal `{0}`...`{4}` in the Strata
measure line: the JSON measures stayed intact, and what became unreadable in Actions were exactly
the cold numbers the `build_kind` label exists to justify. Four such sites are fixed - the strata
and llama measure lines, the no-op line and the architecture-proof line with a suffix - and the
neighbouring `pack_kit` and `install_cuda_redist` come back clean under the same measure (0 hits).
The class is closed in `-SelfTest` by two measures: a textual one over the script (with two sabotage
inputs and one false-alarm control) and a behavioural one - the same template glue with and without
parentheses. After the fix: 116/116.

Suitability of the component index (`redistrib_<version>.json`) is measured by structure: the release
label must equal the requested version and the index must hold at least 20 components. The earlier
byte threshold ("at least 50 000 B") rejected the live full 13.3.1 index, which weighs 47 914 B
(measured 12.11), so the job died before the first download; `-SelfTest` of the same script catches a
return of that threshold with a separate check over the source text.

The archives are laid out by recursive merge, not by moving the top level: component directories
overlap (listing of the 9 archives on 12.11: `bin` in 4 of 9, `include` in 6 of 9, `lib` in 3 of 9),
and moving a directory onto an existing directory makes PowerShell put it INSIDE. The first live run
on 12.11, with all nine sha256 values matching, gave `bin\bin\x64\cublas64_13.dll` and
`include\include\cuda_runtime.h` - the toolchain would have been incomplete, and only the mandatory
file list caught it. The script self-check tests the merge of a second archive with seven separate
checks.

The marker gate is the one thing a green build cannot prove. The registry
`packaging\kit\ci\patch-markers.json` was taken off real binaries on 12.11: 24 markers for Strata
over two carriers (exe) and 5 for the llama leg over three (dll). The markers cover 12 of our 81
Strata commits and 3 of 14 in the llama leg; edits that leave no readable name in a binary (a string
literal or a CUDA kernel name inside the fatbin) are invisible to the gate and are still checked by
parity measurements on the bench. A lost marker is exit code 1 and a red run; an absent carrier is
exit code 2, which reads as "the check did not happen".

Two rules without which the registry lies are measured and recorded in the file itself. A marker
name must be absent from the upstream base tree: finding `--cache-type-k` in an exe would prove
nothing, since the stock build has that flag too. The `commit` field is the oldest of our commits
that changed how often the name occurs, i.e. the one that introduced it. The previous match took the
commit from a "the name occurs in this tree" sample and pulled attribution onto a later mention - for
six markers it pointed at a packaging commit of 11.11 or at a neighbouring patch instead of the
commit that coined the name.

Actions does not measure anything that requires a GPU: serving a model and the per-architecture cost
limit (`-SkipProbe`). The time limits rest on cold builds: the `build_kind` label in build-measure is
decided by the number of real target objects in the build tree BEFORE the run and tells apart
"cold build", "partial build" (a warm-up after an edit), "no-op" and "coldness not measured" - a
warm-up time does not state the price of a full compilation and cannot justify a limit.

The cold numbers on hand each have a carrier file in the bench `dist\` directory: strata 1686.2 s
(`gpu-infer-kit-strata-cold3`: 160 compilations and 14 links out of a plan of 174, 174 of 174 edges
executed in the log, commit `0f37b86e`) and a repeat of the same configuration at 1774.1 s
(`gpu-infer-kit-strata-cold`); llama 3006.1 s (`gpu-infer-kit-llama-sync3`, commit `c8b1899f9`) and
3321.0 s (`gpu-infer-kit-llama-cold`) - both logs show 330/330 edges and 315 compilations out of a
plan of 330. All four runs used the same architecture list: `CMakeCache.txt` of the
`engine-kit-kitall\build-kit-cold3` and `llama-kit\build-kit-cold` trees reads `86;89;120`, and the
fatbin of the binaries taken from those trees gives 26 `sm_86`, 26 `sm_89`, 25 `sm_120` and 1
`sm_120a` entries in `strata-q36.exe`, and 27 `sm_86`, 32 `sm_89`, 43 `sm_120a` in `ggml-cuda.dll`.
The `archs` field is empty in these measure files and `build_kind` still carries the old "full
compilation" label: the snapshots were taken by code predating the coldness-label fix, so coldness
and architecture coverage are proven by the logs and CMakeCache rather than by measure fields.

The numbers this paragraph quoted before rested on unclosed measurements: strata 737.7 s has no
carrier file at all (only the run's stdout and commit bodies), and strata 712.6 s and llama 2788.8 s
are warm-ups - 25+5 and 156+8 executed steps instead of 174 and 330.

Hence the limits. The release run gets 240 minutes and builds both legs on 86, 89 and 120 in a single
tree: the worst measured pair is 1774.1 + 3321.0 = 5095.1 s (84.9 minutes), the pair taken from one
and the same run is 1686.2 + 3006.1 = 4692.3 s (78.2 minutes); 240 minutes is 2.8 times the worst
pair, the rest goes to the CUDA toolchain, packaging and publishing the asset. A push run gets 180
minutes and builds a single architecture (86 by default), so the 1774.1 s three-architecture build
serves as its upper bound: a margin of 6.1 times. There is no separate cold measurement on 86 with a
carrier file, and the price of the llama leg on 86 has not been measured.

## What is not here

- models (the archive contains no `.gguf` file);
- Linux and macOS;
- measurements on hardware other than our bench: a "below / far below" verdict is the honest
  boundary of profile transfer, not a promise of the same speeds;
- MTP at windows of 64k and above (measured as a regression, so it is not enabled), and every other
  rejected lever - their list with numbers is in the bench report `docs\reports`.

Russian version: `README.ru.md`.
