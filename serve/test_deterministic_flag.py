"""serve/test_deterministic_flag.py - #4604: `strata_deterministic` adds `deterministic=1` to the
request line (StrataEngine.sampling_keys; no process, no GPU).

    python -m unittest serve.test_deterministic_flag -v

The engine half restores the expert placement taken at load when it sees the key. The server half
is only this string, so what is easy to get wrong and is pinned down here: a real JSON true turns
it on; absent, false and the non-bool lookalikes (1, 1.0, "true") leave the line exactly as it
was; and the key rides along without disturbing the other sampling keys of the same request.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from serve.server import StrataEngine  # noqa: E402


class DeterministicFlag(unittest.TestCase):
    def test_true_adds_the_key(self):
        keys = StrataEngine.sampling_keys({"strata_deterministic": True})
        self.assertIn(" deterministic=1", keys)

    def test_absent_and_false_emit_nothing(self):
        for sampling in ({}, {"strata_deterministic": False}):
            self.assertNotIn("deterministic", StrataEngine.sampling_keys(sampling))

    def test_only_a_real_bool_turns_it_on(self):
        # the check is `is True`, matching how `strata_checkpoint` reads `is False`: a client that
        # sends 1 instead of true is not restored. Widen it here if the API ever accepts 0/1.
        for value in (1, 1.0, "true", [True]):
            self.assertNotIn("deterministic", StrataEngine.sampling_keys({"strata_deterministic": value}))

    def test_the_other_keys_survive(self):
        keys = StrataEngine.sampling_keys({
            "strata_deterministic": True, "temperature": 0.7, "top_p": 0.9, "seed": 42,
        })
        self.assertIn(" temperature=0.7", keys)
        self.assertIn(" top_p=0.9", keys)
        self.assertIn(" seed=42", keys)
        self.assertIn(" deterministic=1", keys)

    def test_greedy_probe_line_is_the_flag_alone(self):
        # what probe_temp0.py --deterministic actually sends: temperature 0 adds nothing, so the
        # whole line is the flag - the engine sees one knob changed and nothing else
        self.assertEqual(
            StrataEngine.sampling_keys({"temperature": 0, "max_tokens": 64, "strata_deterministic": True}),
            " deterministic=1",
        )

    def test_penalties_and_budget_still_carry_their_window(self):
        keys = StrataEngine.sampling_keys({
            "strata_deterministic": True, "repetition_penalty": 1.1, "top_k": 40,
        })
        self.assertIn(" penalty_repeat=1.1", keys)
        self.assertIn(" penalty_last_n=64", keys)
        self.assertIn(" top_k=40", keys)
        self.assertIn(" deterministic=1", keys)


if __name__ == "__main__":
    unittest.main(verbosity=2)
