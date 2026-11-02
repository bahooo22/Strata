"""serve/test_start_failure_hint.py - the start failure hints (no GPU).

    python -m unittest serve.test_start_failure_hint -v
"""
from __future__ import annotations

import pathlib
import tempfile
import unittest

from serve.server import DRAFT_HEAD_FAIL, start_failure_hint


class StartFailureHintTest(unittest.TestCase):
    def hint(self, text: str) -> str:
        with tempfile.TemporaryDirectory() as d:
            p = pathlib.Path(d) / "engine.log"
            p.write_text(text, encoding="utf-8")
            return start_failure_hint(str(p), 0)

    def test_quiet_log_has_no_hint(self):
        self.assertEqual(self.hint("engine started\nserving\n"), "")

    def test_oom(self):
        got = self.hint("strata-q36: cudaMalloc(&E.ecpu, T * Kp * N * 4) failed: out of memory\n")
        self.assertIn("VRAM:", got)
        self.assertIn("--max-context", got)

    def test_cuda_visibility(self):
        got = self.hint("ggml_cuda_init: failed to initialize CUDA: no CUDA-capable device is detected\n")
        self.assertIn("CUDA:", got)

    def test_cuda_busy(self):
        got = self.hint("cudaMalloc failed: CUDA-capable device(s) is/are busy or unavailable\n")
        self.assertIn("CUDA:", got)

    def test_layout(self):
        got = self.hint("token_embd.weight is [248320, 256], the layout wants [256, 248320]\n")
        self.assertIn("Model:", got)

    def test_ignored_budget_flag(self):
        got = self.hint("ignoring --vram-reserve-mib 700\n")
        self.assertIn("Flags:", got)

    def test_native_crash(self):
        got = self.hint("the engine process ended: exit code 0xC0000409: stack buffer overrun / fast-fail\n")
        self.assertIn("Crash:", got)

    def test_mtp_keeps_its_advice(self):
        got = self.hint(DRAFT_HEAD_FAIL + "\nstrata mtp: hint: use a smaller draft head\n")
        self.assertIn("mtp:", got)


if __name__ == "__main__":
    unittest.main()
