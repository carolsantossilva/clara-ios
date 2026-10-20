"""Regression checks for production coverage embedded in Swift package test bundles."""
import contextlib
import io
import json
from pathlib import Path
import runpy
import subprocess
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "scripts/ci/coverage_gate.py"


def source(path, covered, executable):
    return {"name": Path(path).name, "path": str(ROOT / path),
            "coveredLines": covered, "executableLines": executable}


def target(name, *files):
    return {"name": name, "files": list(files)}


class CoverageGateTests(unittest.TestCase):
    def run_gate(self, *targets):
        result = subprocess.CompletedProcess([], 0, stdout=json.dumps({"targets": targets}))
        output = io.StringIO()
        with patch.object(sys, "argv", [str(SCRIPT), "unused.xcresult"]), \
                patch("subprocess.run", return_value=result), contextlib.redirect_stdout(output):
            try:
                runpy.run_path(str(SCRIPT), run_name="__main__")
            except SystemExit as error:
                return error.code, output.getvalue()
        return 0, output.getvalue()

    def test_production_in_test_bundles_stays_in_the_gate(self):
        code, output = self.run_gate(target("RecordsTests",
            source("Packages/ClaraKit/Sources/ClaraUI/Records/RecordsView.swift", 1, 100),
            source("Packages/ClaraKit/Sources/ClaraUI/DesignSystem/Components.swift", 1, 100)))
        self.assertEqual(code, 1)
        self.assertIn("Total coverage: 1.0%", output)

    def test_test_and_dependency_coverage_cannot_hide_uncovered_production(self):
        code, output = self.run_gate(
            target("Clara.app", source("App/RootView.swift", 1, 100)),
            target("SnapshotTests",
                   source("Packages/ClaraKit/Tests/SnapshotTests/SnapshotTests.swift", 1000, 1000)),
            target("SnapshotTesting",
                   source("Packages/ClaraKit/.build/checkouts/swift-snapshot-testing/Sources/SnapshotTesting.swift", 1000, 1000)))
        self.assertEqual(code, 1)
        self.assertIn("Total coverage: 1.0%", output)

    def test_static_library_copies_count_once_and_test_support_is_excluded(self):
        path = "Packages/ClaraKit/Sources/ClaraUI/Records/RecordsView.swift"
        code, output = self.run_gate(
            target("Clara.app", source("App/RootView.swift", 0, 100)),
            target("ClaraUI", source(path, 100, 100)),
            target("RecordsTests", source(path, 100, 100),
                   source("Packages/ClaraKit/Sources/ClaraTestSupport/Fixtures.swift", 1000, 1000)))
        self.assertEqual(code, 0)
        self.assertIn("Total coverage: 50.0%", output)

    def test_all_swiftui_screens_stay_in_the_gate(self):
        views = ["Today/TodayView.swift", "Today/TodaySheets.swift",
                 "Records/MomentFormView.swift", "Consultation/ConsultationView.swift"]
        for view in views:
            with self.subTest(view=view):
                code, output = self.run_gate(target("ClaraUI",
                    source("App/RootView.swift", 10, 10),
                    source(f"Packages/ClaraKit/Sources/ClaraUI/{view}", 0, 1000)))
                self.assertEqual(code, 1)
                self.assertIn("Total coverage: 1.0%", output)

    def test_missing_production_coverage_fails(self):
        code, _ = self.run_gate(target("SnapshotTests",
            source("Packages/ClaraKit/Tests/SnapshotTests/SnapshotTests.swift", 100, 100)))
        self.assertNotEqual(code, 0)


if __name__ == "__main__":
    unittest.main()
