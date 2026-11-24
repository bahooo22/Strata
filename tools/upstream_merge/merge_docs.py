from __future__ import annotations

import datetime as dt
import json
from pathlib import Path
from typing import Any

from merge_gate import GateError
from merge_gate.gitops import git_stdout, git_text, repo_root, resolve_ref


DECISION_EN = {
    "ours": "Keep the fork implementation",
    "upstream": "Use the upstream implementation",
    "delta": "Apply the fork delta on upstream",
    "hybrid": "Combine both through the recorded contract",
    "drop": "Remove the fork implementation after full replacement",
    "defer": "Defer; not merge-ready",
}

LABELS = {
    "ru": {
        "title": "Upstream merge {upstream} → {candidate}",
        "date": "Дата",
        "refs": "Refs",
        "summary": "Сводка",
        "commits": "Upstream commits",
        "changedFiles": "Changed files",
        "decisions": "Решения",
        "conflicts": "Конфликты",
        "adaptations": "Дополнительные адаптации",
        "upstreamChanges": "Изменения upstream по commits",
        "evidence": "Evidence",
        "review": "Review и waivers",
        "notRun": "Not run",
        "id": "ID",
        "decision": "Решение",
        "status": "Статус",
        "reason": "Основание",
        "oursAlgorithm": "Алгоритм ours",
        "upstreamAlgorithm": "Алгоритм upstream",
        "files": "Файлы",
        "related": "Связанные решения",
        "body": "Исходное сообщение commit",
        "author": "Автор",
        "category": "Категория",
        "details": "Подробности",
        "path": "Путь",
        "resolution": "Разрешение",
        "method": "Метод",
        "change": "Изменение",
        "reviewer": "Reviewer",
        "verdict": "Verdict",
        "noRelated": "Прямого решения в matrix нет; изменение принято как upstream-база.",
        "none": "—",
    },
    "en": {
        "title": "Upstream merge {upstream} → {candidate}",
        "date": "Date",
        "refs": "Refs",
        "summary": "Summary",
        "commits": "Upstream commits",
        "changedFiles": "Changed files",
        "decisions": "Decisions",
        "conflicts": "Conflicts",
        "adaptations": "Additional adaptations",
        "upstreamChanges": "Upstream changes by commit",
        "evidence": "Evidence",
        "review": "Review and waivers",
        "notRun": "Not run",
        "id": "ID",
        "decision": "Decision",
        "status": "Status",
        "reason": "Rationale",
        "oursAlgorithm": "Fork algorithm (source text)",
        "upstreamAlgorithm": "Upstream algorithm (source text)",
        "files": "Files",
        "related": "Related decisions",
        "body": "Original commit message",
        "author": "Author",
        "category": "Category",
        "details": "Details",
        "path": "Path",
        "resolution": "Resolution",
        "method": "Method",
        "change": "Change",
        "reviewer": "Reviewer",
        "verdict": "Verdict",
        "noRelated": "No direct matrix decision; accepted as upstream baseline.",
        "none": "—",
    },
}


def _cell(value: Any) -> str:
    if value is None or value == "":
        return "—"
    return str(value).replace("|", "\\|").replace("\n", "<br>")


def _fenced(value: str) -> str:
    fence = "```"
    while fence in value:
        fence += "`"
    return f"{fence}\n{value.rstrip()}\n{fence}"


def _commit_records(repo: Path, base: str, upstream: str) -> list[dict[str, Any]]:
    raw = git_stdout(
        repo,
        ["log", "--reverse", "--format=%H%x00%cs%x00%an%x00%s%x00%b%x00%x1e", f"{base}..{upstream}"],
        timeout=120,
    )
    records: list[dict[str, Any]] = []
    for chunk in raw.split("\x1e"):
        chunk = chunk.lstrip("\n")
        if not chunk:
            continue
        fields = chunk.split("\0", 4)
        if len(fields) != 5:
            raise GateError("не удалось разобрать git log для документа")
        sha, date, author, subject, body = fields
        body = body.removesuffix("\0")
        numstat = git_stdout(repo, ["diff-tree", "-m", "--no-commit-id", "--numstat", "-r", sha], timeout=60)
        files: list[dict[str, Any]] = []
        for line in numstat.splitlines():
            parts = line.split("\t", 2)
            if len(parts) != 3:
                continue
            added, deleted, path = parts
            files.append({
                "path": path,
                "added": int(added) if added.isdigit() else None,
                "deleted": int(deleted) if deleted.isdigit() else None,
            })
        records.append({"sha": sha, "date": date, "author": author, "subject": subject, "body": body, "files": files})
    return records


