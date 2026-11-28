from __future__ import annotations

import datetime
import json
import os
import pathlib
import subprocess
import sys
import time

import psutil

OUT = pathlib.Path(r"E:/eXample/Documents/Source/Github/_work_with_llm/glm/2026-11-27_session/upstream-4560d0379-copy-session")
MODEL = pathlib.Path(r"D:/Strata/models/katcoder/KAT-Coder-V2.5-Dev-35B-A3B-MTP-ABLITERATED.i1-IQ4_XS.gguf")
MASTER = pathlib.Path(r"E:/tmp/master.txt")
SIDES = {
    "baseline": (pathlib.Path(r"F:/tmp/upstream-main-baseline-build/strata-q36.exe"), pathlib.Path(r"C:/Projects/Strata-3060Ti/engine/terminal")),
    "candidate": (pathlib.Path(r"F:/tmp/upstream-0.2.23-build/strata-q36.exe"), pathlib.Path(r"E:/tmp/cand-upstream-4560d0379/terminal")),
}
sys.path.insert(0, r"C:/Projects/Strata-3060Ti/engine/terminal/tools")
from strata_tokenizer import Tokenizer
sys.path.insert(0, r"E:/tmp/cand-upstream-4560d0379/terminal/tools/qwen35")
from q36_harness import Eng


def iso() -> str:
    return datetime.datetime.now().astimezone().isoformat()


def barrier() -> None:
    deadline = time.time() + 300
    while time.time() < deadline:
        busy = [p.info["name"] for p in psutil.process_iter(["name"]) if (p.info["name"] or "").lower() in {"strata.exe", "strata-q36.exe"}]
        sample = subprocess.run(["nvidia-smi", "--query-gpu=memory.used", "--format=csv,noheader,nounits"], capture_output=True, text=True, timeout=10)
        used = int(sample.stdout.strip()) if sample.returncode == 0 and sample.stdout.strip().isdigit() else 99999
        if not busy and used < 50 and psutil.virtual_memory().available / (1 << 30) >= 20:
            return
        time.sleep(3)
    raise RuntimeError("RAM/VRAM barrier not met")


def batch_request(eng: Eng, ids: list[int], slot: int) -> dict[str, object]:
    eng.send("BGEN %d 1 deterministic=1 %s" % (slot, ",".join(map(str, ids))))
    tokens: list[int] = []
    resume = fresh = None
    done = badm = None
    while True:
        line = eng.line(timeout=600)
        if line is None:
            raise RuntimeError("engine ended")
        if line.startswith("ERR"):
            raise RuntimeError(line)
        if line.startswith("RESUME "):
            resume = int(line.split()[1])
        elif line.startswith("PP "):
            fresh = int(line.split()[2])
        elif line.startswith("T "):
            tokens.append(int(line.split()[1]))
        elif line.startswith("BT ") and int(line.split()[1]) == slot:
            tokens.append(int(line.split()[2]))
        elif line.startswith("DONE "):
            done = line
            fields = line.split()
            if len(fields) >= 15:
                resume = int(fields[8])
                fresh = int(fields[14])
        elif line.startswith("BADM "):
            badm = line
            if line.split()[2] == "0":
                break
        elif line.startswith("BDONE ") and int(line.split()[1]) == slot:
            break
    return {"tokens": tokens, "resume": resume, "fresh": fresh, "done": done, "badm": badm}


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    ids = Tokenizer.from_gguf(str(MODEL)).encode(MASTER.read_text(encoding="utf-8", errors="replace")[:160000])
    primer = ids[:18000]
    edited = primer + ids[18000:20000]
    rows = []
    for side, (exe, root) in SIDES.items():
        barrier()
        log = OUT / f"{side}-engine.log"
        env = dict(os.environ)
        env.pop("STRATA_Q35_PREFIX_CACHE", None)
        env["STRATA_ENGINE_STALL_S"] = "120"
        args = ["--native", str(MODEL), "--max-context", "32768", "--chunk", "128", "--batch", "2",
                "--prefill", "256", "--kv-type", "q4_0", "--super-chunk", "1", "--mtp", "0",
                "--fa", "-2", "--fa-tile", "4", "--vram-reserve-mib", "512", "--att-mb", "256"]
        eng = Eng(str(exe), args, env=env, log=str(log))
        try:
            batch_request(eng, primer, 0)
            copied = batch_request(eng, edited, 1)
            solo = batch_request(eng, edited, 0)
        finally:
            eng.close()
        row = {"side": side, "log": str(log), "copied": copied, "solo": solo,
               "tokensEqual": copied["tokens"] == solo["tokens"],
               "copyPrefix": copied["resume"], "fresh": copied["fresh"]}
        row["ok"] = row["tokensEqual"] and copied["resume"] == 18000 and copied["fresh"] == 2000 and len(copied["tokens"]) == 1 and len(solo["tokens"]) == 1
        rows.append(row)
        print(json.dumps(row, ensure_ascii=False), flush=True)
        if not row["ok"]:
            break
    ok = len(rows) == 2 and all(row["ok"] for row in rows) and rows[0]["copied"]["tokens"] == rows[1]["copied"]["tokens"]
    report = {"ok": ok, "rows": rows, "finishedAt": iso()}
    (OUT / "summary.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False), flush=True)
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
