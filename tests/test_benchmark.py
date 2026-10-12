"""Run with python3 -m unittest discover -s tests."""

import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


HELPER = Path(__file__).resolve().parents[1] / "files/system/usr/bin/bc250-benchmark"
loader = importlib.machinery.SourceFileLoader("benchmark", str(HELPER))
spec = importlib.util.spec_from_loader(loader.name, loader)
benchmark = importlib.util.module_from_spec(spec)
loader.exec_module(benchmark)


class BenchmarkTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def csv(self, name="game.csv", times=(10, 10)):
        path = self.root / name
        path.write_text("version,1\nos,cpu,gpu\nLinux,CPU,GPU\n"
                        "fps,frametime,gpu_temp\n" +
                        "".join(f"999,{t},50\n" for t in times))
        return path

    def test_frame_time_statistics_ignore_instantaneous_fps(self):
        result = benchmark.analyze(self.csv(times=[10] * 99 + [100]))
        self.assertEqual(result["frames"], 100)
        self.assertAlmostEqual(result["average_fps"], 100 / 1.09)
        self.assertEqual(result["low_1pct_fps"], 10)
        self.assertEqual(result["p99_ms"], 10)
        self.assertAlmostEqual(result["over_50ms_per_minute"], 60 / 1.09)
        self.assertEqual(result["sensors"]["gpu_temp"]["average"], 50)

    def test_invalid_frames_are_rejected(self):
        for value in ("nan", "inf", "0", "-1", "broken"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                benchmark.analyze(self.csv(times=(10, value)))

    def test_multiple_captures_require_explicit_selection(self):
        self.csv("one.csv")
        self.csv("two.csv")
        (self.root / "one_summary.csv").write_text("not a per-frame log")
        with self.assertRaises(ValueError):
            benchmark.select(self.root, None)
        self.assertEqual(benchmark.select(self.root, "two.csv")["frames"], 2)

    def test_incomplete_capture_does_not_silently_disappear(self):
        self.csv("good.csv")
        (self.root / "incomplete.csv").write_text("fps,frametime\n60,\n")
        with self.assertRaises(ValueError):
            benchmark.select(self.root, None)
        self.assertEqual(benchmark.select(self.root, "good.csv")["frames"], 2)

    def test_compare_reports_improvement(self):
        before, after = self.root / "before", self.root / "after"
        for directory, frametime in ((before, 20), (after, 10)):
            directory.mkdir()
            (directory / "run.json").write_text(json.dumps({"context": {}}))
            (directory / "game.csv").write_text("fps,frametime\n" + f"1,{frametime}\n" * 4000)
        output = io.StringIO()
        args = SimpleNamespace(before=str(before), after=str(after), before_csv=None, after_csv=None)
        with contextlib.redirect_stdout(output):
            self.assertEqual(benchmark.compare(args), 0)
        self.assertIn("+100.0%", output.getvalue())
        self.assertIn("-50.0%", output.getvalue())

    def test_driver_override_keeps_stock_32bit(self):
        patched = self.root / "patched.json"
        patched.touch()
        stock32 = self.root / "radeon_icd.i686.json"
        stock32.touch()
        args = SimpleNamespace(driver="patched", heap="current")
        with patch.object(benchmark, "PATCHED", patched), patch.object(benchmark, "ICD_DIR", self.root):
            env = benchmark.game_environment(args, self.root)
        self.assertEqual(env["VK_DRIVER_FILES"], f"{patched}:{stock32}")
        self.assertEqual(env["VK_ICD_FILENAMES"], env["VK_DRIVER_FILES"])

    def test_launch_preserves_arguments_exit_status_and_parent_environment(self):
        wrapper = self.root / "mangohud"
        wrapper.write_text('''#!/usr/bin/env python3
import json, os, pathlib, sys
p = pathlib.Path(os.environ["MANGOHUD_CONFIGFILE"]).parent
(p / "received.json").write_text(json.dumps({"argv": sys.argv[1:], "heap": os.environ["radv_enable_unified_heap_on_apu"]}))
(p / "game.csv").write_text("fps,frametime\\n100,10\\n100,10\\n")
sys.exit(7)
''')
        wrapper.chmod(0o755)
        runs = self.root / "runs"
        argv = [str(HELPER), "run", "before", "--heap", "off", "--",
                "game with spaces", "--flag", "literal;$value"]
        with patch.object(benchmark, "ROOT", runs), \
                patch.object(benchmark, "snapshot", return_value={}), \
                patch.dict(os.environ, {"PATH": f"{self.root}:{os.environ['PATH']}",
                                        "radv_enable_unified_heap_on_apu": "true"}), \
                patch("sys.argv", argv), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(benchmark.main(), 7)
            self.assertEqual(os.environ["radv_enable_unified_heap_on_apu"], "true")
        directory = next(runs.iterdir())
        received = json.loads((directory / "received.json").read_text())
        self.assertEqual(received["argv"], argv[6:])
        self.assertEqual(received["heap"], "false")
        metadata = json.loads((directory / "run.json").read_text())
        self.assertEqual(metadata["state"], "finished")
        self.assertEqual(metadata["exit_code"], 7)
        self.assertEqual(json.loads((directory / "summary.json").read_text())["captures"][0]["average_fps"], 100)


if __name__ == "__main__":
    unittest.main()