def _decision_paths(item: dict[str, Any]) -> set[str]:
    paths: set[str] = set()
    for location in item.get("anchorLocations", {}).values():
        if isinstance(location, dict) and isinstance(location.get("path"), str):
            paths.add(location["path"])
    for ref in item.get("evidence", []):
        if isinstance(ref, str) and "/" in ref and not ref.startswith(("http:", "https:")):
            paths.add(ref)
        elif isinstance(ref, dict) and isinstance(ref.get("artifact"), str):
            paths.add(ref["artifact"])
    for ref in item.get("anchorEvidence", []):
        if isinstance(ref, str) and "/" in ref:
            paths.add(ref)
        elif isinstance(ref, dict) and isinstance(ref.get("artifact"), str):
            paths.add(ref["artifact"])
    return paths


def _load_conflicts(path: Path | None) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    if path is None:
        return [], []
    data = json.loads(path.read_text(encoding="utf-8"))
    if isinstance(data, list):
        return data, []
    if not isinstance(data, dict):
        raise GateError("conflict decisions должны быть списком или объектом")
    conflicts = data.get("conflicts", [])
    adaptations = data.get("additionalAdaptations", [])
    if not isinstance(conflicts, list) or not isinstance(adaptations, list):
        raise GateError("conflicts и additionalAdaptations должны быть списками")
    return conflicts, adaptations


