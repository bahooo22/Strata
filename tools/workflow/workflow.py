#!/usr/bin/env python3
from __future__ import annotations

import argparse
import contextlib
import datetime as dt
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any


VERSION = 1
ROLES = ("A", "H", "N")
CRITERIA = tuple(f"C{i}" for i in range(1, 11))
WINDOWS = ("32k", "160k", "200k")
ARTIFACT_AUTHORS = {
    "TASK_IDEA": "A",
    "IMPL_PLAN": "H",
    "PATCH": "H",
    "DOC_IMPL": "H",
    "FAST_RUN_REPORT": "A",
    "FULL_RUN_REPORT": "A",
    "REVIEW_REPORT": "N",
    "INTEGRATION_REPORT": "A",
    "UPSTREAM_PR_CHECK": "A",
    "DECISION_RECORD": "A",
}
TRANSITIONS = {
    "G0": {"G1"},
    "G1": {"G2"},
    "G2": {"G3"},
    "G3": {"G4"},
    "G4": {"G5"},
    "G5": {"UPSTREAM_PR_CHECK", "ARCHIVED"},
    "UPSTREAM_PR_CHECK": {"MERGED"},
    "MERGED": {"CLEANUP"},
    "ARCHIVED": {"CLEANUP"},
    "CLEANUP": set(),
}
TASK_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,80}$")


class WorkflowError(RuntimeError):
    pass


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")


def git(repo: Path, *args: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(repo), *args],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        shell=False,
        check=False,
    )
    if result.returncode != 0:
        raise WorkflowError((result.stderr or result.stdout).strip() or "git command failed")
    return result.stdout.strip()


def repo_root(path: Path) -> Path:
    return Path(git(path, "rev-parse", "--show-toplevel")).resolve()


def read_json(path: Path, default: Any = None) -> Any:
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise WorkflowError(f"не читается {path}: {exc}") from exc


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(tmp, path)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def safe_task_id(value: str) -> str:
    if not TASK_ID.fullmatch(value):
        raise WorkflowError("task-id содержит недопустимые символы")
    return value


def safe_repo_path(repo: Path, value: str) -> Path:
    candidate = Path(value)
    if candidate.is_absolute():
        raise WorkflowError("path должен быть относительным")
    resolved = (repo / candidate).resolve()
    if resolved != repo and repo not in resolved.parents:
        raise WorkflowError("path выходит за пределы репозитория")
    return resolved


def participants(repo: Path) -> dict[str, str]:
    data = read_json(repo / "docs/workflow/participants.json", {})
    if not isinstance(data, dict) or any(role not in data for role in ROLES):
        raise WorkflowError("docs/workflow/participants.json не содержит A/H/N")
    return {role: str(data[role]) for role in ROLES}


def state_path(repo: Path) -> Path:
    return repo / "docs/workflow/state.json"


def events_path(repo: Path) -> Path:
    return repo / "docs/workflow/events.jsonl"


def load_state(repo: Path) -> dict[str, Any]:
    state = read_json(state_path(repo), {"version": VERSION, "tasks": {}})
    if not isinstance(state, dict) or not isinstance(state.get("tasks"), dict):
        raise WorkflowError("некорректный docs/workflow/state.json")
    return state


def get_task(state: dict[str, Any], task_id: str) -> dict[str, Any]:
    task = state["tasks"].get(task_id)
    if not isinstance(task, dict):
        raise WorkflowError(f"задача {task_id} не найдена")
    return task


def append_event(repo: Path, task_id: str, event: str, actor: str, **details: Any) -> None:
    path = events_path(repo)
    path.parent.mkdir(parents=True, exist_ok=True)
    record = {"time": utc_now(), "taskId": task_id, "event": event, "actor": actor, **details}
    with path.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(record, ensure_ascii=False) + "\n")


