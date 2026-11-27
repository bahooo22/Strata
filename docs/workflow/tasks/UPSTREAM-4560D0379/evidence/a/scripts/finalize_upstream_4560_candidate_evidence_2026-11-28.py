from __future__ import annotations

import hashlib
import json
import pathlib
import shutil
import subprocess

CANDIDATE = pathlib.Path(r"E:/tmp/cand-upstream-4560d0379")
TASK = CANDIDATE / "docs/workflow/tasks/UPSTREAM-4560D0379"
TASK_REL = "docs/workflow/tasks/UPSTREAM-4560D0379"
OUT = pathlib.Path(r"E:/eXample/Documents/Source/Github/_work_with_llm/glm/2026-11-27_session")
CLOSURE = OUT / "upstream-4560d0379-H-package-closure"
BUILD_LOG = OUT / "upstream-4560d0379-build/build-all-r2-all-final.log"
EXE = pathlib.Path(r"F:/tmp/upstream-0.2.23-build/strata-q36.exe")
PYTHON = pathlib.Path(r"C:/Projects/Strata-3060Ti/engine/terminal/.venv/Scripts/python.exe")
LEAKCHECK = pathlib.Path(r"E:/eXample/Documents/Source/Github/leakcheck/leakcheck.py")
EXPECTED_HEAD = "2195f9b0f412d7e1f5447dad82a657e4db6904cc"
ARTIFACTS = (
    "upstream-4560d0379-A-gate-2026-11-28.json",
    "upstream-4560d0379-A-candidate-evidence-2026-11-28.md",
    "upstream-4560d0379-candidate-static-summary-2026-11-28.json",
    "upstream-4560d0379-candidate-merge-result-2026-11-28.json",
    "upstream-4560d0379-candidate-matrix.json",
    "upstream-4560d0379-closure-leakcheck.log",
    "upstream-4560d0379-unittest-targeted-final.log",
    "upstream-4560d0379-check-launch-main-baseline.log",
    "upstream-4560d0379-check-links-main-baseline.log",
    "upstream-4560d0379-check-docs.json",
    "N-upstream-4560d0379-package-review.md",
    "msg-42a0bc266.txt",
    "msg-2195f9b0f.txt",
)


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load(path: pathlib.Path) -> dict[str, object]:
    return json.loads(path.read_text(encoding="utf-8"))


def git(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["git", *args], cwd=CANDIDATE, text=True, encoding="utf-8", errors="replace", capture_output=True)


def copy(source: pathlib.Path, destination: pathlib.Path) -> dict[str, object]:
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)
    return {"source": str(source), "path": destination.relative_to(TASK).as_posix(),
            "bytes": destination.stat().st_size, "sha256": sha(destination), "ok": sha(source) == sha(destination)}


def main() -> int:
    head = git("rev-parse", "HEAD").stdout.strip()
    status = git("status", "--porcelain").stdout.splitlines()
    if head != EXPECTED_HEAD or (status and not all(line[3:].startswith(TASK_REL + "/") for line in status)):
        raise RuntimeError(f"candidate must be clean or task-local {EXPECTED_HEAD}: {head}, {status!r}")
    (TASK / ".gitattributes").write_bytes(b"* -text\n")
    shutil.copytree(CLOSURE, TASK, dirs_exist_ok=True)
    copied = []
    for name in ARTIFACTS:
        copied.append(copy(OUT / name, TASK / "evidence/a" / name))
    build_dir = TASK / "evidence/build"
    copied.append(copy(BUILD_LOG, build_dir / "build-all-final.log"))
    identity = {
        "runtimeBuildHead": EXPECTED_HEAD,
        "baseMain": "34bd46b86641d4fe34b3ab523e31b816718347e1",
        "upstream": "4560d03793482ef367294cfbd86a4df8d5679e72",
        "exe": str(EXE), "exeBytes": EXE.stat().st_size, "exeSha256": sha(EXE),
        "configureRc": 0, "buildRc": 0, "buildSeconds": 1196, "markers": "29/29",
        "buildLogSha256": sha(BUILD_LOG),
    }
    (build_dir / "build-identity.json").write_text(json.dumps(identity, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    copied.append(copy(pathlib.Path(__file__), TASK / "evidence/a/scripts" / pathlib.Path(__file__).name))
    files = []
    for path in sorted(TASK.rglob("*")):
        if path.is_file() and path.name != "evidence-index.json":
            files.append({"path": path.relative_to(TASK).as_posix(), "bytes": path.stat().st_size, "sha256": sha(path)})
    index = load(TASK / "evidence-index.json")
    index["stage"] = "UPSTREAM-4560D0379+metadata-closure+a-build-evidence"
    index["files"] = files
    (TASK / "evidence-index.json").write_text(json.dumps(index, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    diff_check = git("-c", "core.whitespace=cr-at-eol", "diff", "--check", EXPECTED_HEAD, "--", TASK_REL,
                     f":(exclude){TASK_REL}/evidence/**", f":(exclude){TASK_REL}/PATCH.diff")
    task_files = [str(path) for path in sorted(TASK.rglob("*")) if path.is_file() and path.name != "qwen35-upstream-delta.txt"]
    logs = []
    leak_rc = 0
    for offset in range(0, len(task_files), 32):
        result = subprocess.run([str(PYTHON), "-X", "utf8", str(LEAKCHECK), "--prose", *task_files[offset:offset + 32]],
                                cwd=CANDIDATE, text=True, encoding="utf-8", errors="replace", capture_output=True, timeout=600)
        logs.append(f"=== batch {offset // 32 + 1} ===\n" + result.stdout + result.stderr)
        leak_rc = max(leak_rc, result.returncode)
    (OUT / "upstream-4560d0379-finalize-leakcheck.log").write_text("".join(logs), encoding="utf-8", errors="replace")
    status_after = git("status", "--porcelain").stdout.splitlines()
    checks = {
        "copied": all(item["ok"] for item in copied),
        "diffCheck": diff_check.returncode == 0,
        "leakcheck": leak_rc == 0,
        "onlyTaskDir": bool(status_after) and all(line[3:].startswith(TASK_REL + "/") for line in status_after),
    }
    report = {"ok": all(checks.values()), "checks": checks, "copied": copied, "indexedFiles": len(files),
              "identity": identity, "status": status_after}
    (OUT / "upstream-4560d0379-finalize.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"ok": report["ok"], "checks": checks, "copied": len(copied), "indexedFiles": len(files)}, ensure_ascii=False))
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