def _render(lang: str, plan: dict[str, Any], commits: list[dict[str, Any]], conflicts: list[dict[str, Any]],
            adaptations: list[dict[str, Any]], changed_files: list[str], review: dict[str, Any]) -> str:
    labels = LABELS[lang]
    ours = plan["oursRef"]
    upstream = plan["upstreamRef"]
    candidate = plan["candidateRef"]
    lines = [
        f"# {labels['title'].format(upstream=upstream, candidate=candidate)}",
        "",
        f"- {labels['date']}: {dt.date.today().isoformat()}",
        f"- ours: `{ours}`",
        f"- upstream: `{upstream}`",
        f"- candidate: `{candidate}`",
        "",
        f"## {labels['summary']}",
        "",
        f"- {labels['commits']}: {len(commits)}",
        f"- {labels['changedFiles']}: {len(changed_files)}",
        f"- {labels['decisions']}: {len(plan['matrix'])}",
        "",
        f"## {labels['decisions']}",
        "",
        f"| {labels['id']} | {labels['decision']} | {labels['status']} | {labels['reason']} | {labels['oursAlgorithm']} | {labels['upstreamAlgorithm']} |",
        "|---|---|---|---|---|---|",
    ]
    for item in plan["matrix"]:
        decision = item["decision"]
        decision_text = DECISION_EN.get(decision, decision) if lang == "en" else decision
        lines.append(
            f"| {_cell(item['id'])} | {_cell(decision_text)} | {_cell(item.get('upstreamStatus'))} | "
            f"{_cell(item.get('reason'))} | {_cell(item.get('oursAlgorithm'))} | {_cell(item.get('upstreamAlgorithm'))} |"
        )
    lines.extend(["", f"## {labels['conflicts']}", ""])
    if conflicts:
        lines.extend([
            f"| {labels['path']} | {labels['resolution']} | {labels['method']} | {labels['reason']} |",
            "|---|---|---|---|",
        ])
        for item in conflicts:
            lines.append(
                f"| {_cell(item.get('path'))} | {_cell(item.get('resolution'))} | {_cell(item.get('method'))} | {_cell(item.get('reason'))} |"
            )
    else:
        lines.append(labels["none"])
    lines.extend(["", f"## {labels['adaptations']}", ""])
    if adaptations:
        lines.extend([f"| {labels['path']} | {labels['change']} | {labels['details']} |", "|---|---|---|"])
        for item in adaptations:
            lines.append(
                f"| {_cell(item.get('path'))} | {_cell(item.get('change'))} | {_cell(item.get('evidence') or item.get('revision'))} |"
            )
    else:
        lines.append(labels["none"])
    lines.extend(["", f"## {labels['upstreamChanges']}", ""])
    decision_paths = {item["id"]: _decision_paths(item) for item in plan["matrix"]}
    for commit in commits:
        lines.extend([
            f"### `{commit['sha'][:12]}` — {commit['subject']}",
            "",
            f"- {labels['date']}: {commit['date']}",
            f"- {labels['author']}: {commit['author']}",
            f"- {labels['files']}:",
        ])
        for file in commit["files"]:
            suffix = ""
            if file["added"] is not None and file["deleted"] is not None:
                suffix = f" (+{file['added']}/-{file['deleted']})"
            lines.append(f"  - `{file['path']}`{suffix}")
        related = [item for item in plan["matrix"] if decision_paths[item["id"]] & {f["path"] for f in commit["files"]}]
        lines.extend(["", f"- {labels['related']}:"])
        if related:
            for item in related:
                lines.append(f"  - `{item['id']}`: {item['decision']} — {item.get('reason', '')}")
        else:
            lines.append(f"  - {labels['noRelated']}")
        if commit["body"].strip():
            lines.extend(["", f"**{labels['body']}**", "", _fenced(commit["body"])])
        lines.append("")
    lines.extend([f"## {labels['evidence']}", "", f"| {labels['category']} | {labels['status']} | {labels['details']} |", "|---|---|---|"])
    for key, item in plan["evidence"].items():
        lines.append(f"| {_cell(key)} | {_cell(item.get('status'))} | {_cell(item.get('details') or item.get('reason'))} |")
    lines.extend(["", f"## {labels['review']}", ""])
    lines.append(f"- {labels['reviewer']}: {review.get('reviewer', labels['none'])}")
    lines.append(f"- {labels['verdict']}: {review.get('verdict', labels['none'])}")
    for item in plan.get("warningAcknowledgments", []):
        lines.append(f"- `{item['code']}`: {item.get('outcome')} — {item.get('reason', '')}")
    not_run = [key for key, item in plan["evidence"].items() if item.get("status") == "not-run"]
    lines.extend(["", f"## {labels['notRun']}", ""])
    lines.extend(f"- `{key}`: {plan['evidence'][key].get('reason', labels['none'])}" for key in not_run)
    if not not_run:
        lines.append(labels["none"])
    return "\n".join(lines) + "\n"


def generate(repo: Path, plan: dict[str, Any], out_dir: Path, conflict_decisions: Path | None = None) -> dict[str, Any]:
    root = repo_root(repo)
    ours = resolve_ref(root, plan["oursRef"])
    upstream = resolve_ref(root, plan["upstreamRef"])
    candidate = resolve_ref(root, plan["candidateRef"])
    base = git_text(root, ["merge-base", ours, upstream])
    commits = _commit_records(root, base, upstream)
    changed_files = git_stdout(root, ["diff", "--name-only", base, candidate, "--"]).splitlines()
    conflicts, adaptations = _load_conflicts(conflict_decisions)
    if out_dir.is_absolute():
        raise GateError("out-dir должен быть относительным путём внутри репозитория")
    output = (root / out_dir).resolve()
    if output == root or root not in output.parents:
        raise GateError("out-dir выходит за пределы репозитория")
    output.mkdir(parents=True, exist_ok=True)
    stamp = f"{upstream[:12]}-{candidate[:12]}-{dt.date.today().isoformat()}"
    files = []
    for lang, suffix in (("ru", "ru"), ("en", "en")):
        path = output / f"{stamp}.{suffix}.md"
        path.write_text(_render(lang, plan, commits, conflicts, adaptations, changed_files, plan.get("architectureReview", {})), encoding="utf-8")
        files.append(str(path.relative_to(root)))
    return {
        "result": "written",
        "files": files,
        "upstreamCommits": len(commits),
        "changedFiles": len(changed_files),
        "decisions": len(plan["matrix"]),
        "conflicts": len(conflicts),
        "adaptations": len(adaptations),
    }
