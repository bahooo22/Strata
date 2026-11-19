#!/usr/bin/env python3
"""One entry point for a shareable bundle: a local, test-signed feed for a machine we do not have.

    python packaging/make_share_bundle.py --build <folder with strata.exe> --archs 120 --cuda 13 \
        --platform windows-x86_64 --version 0.1.45 --out FEED --keys KEYDIR \
        [--url http://127.0.0.1:8099] [--terminal <archive> ...] [--dry-run]

The script does not build and does not package by itself. It refuses a build without the engine binary,
checks the architecture/CUDA pair against the constants in `setup.py`, and then calls the two packagers
that already exist:

    packaging/package_engine.py   one CUDA engine package (engine-component.json, per-file SHA-256)
    packaging/make_local_feed.py  a local, TEST-SIGNED feed: strata-feed.json + .sig, control/engine
                                  members, install-manifest.txt, install.sh / install.ps1, test-trust.json

`--dry-run` prints exactly those two calls and writes nothing.

Architectures: `--archs 120` is accepted in the short form and becomes `sm_120` for package_engine.py;
`sm_86` and `compute_89` pass through unchanged (`compute_*` is PTX, not a card). A `gfx*` (HIP) value is
refused: this bundle is the CUDA package, and an AMD engine is `package_engine.py --backend hip`.

Exit codes: 0 done (or a clean dry run); 2 refused: no engine binary, empty --archs, unknown CUDA, or an
architecture/CUDA pair the engine's own rules do not allow.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACKAGERS = ("package_engine.py", "make_local_feed.py")
DEFAULT_URL = "http://127.0.0.1:8099"


def setup_rules(setup_py: Path | None = None) -> dict:
    """The numbers that decide the arch/CUDA check, read from setup.py so they are not copied here:
    CUDA13_MIN_ARCH (the oldest card CUDA 13 compiles for), MIN_DRIVER (the oldest NVIDIA driver), and
    the RTX 50 threshold used by cuda_choice() (`archs[-1] >= 120`)."""
    path = setup_py or ROOT / "setup.py"
    text = path.read_text(encoding="utf-8", errors="replace")
    rules = {}
    m = re.search(r"^CUDA13_MIN_ARCH\s*=\s*(\d+)", text, re.MULTILINE)
    if m:
        rules["cuda13_min_arch"] = int(m.group(1))
    m = re.search(r"^MIN_DRIVER\s*=\s*(\d+)", text, re.MULTILINE)
    if m:
        rules["min_driver"] = int(m.group(1))
    m = re.search(r"archs\[-1\]\s*>=\s*(\d+)", text)
    if m:
        rules["sm120"] = int(m.group(1))
    return rules


def arch_number(value: str) -> int | None:
    m = re.fullmatch(r"(?:sm_|compute_)?(\d+)(?:a|f)?", value.strip().lower())
    return int(m.group(1)) if m else None


def package_arch(value: str) -> str:
    """`120` -> `sm_120`; `sm_120`, `compute_89`, `gfx1201` stay as given."""
    v = value.strip().lower()
    if re.fullmatch(r"\d+(?:a|f)?", v):
        return "sm_" + v
    return v


def check_archs(archs: list[str], cuda: int, rules: dict) -> list[str]:
    """Refusals before anything is written. Empty input is a refusal, not a silent ok."""
    problems: list[str] = []
    if not archs:
        problems.append("no --archs: an empty list means the check did not happen, not that it passed "
                        "(give at least the card of the target machine, e.g. --archs 120)")
        return problems
    numbers = [arch_number(a) for a in archs]
    bad = [a for a, n in zip(archs, numbers) if n is None]
    if bad:
        problems.append("not an architecture: " + ", ".join(bad))
        return problems
    hip = [a for a in archs if a.strip().lower().startswith("gfx")]
    if hip:
        problems.append("HIP architecture in a CUDA bundle: " + ", ".join(hip) +
                        " (an AMD engine is package_engine.py --backend hip)")
        return problems
    numbers = [n for n in numbers if n is not None]
    if cuda not in (12, 13):
        problems.append(f"--cuda {cuda} is unknown: the engine ships CUDA 12 (Pascal/Volta) or CUDA 13")
        return problems
    sm120 = rules.get("sm120", 120)
    floor = rules.get("cuda13_min_arch", 75)
    if cuda == 12 and max(numbers) >= sm120:
        problems.append(
            f"refusing CUDA 12 with sm_{max(numbers)}: RTX 50 (sm_{sm120}) engines built with CUDA 12.8 "
            "crashed on long prompts (#220); the CUDA 12 engine is the Pascal/Volta build "
            "(setup.py:1948-1959, cuda_choice). Build the bundle with --cuda 13.")
    if cuda == 13 and min(numbers) < floor:
        problems.append(
            f"refusing CUDA 13 with sm_{min(numbers)}: CUDA 13 compiles for sm_{floor} and newer "
            f"(setup.py:262, CUDA13_MIN_ARCH = {floor}); an older card needs the CUDA 12 engine.")
    return problems


def check_build(build: Path, platform: str) -> str | None:
    """The engine binary package_engine.py will take: strata.exe on Windows, strata elsewhere."""
    if not build.is_dir():
        return f"--build {build} is not a folder"
    entry = "strata.exe" if platform.startswith("windows") else "strata"
    if not (build / entry).is_file():
        return (f"--build {build} has no {entry}: package_engine.py refuses a package without its "
                "entrypoint, so the bundle is refused before anything is written")
    return None


def package_call(a, out: Path) -> list[str]:
    rules = setup_rules()
    calls = [sys.executable, str(ROOT / "packaging" / PACKAGERS[0]),
             "--src", str(a.build), "--backend", "cuda", "--version", a.version,
             "--out", str(out), "--platform", a.platform, "--variant", f"cuda{a.cuda}",
             "--min-driver", f"nvidia={rules.get('min_driver', 580)}"]
    for arch in a.archs:
        calls += ["--arch", package_arch(arch)]
    return calls


def feed_call(a, out: Path, package_folder: Path) -> list[str]:
    calls = [sys.executable, str(ROOT / "packaging" / PACKAGERS[1]), "--out", str(a.out),
             "--engine", str(package_folder), "--keys", str(a.keys), "--url", a.url,
             "--version", a.version]
    for term in a.terminal:
        calls += ["--terminal", str(term)]
    return calls


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--build", type=Path, required=True, help="folder with the built strata.exe (or strata)")
    ap.add_argument("--archs", action="append", default=[], metavar="ARCH",
                    help="card architecture, repeatable: 120, sm_86, compute_89, gfx1201")
    ap.add_argument("--cuda", type=int, default=13, choices=(12, 13))
    ap.add_argument("--platform", default="windows-x86_64")
    ap.add_argument("--version", required=True)
    ap.add_argument("--out", type=Path, required=True, help="the feed folder to write")
    ap.add_argument("--keys", type=Path, required=True, help="folder for the test signing key")
    ap.add_argument("--url", default=DEFAULT_URL, help="the address the feed will be served at")
    ap.add_argument("--terminal", type=Path, action="append", default=[],
                    help="a Terminal archive; without it the feed has no control package and install.ps1 "
                         "has nothing to install first")
    ap.add_argument("--dry-run", action="store_true", help="print the two calls; write nothing")
    a = ap.parse_args(argv)

    rules = setup_rules()
    problems = check_archs(a.archs, a.cuda, rules)
    build_problem = check_build(a.build, a.platform)
    if build_problem:
        problems.append(build_problem)
    if problems:
        print("refusing the share bundle:", file=sys.stderr)
        for problem in problems:
            print("  " + problem, file=sys.stderr)
        return 2

    out = a.out.resolve()
    package_dir = out / ".packages"
    expected = package_dir / f"{a.version}-{a.platform}-cuda-cuda{a.cuda}"
    calls = [package_call(a, package_dir), feed_call(a, out, expected)]
    if a.dry_run:
        print("dry run: nothing is written")
        for call in calls:
            print("  " + " ".join(call))
        if not a.terminal:
            print("  note: no --terminal given, so the feed carries the engine only; install.ps1 and "
                  "strata update expect a control package too")
        return 0

    for call in calls:
        print("+ " + " ".join(call))
        rc = subprocess.call(call)
        if rc != 0:
            print(f"stopped: {call[1]} exited with {rc}", file=sys.stderr)
            return rc
    if not expected.is_dir():
        print(f"the packager did not leave {expected} behind", file=sys.stderr)
        return 2
    print(f"feed written to {out}")
    print(f"  serve it:  python -m http.server {a.url.rsplit(':', 1)[-1]} --bind 127.0.0.1 "
          f"--directory {out}")
    print(f"  trust it:  STRATA_UPDATE_TRUSTED_KEYS={out / 'test-trust.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
