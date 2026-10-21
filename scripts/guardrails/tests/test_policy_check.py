import importlib.util
import os
from pathlib import Path
import sys
import subprocess
import tempfile
import unittest
from unittest.mock import patch

MODULE_PATH = Path(os.environ.get('POLICY_CHECK_PATH', Path(__file__).parents[1] / 'policy_check.py'))
spec = importlib.util.spec_from_file_location('policy_check', MODULE_PATH)
policy = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = policy
spec.loader.exec_module(policy)
policy.ROOT = Path(os.environ.get('POLICY_CHECK_ROOT', policy.ROOT))


class SuppressionCommentTests(unittest.TestCase):
    def check_line(self, text, expected, labels=None, source=None, line=1):
        report = policy.Report()
        path = 'Sources/Box.swift'
        diff = policy.Diff([path], [(path, line, text)], {path: source or text})
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
        for text in ('// @unchecked Sendable', '/* @unchecked Sendable */', '/* @unchecked Sendable */ let safe = 1', '/* outer /* inner */ @unchecked Sendable */ let safe = 1'):
            with self.subTest(text=text):
                self.check_line(text, 0)
        self.check_line(' * @unchecked Sendable', 0,
                        source='/* rationale\n * @unchecked Sendable\n */', line=2)

    def test_comment_directives_are_still_detected(self):
        for text in ('// swiftlint:disable all', '/* swiftlint:disable all */', '/* swiftformat:disable all */'):
            with self.subTest(text=text):
                self.check_line(text, 1)
        self.check_line(' * swiftlint:disable all', 1,
                        source='/*\n * swiftlint:disable all\n */', line=2)

    def test_directive_text_inside_a_string_is_not_a_suppression(self):
        self.check_line('let example = "swiftlint:disable all"', 0)

    def test_suppression_text_inside_multiline_string_is_not_a_suppression(self):
        source = 'let example = """\ntry!\n"""\n'
        self.check_line('try!', 0, source=source, line=2)

    def test_raw_string_content_is_not_a_suppression(self):
        source = 'let example = #"""\ntry!\n"""#\n'
        self.check_line('try!', 0, source=source, line=2)

    def test_raw_regex_content_is_not_a_suppression(self):
        self.check_line('let example = #/try!/#', 0)
        source = 'let example = ##/\ntry!\n/##\n'
        self.check_line('try!', 0, source=source, line=2)

    def test_raw_regex_interpolation_is_scanned_as_code(self):
        self.check_line(r'let example = #/\#(try! risky())/#', 1)
        self.check_line(r'let example = #/\#("try!")/#', 0)

    def test_interpolation_is_code_but_nested_string_content_is_not(self):
        self.check_line('let example = "\\(try! risky())"', 1)
        self.check_line('let example = "\\("try!")"', 0)

    def test_active_suppression_without_comment(self):
        self.check_line('final class Box: @unchecked Sendable {}', 1)

    def test_exception_label_accepts_with_notice(self):
        report = self.check_line('/* rationale */ final class Box: @unchecked Sendable {}', 0, {policy.LABEL_EXCEPTION})
        self.assertEqual(len(report.notices), 1)


