"""Maestro may not pass when tag filtering discovers no flows."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location(
    "maestro_result_gate", Path(__file__).parents[1] / "maestro_result_gate.py"
)
gate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gate)


class MaestroResultGateTests(unittest.TestCase):
    def check_xml(self, xml):
        with tempfile.TemporaryDirectory() as directory:
            report = Path(directory) / "maestro.xml"
            report.write_text(xml)
            gate.check_results(report)

    def test_requires_at_least_one_discovered_flow(self):
        self.check_xml('<testsuite tests="1"><testcase name="smoke" /></testsuite>')
        self.check_xml('<testsuite tests="2"><testcase><skipped /></testcase>'
                       '<testcase name="executed" /></testsuite>')
        for xml in ('<testsuite tests="0" />', '<testsuites />'):
            with self.subTest(xml=xml), self.assertRaises(ValueError):
                self.check_xml(xml)

    def test_all_skipped_flows_fail(self):
        with self.assertRaises(ValueError):
            self.check_xml('<testsuite tests="1"><testcase><skipped /></testcase></testsuite>')

    def test_missing_or_malformed_report_fails_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(ValueError):
                gate.check_results(Path(directory) / "missing.xml")
            report = Path(directory) / "malformed.xml"
            report.write_text("<testsuite>")
            with self.assertRaises(ValueError):
                gate.check_results(report)


if __name__ == "__main__":
    unittest.main()
