"""Regression checks for policy data shared by preventive and diff-based checks."""
from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts/guardrails"))
from guardrail_rules import is_protected, read_list


class SharedRulesTests(unittest.TestCase):
    def test_list_ignores_blank_and_comment_lines_but_preserves_content(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "rules.txt"
            path.write_text("\n  # comment\n \n  scripts/  \nregex\treason  \n", encoding="utf-8")
            self.assertEqual(read_list(path), ["  scripts/  ", "regex\treason  "])

    def test_missing_list_is_required_unless_caller_explicitly_allows_it(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "missing.txt"
            with self.assertRaises(FileNotFoundError):
                read_list(path)
            self.assertEqual(read_list(path, missing_ok=True), [])

    def test_protected_paths_match_files_and_directory_boundaries(self):
        prefixes = ["AGENTS.md", "scripts/guardrails/"]
        for path in ["AGENTS.md", "scripts/guardrails/rules.py", "scripts/guardrails/nested/rules.py"]:
            with self.subTest(path=path):
                self.assertTrue(is_protected(path, prefixes))
        for path in ["AGENTS.md.bak", "nested/AGENTS.md", "scripts/guardrails-other/rules.py", "App/Clara.swift"]:
            with self.subTest(path=path):
                self.assertFalse(is_protected(path, prefixes))


class EntryPointTests(unittest.TestCase):
    def test_edit_hook_blocks_before_file_exists_from_another_working_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for path in [str(ROOT / "scripts/guardrails/new.py"), "scripts/guardrails/new.py", "AGENTS.md"]:
                with self.subTest(path=path):
                    result = self.run_hook(root, path)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(json.loads(result.stdout)["hookSpecificOutput"]["permissionDecision"], "deny")
                    self.assertFalse((ROOT / "scripts/guardrails/new.py").exists())
            for path in ["scripts/guardrails-other/new.py", str(root / "AGENTS.md")]:
                with self.subTest(path=path):
                    result = self.run_hook(root, path)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout, "")

    def test_codex_multi_file_patch_denies_a_protected_edit(self):
        with tempfile.TemporaryDirectory() as directory:
            result = self.run_hook(Path(directory), "scripts/guardrails/new.py", codex=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout)["hookSpecificOutput"]["permissionDecision"], "deny")

    def test_policy_keeps_local_notice_and_pr_label_requirement(self):
        spec = importlib.util.spec_from_file_location("policy_check", ROOT / "scripts/guardrails/policy_check.py")
        policy = importlib.util.module_from_spec(spec)
        with patch.dict(sys.modules, {spec.name: policy}):
            spec.loader.exec_module(policy)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "guardrails").mkdir()
            (root / "guardrails/protected-paths.txt").write_text("  scripts/guardrails/  \nAGENTS.md\n")
            diff = policy.Diff(["scripts/guardrails/new.py"], ["AGENTS.md"], [])
            with patch.object(policy, "ROOT", root), patch.object(policy, "IN_CI", False):
                local = policy.Report()
                policy.check_protected(local, diff, None)
                self.assertEqual(local.errors, [])
                self.assertEqual(len(local.notices), 1)
                pr = policy.Report()
                policy.check_protected(pr, diff, set())
                self.assertEqual(len(pr.errors), 1)
                approved = policy.Report()
                policy.check_protected(approved, diff, {policy.LABEL_GUARDRAILS})
                self.assertEqual(approved.errors, [])

    def test_policy_can_start_from_another_working_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run([sys.executable, "-B", str(ROOT / "scripts/guardrails/policy_check.py"), "--help"],
                                    cwd=directory, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)

    def run_hook(self, cwd, path, *, codex=False):
        tool_input = {"file_path": path, "content": "new content"}
        if codex:
            tool_input = {"command": (
                "*** Begin Patch\n*** Add File: App/new.swift\n+let value = 1\n"
                f"*** Add File: {path}\n+new content\n*** End Patch\n"
            )}
        return subprocess.run(
            [sys.executable, "-B", str(ROOT / "scripts/agent-hooks/guard.py"), "edit", *(["codex"] if codex else [])],
            input=json.dumps({"tool_input": tool_input}),
            cwd=cwd, env={**os.environ, "CLARA_GUARDRAILS_UNLOCK": "0"},
            capture_output=True, text=True,
        )


if __name__ == "__main__":
    unittest.main()