class DependencyTests(unittest.TestCase):
    allowed_url = "https://github.com/pointfreeco/swift-snapshot-testing"

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.patcher = patch.object(policy, "ROOT", self.root)
        self.patcher.start()
        self.addCleanup(self.patcher.stop)
        self.annotations = patch.object(policy, "IN_CI", False)
        self.annotations.start()
        self.addCleanup(self.annotations.stop)
        self.git("init", "--quiet")
        (self.root / "guardrails").mkdir()
        (self.root / "guardrails/allowed-dependencies.txt").write_text(
            f"swift {self.allowed_url}\ngem fastlane\n", encoding="utf-8"
        )
        self.git("add", "guardrails/allowed-dependencies.txt")

    def git(self, *args):
        subprocess.run(["git", *args], cwd=self.root, check=True, capture_output=True)

    def manifest(self, declaration):
        (self.root / "Package.swift").write_text(
            f"let dependencies = [{declaration}]\n", encoding="utf-8"
        )

    def report(self, staged=False):
        report = policy.Report()
        if staged:
            policy.check_dependencies(report, staged=True)
        else:
            policy.check_dependencies(report)
        return report

    def test_ranges_and_unknown_forms_fail_closed(self):
        for requirement in ('"1.0.0"..<"2.0.0"', 'from: "1.0.0"',
                            'branch: "main"', 'requirement', 'exact: version'):
            with self.subTest(requirement=requirement):
                self.manifest(f'.package(url: "{self.allowed_url}", {requirement})')
                self.assertTrue(self.report().errors)

    def test_unapproved_url_rejected_with_range_or_exact_requirement(self):
        for requirement in ('"1.0.0"..<"2.0.0"', 'exact: "1.0.0"'):
            with self.subTest(requirement=requirement):
                self.manifest(f'.package(url: "https://example.invalid/unapproved.git", {requirement})')
                self.assertTrue(self.report().errors)

    def test_literal_exact_revision_and_local_packages_are_accepted(self):
        for declaration in (f'.package(url: "{self.allowed_url}.git", exact: "1.0.0")',
                            f'.package(name: "Snapshots", url: "{self.allowed_url}", revision: "abc123")',
                            '.package(path: "../ClaraCore")'):
            with self.subTest(declaration=declaration):
                self.manifest(declaration)
                self.assertEqual(self.report().errors, [])

    def test_dynamic_url_is_rejected(self):
        self.manifest('.package(url: repository, exact: "1.0.0")')
        self.assertTrue(self.report().errors)

    def test_comments_and_string_examples_are_not_dependencies(self):
        self.manifest('''// .package(url: "unapproved", from: "1.0.0")
/* outer /* nested */ .package(url: "unapproved", from: "1.0.0") */
let example = \".package(url: repository, exact: version)\"
let raw = #".package(url: "unapproved", from: "1.0.0")"#
let multiline = """
.package(url: "unapproved", from: "1.0.0")
"""
''')
        self.assertEqual(self.report().errors, [])

    def test_whitespace_and_comments_between_arguments(self):
        self.manifest(f''' . package (
            /* outer /* nested */ rationale */ url : "{self.allowed_url}.git",
            exact : "1.0.0" // pinned
        )''')
        self.assertEqual(self.report().errors, [])

    def test_comments_do_not_hide_active_package(self):
        self.manifest('''/* rationale */ .package /* reason */ (
            url: "https://example.invalid/unapproved", exact: "1.0.0"
        )''')
        self.assertTrue(self.report().errors)

    def test_staged_reads_allowlist_from_index(self):
        self.manifest('.package(url: "https://example.invalid/unapproved", exact: "1.0.0")')
        self.git("add", "Package.swift")
        with (self.root / "guardrails/allowed-dependencies.txt").open("a") as allowed:
            allowed.write("swift https://example.invalid/unapproved\n")
        self.assertTrue(self.report(staged=True).errors)
        self.assertEqual(self.report().errors, [])

    def test_staged_cli_selects_index_content(self):
        (self.root / "scripts/guardrails").mkdir(parents=True)
        script = self.root / "scripts/guardrails/policy_check.py"
        script.write_text(MODULE_PATH.read_text(encoding="utf-8"), encoding="utf-8")
        shared_rules = MODULE_PATH.with_name("guardrail_rules.py")
        if shared_rules.exists():
            (script.parent / shared_rules.name).write_text(
                shared_rules.read_text(encoding="utf-8"), encoding="utf-8"
            )
        for name in ("protected-paths.txt", "suppression-patterns.txt"):
            (self.root / "guardrails" / name).write_text("", encoding="utf-8")
        self.manifest('.package(url: "https://example.invalid/unapproved", exact: "1.0.0")')
        self.git("add", "Package.swift")
        self.manifest("")
        result = subprocess.run([sys.executable, str(script), "--mode", "staged"],
                                cwd=self.root, text=True, capture_output=True,
                                env={**os.environ, "GITHUB_ACTIONS": "false"})
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("fora da lista permitida", result.stderr)

    def test_staged_reads_index_instead_of_clean_worktree(self):
        for path, unsafe, safe in (
            ("Package.swift", '.package(url: "https://example.invalid/unapproved", exact: "1.0.0")', ''),
            ("Gemfile", 'gem "unapproved"', 'gem "fastlane"'),
        ):
            with self.subTest(path=path):
                target = self.root / path
                target.write_text(unsafe, encoding="utf-8")
                self.git("add", path)
                target.write_text(safe, encoding="utf-8")
                self.assertTrue(self.report(staged=True).errors)
                self.assertEqual(self.report().errors, [])
                self.git("rm", "--cached", "--force", path)
                target.unlink()

    def test_staged_ignores_untracked_files_and_unstaged_manifest_changes(self):
        self.manifest(f'.package(url: "{self.allowed_url}", exact: "1.0.0")')
        self.git("add", "Package.swift")
        self.manifest('.package(url: "https://example.invalid/unapproved", exact: "1.0.0")')
        (self.root / "Gemfile").write_text('gem "unapproved"', encoding="utf-8")
        self.assertEqual(self.report(staged=True).errors, [])
        self.assertTrue(self.report().errors)

    def test_staged_manifest_missing_from_worktree_is_still_checked(self):
        self.manifest('.package(url: "https://example.invalid/unapproved", exact: "1.0.0")')
        self.git("add", "Package.swift")
        (self.root / "Package.swift").unlink()
        self.assertTrue(self.report(staged=True).errors)

    def test_allowlisted_gem_from_git_or_path_source_is_rejected(self):
        for declaration in ('gem "fastlane", git: "https://example.invalid/fastlane.git"',
                            'gem "fastlane", path: "../fastlane"',
                            'gem "fastlane", :git => "https://example.invalid/fastlane.git"'):
            with self.subTest(declaration=declaration):
                (self.root / "Gemfile").write_text(declaration + "\n", encoding="utf-8")
                self.assertTrue(self.report().errors)

    def test_gemspec_and_nested_gemfiles_fail_closed(self):
        for declaration in ('gemspec', 'eval_gemfile "other.Gemfile"'):
            with self.subTest(declaration=declaration):
                (self.root / "Gemfile").write_text(declaration + "\n", encoding="utf-8")
                self.assertTrue(self.report().errors)

    def test_only_the_canonical_rubygems_source_is_allowed(self):
        gemfile = self.root / "Gemfile"
        for source, expected_errors in (("https://rubygems.org", 0),
                                        ("https://example.invalid", 1)):
            with self.subTest(source=source):
                gemfile.write_text(f'source "{source}"\n', encoding="utf-8")
                self.assertEqual(len(self.report().errors), expected_errors)


