from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
import pathlib
import re
import subprocess
import threading
import time

import psutil

OUT = pathlib.Path(r"E:/eXample/Documents/Source/Github/_work_with_llm/glm/2026-11-27_session/upstream-4560d0379-runtime")
RUN_ONE = pathlib.Path(r"E:/eXample/Documents/Source/Github/_work_with_llm/glm/scripts/run_one_160k_2026-11-20.py")
PYTHON = pathlib.Path(r"C:/Projects/Strata-3060Ti/engine/terminal/.venv/Scripts/python.exe")
MODEL = pathlib.Path(r"D:/Strata/models/katcoder/KAT-Coder-V2.5-Dev-35B-A3B-MTP-ABLITERATED.i1-IQ4_XS.gguf")
MASTER = pathlib.Path(r"E:/tmp/master-upstream-200k.txt")
SIDES = {
    "baseline": {"exe": pathlib.Path(r"F:/tmp/upstream-main-baseline-build/strata-q36.exe"),
                 "root": pathlib.Path(r"C:/Projects/Strata-3060Ti/engine/terminal")},
    "candidate": {"exe": pathlib.Path(r"F:/tmp/upstream-0.2.23-build/strata-q36.exe"),
                  "root": pathlib.Path(r"E:/tmp/cand-upstream-4560d0379/terminal")},
}
WINDOWS = {"32k": (32768, 30000, 64), "160k": (163840, 440000, 256), "200k": (204800, 616000, 256)}
MTP = 0
DRAFT_VOCAB = None
RESULT = re.compile(r"RESULT pp=([\d.]+) tg=([\d.]+) prefill_ms=(\d+) gen_ms=(\d+) chars=(\d+)")


def iso() -> str:
    return datetime.datetime.now().astimezone().isoformat()


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def barrier() -> dict[str, object]:
    deadline = time.time() + 300
    while time.time() < deadline:
        busy = [p.info["name"] for p in psutil.process_iter(["name"]) if (p.info["name"] or "").lower() in {"strata.exe", "strata-q36.exe"}]
        sample = subprocess.run(["nvidia-smi", "--query-gpu=memory.used", "--format=csv,noheader,nounits"], capture_output=True, text=True, timeout=10)
        used = int(sample.stdout.strip()) if sample.returncode == 0 and sample.stdout.strip().isdigit() else 99999
        free = psutil.virtual_memory().available / (1 << 30)
        if not busy and used < 50 and free >= 20:
            return {"vramUsedMiB": used, "ramAvailableGiB": round(free, 2)}
        time.sleep(3)
    raise RuntimeError("RAM/VRAM barrier not met")


class Sampler:
    def __init__(self) -> None:
        self.stop_event = threading.Event()
        self.samples: list[dict[str, object]] = []
        self.thread = threading.Thread(target=self._run, daemon=True)

    def _run(self) -> None:
        while not self.stop_event.is_set():
            try:
                gpu = subprocess.run(["nvidia-smi", "--query-gpu=memory.used,utilization.gpu", "--format=csv,noheader,nounits"],
                                     capture_output=True, text=True, timeout=10)
                used = util = None
                if gpu.returncode == 0 and "," in gpu.stdout:
                    used_s, util_s = [x.strip() for x in gpu.stdout.splitlines()[0].split(",", 1)]
                    used, util = int(used_s), int(util_s)
                self.samples.append({"at": iso(), "vramUsedMiB": used, "gpuUtil": util,
                                     "ramAvailableGiB": round(psutil.virtual_memory().available / (1 << 30), 2)})
            except Exception:
                pass
            self.stop_event.wait(2)

    def start(self) -> None:
        self.thread.start()

    def stop(self) -> list[dict[str, object]]:
        self.stop_event.set()
        self.thread.join(timeout=10)
        return self.samples


