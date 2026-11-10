# Sharing a ready-to-run bundle (RTX 5080, two machines)

Status: 2026-11-09. One bundle for both target machines; two launch profiles, no second build.

## Why one bundle serves both

The GPU is the same on both machines: RTX 5080, compute capability 12.0 (`sm_120`, Blackwell). What
differs is the CPU (Intel Ultra 5 225F against Ryzen 7 9800X3D), the RAM (64 GiB DDR5-6400 against
96 GiB) and the disk (about 14 700 MB/s). An engine package carries code per architecture, not per
machine: `package_engine.py` takes `--arch` repeatedly (`action="append"`, package_engine.py:304) and
writes the list into `engine-component.json` (schema 2, per-file SHA-256 and size, package_engine.py:11,
:219-222). One CUDA package built with `--arch sm_120` therefore runs on both machines.

The CUDA toolkit is fixed by the card, not by the machine: `cuda_choice()` keeps RTX 50 cards on CUDA 13
because CUDA 12.8 engines crashed on long prompts for `sm_120` (#220, setup.py:1948-1959). CUDA 13
itself compiles for `sm_75` and newer (setup.py:262, `CUDA13_MIN_ARCH = 75`), and the upstream release
recipes already list the architecture string `"75;86;89;120"` (setup.py:2088-2090). So the bundle for
these two machines is "CUDA 13, arch 120"; adding more architectures to the same package only costs
compile time in `package_engine.py` (PTX via `compute_*` is optional).

CI is not a delivery channel for such a bundle, and waiting for "CI for every configuration" does not
produce one: the backend workflow says so itself - "Architectures are fewer than the release package's
(compile time)" (.github/workflows/backends.yml:10) - and the workflows keep artifacts only when a run
fails (`upload-artifact` under `if: ${{ failure() }}`, check.yml:101-109 and :144-152,
snapshot.yml:77-83) with `retention-days: 7`. In this fork the runs also wait for a maintainer's approval,
so a CI run cannot be the way a ready package reaches another person.

## Building the bundle

1. Build the engine for `sm_120` with CUDA 13. The current Windows recipe is pinned to `sm_86` and the
   toolkit in `CUDA_DIR` (it lives outside this repository: `../harness/scripts/build_strata.bat` in the
   Strata tree), so it is the wrong one for this bundle:
   build with the CUDA 13 toolkit and `sm_120` (plus `compute_89` if a PTX fallback is wanted).
   Nothing here builds; the wrapper takes a finished build folder.
2. Make the bundle and print the two calls first:

```
python packaging/make_share_bundle.py --build <build folder with strata.exe> --archs 120 --cuda 13 \
    --platform windows-x86_64 --version 0.1.45 --out FEED --keys KEYDIR \
    --url http://<this machine>:8099 [--terminal strata-terminal-0.1.45-windows-x86_64.zip] --dry-run
```

   Drop `--dry-run` to run it. The wrapper refuses a build folder without `strata.exe` (exit 2), an
   empty `--archs` (exit 2, an empty list is not a passed check), CUDA 12 with `sm_120` (exit 2,
   referencing setup.py:1948-1959 and #220) and CUDA 13 below `sm_75` (exit 2, setup.py:262). It then
   calls the two packagers that already exist and does not re-implement either:

   * `packaging/package_engine.py` - one CUDA package with `engine-component.json`;
   * `packaging/make_local_feed.py` - a local, test-signed feed: `strata-feed.json` + `.sig`,
     `control/` and `engine/` members, `install-manifest.txt`, `install.sh`, `install.ps1` with the
     `--url` address baked in, and `test-trust.json` (the public test key).

3. Serve the feed:

```
python -m http.server 8099 --bind 0.0.0.0 --directory FEED
```

Without `--terminal` the feed has no control package: `install.ps1` then has nothing to install first,
so pass the Terminal archive when the person needs `strata update` and `strata launch`.

## What the person on the other side gets

* `install.ps1` - one line, the address is already inside it.
* `strata update` - pulls the engine package from this feed; the trust comes from
  `STRATA_UPDATE_TRUSTED_KEYS=<FEED>/test-trust.json` (a test key, fine for a trial run).
* `strata launch` - starts the engine from the installed component.

The test key exists only for such a trial: a real release signs with the release key, which never
leaves the key folder (make_local_feed.py:11-16). Do not pass `test-trust.json` to anyone as a
production key.

## Models are not in the bundle

GGUF files are tens of GiB, so the bundle lists them instead of shipping them. The person downloads
them from the same place we did. Entries already pinned in `setup.py` (name, bytes, SHA-256; the file
uses two forms, `("ple", bytes, sha)` and `(bytes, sha)`):

| file | bytes | SHA-256 |
| --- | ---: | --- |
| ple-fp8.gguf | 51 200 246 176 | `37f89b8ce5a3425932763257c40229ec02723ad2ab14b4bbfc26a486f4725c9c` |
| Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf | 22 853 663 008 | `55983c5a75a1ab969824077b3bb3de4146e82a9234072b48ad4e8f92ad3fe9f1` |
| Qwen3.6-35B-A3B-UD-Q6_K_XL.gguf | 32 611 711 264 | `35fce994cd36104a7dc1bd8a4bdf13778145664c00fdef6773aebc9246e5019c` |
| Qwen3.6-35B-A3B-Q8_0.gguf | 37 801 097 504 | `c1283d8b80c3e38b2735ddbc9766d3b3126f44d6c484be419d4e101d09a76131` |

The full pinned list is in `setup.py` (grep for `.gguf":`). The models used in our own measurements
(KAT IQ4_XS, heretic Q4_K_M, HauhauCS IQ4_XS) are local files and are **not** in `setup.py`: whoever
repeats our numbers has to obtain the same files and check their SHA-256 themselves.

## Honest limits: the tuning profiles are not for this hardware

Every profile number we have was measured on an 8 GiB RTX 3060 Ti, a 4-core i7-4790K, 32 GiB of DDR3
and disk `D:` - not on an RTX 5080 with a 20-thread CPU and 64-96 GiB of RAM. Nothing below was
re-measured on the target machines. The levers have to be taken again from scratch:

* `--n-cpu-moe` (how many expert layers stay in host memory) - on 16 GB of VRAM it will be far lower
  than the 30-33 we use on 8 GB;
* `-ub` and `-b` (physical chunk) - the 2048 that is right here is a clamp from `-b 2048`, not a
  universal value;
* `att-mb` (attention workspace) and `--vram-reserve-mib` (headroom kept free) - both were tuned to a
  card where free VRAM was the bottleneck;
* super-chunk N (our N=4), MTP depth (our 2), FA on/off - the last two change output only through
  sampling mode and were measured on a different GPU generation.

## Two profile skeletons (placeholders, NOT numbers)

Every value is `null` on purpose: a skeleton is not a measurement. Fill them only after a run on the
target machine, and write the numbers into the comment next to them.

```json
{
  "_comment": "NOT MEASURED ON THIS HARDWARE - placeholders only",
  "target": "Intel Ultra 5 225F + RTX 5080 16 GB + 64 GiB DDR5-6400",
  "model": "<pick from the GGUF list>",
  "ctx": null,
  "batch": null,
  "ub": null,
  "ncmoe": null,
  "att_mb": null,
  "vram_reserve_mib": null,
  "super_chunk": null,
  "mtp": null,
  "fa": null
}
```

```json
{
  "_comment": "NOT MEASURED ON THIS HARDWARE - placeholders only",
  "target": "AMD Ryzen 7 9800X3D + RTX 5080 16 GB + 96 GiB RAM + SSD ~14700 MB/s",
  "model": "<pick from the GGUF list>",
  "ctx": null,
  "batch": null,
  "ub": null,
  "ncmoe": null,
  "att_mb": null,
  "vram_reserve_mib": null,
  "super_chunk": null,
  "mtp": null,
  "fa": null
}
```

The faster disk of the second machine matters only for model loading and for the file tier; it does not
make a VRAM-bound profile faster once the model is in memory.
