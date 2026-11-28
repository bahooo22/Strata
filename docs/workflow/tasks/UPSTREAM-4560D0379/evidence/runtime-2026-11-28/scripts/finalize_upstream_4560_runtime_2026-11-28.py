from __future__ import annotations

import hashlib
import json
import pathlib
import shutil
import statistics
import subprocess

CANDIDATE = pathlib.Path(r"E:/tmp/cand-upstream-4560d0379")
TASK = CANDIDATE / "docs/workflow/tasks/UPSTREAM-4560D0379"
TASK_REL = "docs/workflow/tasks/UPSTREAM-4560D0379"
OUT = pathlib.Path(r"E:/eXample/Documents/Source/Github/_work_with_llm/glm/2026-11-27_session")
SCRIPTS = pathlib.Path(r"E:/eXample/Documents/Source/Github/_work_with_llm/glm/scripts")
PYTHON = pathlib.Path(r"C:/Projects/Strata-3060Ti/engine/terminal/.venv/Scripts/python.exe")
LEAKCHECK = pathlib.Path(r"E:/eXample/Documents/Source/Github/leakcheck/leakcheck.py")
EXPECTED_HEAD = "81dccf48236782eb01f92fc999e2210e47170385"
TARGET = TASK / "evidence/runtime-2026-11-28"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load(path: pathlib.Path) -> dict[str, object]:
    return json.loads(path.read_text(encoding="utf-8"))


def git(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["git", *args], cwd=CANDIDATE, text=True, encoding="utf-8", errors="replace", capture_output=True)


def copy_file(source: pathlib.Path, destination: pathlib.Path) -> dict[str, object]:
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)
    return {"source": str(source), "path": destination.relative_to(TASK).as_posix(),
            "bytes": destination.stat().st_size, "sha256": sha(destination), "ok": sha(source) == sha(destination)}


def copy_tree(source: pathlib.Path, destination: pathlib.Path) -> list[dict[str, object]]:
    shutil.copytree(source, destination, dirs_exist_ok=True)
    return [copy_file(path, destination / path.relative_to(source)) for path in sorted(source.rglob("*")) if path.is_file()]


def median(values: list[float]) -> float:
    return statistics.median(values)


def aggregate() -> dict[str, object]:
    ledger = OUT / "upstream-4560d0379-runtime/ledger.jsonl"
    rows = [json.loads(line) for line in ledger.read_text(encoding="utf-8").splitlines() if line.strip()]
    per_window = {}
    for window in ("32k", "160k", "200k"):
        base = [r for r in rows if r["window"] == window and r["side"] == "baseline"]
        cand = [r for r in rows if r["window"] == window and r["side"] == "candidate"]
        bp, cp = median([r["pp"] for r in base]), median([r["pp"] for r in cand])
        bt, ct = median([r["tg"] for r in base]), median([r["tg"] for r in cand])
        per_window[window] = {"baselinePp": bp, "candidatePp": cp, "deltaPpPct": (cp / bp - 1) * 100,
                              "baselineTg": bt, "candidateTg": ct, "deltaTgPct": (ct / bt - 1) * 100,
                              "answerParity": len({r["contentSha256"] for r in base + cand}) == 1,
                              "baselineRuns": len(base), "candidateRuns": len(cand)}
    repeat = load(OUT / "upstream-4560d0379-32k-repeat-summary.json")
    mtp2 = load(OUT / "upstream-4560d0379-runtime-mtp2/summary.json")
    quality = load(OUT / "upstream-4560d0379-quality/summary.json")
    copy_session = load(OUT / "upstream-4560d0379-copy-session/summary.json")
    ok = (len(rows) == 12 and all(r["rc"] == 0 for r in rows)
          and all(row["answerParity"] for row in per_window.values())
          and repeat["ok"] and mtp2["ok"] and quality["ok"] and copy_session["ok"])
    return {"ok": ok, "perWindow": per_window, "repeat32k": repeat, "mtp2": mtp2,
            "quality": quality, "copySession": copy_session, "rawRows": len(rows)}


def markdown(summary: dict[str, object]) -> str:
    lines = ["# UPSTREAM-4560D0379 — runtime acceptance", "",
             "- Candidate runtime/build HEAD: `2195f9b0f`; immutable review tip: `81dccf482`.", "",
             "| window | baseline pp/tg | candidate pp/tg | Δpp | Δtg | answer parity |",
             "|---|---:|---:|---:|---:|---|"]
    for window, row in summary["perWindow"].items():
        lines.append(f"| {window} | {row['baselinePp']:.2f}/{row['baselineTg']:.2f} | {row['candidatePp']:.2f}/{row['candidateTg']:.2f} | {row['deltaPpPct']:+.3f}% | {row['deltaTgPct']:+.3f}% | {row['answerParity']} |")
    lines.extend(["", "## Дополнительные gates", "",
                  f"- 32k repeat 3+3: {summary['repeat32k']['ok']}; Δpp {summary['repeat32k']['deltaPpPct']:+.3f}%, Δtg {summary['repeat32k']['deltaTgPct']:+.3f}%.",
                  f"- MTP2 32k: {summary['mtp2']['ok']}; exact answer parity.",
                  f"- Quality general: {summary['quality']['ok']}; 12 задач, 16/22 у обеих сторон.",
                  f"- Copy_session: {summary['copySession']['ok']}; prefix 18000, fresh 2000, tokens equal.", "",
                  "## Ограничения", "",
                  "- Performance является descriptive; speed progress не заявляется.",
                  "- GPU parity: 85 passed, 1 skipped, 1 baseline-identical failure (Q6_K+Q8_0).",
                  "- Полный protocol edge matrix и full engine sanitizer не запускались по baseline blockers.",
                  "- Main merge/push не выполнялись.", ""])
    return "\n".join(lines)


