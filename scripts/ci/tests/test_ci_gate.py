"""Regression cases for the required CI gate; no network or wall clock."""
import importlib.util
from pathlib import Path
import unittest
import json
import os
import subprocess
import tempfile
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("ci_gate", Path(__file__).parents[1] / "ci_gate.py")
gate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gate)


class CodeResultsTests(unittest.TestCase):
    def results(self, app="true", maestro="true", maestro_mode="smoke"):
        return {
            "detect": {"result": "success", "outputs": {
                "app": app, "maestro": maestro, "maestro_mode": maestro_mode,
            }},
            "lint": {"result": "success" if app == "true" else "skipped"},
            "test": {"result": "success" if app == "true" else "skipped"},
            "maestro": {"result": "success" if app == maestro == "true" and maestro_mode != "skip" else "skipped"},
        }

    def test_all_required_jobs_must_succeed(self):
        gate.check_code(self.results())
        for job in ("detect", "lint", "test", "maestro"):
            for result in ("failure", "cancelled", "skipped", "pending"):
                with self.subTest(job=job, result=result), self.assertRaises(ValueError):
                    needs = self.results()
                    needs[job]["result"] = result
                    gate.check_code(needs)

    def test_only_absent_app_or_flows_can_skip(self):
        gate.check_code(self.results(app="false"))
        gate.check_code(self.results(maestro="false"))
        gate.check_code(self.results(maestro_mode="skip"))
        with self.assertRaises(ValueError):
            gate.check_code({})
        needs = self.results()
        needs["detect"]["outputs"] = {}
        with self.assertRaises(ValueError):
            gate.check_code(needs)

    def test_only_selected_modes_can_skip_and_missing_mode_fails_closed(self):
        for mode in ("smoke", "full"):
            needs = self.results(maestro_mode=mode)
            needs["maestro"]["result"] = "skipped"
            with self.subTest(mode=mode), self.assertRaises(ValueError):
                gate.check_code(needs)
        needs = self.results()
        del needs["detect"]["outputs"]["maestro_mode"]
        with self.assertRaises(ValueError):
            gate.check_code(needs)


