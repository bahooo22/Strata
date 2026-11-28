from __future__ import annotations

import datetime
import hashlib
import json
import pathlib
import subprocess

OUT = pathlib.Path(r"E:/eXample/Documents/Source/Github/_work_with_llm/glm/2026-11-27_session/upstream-4560d0379-quality")
PYTHON = pathlib.Path(r"C:/Projects/Strata-3060Ti/engine/terminal/.venv/Scripts/python.exe")
SUITE = pathlib.Path(r"E:/eXample/Documents/Source/Github/_work_with_llm/glm/scripts/hard_suite_2026-11-22.py")
SIDES = {
    "baseline": (pathlib.Path(r"F:/tmp/upstream-main-baseline-build/strata-q36.exe"), pathlib.Path(r"C:/Projects/Strata-3060Ti/engine/terminal")),
    "candidate": (pathlib.Path(r"F:/tmp/upstream-0.2.23-build/strata-q36.exe"), pathlib.Path(r"E:/tmp/cand-upstream-4560d0379/terminal")),
}


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    rows = []
    for side, (exe, root) in SIDES.items():
        target = OUT / side
        tag = f"upstream-{side}"
        console = OUT / f"{side}.console.log"
        argv = [str(PYTHON), "-X", "utf8", str(SUITE), "--model", "kat-iq4xs", "--profile", "general",
                "--exe", str(exe), "--port", "8186", "--ctx", "32768", "--tag", tag,
                "--out", str(target), "--server-root", str(root)]
        started = datetime.datetime.now().astimezone().isoformat()
        result = subprocess.run(argv, cwd=root, text=True, encoding="utf-8", errors="replace",
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=7200)
        ended = datetime.datetime.now().astimezone().isoformat()
        console.write_text(result.stdout + result.stderr, encoding="utf-8", errors="replace")
        raw = target / f"{tag}-raw.jsonl"
        records = [json.loads(line) for line in raw.read_text(encoding="utf-8").splitlines() if line.strip()] if raw.exists() else []
        record = records[-1] if records else {}
        row = {"side": side, "rc": result.returncode, "startedAt": started, "endedAt": ended,
               "console": str(console), "consoleSha256": sha(console), "raw": str(raw),
               "score": record.get("score"), "tasks": len(record.get("tasks", [])), "tag": tag}
        rows.append(row)
        print(json.dumps(row, ensure_ascii=False), flush=True)
        if row["rc"] != 0:
            break
    ok = len(rows) == 2 and all(row["rc"] == 0 and row["tasks"] == 12 for row in rows) and rows[0]["score"] == rows[1]["score"]
    report = {"ok": ok, "rows": rows, "scoreEqual": len(rows) == 2 and rows[0]["score"] == rows[1]["score"],
              "finishedAt": datetime.datetime.now().astimezone().isoformat()}
    (OUT / "summary.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False), flush=True)
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