def main() -> int:
    head = git("rev-parse", "HEAD").stdout.strip()
    status = git("status", "--porcelain").stdout.splitlines()
    if head != EXPECTED_HEAD or (status and not all(line[3:].startswith(TASK_REL + "/") for line in status)):
        raise RuntimeError(f"candidate must be clean or task-local {EXPECTED_HEAD}: {head}, {status!r}")
    summary = aggregate()
    if not summary["ok"]:
        raise RuntimeError("runtime aggregate is not green")
    copied = []
    copied += copy_tree(OUT / "upstream-4560d0379-runtime", TARGET / "ab")
    for index in (1, 2, 3):
        copied += copy_tree(OUT / f"upstream-4560d0379-runtime-32k-repeat{index}", TARGET / f"repeat32k-{index}")
    copied += copy_tree(OUT / "upstream-4560d0379-runtime-mtp2", TARGET / "mtp2")
    copied += copy_tree(OUT / "upstream-4560d0379-quality", TARGET / "quality")
    copied += copy_tree(OUT / "upstream-4560d0379-copy-session", TARGET / "copy-session")
    copied += copy_tree(OUT / "upstream-4560d0379-runtime-200k-short-master", TARGET / "diagnostic-short-master")
    copied += copy_tree(OUT / "upstream-4560d0379-copy-session-parser-defect", TARGET / "diagnostic-copy-parser-v1")
    copied += copy_tree(OUT / "upstream-4560d0379-copy-session-parser-defect-v2", TARGET / "diagnostic-copy-parser-v2")
    for name in ("upstream-4560d0379-performance-flow.mmd", "upstream-4560d0379-performance-flow.evidence.md",
                 "upstream-4560d0379-32k-repeat-summary.json"):
        copied.append(copy_file(OUT / name, TARGET / "a" / name))
    for name in ("run_upstream_4560_ab_2026-11-28.py", "run_upstream_4560_quality_2026-11-28.py",
                 "run_upstream_4560_copy_session_2026-11-28.py", "finalize_upstream_4560_runtime_2026-11-28.py"):
        copied.append(copy_file(SCRIPTS / name, TARGET / "scripts" / name))
    copied.append(copy_file(OUT / "upstream-main-baseline-build/build-all-all-final.log", TARGET / "baseline-build-all-final.log"))
    (TARGET / "runtime-summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (TARGET / "RUNTIME-ACCEPTANCE.md").write_text(markdown(summary), encoding="utf-8")
    files = []
    for path in sorted(TASK.rglob("*")):
        if path.is_file() and path.name != "evidence-index.json":
            files.append({"path": path.relative_to(TASK).as_posix(), "bytes": path.stat().st_size, "sha256": sha(path)})
    index = load(TASK / "evidence-index.json")
    index["stage"] = "UPSTREAM-4560D0379+metadata-closure+a-build-evidence+code-algorithms+runtime-2026-11-28"
    index["files"] = files
    (TASK / "evidence-index.json").write_text(json.dumps(index, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    diff_check = git("-c", "core.whitespace=cr-at-eol", "diff", "--check", EXPECTED_HEAD, "--", TASK_REL,
                     f":(exclude){TASK_REL}/evidence/**", f":(exclude){TASK_REL}/PATCH.diff")
    task_files = [str(path) for path in sorted(TASK.rglob("*")) if path.is_file() and path.stat().st_size > 0]
    logs = []
    leak_rc = 0
    for offset in range(0, len(task_files), 32):
        result = subprocess.run([str(PYTHON), "-X", "utf8", str(LEAKCHECK), "--prose", *task_files[offset:offset + 32]],
                                cwd=CANDIDATE, text=True, encoding="utf-8", errors="replace", capture_output=True, timeout=600)
        logs.append(f"=== batch {offset // 32 + 1} ===\n" + result.stdout + result.stderr)
        leak_rc = max(leak_rc, result.returncode)
    (OUT / "upstream-4560d0379-runtime-finalize-leakcheck.log").write_text("".join(logs), encoding="utf-8", errors="replace")
    status_after = git("status", "--porcelain").stdout.splitlines()
    checks = {"copied": all(item["ok"] for item in copied), "runtime": summary["ok"],
              "diffCheck": diff_check.returncode == 0, "leakcheck": leak_rc == 0,
              "onlyTaskDir": bool(status_after) and all(line[3:].startswith(TASK_REL + "/") for line in status_after)}
    report = {"ok": all(checks.values()), "checks": checks, "copied": len(copied), "indexedFiles": len(files),
              "summary": summary, "status": status_after}
    (OUT / "upstream-4560d0379-runtime-finalize.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"ok": report["ok"], "checks": checks, "copied": len(copied), "indexedFiles": len(files)}, ensure_ascii=False))
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
