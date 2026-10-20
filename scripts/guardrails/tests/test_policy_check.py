import importlib.util
import os
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

MODULE_PATH = Path(os.environ.get('POLICY_CHECK_PATH', Path(__file__).parents[1] / 'policy_check.py'))
spec = importlib.util.spec_from_file_location('policy_check', MODULE_PATH)
policy = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = policy
spec.loader.exec_module(policy)
policy.ROOT = Path(os.environ.get('POLICY_CHECK_ROOT', policy.ROOT))


class SuppressionCommentTests(unittest.TestCase):
    def check_line(self, text, expected, labels=None):
        report = policy.Report()
        diff = policy.Diff(['Sources/Box.swift'], [], [('Sources/Box.swift', 1, text)])
        # Inspect reports without emitting annotations for intentional failing inputs.
        with patch.object(policy, "IN_CI", False):
            policy.check_suppressions(report, diff, set() if labels is None else labels)
        self.assertEqual(len(report.errors), expected, report.errors)
        return report

    def test_active_code_after_leading_block_comment(self):
        self.check_line('/* rationale */ final class Box: @unchecked Sendable {}', 1)

    def test_multiple_leading_block_comments(self):
        self.check_line(' /* first */ /* second */ final class Box: @unchecked Sendable {}', 1)

    def test_nested_leading_block_comments(self):
        self.check_line('/* outer /* inner */ rationale */ final class Box: @unchecked Sendable {}', 1)

    def test_comment_mentions_are_not_suppressions(self):
        for text in ('// @unchecked Sendable', '/* @unchecked Sendable */', '* @unchecked Sendable', '/* @unchecked Sendable */ let safe = 1', '/* outer /* inner */ @unchecked Sendable */ let safe = 1'):
            with self.subTest(text=text):
                self.check_line(text, 0)

    def test_comment_directives_are_still_detected(self):
        for text in ('// swiftlint:disable all', '/* swiftlint:disable all */', '/* swiftformat:disable all */', '* swiftlint:disable all'):
            with self.subTest(text=text):
                self.check_line(text, 1)

    def test_active_suppression_without_comment(self):
        self.check_line('final class Box: @unchecked Sendable {}', 1)

    def test_exception_label_accepts_with_notice(self):
        report = self.check_line('/* rationale */ final class Box: @unchecked Sendable {}', 0, {policy.LABEL_EXCEPTION})
        self.assertEqual(len(report.notices), 1)


if __name__ == '__main__':
    unittest.main()
