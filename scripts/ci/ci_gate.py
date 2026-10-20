#!/usr/bin/env python3
"""Fail closed when label events reuse code checks; recheck live PR policy last."""
import json
import os
from pathlib import Path
import subprocess
import sys
from urllib.parse import urlencode
from urllib.request import Request, urlopen

CODE_JOB = "Validação do código"
CODE_ACTIONS = ("opened", "synchronize", "reopened")


def require(condition, message):
    if not condition:
        raise ValueError(message)


def check_code(needs):
    detect = needs.get("detect", {})
    outputs = detect.get("outputs", {})
    require(detect.get("result") == "success", "Detection did not succeed")
    require(outputs.get("app") in ("true", "false"), "Missing app detection")
    require(outputs.get("maestro") in ("true", "false"), "Missing flow detection")
    for job in ("lint", "test", "maestro"):
        applies = outputs["app"] == "true" and (job != "maestro" or outputs["maestro"] == "true")
        expected = "success" if applies else "skipped"
        require(needs.get(job, {}).get("result") == expected, f"{job} must be {expected}")


def select_code_run(runs, *, workflow_id, head_sha, merge_sha, pr_number=None):
    titles = {f"CI / {action} / {merge_sha}" for action in CODE_ACTIONS}
    candidates = [run for run in runs if
                  run.get("workflow_id") == workflow_id and
                  run.get("head_sha") == head_sha and
                  run.get("event") == "pull_request" and
                  run.get("display_title") in titles and
                  (pr_number is None or any(pr["number"] == pr_number
                                           for pr in run.get("pull_requests", [])))]
    require(candidates, "No code run for this exact merge SHA; rerun CI for the code event")
    return max(candidates, key=lambda run: (run["id"], run.get("run_attempt", 1)))


def check_reused_jobs(jobs):
    matches = [job for job in jobs if job.get("name") == CODE_JOB]
    require(len(matches) == 1 and matches[0].get("conclusion") == "success",
            "Code validation is missing, pending, failed or cancelled; rerun after code CI finishes")


def api(path):
    request = Request(f"{os.environ['GITHUB_API_URL']}/repos/{os.environ['GITHUB_REPOSITORY']}/{path}",
                      headers={"Authorization": f"Bearer {os.environ['GH_TOKEN']}",
                               "Accept": "application/vnd.github+json",
                               "X-GitHub-Api-Version": "2022-11-28"})
    with urlopen(request, timeout=30) as response:
        return json.load(response)


def pages(path, key):
    page = 1
    while True:
        separator = "&" if "?" in path else "?"
        rows = api(f"{path}{separator}per_page=100&page={page}")[key]
        yield from rows
        if len(rows) < 100:
            return
        page += 1


def live_labels(event):
    expected = event["pull_request"]
    pr = api(f"pulls/{expected['number']}")
    require(pr["state"] == "open" and pr["head"]["sha"] == expected["head"]["sha"]
            and pr["base"]["sha"] == expected["base"]["sha"],
            "PR head/base changed during CI; use the current code run")
    return json.dumps([label["name"] for label in pr["labels"]])


def main():
    needs = json.loads(os.environ["NEEDS"])
    event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
    is_pr = os.environ["GITHUB_EVENT_NAME"] == "pull_request"
    label_event = is_pr and event.get("action") in ("labeled", "unlabeled")
    for job in ("detect", "secrets", "dependency-review"):
        expected = "skipped" if job == "dependency-review" and not is_pr else "success"
        require(needs.get(job, {}).get("result") == expected, f"{job} must be {expected}")
    if label_event:
        current = api(f"actions/runs/{os.environ['GITHUB_RUN_ID']}")
        query = urlencode({"event": "pull_request", "head_sha": event["pull_request"]["head"]["sha"]})
        runs = pages(f"actions/workflows/{current['workflow_id']}/runs?{query}", "workflow_runs")
        code_run = select_code_run(runs, workflow_id=current["workflow_id"],
                                   head_sha=event["pull_request"]["head"]["sha"],
                                   merge_sha=os.environ["GITHUB_SHA"],
                                   pr_number=event["pull_request"]["number"])
        check_reused_jobs(list(pages(f"actions/runs/{code_run['id']}/attempts/{code_run['run_attempt']}/jobs", "jobs")))
        print(f"Reusing code validation: {code_run['html_url']}")
    else:
        require(needs.get("code-validation", {}).get("result") == "success", "Code validation did not pass")
    run_policy(event)


def run_policy(event):
    # Labels in the triggering event can be stale after a queued job starts.
    env = os.environ.copy()
    is_pr = os.environ["GITHUB_EVENT_NAME"] in ("pull_request", "pull_request_target")
    if is_pr:
        env["PR_LABELS"] = live_labels(event)
    # Main has already passed human review; pushes validate its current rules.
    base = event["pull_request"]["base"]["sha"] if is_pr else "HEAD"
    command = [sys.executable, "scripts/ci/trusted_policy.py"]
    if os.environ["GITHUB_EVENT_NAME"] == "pull_request_target":
        command += ["--head", event["pull_request"]["head"]["sha"]]
    command += ["--mode", "pr" if is_pr else "push", "--base", base]
    subprocess.run(command, env=env, check=True)


if __name__ == "__main__":
    try:
        if sys.argv[1:] == ["code"]:
            check_code(json.loads(os.environ["NEEDS"]))
        elif sys.argv[1:] == ["policy"]:
            run_policy(json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text()))
        else:
            main()
    except (ValueError, KeyError) as error:
        sys.exit(str(error))
