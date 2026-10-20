"""Run base policy against hostile PR data without executing PR files."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

RUNNER = Path(__file__).parents[1] / 'trusted_policy.py'
SOURCE = Path(__file__).parents[2] / 'guardrails' / 'policy_check.py'


class TrustedPolicyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.git('init', '--quiet')
        self.git('config', 'user.email', 'test@example.invalid')
        self.git('config', 'user.name', 'Test')
        for source in SOURCE.parent.glob('*.py'):
            self.write(f'scripts/guardrails/{source.name}', source.read_text())
        self.write('guardrails/protected-paths.txt', 'guardrails/\nscripts/guardrails/\n.github/\n')
        self.write('guardrails/allowed-dependencies.txt', '')
        self.write('guardrails/suppression-patterns.txt', 'try!\tforced try\n')
        self.git('add', '.')
        self.git('commit', '--quiet', '-m', 'base')
        self.base = self.git('rev-parse', 'HEAD').strip()

    def git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.root, text=True)

    def write(self, path, text):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)

    def invoke(self, labels='[]'):
        self.git('add', '.')
        self.git('commit', '--quiet', '--allow-empty', '-m', 'proposal')
        return subprocess.run(['python3', str(RUNNER), '--base', self.base], cwd=self.root,
                              env=dict(os.environ, PR_LABELS=labels), capture_output=True, text=True)

    def test_proposed_checker_rules_and_workflow_cannot_approve_themselves(self):
        marker = self.root / 'executed'
        self.write('scripts/guardrails/policy_check.py', f"open({str(marker)!r}, 'w').write('bad')\n")
        self.write('guardrails/protected-paths.txt', '')
        self.write('.github/workflows/ci.yml', 'jobs: {}\n')
        result = self.invoke()
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn('guardrails-change', result.stderr)
        self.assertIn('.github/workflows/ci.yml', result.stderr)
        self.assertFalse(marker.exists())

    def test_human_label_still_allows_protected_changes_without_running_them(self):
        marker = self.root / 'executed'
        self.write('scripts/guardrails/policy_check.py', f"open({str(marker)!r}, 'w').write('bad')\n")
        result = self.invoke('["guardrails-change"]')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(marker.exists())

    def test_manifest_is_data_and_allowlist_comes_from_base(self):
        self.write('Package.swift', '.package(url: "https://example.invalid/evil", exact: "1.0.0")')
        self.write('guardrails/allowed-dependencies.txt', 'swift https://example.invalid/evil\n')
        result = self.invoke('["guardrails-change"]')
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn('fora da lista', result.stderr)

    def test_suppression_list_cannot_be_cleared_in_proposal(self):
        self.write('guardrails/suppression-patterns.txt', '')
        self.write('Feature.swift', 'let value = try! load()\n')
        result = self.invoke('["guardrails-change"]')
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn('guardrail-exception', result.stderr)

    def test_manifest_symlink_is_rejected_without_following_it(self):
        (self.root / 'Package.swift').symlink_to('/outside/Package.swift')
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('regular file', result.stderr)

    def test_deleted_swift_tests_still_require_exception(self):
        self.write('Tests/FeatureTests.swift', '@Test func example() {}\n')
        self.git('add', '.')
        self.git('commit', '--quiet', '-m', 'base tests')
        self.base = self.git('rev-parse', 'HEAD').strip()
        (self.root / 'Tests/FeatureTests.swift').unlink()
        result = self.invoke()
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn('guardrail-exception', result.stderr)

    def test_explicit_head_is_checked_even_with_base_checked_out(self):
        self.write('Package.swift', '.package(url: "https://example.invalid/evil", exact: "1.0.0")')
        self.git('add', '.')
        self.git('commit', '--quiet', '-m', 'proposal')
        head = self.git('rev-parse', 'HEAD').strip()
        self.git('checkout', '--quiet', '--detach', self.base)
        result = subprocess.run(['python3', str(RUNNER), '--base', self.base, '--head', head],
                                cwd=self.root, capture_output=True, text=True)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn('fora da lista', result.stderr)

    def test_clean_change_passes(self):
        self.write('README.md', 'hello\n')
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__':
    unittest.main()
