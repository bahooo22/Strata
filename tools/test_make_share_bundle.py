"""The share-bundle wrapper refuses what the engine's own rules refuse, and its dry run shows both calls.

    python -m unittest tools.test_make_share_bundle

No compiler, no GPU, no network: the build folder holds a stub `strata.exe` and every case stops before
the packagers are called (dry run) or is refused earlier still.
"""
import contextlib
import io
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "packaging"))
import make_share_bundle as msb  # noqa: E402


class ShareBundle(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.build = self.root / "build"
        self.build.mkdir()
        (self.build / "strata.exe").write_bytes(b"MZ")          # a stub: nothing runs it
        self.out = self.root / "FEED"
        self.cmd = ["--build", str(self.build), "--version", "0.1.45", "--out", str(self.out),
                    "--keys", str(self.root / "keys")]

    def run_main(self, argv):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            rc = msb.main(list(argv))
        return rc, out.getvalue(), err.getvalue()

    def test_dry_run_prints_both_calls_and_writes_nothing(self):
        rc, out, _ = self.run_main(self.cmd + ["--archs", "120", "--cuda", "13", "--dry-run"])
        self.assertEqual(rc, 0)
        self.assertIn("package_engine.py", out)
        self.assertIn("--arch sm_120", out)
        self.assertIn("--variant cuda13", out)
        self.assertIn("make_local_feed.py", out)
        self.assertIn("--engine", out)
        self.assertFalse(self.out.exists(), "a dry run must not create the feed folder")

    def test_cuda12_with_sm120_is_refused(self):
        rc, _, err = self.run_main(self.cmd + ["--archs", "120", "--cuda", "12", "--dry-run"])
        self.assertEqual(rc, 2)
        self.assertIn("#220", err)
        self.assertIn("setup.py:1948-1959", err)
        self.assertIn("--cuda 13", err)

    def test_cuda13_below_the_floor_is_refused(self):
        rc, _, err = self.run_main(self.cmd + ["--archs", "61", "--cuda", "13", "--dry-run"])
        self.assertEqual(rc, 2)
        self.assertIn("setup.py:262", err)
        self.assertIn("CUDA13_MIN_ARCH", err)

    def test_missing_binary_is_refused_with_rc2(self):
        empty = self.root / "empty"
        empty.mkdir()
        rc, _, err = self.run_main(["--build", str(empty), "--version", "0.1.45",
                                    "--out", str(self.out), "--keys", str(self.root / "k"),
                                    "--archs", "120", "--dry-run"])
        self.assertEqual(rc, 2)
        self.assertIn("has no strata.exe", err)

    def test_empty_archs_is_a_refusal_not_an_ok(self):
        rc, _, err = self.run_main(self.cmd + ["--dry-run"])
        self.assertEqual(rc, 2)
        self.assertIn("no --archs", err)
        self.assertIn("empty list", err)
        self.assertFalse(self.out.exists())

    def test_short_arch_becomes_sm_and_ptx_stays(self):
        self.assertEqual(msb.package_arch("120"), "sm_120")
        self.assertEqual(msb.package_arch("sm_86"), "sm_86")
        self.assertEqual(msb.package_arch("compute_89"), "compute_89")
        self.assertEqual(msb.arch_number("sm_120"), 120)
        self.assertIsNone(msb.arch_number("gfx1201"))

    def test_rules_come_from_setup(self):
        rules = msb.setup_rules()
        self.assertEqual(rules.get("cuda13_min_arch"), 75)
        self.assertEqual(rules.get("sm120"), 120)


if __name__ == "__main__":
    unittest.main()
