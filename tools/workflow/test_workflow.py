#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

CLI = Path(__file__).with_name("workflow.py")


def git(repo: Path, *args: str) -> str:
    result = subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True, encoding="utf-8", errors="replace")
    if result.returncode != 0:
        raise RuntimeError((result.stderr or result.stdout).strip())
    return result.stdout.strip()


def run(repo: Path, *args: str) -> tuple[int, dict]:
    env = {**os.environ, "PYTHONIOENCODING": "utf-8", "PYTHONUTF8": "1"}
    result = subprocess.run([sys.executable, str(CLI), *args, "--repo", str(repo)], capture_output=True, text=True, encoding="utf-8", errors="replace", env=env)
    if not result.stdout.strip():
        return result.returncode, {"stderr": result.stderr}
    return result.returncode, json.loads(result.stdout)


class WorkflowTests(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path(tempfile.mkdtemp(prefix="workflow-test-"))
        self.repo = self.root / "repo"
        self.repo.mkdir()
        git(self.repo, "init", "-q", "-b", "main")
        git(self.repo, "config", "user.name", "Workflow Test")
        git(self.repo, "config", "user.email", "workflow@example.invalid")
        (self.repo / "base.txt").write_text("base\n", encoding="utf-8")
        git(self.repo, "add", "base.txt")
        git(self.repo, "commit", "-q", "-m", "base")
        git(self.repo, "branch", "task/T1")
        docs = self.repo / "docs/workflow"
        (docs / "locks").mkdir(parents=True)
        (docs / "tasks/T1").mkdir(parents=True)
        (docs / "participants.json").write_text(json.dumps({
            "A": "A-session", "H": "H-session", "N": "N-session",
        }), encoding="utf-8")
        (docs / "state.json").write_text(json.dumps({"version": 1, "tasks": {}}), encoding="utf-8")
        (docs / "events.jsonl").write_text("", encoding="utf-8")
        self.base = git(self.repo, "rev-parse", "HEAD")

    def tearDown(self) -> None:
        shutil.rmtree(self.root, ignore_errors=True)

    def artifact(self, name: str, author: str, status: str | None = None) -> str:
        path = self.repo / f"docs/workflow/tasks/T1/{name}.md"
        path.write_text(f"# {name}\n", encoding="utf-8")
        args = ["record", "--task-id", "T1", "--name", name, "--path", str(path.relative_to(self.repo)), "--author", author]
        if status:
            args += ["--status", status]
        code, data = run(self.repo, *args)
        self.assertEqual(code, 0, data)
        return str(path.relative_to(self.repo))

    def metrics(self, decision: str = "progress") -> None:
        path = self.repo / "docs/workflow/tasks/T1/metrics.json"
        path.write_text(json.dumps({
            "taskId": "T1",
            "metrics": {
                "32k": {"profile": "p", "baseline": {"window": "32k", "profile": "p"}, "runs": [{"window": "32k", "value": 1} for _ in range(3)], "decision": "pass"},
                "160k": {"profile": "p", "baseline": {"window": "160k", "profile": "p"}, "runs": [{"window": "160k", "value": 2}], "decision": decision},
                "200k": {"profile": "p", "baseline": {"window": "200k", "profile": "p"}, "runs": [{"window": "200k", "value": 2}], "decision": decision},
            },
        }), encoding="utf-8")
        code, data = run(self.repo, "metrics", "--task-id", "T1", "--file", str(path))
        self.assertEqual(code, 0, data)

    def prepare(self, decision: str = "progress", review: bool = True) -> None:
        code, data = run(self.repo, "init", "--task-id", "T1", "--base-sha", self.base, "--branch", "task/T1")
        self.assertEqual(code, 0, data)
        self.artifact("TASK_IDEA", "A")
        code, data = run(self.repo, "transition", "--task-id", "T1", "--to", "G1")
        self.assertEqual(code, 0, data)
        self.artifact("IMPL_PLAN", "H")
        code, data = run(self.repo, "transition", "--task-id", "T1", "--to", "G2")
        self.assertEqual(code, 0, data)
        self.artifact("PATCH", "H")
        self.artifact("DOC_IMPL", "H")
        code, data = run(self.repo, "transition", "--task-id", "T1", "--to", "G3")
        self.assertEqual(code, 0, data)
        self.metrics(decision)
        self.artifact("FAST_RUN_REPORT", "A")
        code, data = run(self.repo, "transition", "--task-id", "T1", "--to", "G4")
        self.assertEqual(code, 0, data)
        if not review:
            return
        report = self.repo / "docs/workflow/tasks/T1/REVIEW_REPORT.md"
        report.write_text("# review\n", encoding="utf-8")
        code, data = run(self.repo, "review", "--task-id", "T1", "--verdict", "CODE_APPROVED", "--report", str(report.relative_to(self.repo)))
        self.assertEqual(code, 0, data)
        code, data = run(self.repo, "transition", "--task-id", "T1", "--to", "G5")
        self.assertEqual(code, 0, data)

    def test_happy_path_to_merged(self) -> None:
        self.prepare()
        self.artifact("FULL_RUN_REPORT", "A")
        self.artifact("INTEGRATION_REPORT", "A", "INTEGRATION_APPROVED")
        code, data = run(self.repo, "transition", "--task-id", "T1", "--to", "UPSTREAM_PR_CHECK")
        self.assertEqual(code, 0, data)
        self.artifact("UPSTREAM_PR_CHECK", "A", "pass")
        code, data = run(self.repo, "transition", "--task-id", "T1", "--to", "MERGED")
        self.assertEqual(code, 0, data)
        code, data = run(self.repo, "validate", "--task-id", "T1")
        self.assertEqual(code, 0, data)

    def test_no_change_archives(self) -> None:
        self.prepare("no_change")
        self.artifact("DECISION_RECORD", "A")
        code, data = run(self.repo, "transition", "--task-id", "T1", "--to", "ARCHIVED")
        self.assertEqual(code, 0, data)
        code, data = run(self.repo, "transition", "--task-id", "T1", "--to", "UPSTREAM_PR_CHECK")
        self.assertEqual(code, 1, data)

    def test_skip_gate_blocked(self) -> None:
        code, data = run(self.repo, "init", "--task-id", "T1", "--base-sha", self.base, "--branch", "task/T1")
        self.assertEqual(code, 0, data)
        code, data = run(self.repo, "transition", "--task-id", "T1", "--to", "G2")
        self.assertEqual(code, 1, data)

    def test_self_approval_blocked(self) -> None:
        participants = self.repo / "docs/workflow/participants.json"
        participants.write_text(json.dumps({"A": "A", "H": "same", "N": "same"}), encoding="utf-8")
        self.prepare(review=False)
        report = self.repo / "docs/workflow/tasks/T1/REVIEW_REPORT.md"
        report.write_text("# review\n", encoding="utf-8")
        code, data = run(self.repo, "review", "--task-id", "T1", "--verdict", "CODE_APPROVED", "--report", str(report.relative_to(self.repo)))
        self.assertEqual(code, 1, data)
        self.assertIn("self-approval", data["error"])

    def test_cross_context_metrics_blocked(self) -> None:
        code, data = run(self.repo, "init", "--task-id", "T1", "--base-sha", self.base, "--branch", "task/T1")
        self.assertEqual(code, 0, data)
        path = self.repo / "docs/workflow/tasks/T1/bad-metrics.json"
        path.write_text(json.dumps({
            "taskId": "T1",
            "metrics": {"160k": {"profile": "p", "baseline": {"window": "200k", "profile": "p"}, "runs": [{"window": "160k"}], "decision": "progress"}},
        }), encoding="utf-8")
        code, data = run(self.repo, "metrics", "--task-id", "T1", "--file", str(path))
        self.assertEqual(code, 1, data)
        self.assertIn("baseline", data["error"])

    def test_lock_and_tamper_blocked(self) -> None:
        lock = self.repo / "docs/workflow/locks/global.lock"
        lock.write_text("busy\n", encoding="utf-8")
        code, data = run(self.repo, "init", "--task-id", "T1", "--base-sha", self.base, "--branch", "task/T1")
        self.assertEqual(code, 1, data)
        self.assertIn("lock", data["error"])
        lock.unlink()
        self.prepare()
        path = self.repo / "docs/workflow/tasks/T1/TASK_IDEA.md"
        path.write_text("tampered\n", encoding="utf-8")
        code, data = run(self.repo, "validate", "--task-id", "T1")
        self.assertEqual(code, 1, data)
        self.assertIn("artifact TASK_IDEA", data["error"])


if __name__ == "__main__":
    unittest.main()