class ReuseTests(unittest.TestCase):
    def fixture_run(self, id=10, action="synchronize", sha="merge", **kw):
        return dict(id=id, display_title=f"CI / {action} / {sha}", event="pull_request",
                    workflow_id=7, head_sha="head", **kw)

    def select(self, runs):
        return gate.select_code_run(runs, workflow_id=7, head_sha="head", merge_sha="merge")

    def test_reuses_exact_code_run_and_ignores_labels(self):
        self.assertEqual(self.select([self.fixture_run(11, action="labeled"), self.fixture_run()])["id"], 10)
        for field, value in (("workflow_id", 8), ("head_sha", "other"), ("event", "push")):
            run = self.fixture_run()
            run[field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                self.select([run])
        for run in (self.fixture_run(sha="old-merge"), self.fixture_run(action="unlabeled")):
            with self.assertRaises(ValueError):
                self.select([run])

    def test_latest_attempt_cannot_fall_back_to_old_success(self):
        self.assertEqual(self.select([self.fixture_run(10), self.fixture_run(12)])["id"], 12)
        self.assertEqual(self.select([self.fixture_run(12, run_attempt=1),
                                      self.fixture_run(12, run_attempt=2)])["run_attempt"], 2)
        for conclusion in ("failure", "cancelled", "skipped", None):
            with self.subTest(conclusion=conclusion), self.assertRaises(ValueError):
                gate.check_reused_jobs([{"name": gate.CODE_JOB, "conclusion": conclusion}])
        gate.check_reused_jobs([{"name": gate.CODE_JOB, "conclusion": "success"}])
        with self.assertRaises(ValueError):
            gate.check_reused_jobs([])


class LivePolicyTests(unittest.TestCase):
    def test_uses_live_labels_instead_of_event_snapshot(self):
        event = {"pull_request": {"number": 24, "head": {"sha": "head"},
                                   "base": {"sha": "base"},
                                   "labels": [{"name": "guardrail-exception"}]}}
        current = dict(state="open", head={"sha": "head"}, base={"sha": "base"}, labels=[])
        with patch.object(gate, "api", return_value=current):
            self.assertEqual(gate.live_labels(event), "[]")
        for field in ("head", "base"):
            changed = dict(current, **{field: {"sha": "new"}})
            with self.subTest(field=field), patch.object(gate, "api", return_value=changed):
                with self.assertRaises(ValueError):
                    gate.live_labels(event)

    def test_trusted_event_passes_explicit_head_and_live_labels(self):
        event = {"pull_request": {"number": 24, "head": {"sha": "proposal"},
                                  "base": {"sha": "base"}}}
        env = {"GITHUB_EVENT_NAME": "pull_request_target"}
        with patch.dict(os.environ, env), patch.object(gate, "live_labels", return_value="[]"), \
                patch.object(gate.subprocess, "run") as policy:
            gate.run_policy(event)
            self.assertEqual(policy.call_args.args[0],
                             [gate.sys.executable, "scripts/ci/trusted_policy.py", "--head", "proposal",
                              "--mode", "pr", "--base", "base"])
            self.assertEqual(policy.call_args.kwargs["env"]["PR_LABELS"], "[]")

    def test_other_pr_cannot_supply_code_validation(self):
        run = dict(id=1, display_title="CI / opened / merge", event="pull_request",
                   workflow_id=7, head_sha="head", pull_requests=[{"number": 2}])
        with self.assertRaises(ValueError):
            gate.select_code_run([run], workflow_id=7, head_sha="head", merge_sha="merge", pr_number=1)


class GateIntegrationTests(unittest.TestCase):
    def invoke(self, action="synchronize", summary="success", early_policy="success", code="success", policy_error=False):
        event = {"action": action, "pull_request": {"number": 24, "head": {"sha": "head"},
                                                     "base": {"sha": "base"}}}
        needs = {job: {"result": "success"} for job in ("detect", "secrets", "dependency-review")}
        needs.update({"code-validation": {"result": code}, "policy": {"result": early_policy}})
        run = dict(id=10, workflow_id=7, head_sha="head", event="pull_request", run_attempt=2,
                   display_title="CI / synchronize / merge", pull_requests=[{"number": 24}],
                   html_url="https://github.com/example/run/10")
        calls = []

        def fake_api(path):
            calls.append(path)
            if path == "actions/runs/11":
                return {"workflow_id": 7}
            if path.startswith("actions/workflows/7/runs?"):
                return {"workflow_runs": [run]}
            if path.startswith("actions/runs/10/attempts/2/jobs?"):
                return {"jobs": [{"name": gate.CODE_JOB, "conclusion": summary}]}
            if path == "pulls/24":
                return dict(state="open", head={"sha": "head"}, base={"sha": "base"}, labels=[])
            self.fail(f"Unexpected API call {path}")

        with tempfile.TemporaryDirectory() as directory:
            event_path = Path(directory) / "event.json"
            event_path.write_text(json.dumps(event))
            env = dict(NEEDS=json.dumps(needs), GITHUB_EVENT_PATH=str(event_path),
                       GITHUB_EVENT_NAME="pull_request", GITHUB_RUN_ID="11", GITHUB_SHA="merge")
            with patch.dict(os.environ, env), patch.object(gate, "api", side_effect=fake_api), \
                    patch.object(gate.subprocess, "run") as policy:
                if policy_error:
                    policy.side_effect = subprocess.CalledProcessError(1, "policy_check")
                if (action in ("labeled", "unlabeled") and summary != "success") or code != "success":
                    with self.assertRaises(ValueError):
                        gate.main()
                    policy.assert_not_called()
                elif policy_error:
                    with self.assertRaises(subprocess.CalledProcessError):
                        gate.main()
                else:
                    gate.main()
                    self.assertEqual(policy.call_args.kwargs["env"]["PR_LABELS"], "[]")
                    self.assertTrue(policy.call_args.kwargs["check"])
                    self.assertEqual(policy.call_args.args[0][1], "scripts/ci/trusted_policy.py")
                    self.assertEqual(policy.call_args.args[0][-4:], ["--mode", "pr", "--base", "base"])
        return calls

    def test_label_event_reuses_exact_attempt_and_live_policy(self):
        calls = self.invoke(action="labeled", early_policy="failure")
        self.assertTrue(any(path.startswith("actions/runs/10/attempts/2/jobs?") for path in calls))
        self.invoke(action="unlabeled", summary=None)

    def test_code_gate_rechecks_policy_regardless_of_early_snapshot(self):
        for result in ("success", "failure"):
            with self.subTest(early_policy=result):
                self.invoke(early_policy=result)
        self.invoke(code="cancelled")
        self.invoke(policy_error=True)


if __name__ == "__main__":
    unittest.main()
