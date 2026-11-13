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

A finished kit does not have to be built: it sits there as an asset of the release `kit-2026-11-13` -
[the release page](https://github.com/bahooo22/Strata/releases/tag/kit-2026-11-13) and the direct
download link [gpu-infer-kit-2026-11-13.zip](https://github.com/bahooo22/Strata/releases/download/kit-2026-11-13/gpu-infer-kit-2026-11-13.zip).
Both links were measured on 13.11 with an anonymous request and no token: the release answers 200 with
`draft=false` and `prerelease=false`, and the download returns the header `504b0304` and a length of
852 112 426 bytes - the same archive and the same bytes that the acceptance of run `43422717479`
disassembles further down in this file.

The entry point of these self-checks is pwsh 7 - the same one Actions calls them with. Windows
PowerShell 5.1 stopped being a separate story: `pack_kit`'s test tree is now written the same way the
real measures are (`[System.IO.File]::WriteAllText` with `UTF8Encoding($false)`), because
`-Encoding utf8NoBOM` on `Set-Content` only exists from PowerShell 6 on and on 5.1 the tree was never
created at all - four controls failed on a tree that did not exist, and two of them waited for ZERO
findings and passed idly (this entry used to report `ok=69 bad=4`). After the fix both entries give
the same verdict: `pack_kit` 89/0 and `build_kit` 117/117 under pwsh 7 and under 5.1 alike (measured
13.11, one run per entry). The only script that still does not parse in
5.1 is `install_cuda_redist.ps1` (line 89): its source is UTF-8 without a BOM, which 5.1 reads as
OEM. That is an entry boundary, not a packing regression: Actions calls all three scripts with pwsh,
and the real packing path never depended on the shell - measures are written with `WriteAllText`, not
`-Encoding`. One more difference between the entries is a JSON round-trip: `ConvertTo-Json` writes
the Double `3321.0` as `3321`, and `ConvertFrom-Json` returns Int32 in 5.1 where pwsh returns Double;
`Chk` in `build_kit.ps1` compares fractional values as numbers under any types and prints the types
in the FAIL line, so equal values are never compared as strings.

- `kit-build.yml` (this fork, started on demand only: Actions → "Kit build (Strata CUDA servers)"
  → Run workflow, with the `arch` input defaulting to 86). Tying the compile to a push is what was
  dropped on purpose: the run pulls in the CUDA toolchain and a full engine build, while composition
  and markers are what has to be checked pointwise. The first job runs six controls without a
  toolchain and without sources: `-SelfTest` of build_kit, pack_kit and install_cuda_redist, plus
  `patch_markers.py --selftest`, `kit_dll_deps.py --selftest` and `verify_zip.sh --selftest`. The same
  pwsh step then calls `pack_kit.ps1 -TextGate` over the `packaging/kit` tree, right after the
  selftest loop: it measures the inputs themselves rather than the controls - the nine text files of
  the manifest - and it too needs no toolchain and no compilation. The
  second job builds CUDA 13.3.1
  from redist archives (a pinned sha256 per archive, the download folder in actions/cache), compiles
  `strata.exe` and `strata-q36.exe` for architecture 86 and gates the markers byte-wise in both
  executables.
- `kit-build-cuda.yml` (the llama.cpp fork, on demand too, from the `kit-all-sync` branch) does the
  same for the llama.cpp
  build: the scripts and the marker registry are checked out from this fork, because a copy would
  diverge at the first edit; `-Engines llama`, then the gate over ggml-base.dll, ggml-cuda.dll and
  llama.dll.
  The build file must also sit on the default branch `master`, not only on the working
  `kit-all-sync` branch: the Actions interface builds its workflow list from the default branch, so
  the manual "Run workflow" button is only visible there, and pressing it runs the text of the file
  as it exists on that branch. Measured 13.11 after the synchronization: on GitHub both branches
  serve the same blob `07f54bd27` - 11 226 bytes, 198 lines - and the Actions list holds exactly one
  kit workflow in state active. A local, behind `master` checkout still shows the previous revision
  at 7 616 bytes, 3 610 smaller: it has neither `env.ARTIFACT_FILES` nor the "the artifact set is
  complete" gate; its binary upload step does not set `if-no-files-found` at all, and the default is a
  warning, so a run stayed green even on an incomplete set - the path list held four files instead of
  nine, and the red composition went through. The one deliberate `warn` in that edition sits in the
  "measures and logs" step under `if: always()`, and it survives in the current edition: empty measures
  are a symptom of an already failed job, not a new cause. That same spot is what let the red
  composition through, so this is checked against the repository on GitHub, not against one's own
  checkout.
- `kit-release.yml` (this fork, a published release by tag or a manual run with a tag) is the whole
  kit: both engines in ONE run (`-Engines 'strata;llama'`) for `86;89;120`, because only the paired
  run writes the merged build-measure.json and elf-proof.json that the packer reads; then the marker
  gate for both engines, the native dependency registry over seven binaries, packaging, a byte-level
  format gate on the archive bytes (the PK header and the EOCD) and the upload as an asset of an
  already existing release. Without a tag it stays a run artifact. The upload runs `gh`, which does
  NOT inherit the automatic run token: the step must receive `GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}`
  (the workflow already declares `contents: write`). Without that line the LAST step dies - after a
  two-hour build - with "set the GH_TOKEN environment variable"; an empty token is caught by a
  separate guard that returns rc=2 with its own reason, so the refusal reads as "the publication did
  not happen" rather than as "our patches are missing". The second character of the same class: `gh`
  does receive a token and still does not know which repository to address unless the step is given
  `GH_REPO: ${{ github.repository }}`. Measured 13.11 on the `release`-event run `43415264688` - the
  REST call for the tag answers 200 (the release exists), yet the cheap guard is red: the step
  itself 5 s (11:13:35Z -> 11:13:40Z), the whole run 47 s; what
  was missing was not the release but the repository for `gh`. Hence the rule about the tag - a
  `release`-event run executes the workflow FROM THE REVISION THE TAG POINTS AT, so the tag must sit
  on a commit carrying the needed edition of `.github/workflows/kit-release.yml`. That tag pointed at
  `370c93fad` - three commits before the tip - and the `GH_REPO` fix never reached the run; all three
  commits touched only the workflow, so the built binaries still match the tag: exactly one path
  changed, and it lies under `.github/workflows/`.
  The portability gate over the text inputs
  (`pack_kit.ps1 -TextGate` over the `packaging/kit` sources) is a separate cheap step in this
  workflow too, and it runs before both the toolchain and the release check. The CI-eligibility of the
  scripts themselves is not measured by that gate: the `ci\` directory is not in the manifest list and
  does not travel in the archive, while each build script carries its own two controls inside
  `-SelfTest` - "no stand path literals in the code" (`build_kit.ps1:672`, `pack_kit.ps1:506`) and "no
  references to a root derived from the script location" (`build_kit.ps1:673`, `pack_kit.ps1:507`). Both
  measure the script's own text with comments and doc blocks cut out beforehand, and the literals are
  assembled in code from two pieces: whole they would stay in that same file, and the measure would find
  its own explanations instead of the build code (checked on a red run - all 7 findings were its own).
  Live run 13.11: `build_kit.ps1 -SelfTest` gives 117/117 and rc=0. The subject of those two controls is
  stand literals specifically, not any absolute path: legitimate runner paths under `ci\` are not the
  gate's complaint, which is also why `ci\` does not enter the manifest list (`pack_kit.ps1:125`), and
  invented directories appear in the selftest fixtures by the tens. Whether a release
  exists for the asset is checked by an early cheap step, before the CUDA toolchain: the same
  `gh release view`, with the run's `GH_TOKEN`. An empty tag reads "no publication needed", a found release reads "the asset
  will land in it", and a missing one fails within seconds, hinting that the release must be
  created and never starting the compiler. Without that gate the same refusal arrived as the last
  step, after a two-hour build, and the fork held zero releases on the morning of 13.11 (with a fully
  inherited tag list), so the scenario is not hypothetical. By the evening of the same day the release
  `kit-2026-11-13` exists (not a draft, zero assets at the time of measuring), so the green cheap
  release check in run `43422717479` is a check against a real release rather than against nothing.

Before any push, acceptance stays an offline measure made of three parts. The first is the `ci-gates`
job on a clean tree export (`git archive main packaging/kit | tar -x`, with no `.git` and no stand
paths): `build_kit` 117/117 controls, `pack_kit` 89/0, `install_cuda_redist` 27/0,
`patch_markers --selftest` 44/0, `kit_dll_deps --selftest` 14/0, `verify_zip --selftest` 6/0
(taken 13.11 in one wrapper run). The second is the marker gate over the stand's binaries:
24/24 Strata markers across 12 commits and 5/5 for llama.cpp across 3. The third compares the two
format gates of the archive with each other: `verify_zip.sh` measures the zip inside the run, while
the python gate measures the released asset from outside. Both must demand the same thing, otherwise
a green verdict from one says nothing about the other. Measured 13.11 over the sources of both gates:
12 mandatory entries each, the lower bound on the entry count 20 in both, and the same set in the
same order. That bound sits deliberately below the live kit (25 entries, 26 with `bin/strata_kq.dll`)
so the gate catches incomplete packaging instead of tracking the current contents. Add to them a static audit
of the three workflows: it catches GH_TOKEN-class defects
before a long run starts, its own sabotage control (six buried failures plus a false-alarm
control) gives 7/7, and over the three files it is clean except one warning - the llama.cpp build takes
the CI scripts at a floating `ref: main`, which is the price of one source of truth, not a forgotten
pin.

A fourth class closed only now: the "upload as an asset of the release" step in run `43422717479`
died seconds before the upload - the `if`/`then` scope in that shell block was closed with a brace
instead of `fi`, and the log reads `syntax error near unexpected token '}'` on line 17. No YAML parser
sees this: only the runner's shell parses the block, and it does so as the LAST step, after the build
already cost 112 minutes (the 15 steps before it are green, marker gate and byte-level archive format
gate included). The measure is local now: `bash -n` over the text of every bash block of both
workflows, with `${{ ... }}` substitutions collapsed into one token because for the shell that is not
syntax. Acceptance of the measure runs on the real defect, not an invented one: over the edition still
published on GitHub it prints `broken: 1` with exactly the log line that killed the run, and over the
fixed one `blocks checked: 5, broken: 0` at rc=0. Two guards against a false verdict are built in: a
bare `bash` in this window resolves to a WSL stub that answers `execvpe(/bin/bash) failed` with exit
code 1 on HEALTHY text, so the measure takes the full path to a real GNU bash and verifies it through
`--version`; and a non-zero exit without the word syntax in stderr reads as "the check did not happen"
(rc=2), not as a finding. The remaining six blocks of the two files are PowerShell: there is no separate
local syntax control for them, but run `43422717479` already proved they parse - every one of those
steps ran green.

Three defects were found only by the live release run 43345549955 (13.11, the rehearsal branch
`kit-ci-live` at commit `722299be`, `86;89;120`, toolchain 13.3.1): Strata built in 18.6 + 1147.8 s
and llama in 8.8 + 2249.9 s, both `build_kind` labels read "cold build" with zero objects before the
run, the marker gate was green on both engines (24/24 and 5/5) - and the run still failed.

- `rc(kit_dll_deps)=1`: `llama-common.dll` and `llama-server-impl.dll` imported
  `libssl-3-x64.dll` and `libcrypto-3-x64.dll`. The cause is the `LLAMA_OPENSSL=ON` default
  (`CMakeLists.txt:145` of the pin): the runner image has OpenSSL and linked it, the bench does not
  (`OPENSSL_INCLUDE_DIR-NOTFOUND` in the 12.11 CMakeCache), so on the bench the import tables are
  clean and no local measure can see the defect. The llama.cpp build now configures with
  `-DLLAMA_OPENSSL=OFF`, and the control "openssl is off in llama" keeps that flag in the
  configuration text; a control is not a substitute for a run - it fails if someone removes the
  flag. Shipping someone else's dlls in the kit is not an option: their version would depend on the
  runner image while everything else in the kit is pinned by sha256, and the kit needs no HTTPS -
  the models are local.
- The llama artifact held 4 of the 9 binaries the build produces: the `llama-server.exe` wrapper
  does not start without `llama-server-impl.dll` and `llama-common.dll`, and `ggml.dll` and
  `ggml-cpu.dll` are called by `ggml-base.dll` inside it. What a build run uploads is called a set
  of servers, so it has to be runnable, not a list of three marker carriers. The class is closed by a
  per-file gate, not by a flag: the primary source of `actions/upload-artifact`
  (`src/upload/upload-artifact.ts:31`) turns `if-no-files-found` on only for an empty set, and its
  search is a single glob over all paths at once (`src/shared/search.ts:82-91`) - with 4 files out of
  9 the set is not empty and the flag stays silent. The set lives in `env.ARTIFACT_FILES`, and the
  step's `path:` is fed the very same value: a second copy of the list would be exactly this defect.
  An empty list gives rc=2 ("nothing to measure") rather than a green "0 files in place". The measure
  is accepted by running the real step text taken from the YAML over a synthetic tree (13.11):
  16/16, the sabotages "1 of 9 gone" and "typo in the directory" go red naming the file, an empty
  list gives rc=2, and the false-alarm control is green. Live runs confirmed the gate in both build
  workflows: the Strata run `43367282553` (push to `main` at commit `71f5e49a`, 13.11, job 04:42:51Z -
  04:56:24Z, 813 s; the gate step itself 04:56:13Z - 04:56:14Z) prints "artifact set: 3 files in
  place", and the llama.cpp run `43367290681` (push to `kit-all-sync`, 13.11, job 04:42:56Z - 05:08:45Z,
  1549 s; the gate step itself 05:08:36Z) prints "artifact set: 9 files in place" - both green. The
  named paths reconciled against the numbers in those same logs (`kit418_artifact_count.py`) give
  `[4, 3]` against `[4, 3]` and `[4, 9]` against `[4, 9]` with zero "no files", rc=0 in both runs.
- `strata_kq.dll` was in neither the kit nor the artifacts, and no earlier gate could see that: it
  is loaded by code (`LoadLibraryA` next to the engine, `src/prefill/mmq_kq_loader.cpp:57-70`, the
  name from `include/strata/prefill/mmq_kq_abi.hpp:9`), so it appears in no import table. Its
  absence meant silent degradation: the K-quant experts of the prompt would fall back to the FP16
  path while the build stayed green. Measured on the stand binary: `kit_dll_deps` reports exactly
  one import for it - `KERNEL32.dll` (the CUDA runtime is linked statically,
  `cmake/backends/cuda.cmake`), so it sits in the release gate's list because of how it is loaded,
  not because of tricky dependencies.

The class "the build produced it and the kit did not take it" is closed by a set-closure measure in
`pack_kit`: the set of exe/dll files the build actually produced (a flat scan of the Strata root and
`llama\bin`: under those trees sit `CMakeFiles\**\*.exe`, so a recursive walk would give false
findings) is compared against the `bin\*` keys of the manifest, and a finding is a refusal with rc=2
and the file list. A waiver (`$BIN_WAIVERS`) must carry its reason inside the dictionary: the only
entry there, `test-cuda-upload-stream.exe`, appears only with `LLAMA_BUILD_TESTS=ON`, and CI builds
with `OFF`. An empty or missing tree is rc=2 as well, not "zero findings". The `bin\strata_kq.dll`
key was added to the manifest, to the format gate's mandatory file list (`verify_zip.sh`,
false-alarm control - 12 mandatory files instead of 11) and to the Strata artifact of `kit-build.yml`.
Live acceptance of the measure (13.11, `pack_kit` driven by stand code over the real Strata and llama
trees through a hardlink mirror - no gigabytes copied and no edits to the bench): the sabotage
`orphan_probe.dll` gives rc=2 naming the file, the full run gives rc=0 and the line "produced 13
exe/dll, 14 bin\ keys in the manifest, 1 waiver", the archive is 810.0 MiB and 26 entries including
`bin/strata_kq.dll`, the format gate on it is green, and the thin run without the CUDA runtime gives
rc=0 and "12 bin\ keys, 1 waiver" (a smaller manifest, the same closure finding).

A fourth class - the text of the kit itself - was found by the release run `43359812438` (13.11, a
manual run from the rehearsal branch `kit-ci-live`): job 03:34:02Z - 05:07:07Z, 5585 s, of which
5454 s were the compilation of both engines; it failed on the step "Layout and packing of the kit"
(35 s, 05:06:24Z - 05:06:59Z) with the line "WARNING: the kit still contains stand paths (2)" and
`rc(pack_kit)=1`, while the archive format gate was skipped. The findings were `README.en.md` and
`README.ru.md` - the very text that describes this gate: commit `aab79d10` had put an absolute path
to the directory of an earlier rehearsal into it. The README pair physically travels inside the
archive (`pack_kit.ps1:190`), and `Remove-StandPaths` scrubs only the measure sidecars (`$SIDECARS`,
`:732`) - so a document has to be left clean by its author, and that has to be checked before the
compiler runs, not after it.

The class is closed by the `pack_kit.ps1 -TextGate` entry. The file list comes from the same
`Get-Manifest` that drives the real packing: a second copy of the list would be exactly the defect
that was closed for `env.ARTIFACT_FILES`. Text extensions are measured (`.py`, `.ps1`, `.bat`,
`.json`, `.md`, `.txt`, `.cmd`), a finding prints the relative file name and the offending line, and
a missing `-KitSrc` directory, a missing input file or an empty measured set is a refusal with rc=2
("the check did not happen"), not "zero findings". Acceptance over four entries (13.11): `-SelfTest`
gives `ok=89 bad=0` (it used to be 82/0; the selftest now holds 69 controlling calls instead of 62),
the run over the live `packaging/kit` tree gives rc=0 and the line "text inputs: no stand paths left,
9 files checked", the sabotage (a copy of the tree with an absolute path planted in it) gives rc=1
naming the file relatively and without the copy's own path in the output, and a missing directory
gives rc=2. Both shell entries, pwsh 7 and Windows PowerShell 5.1, give the same 89/0. The same call
now stands in the first job of `kit-build.yml` and as its own cheap step in the release run - before
the CUDA toolchain and before the release check - so a run that has to fail on this class costs
seconds instead of 5585 s.

Log-line formatting is a class a green build never notices: `-f` binds tighter than `+`, so
`"template {0}" + "tail {1}" -f a, b` substitutes into the second piece only. The live run of
12.11 (`build-strata.log` of the kit378 rehearsal) printed literal `{0}`...`{4}` in the Strata
measure line: the JSON measures stayed intact, and what became unreadable in Actions were exactly
the cold numbers the `build_kind` label exists to justify. Four such sites are fixed - the strata
and llama measure lines, the no-op line and the architecture-proof line with a suffix - and the
neighbouring `pack_kit` and `install_cuda_redist` come back clean under the same measure (0 hits).
The class is closed in `-SelfTest` by two measures: a textual one over the script (with two sabotage
inputs and one false-alarm control) and a behavioural one - the same template glue with and without
parentheses. After the fix: 117/117 on both entries (pwsh 7 and Windows PowerShell 5.1).

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
over two carriers (exe) and 5 for llama.cpp over three (dll). The markers cover 12 of our 81
Strata commits and 3 of 14 in llama.cpp; edits that leave no readable name in a binary (a string
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

The four numbers above are three-architecture runs; `kit-build.yml` builds one architecture (86 by
default) - that was the last open gap in the limit's justification. It is closed by a 13.11 run on
clean clones taken from the GitHub remotes of both forks: the toolchain from the redist archives,
the same `ci/build_kit.ps1` called with the same arguments, the architecture probe switched off
explicitly (`-SkipProbe`) exactly as in the real run. strata - 751.6 s of compilation after 13.9 s of
configure (carrier `gpu-infer-kit-strata-cold86`, commit `11cbea3`, 160 compilations and 14 links,
174 of 174 edges executed in the log); llama - 1370.2 s after 12.1 s
(`gpu-infer-kit-llama-cold86`, commit `39628e5`, 315 compilations and 14 links, 330 of 330 edges).
Both measure files now carry correct fields: `archs` = `["86"]`, `build_kind` = "cold build",
`prebuilt_objects` = 0 - coldness is proven by the field itself, not only by CMakeCache. The
`elf-proof` of the same runs gives cubin on 86 only: 28 `sm_86` entries in `strata-q36.exe`, 71 in
`strata.exe` and 149 in `ggml-cuda.dll`; the marker gate on those binaries is green - strata 24/24
with 12 of 12 commits covered, llama 5/5 with 3 of 3, and the `markers-*.json` files sit next to
the measures.

The earlier version of the four-run paragraph rested on unclosed measurements: strata 737.7 s has no
carrier file at all (only the run's stdout and commit bodies), and strata 712.6 s and llama 2788.8 s
are warm-ups - 25+5 and 156+8 executed steps instead of 174 and 330.

Hence the limits. The release run gets 240 minutes and builds both engines on 86, 89 and 120 in a single
tree. Since 13.11 this limit has a full live measurement inside Actions itself: run `43388763285`
(`workflow_dispatch` on commit `e5bcd9c3`, architecture set `86;89;120`) closed green after 6044 s
(07:51:38Z -> 09:32:22Z, 16 of 16 steps `success`), and its `build-measure.json` gives pure compilation of
2108.9 s for Strata (configure 21.3 s) and 3704.5 s for llama (configure 12.7 s) - 5813.4 s (96.9 minutes) -
with `build_kind` = "cold build" on both engines. The margin is 14 400 / 5813.4 = 2.5 times, half of the
earlier estimate, because that estimate was built on runs with a single engine or with warm caches. The worst
previous pair is 1774.1 + 3321.0 = 5095.1 s (84.9 minutes), and run `43345549955` (1147.8 + 2249.9 =
3397.7 s, a margin of 4.2 times) is now an incomplete measurement rather than an upper bound: both engines
finished there, but the failure came later, at the native dependency gate. `kit-build.yml`
gets 180 minutes and builds a single architecture (86 by default), and since 13.11 it has a direct
measurement on that very configuration: the worse of the two engines on 86 is llama at 1370.2 s, so the
margin is 10 800 / 1370.2 = 7.9 times, and for strata at 751.6 s it is 14.4 times. The earlier
estimate rested on the 1774.1 s three-architecture build (a margin of 6.1 times) - an upper bound
rather than a measured price.

Acceptance of that green run is measured by the fields of the carrier files and by bytes, not by the colour
of the build. The kit archive of run 6 (`43388763285`), `gpu-infer-kit-2026-11-13.zip`, weighs
852 155 223 bytes and holds 26 entries; the run artifact `kit-release-6.zip` is 850 185 286 bytes with
8 entries, and these are different quantities:
the artifact carries the measures, the logs and the archive together. Further down this file there is a
second kit - 852 112 426 bytes from run `43422717479`, and that is the one sitting on the release; the two
weights differ by 42 797 bytes because the two runs packaged different builds, not because the numbers
disagree. `verify_zip.sh` is green on the archive
by the local-file-header signature, by EOCD and by all 12 required entries. The marker gate on binaries
extracted from that very archive: strata 24/24 at 12 of 12 covered commits, llama 5/5 at 3 of 3.
`elf-proof.json` proves cubin on all three architectures: `strata-q36.exe` has 28 `sm_86`, 28 `sm_89`,
27 `sm_120` and 1 `sm_120a` records; `strata.exe` - 71, 71, 70 and 1; `ggml-cuda.dll` - 149 on each of
`sm_86`, `sm_89`, `sm_120a`; `llama-server.exe` is 11 264 bytes with no CUDA code, because the code lives in
`ggml-cuda.dll`. The closure of the set: the `missing` field is empty, and the kit carries
`cublas64_13.dll` (52 697 712 bytes) and `cublaslt64_13.dll` (463 655 536) - 516 353 248 bytes of CUDA
runtime in total. The step "Публикация ассетом релиза" (publish as a release asset) took 0 s along the branch
"release tag not set": the build was verified, nothing was uploaded, and the fork had no releases at that
moment.

The same run surfaced a defect that a green build does not show: `kit-weight.json`, the kit weight measure
that `pack_kit.ps1` writes into the measures directory, did not reach the artifact, because the
`upload-artifact` path list named a path in the staging directory, while `if-no-files-found: warn` kept the
run green without the measure. Since 13.11 the path points at the measures directory, and the packaging step
checks that all four measures are present (`build-measure.json`, `elf-proof.json`, `runtime-deps.json`,
`kit-weight.json`) and otherwise exits with `rc=2` and the line "the check did not happen". The workflow
syntax was verified separately after the edit: the YAML parses, all six pwsh steps are read by the PowerShell
parser without errors, and the artifact path list contains no comment lines - inside the `path: |` block
scalar a `#` would be a literal path, not a comment.

The full rehearsal of the release job, run `43373203768` (13.11, `workflow_dispatch` on commit
`f6e09d27`, architecture set `86;89;120`), gave the first live price of a three-architecture Strata
build inside Actions itself: "configure 20.4 s, build 1909.7 s [cold build] (160 compilations, 14
links, objects before the run: 0), rc=0". The cheap steps ran before the compilation:
`rc(pack_kit -TextGate)=0` one second later, and the CUDA toolchain from the redist archives took
22 s. The step "Build both engines for CUDA" lasted 5269 s (05:38:07Z -> 07:05:56Z) and was
stopped: the run closed as `conclusion=cancelled` in its 89th minute, and the API does not answer
who cancelled it. Strata had already completed inside that step, llama had been running 3331 s
without a final measure, so the rehearsal left no merged build-measure.json or elf-proof.json: the
marker gate, the native dependency registry, packaging and the format gate stayed `skipped`, and the
`kit-release-4` artifact is 30 363 bytes holding two log files (971 907 and 3 233 bytes) and no kit
archive. The 240-minute limit rests on
run `43388763285`, where both engines completed and packaging ran, not on this rehearsal and not on
`43345549955`, where the build also completed in full but the failure came at the native dependency gate.

The same job in run `43374984065` (the release-existence gate probed with a deliberately wrong tag)
turns red in 35 s (05:53:47Z -> 05:54:22Z) with the line "релиза probe-no-such-release нет в этом
репозитории", and every expensive step is `skipped`: a publish refusal is readable in seconds
rather than after a two-hour build.

Engine compilation no longer starts on a push: since 13.11 `kit-build.yml` and `kit-build-cuda.yml`
have one trigger, `workflow_dispatch`, with an `arch` input. The measure: the pushes `5256c062`
(main of this fork) and `b206f728c` (`kit-all-sync` in the llama.cpp fork) at 07:38Z on 13.11
created no run at all - `GET /actions/runs?created=>2026-11-13T07:35Z` answers `total_count=0` in
both forks, and the newest runs there are dated 05:53Z and 04:42Z, that is, before those pushes.

Acceptance of run `43422717479` (number 11, artifact `kit-release-11`) rests on the fields of the
measures inside the artifact, not on the colour of the steps. `kit-weight.json`: the kit is
852 112 426 bytes over 26 entries, 516 353 248 of them being the CUDA runtime, packaging verdict
"green". The same archive checked locally by the byte-level format gate: header and EOCD present,
all 12 mandatory entries found. Both builds carry `build_kind` = "cold build" with
`prebuilt_objects: 0`: Strata `5db1fd6` (main) - configure 33.9 s and build 2113.8 s, 160 compiles
and 14 links; llama.cpp `b206f72` (`kit-all-sync`) - 12.9 s and 3710.3 s, 315 compiles and 14 links.
This is the most expensive measured pair so far - 5824.1 s (97.1 minutes) against the previous
5095.1 s - and the 240-minute limit stands 2.47 times above it. The marker gate over binaries taken
from this same archive: Strata 24/24 across 12 of 12 covered commits, llama.cpp 5/5 across 3 of 3;
`elf-proof.json` proves cubin for all three architectures (84, 213 and 447 entries in
`strata-q36.exe`, `strata.exe` and `ggml-cuda.dll`), while `llama-server.exe` is 11 264 bytes with
no CUDA code, because that code lives in `ggml-cuda.dll`.

The release asset is published: `gpu-infer-kit-2026-11-13.zip`, 852 112 426 bytes, `state=uploaded`,
`content_type=application/zip`, and accepting the released file by bytes - not through the local
copy but with partial HTTP range requests against the download address - gives the same 26 entries
and all 12 mandatory ones. It was uploaded by hand from the artifact of run 11, and the reason the
upload had to be manual is measured by the `release` event: run `43415264688` (number 7, 47 s in
total) is red at the cheap release-existence gate with the line «релиза kit-2026-11-13 нет в этом
репозитории», although by that hour the release had lived for 41 seconds (`published_at` 11:12:59Z
against a start at 11:13:01Z) and the REST call for that tag answers 200. What was missing was not
the release but the repository for `gh`: without `GH_REPO` it looks the repository up in the git
remote of the current directory, and `$GITHUB_WORKSPACE` has no remote repository - all three
`checkout` steps put the tree into subdirectories. The measure has lived in main since commit
`04d6a4c2`; the tag `kit-2026-11-13` points at `370c93fa`, where `GH_REPO` is absent from the file
(the measure over that edition: 0 matches), so the step printed the old line. Hence the honest
boundary: the asset is in place and checked from outside, but automatic publication by step 16 is not
yet proven - it needs a release whose tag sits on a commit carrying both edits (`GH_REPO` and the
`fi` in the publication condition).

## What is not here

- models (the archive contains no `.gguf` file);
- Linux and macOS;
- measurements on hardware other than our bench: a "below / far below" verdict is the honest
  boundary of profile transfer, not a promise of the same speeds;
- MTP at windows of 64k and above (measured as a regression, so it is not enabled), and every other
  rejected lever - their list with numbers is in the bench report `docs\reports`.

Russian version: `README.ru.md`.