def run_point(side: str, window: str, order: str, index: int) -> dict[str, object]:
    ctx, chars, max_tokens = WINDOWS[window]
    prefix = OUT / f"{window}-{order}-{index}-{side}"
    engine_log = prefix.with_suffix(".engine.log")
    answer = prefix.with_suffix(".answer.json")
    provenance = prefix.with_suffix(".provenance.json")
    console = prefix.with_suffix(".console.log")
    resources = prefix.with_suffix(".resources.json")
    run_id = f"upstream4560-{window}-{order}-{index}-{side}"
    argv = [str(PYTHON), "-X", "utf8", str(RUN_ONE), "--exe", str(SIDES[side]["exe"]),
            "--model", str(MODEL), "--port", "8186", "--ctx", str(ctx), "--chars", str(chars),
            "--master", str(MASTER), "--super", "8", "--att", "256", "--reserve", "512", "--mtp", str(MTP),
            "--prefill", "2048", "--kv-type", "q4_0", "--max-tokens", str(max_tokens), "--fa", "-2", "--fa-tile", "4",
            "--server-root", str(SIDES[side]["root"]), "--log", str(engine_log), "--answer-out", str(answer),
            "--provenance-out", str(provenance), "--run-id", run_id, "--started-at", iso(), "--order", order,
            "--instruction", "Write a detailed explanation of mixture-of-experts inference.", "--graph", "--no-thinking"]
    if DRAFT_VOCAB is not None:
        argv.extend(["--draft-vocab", str(DRAFT_VOCAB)])
    env = dict(os.environ)
    env.pop("STRATA_Q36_ROUTE_SELECTOR", None)
    env["STRATA_Q36_ROUTE_TRACE"] = "0"
    before = barrier()
    sampler = Sampler()
    sampler.start()
    started = iso()
    result = subprocess.run(argv, cwd=SIDES[side]["root"], env=env, text=True, encoding="utf-8", errors="replace",
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=3900)
    samples = sampler.stop()
    ended = iso()
    console.write_text(result.stdout + result.stderr, encoding="utf-8", errors="replace")
    vram = [s["vramUsedMiB"] for s in samples if isinstance(s.get("vramUsedMiB"), int)]
    ram = [s["ramAvailableGiB"] for s in samples if isinstance(s.get("ramAvailableGiB"), (int, float))]
    resources.write_text(json.dumps({"before": before, "samples": samples, "peakVramMiB": max(vram) if vram else None,
                                     "minRamAvailableGiB": min(ram) if ram else None}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    match = RESULT.findall(result.stdout + result.stderr)
    answer_data = json.loads(answer.read_text(encoding="utf-8")) if answer.exists() else {}
    row = {"runId": run_id, "side": side, "window": window, "order": order, "index": index,
           "startedAt": started, "endedAt": ended, "rc": result.returncode, "console": str(console),
           "engineLog": str(engine_log), "answer": str(answer), "provenance": str(provenance),
           "resources": str(resources), "pp": float(match[-1][0]) if match else None,
           "tg": float(match[-1][1]) if match else None, "prefillMs": int(match[-1][2]) if match else None,
           "genMs": int(match[-1][3]) if match else None, "chars": int(match[-1][4]) if match else None,
           "answerSha256": sha(answer) if answer.exists() else None,
           "contentSha256": hashlib.sha256(str(answer_data.get("content", "")).encode("utf-8")).hexdigest(),
           "completionTokens": (answer_data.get("usage") or {}).get("completion_tokens"),
           "finishReason": answer_data.get("finishReason"), "peakVramMiB": max(vram) if vram else None,
           "minRamAvailableGiB": min(ram) if ram else None}
    print(json.dumps(row, ensure_ascii=False), flush=True)
    return row


def median(values: list[float]) -> float:
    values = sorted(values)
    mid = len(values) // 2
    return values[mid] if len(values) % 2 else (values[mid - 1] + values[mid]) / 2


def main() -> int:
    global OUT, MTP, DRAFT_VOCAB
    ap = argparse.ArgumentParser()
    ap.add_argument("--windows", default="32k,160k,200k")
    ap.add_argument("--out", default=str(OUT))
    ap.add_argument("--mtp", type=int, default=0)
    ap.add_argument("--draft-vocab", type=int)
    args = ap.parse_args()
    OUT = pathlib.Path(args.out)
    MTP = args.mtp
    DRAFT_VOCAB = args.draft_vocab
    OUT.mkdir(parents=True, exist_ok=True)
    ledger = OUT / "ledger.jsonl"
    rows: list[dict[str, object]] = []
    failed = False
    for window in args.windows.split(","):
        for order in ("AB", "BA"):
            sequence = ("baseline", "candidate") if order == "AB" else ("candidate", "baseline")
            pair = []
            for index, side in enumerate(sequence, 1):
                row = run_point(side, window, order, index)
                rows.append(row)
                pair.append(row)
                with ledger.open("a", encoding="utf-8") as fh:
                    fh.write(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n")
                minimum = 64 if window == "32k" else 128
                if row["rc"] != 0 or row["pp"] is None or row["tg"] is None or (row["completionTokens"] or 0) < minimum:
                    failed = True
                if failed:
                    break
            if failed:
                break
            if pair[0]["contentSha256"] != pair[1]["contentSha256"]:
                failed = True
        if failed:
            break
    summary: dict[str, object] = {"ok": not failed, "windows": args.windows.split(","), "mtp": MTP,
                                 "draftVocab": DRAFT_VOCAB, "rows": rows, "finishedAt": iso()}
    if not failed:
        per_window = {}
        for window in args.windows.split(","):
            base = [r for r in rows if r["window"] == window and r["side"] == "baseline"]
            cand = [r for r in rows if r["window"] == window and r["side"] == "candidate"]
            bp, cp = median([r["pp"] for r in base]), median([r["pp"] for r in cand])
            bt, ct = median([r["tg"] for r in base]), median([r["tg"] for r in cand])
            per_window[window] = {"baselinePp": bp, "candidatePp": cp, "deltaPpPct": (cp / bp - 1) * 100,
                                  "baselineTg": bt, "candidateTg": ct, "deltaTgPct": (ct / bt - 1) * 100,
                                  "answerParity": all(r["contentSha256"] == base[0]["contentSha256"] for r in cand),
                                  "baselineRuns": len(base), "candidateRuns": len(cand)}
        summary["perWindow"] = per_window
    (OUT / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"ok": summary["ok"], "perWindow": summary.get("perWindow")}, ensure_ascii=False), flush=True)
    return 0 if summary["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