def write_templates(repo: Path, task_id: str, base: str, branch: str) -> None:
    folder = repo / "docs/workflow/tasks" / task_id
    folder.mkdir(parents=True, exist_ok=True)
    templates = {
        "TASK_IDEA.md": f"# TASK_IDEA {task_id}\n\n- goal:\n- idea_algorithm:\n- constraints:\n- expected_effect:\n- base_sha: `{base}`\n- branch: `{branch}`\n",
        "IMPL_PLAN.md": "# IMPL_PLAN\n\n- implementation_algorithm:\n- code_parts:\n- delegation:\n- risks:\n",
        "DOC_IMPL.md": "# DOC_IMPL\n\n- math:\n- code_map:\n- algorithm_argumentation:\n",
        "FAST_RUN_REPORT.md": "# FAST_RUN_REPORT\n\n- window: 32k\n- runs: >=3\n- hardware:\n- build_flags:\n- median:\n- spread:\n- sanity_threshold:\n- delta_vs_32k_baseline:\n",
        "FULL_RUN_REPORT.md": "# FULL_RUN_REPORT\n\n- 160k: result / baseline / decision\n- 200k: result / baseline / decision\n- comparison_rule: только одноимённые окна и профили\n",
        "REVIEW_REPORT.md": "# REVIEW_REPORT\n\n- C1..C10:\n- rejection_code:\n- verdict:\n",
        "INTEGRATION_REPORT.md": "# INTEGRATION_REPORT\n\n- fast_32k_dynamics:\n- full_160k_dynamics:\n- full_200k_dynamics:\n- verdict: INTEGRATION_APPROVED | ARCHIVED\n",
        "UPSTREAM_PR_CHECK.md": "# UPSTREAM_PR_CHECK\n\n- requirements_checked:\n- result: pass | fail\n",
        "DECISION_RECORD.md": "# DECISION_RECORD\n\n- decision:\n- reason:\n- evidence:\n- feedback:\n",
    }
    for name, text in templates.items():
        (folder / name).write_text(text, encoding="utf-8")
    (folder / "PATCH.diff").write_text("", encoding="utf-8")
    (folder / "metrics.template.json").write_text(json.dumps({
        "taskId": task_id,
        "metrics": {
            "32k": {"profile": "", "baseline": {"window": "32k", "profile": ""}, "runs": [], "decision": "pass"},
            "160k": {"profile": "", "baseline": {"window": "160k", "profile": ""}, "runs": [], "decision": "progress"},
            "200k": {"profile": "", "baseline": {"window": "200k", "profile": ""}, "runs": [], "decision": "progress"},
        },
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


@contextlib.contextmanager
def global_lock(repo: Path):
    lock = repo / "docs/workflow/locks/global.lock"
    lock.parent.mkdir(parents=True, exist_ok=True)
    try:
        fh = lock.open("x", encoding="utf-8")
    except FileExistsError as exc:
        raise WorkflowError("workflow lock занят; одновременная запись запрещена") from exc
    try:
        fh.write(json.dumps({"pid": os.getpid(), "time": utc_now()}) + "\n")
        fh.close()
        yield
    finally:
        with contextlib.suppress(FileNotFoundError):
            lock.unlink()


def artifact(repo: Path, task: dict[str, Any], name: str) -> dict[str, Any]:
    item = task.get("artifacts", {}).get(name)
    if not isinstance(item, dict):
        raise WorkflowError(f"отсутствует artifact {name}")
    path = safe_repo_path(repo, item["path"])
    if not path.is_file():
        raise WorkflowError(f"artifact {name} не найден: {item['path']}")
    if item.get("author") != ARTIFACT_AUTHORS[name]:
        raise WorkflowError(f"неверный author для {name}")
    if sha256(path) != item.get("sha256"):
        raise WorkflowError(f"хеш artifact {name} не совпадает")
    return item


def validate_fast_metrics(task: dict[str, Any]) -> None:
    fast = task.get("metrics", {}).get("32k", {})
    runs = fast.get("runs", [])
    if len(runs) < 3:
        raise WorkflowError("fast 32k требует минимум 3 прогона")
    if any(run.get("window") != "32k" for run in runs):
        raise WorkflowError("fast metrics содержат другое окно")
    if fast.get("decision") not in {"pass", "flag"}:
        raise WorkflowError("fast 32k не имеет решения pass/flag")


def validate_full_metrics(task: dict[str, Any]) -> None:
    for window in ("160k", "200k"):
        full = task.get("metrics", {}).get(window, {})
        full_runs = full.get("runs", [])
        if len(full_runs) != 1 or full_runs[0].get("window") != window:
            raise WorkflowError(f"full {window} требует ровно один прогон своего окна")
        if full.get("decision") not in {"progress", "no_change", "regress", "critical_risk"}:
            raise WorkflowError(f"full {window} не имеет решения")
        baseline = full.get("baseline", {})
        if baseline.get("window") != window or baseline.get("profile") != full.get("profile"):
            raise WorkflowError(f"baseline {window} не совпадает по окну/профилю")


def validate_review(repo: Path, task: dict[str, Any]) -> None:
    review = task.get("review", {})
    if review.get("verdict") != "CODE_APPROVED":
        raise WorkflowError("нет CODE_APPROVED")
    if review.get("reviewer") != participants(repo)["N"] or review.get("reviewer") == task.get("codeAuthor"):
        raise WorkflowError("reviewer не независим")
    if any(review.get("criteria", {}).get(code) is not True for code in CRITERIA):
        raise WorkflowError("не все C1-C10 равны true")
    artifact(repo, task, "REVIEW_REPORT")


def validate_task(repo: Path, task: dict[str, Any]) -> None:
    for name in task.get("artifacts", {}):
        artifact(repo, task, name)
    if task.get("gate") in {"G3", "G4", "G5", "UPSTREAM_PR_CHECK", "MERGED"}:
        branch = git(repo, "rev-parse", "--verify", f"{task['branch']}^{{commit}}")
        if git(repo, "merge-base", "--is-ancestor", task["baseSha"], branch) != "":
            raise WorkflowError("base_sha не является предком branch")
    if task.get("gate") in {"G4", "G5", "UPSTREAM_PR_CHECK", "MERGED"}:
        validate_fast_metrics(task)
    if task.get("gate") in {"G5", "UPSTREAM_PR_CHECK", "MERGED"}:
        validate_review(repo, task)
    if task.get("gate") in {"UPSTREAM_PR_CHECK", "MERGED"}:
        validate_full_metrics(task)
    if task.get("gate") in {"ARCHIVED", "CLEANUP"}:
        report = task.get("artifacts", {}).get("INTEGRATION_REPORT", {})
        if report.get("status") == "ARCHIVED" and task.get("integration", {}).get("verdict") != "ARCHIVED":
            raise WorkflowError("archive gate требует integration verdict ARCHIVED")


def cmd_init(args: argparse.Namespace) -> dict[str, Any]:
    repo = repo_root(Path(args.repo))
    task_id = safe_task_id(args.task_id)
    base = git(repo, "rev-parse", "--verify", f"{args.base_sha}^{{commit}}")
    with global_lock(repo):
        state = load_state(repo)
        if task_id in state["tasks"]:
            raise WorkflowError(f"задача {task_id} уже существует")
        task = {
            "taskId": task_id,
            "gate": "G0",
            "baseSha": base,
            "branch": args.branch,
            "codeAuthor": participants(repo)["H"],
            "artifacts": {},
            "metrics": {},
            "review": {"verdict": "pending", "criteria": {}},
            "integration": {"verdict": "pending"},
            "upstreamPr": {"status": "not-run"},
            "createdAt": utc_now(),
            "updatedAt": utc_now(),
        }
        state["tasks"][task_id] = task
        write_templates(repo, task_id, base, args.branch)
        write_json(state_path(repo), state)
        append_event(repo, task_id, "init", participants(repo)["A"], baseSha=base, branch=args.branch)
    return {"result": "ok", "taskId": task_id, "gate": "G0"}


def cmd_status(args: argparse.Namespace) -> dict[str, Any]:
    repo = repo_root(Path(args.repo))
    task = get_task(load_state(repo), safe_task_id(args.task_id))
    return {"result": "ok", "task": task}


def cmd_record(args: argparse.Namespace) -> dict[str, Any]:
    repo = repo_root(Path(args.repo))
    task_id = safe_task_id(args.task_id)
    if args.name not in ARTIFACT_AUTHORS:
        raise WorkflowError("неизвестный artifact")
    if args.author != ARTIFACT_AUTHORS[args.name]:
        raise WorkflowError(f"{args.name} должен создать {ARTIFACT_AUTHORS[args.name]}")
    path = safe_repo_path(repo, args.path)
    if not path.is_file():
        raise WorkflowError(f"artifact не найден: {args.path}")
    with global_lock(repo):
        state = load_state(repo)
        task = get_task(state, task_id)
        task["artifacts"][args.name] = {
            "path": args.path,
            "author": args.author,
            "sha256": sha256(path),
            "status": args.status,
            "recordedAt": utc_now(),
        }
        task["updatedAt"] = utc_now()
        write_json(state_path(repo), state)
        append_event(repo, task_id, "artifact", args.author, name=args.name, path=args.path, status=args.status)
    return {"result": "ok", "artifact": args.name, "sha256": task["artifacts"][args.name]["sha256"]}


def cmd_metrics(args: argparse.Namespace) -> dict[str, Any]:
    repo = repo_root(Path(args.repo))
    task_id = safe_task_id(args.task_id)
    data = read_json(Path(args.file))
    if not isinstance(data, dict) or data.get("taskId") != task_id:
        raise WorkflowError("metrics file не соответствует task-id")
    candidate = get_task(load_state(repo), task_id)
    candidate["metrics"] = data["metrics"]
    if "32k" in candidate["metrics"]:
        validate_fast_metrics(candidate)
    if any(window in candidate["metrics"] for window in ("160k", "200k")):
        validate_full_metrics(candidate)
    with global_lock(repo):
        state = load_state(repo)
        task = get_task(state, task_id)
        task["metrics"] = candidate["metrics"]
        task["updatedAt"] = utc_now()
        write_json(state_path(repo), state)
        append_event(repo, task_id, "metrics", participants(repo)["A"], file=str(args.file))
    return {"result": "ok", "metrics": task["metrics"]}


def cmd_review(args: argparse.Namespace) -> dict[str, Any]:
    repo = repo_root(Path(args.repo))
    task_id = safe_task_id(args.task_id)
    reviewer = participants(repo)["N"]
    if args.verdict == "CODE_APPROVED":
        criteria = {code: True for code in CRITERIA}
    else:
        criteria = {code: code != args.failed_criterion for code in CRITERIA}
        if not args.failed_criterion:
            raise WorkflowError("для rejection нужен --failed-criterion")
    report = safe_repo_path(repo, args.report)
    if not report.is_file():
        raise WorkflowError("review report не найден")
    with global_lock(repo):
        state = load_state(repo)
        task = get_task(state, task_id)
        if reviewer == task.get("codeAuthor"):
            raise WorkflowError("self-approval запрещён")
        task["review"] = {"verdict": args.verdict, "reviewer": reviewer, "criteria": criteria, "report": args.report}
        task["artifacts"]["REVIEW_REPORT"] = {
            "path": args.report,
            "author": "N",
            "sha256": sha256(report),
            "status": args.verdict,
            "recordedAt": utc_now(),
        }
        task["updatedAt"] = utc_now()
        write_json(state_path(repo), state)
        append_event(repo, task_id, "review", reviewer, verdict=args.verdict, failedCriterion=args.failed_criterion)
    return {"result": "ok", "review": task["review"]}


def cmd_transition(args: argparse.Namespace) -> dict[str, Any]:
    repo = repo_root(Path(args.repo))
    task_id = safe_task_id(args.task_id)
    with global_lock(repo):
        state = load_state(repo)
        task = get_task(state, task_id)
        current = task["gate"]
        target = args.to
        if target not in TRANSITIONS.get(current, set()):
            raise WorkflowError(f"переход {current} -> {target} запрещён")
        required = {
            "G1": ("TASK_IDEA",),
            "G2": ("IMPL_PLAN",),
            "G3": ("PATCH", "DOC_IMPL"),
            "G4": ("FAST_RUN_REPORT",),
            "G5": ("REVIEW_REPORT",),
            "UPSTREAM_PR_CHECK": ("FULL_RUN_REPORT", "INTEGRATION_REPORT"),
            "MERGED": ("UPSTREAM_PR_CHECK",),
            "ARCHIVED": ("DECISION_RECORD",),
            "CLEANUP": (),
        }[target]
        for name in required:
            artifact(repo, task, name)
        if target == "G4":
            validate_fast_metrics(task)
        if target == "G5":
            validate_task(repo, task)
            validate_review(repo, task)
        if target == "UPSTREAM_PR_CHECK":
            validate_task(repo, task)
            validate_full_metrics(task)
            if any(task["metrics"][window]["decision"] != "progress" for window in ("160k", "200k")):
                raise WorkflowError("merge требует progress на 160k и 200k")
            if task["artifacts"]["INTEGRATION_REPORT"].get("status") != "INTEGRATION_APPROVED":
                raise WorkflowError("INTEGRATION_REPORT не approved")
            task["integration"] = {"verdict": "INTEGRATION_APPROVED", "at": utc_now()}
        if target == "ARCHIVED":
            if not any(task.get("metrics", {}).get(window, {}).get("decision") in {"no_change", "regress", "critical_risk"} for window in ("160k", "200k")):
                raise WorkflowError("archive требует no_change/regress/critical_risk")
            task["integration"] = {"verdict": "ARCHIVED", "at": utc_now()}
        if target == "MERGED":
            if task["artifacts"]["UPSTREAM_PR_CHECK"].get("status") != "pass":
                raise WorkflowError("upstream PR check не pass")
        task["gate"] = target
        task["updatedAt"] = utc_now()
        write_json(state_path(repo), state)
        append_event(repo, task_id, "transition", participants(repo)["A"], **{"from": current, "to": target})
    return {"result": "ok", "taskId": task_id, "gate": target}


def cmd_validate(args: argparse.Namespace) -> dict[str, Any]:
    repo = repo_root(Path(args.repo))
    task = get_task(load_state(repo), safe_task_id(args.task_id))
    validate_task(repo, task)
    return {"result": "ok", "taskId": task["taskId"], "gate": task["gate"]}


def cmd_event(args: argparse.Namespace) -> dict[str, Any]:
    repo = repo_root(Path(args.repo))
    task_id = safe_task_id(args.task_id)
    get_task(load_state(repo), task_id)
    with global_lock(repo):
        append_event(repo, task_id, args.type, args.actor, note=args.note)
    return {"result": "ok"}


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Workflow G0-G5 для A/H/N")
    sub = parser.add_subparsers(dest="command", required=True)
    init = sub.add_parser("init")
    init.add_argument("--repo", type=Path, default=Path("."))
    init.add_argument("--task-id", required=True)
    init.add_argument("--base-sha", required=True)
    init.add_argument("--branch", required=True)
    init.set_defaults(func=cmd_init)
    status = sub.add_parser("status")
    status.add_argument("--repo", type=Path, default=Path("."))
    status.add_argument("--task-id", required=True)
    status.set_defaults(func=cmd_status)
    record = sub.add_parser("record")
    record.add_argument("--repo", type=Path, default=Path("."))
    record.add_argument("--task-id", required=True)
    record.add_argument("--name", required=True, choices=sorted(ARTIFACT_AUTHORS))
    record.add_argument("--path", required=True)
    record.add_argument("--author", required=True, choices=ROLES)
    record.add_argument("--status")
    record.set_defaults(func=cmd_record)
    metrics = sub.add_parser("metrics")
    metrics.add_argument("--repo", type=Path, default=Path("."))
    metrics.add_argument("--task-id", required=True)
    metrics.add_argument("--file", type=Path, required=True)
    metrics.set_defaults(func=cmd_metrics)
    review = sub.add_parser("review")
    review.add_argument("--repo", type=Path, default=Path("."))
    review.add_argument("--task-id", required=True)
    review.add_argument("--verdict", required=True)
    review.add_argument("--report", required=True)
    review.add_argument("--failed-criterion", choices=CRITERIA)
    review.set_defaults(func=cmd_review)
    transition = sub.add_parser("transition")
    transition.add_argument("--repo", type=Path, default=Path("."))
    transition.add_argument("--task-id", required=True)
    transition.add_argument("--to", required=True, choices=sorted({gate for gates in TRANSITIONS.values() for gate in gates}))
    transition.set_defaults(func=cmd_transition)
    validate = sub.add_parser("validate")
    validate.add_argument("--repo", type=Path, default=Path("."))
    validate.add_argument("--task-id", required=True)
    validate.set_defaults(func=cmd_validate)
    event = sub.add_parser("event")
    event.add_argument("--repo", type=Path, default=Path("."))
    event.add_argument("--task-id", required=True)
    event.add_argument("--type", required=True)
    event.add_argument("--actor", required=True, choices=ROLES)
    event.add_argument("--note", default="")
    event.set_defaults(func=cmd_event)
    return parser


def main(argv: list[str] | None = None) -> int:
    try:
        args = build_parser().parse_args(argv)
        print(json.dumps(args.func(args), ensure_ascii=False, indent=2))
        return 0
    except (WorkflowError, OSError, UnicodeError, json.JSONDecodeError, TypeError, KeyError) as exc:
        print(json.dumps({"result": "blocked", "error": str(exc)}, ensure_ascii=False))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