class TestCountTests(unittest.TestCase):
    def test_counts_only_test_target_declarations_outside_comments_and_strings(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["git", "init", "--quiet"], cwd=root, check=True)
            tests = root / "Packages/ClaraKit/Tests/ClaraCoreTests/ActualTests.swift"
            tests.parent.mkdir(parents=True)
            tests.write_text(
                "/*\n@Test\n*/\n"
                'let example = """\n@Test func fakeInString() {}\n"""\n'
                "@Test func actual() {}\n"
                "func testAnotherActual() {}\n",
                encoding="utf-8",
            )
            production = root / "Packages/ClaraKit/Sources/ClaraCore/Fake.swift"
            production.parent.mkdir(parents=True)
            production.write_text("@Test func fake() {}\nfunc testFake() {}\n", encoding="utf-8")
            subprocess.run(["git", "add", "."], cwd=root, check=True)

            with patch.object(policy, "ROOT", root):
                self.assertEqual(policy.count_tests(None), 2)


class DiffTests(unittest.TestCase):
    def test_added_double_plus_line_does_not_end_file_context(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["git", "init", "--quiet"], cwd=root, check=True)
            subprocess.run(["git", "config", "user.name", "Test"], cwd=root, check=True)
            subprocess.run(["git", "config", "user.email", "test@example.invalid"], cwd=root, check=True)
            source = root / "Sources/Thing.m"
            source.parent.mkdir()
            source.write_text("void update(void) {\n}\n", encoding="utf-8")
            subprocess.run(["git", "add", "."], cwd=root, check=True)
            subprocess.run(["git", "commit", "--quiet", "-m", "base"], cwd=root, check=True)
            source.write_text("void update(void) {\n++ counter;\nXCTSkip();\n}\n", encoding="utf-8")

            with patch.object(policy, "ROOT", root):
                diff = policy.collect_diff("HEAD", local=True)

            self.assertEqual([line for _, _, line in diff.added_lines],
                             ["++ counter;", "XCTSkip();"])


if __name__ == '__main__':
    unittest.main()
