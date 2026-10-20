"""Maestro impact selection stays conservative for unknown paths."""
import importlib.util
from pathlib import Path
import unittest
import subprocess
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "maestro_selection", Path(__file__).parents[1] / "maestro_selection.py"
)
selection = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(selection)


class MaestroSelectionTests(unittest.TestCase):
    def test_only_recognized_documentation_changes_skip_maestro(self):
        for paths in (["docs/guide.md"], ["README.md"], ["docs/image.png"]):
            with self.subTest(paths=paths):
                self.assertEqual(selection.mode_for("pull_request", paths), "skip")
        for path in ("docs/config.yml", "docs/example.swift", ".github/workflows/ci.yml",
                     "Packages/ClaraKit/Sources/Core.swift", ".maestro/new.yaml",
                     "App/Assets.xcassets/icon.png", "Resources/fixture.txt",
                     ".maestro/fixture.txt"):
            with self.subTest(path=path):
                self.assertEqual(selection.mode_for("pull_request", [path]), "smoke")

    def test_empty_or_unknown_diff_runs_smoke(self):
        self.assertEqual(selection.mode_for("pull_request", []), "smoke")
        self.assertEqual(selection.mode_for("pull_request", ["new-file.unknown"]), "smoke")
        self.assertEqual(selection.mode_for("pull_request", ["docs/guide.md", "App/View.swift"]), "smoke")

    def test_diff_failure_and_rename_keep_the_conservative_result(self):
        with patch.object(selection.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "git")):
            self.assertEqual(selection.changed_paths("base", "head"), [])
        with patch.object(selection.subprocess, "run", return_value=type(
            "Result", (), {"stdout": "App/View.swift\0docs/View.md\0"}
        )()) as run:
            paths = selection.changed_paths("base", "head")
            self.assertEqual(paths, ["App/View.swift", "docs/View.md"])
            self.assertIn("--no-renames", run.call_args.args[0])
            self.assertEqual(selection.mode_for("pull_request", paths), "smoke")

    def test_schedule_and_manual_runs_are_always_full(self):
        for event in ("schedule", "workflow_dispatch"):
            with self.subTest(event=event):
                self.assertEqual(selection.mode_for(event, ["README.md"]), "full")

    def test_other_events_are_conservative(self):
        self.assertEqual(selection.mode_for("push", ["docs/guide.md"]), "smoke")


if __name__ == "__main__":
    unittest.main()
