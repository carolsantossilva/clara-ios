#!/usr/bin/env python3
"""Claude Code hooks for this repository.

  guard.py edit   PreToolUse (Edit|Write|MultiEdit|NotebookEdit)
                  - denies edits to guardrail files
                  - asks a person to confirm edits that add suppressions (swiftlint:disable, try!, ...)
  guard.py bash   PreToolUse (Bash)
                  - denies commands that bypass the guardrails (--no-verify, force push,
                    push to main, changing rulesets/labels through gh, writing to protected files)
  guard.py stop   Stop
                  - runs the policies and SwiftLint before the AI ends the task

A person unlocks guardrail edits by starting Claude Code with
CLARA_GUARDRAILS_UNLOCK=1. The AI cannot set that variable: the hooks run in the
Claude Code process environment, not in the Bash tool's shell.

These hooks are the first barrier and use heuristics. The definitive barrier is CI
with the main branch rules on GitHub.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(os.environ.get("CLAUDE_PROJECT_DIR") or Path(__file__).resolve().parents[2])
UNLOCKED = os.environ.get("CLARA_GUARDRAILS_UNLOCK") == "1"


def read_list(name: str) -> list[str]:
    path = ROOT / "guardrails" / name
    if not path.exists():
        return []
    lines = path.read_text(encoding="utf-8").splitlines()
    return [line for line in lines if line.strip() and not line.lstrip().startswith("#")]


PROTECTED = [line.strip() for line in read_list("protected-paths.txt")]


def relative(path: str) -> str:
    try:
        return str(Path(path).resolve().relative_to(ROOT.resolve()))
    except ValueError:
        return path


def is_protected(path: str) -> bool:
    rel = relative(path)
    return any(rel == p or (p.endswith("/") and rel.startswith(p)) for p in PROTECTED)


def decide(decision: str, reason: str) -> None:
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": decision,
            "permissionDecisionReason": reason,
        }
    }))
    sys.exit(0)


# ---------------------------------------------------------------- edit


def new_text(tool_input: dict) -> str:
    parts = [tool_input.get("content", ""), tool_input.get("new_string", ""), tool_input.get("new_source", "")]
    parts += [edit.get("new_string", "") for edit in tool_input.get("edits", []) or []]
    return "\n".join(p for p in parts if p)


def old_text(tool_input: dict) -> str:
    parts = [tool_input.get("old_string", "")]
    parts += [edit.get("old_string", "") for edit in tool_input.get("edits", []) or []]
    return "\n".join(p for p in parts if p)


def on_edit(payload: dict) -> None:
    tool_input = payload.get("tool_input", {})
    path = tool_input.get("file_path") or tool_input.get("notebook_path") or ""

    if path and is_protected(path) and not UNLOCKED:
        decide("deny", (
            f"{relative(path)} is part of the project's guardrails (guardrails/protected-paths.txt). "
            "Do not change checks to make something pass: fix the code. If the rule is wrong, "
            "explain why to the person and stop; she decides and unlocks the edit."
        ))

    if not path.endswith((".swift", ".m", ".h")):
        return
    added, removed = new_text(tool_input), old_text(tool_input)
    found = []
    for line in read_list("suppression-patterns.txt"):
        regex, _, why = line.partition("\t")
        pattern = re.compile(regex)
        if len(pattern.findall(added)) > len(pattern.findall(removed)):
            found.append(why.strip())
    if found:
        decide("ask", (
            "This edit adds suppressions: " + "; ".join(found) + ". "
            "Prefer fixing the cause. If the suppression is needed, the person has to approve it, "
            "and the PR will require the guardrail-exception label."
        ))


# ---------------------------------------------------------------- bash


BASH_RULES = [
    (r"--no-verify\b|\bgit\s+commit\b[^|;&]*\s-n\b", "skipping git hooks (--no-verify) bypasses the secrets check"),
    (r"\bgit\s+push\b[^|;&]*(\s-f\b|--force\b|--force-with-lease\b|\s\+\S)", "force push rewrites history"),
    (r"\bgit\s+push\b[^|;&]*\s(\S+:)?(refs/heads/)?main\b", "direct push to main: all code goes through a PR"),
    (r"\bgit\s+config\b[^|;&]*core\.hooksPath", "changing core.hooksPath turns off the git hooks"),
    (r"\bgit\s+(update-ref|filter-branch|filter-repo|replace)\b", "rewriting refs or history"),
    (r"\bgh\s+pr\s+merge\b[^|;&]*--admin", "merging with --admin ignores the branch rules"),
    (r"\bgh\s+pr\s+merge\b", "merging is a human decision"),
    (r"\bgh\s+pr\s+(edit|create)\b[^|;&]*--(add-)?label\b", "exception labels are a human decision"),
    (r"\bgh\s+(label|secret|variable|ruleset|repo\s+edit|repo\s+delete|workflow\s+disable)\b", "repository settings are a human decision"),
    (r"\bgh\s+api\b[^|;&]*(rulesets|protection|labels|/secrets|/variables|/hooks|security_and_analysis)", "repository settings are a human decision"),
    (r"\bgh\s+api\b[^|;&]*(-X|--method)\s*(PUT|PATCH|DELETE)", "writing through the GitHub API is a human decision"),
    (r"\brm\s+-[a-zA-Z]*r[a-zA-Z]*f?\s+(/|~|\$HOME)(\s|$)", "deleting the root or home folder"),
    (r"(curl|wget)\b[^|;&]*\|\s*(ba|z)?sh\b", "downloading and running a script without checking it"),
]

WRITE_VERBS = re.compile(
    r"(\btee\b|\bsed\s+[^|;&]*-i|\bperl\s+[^|;&]*-i|\bmv\b|\bcp\b|\brm\b|\bchmod\b|\btruncate\b|"
    r"\bgit\s+(checkout\s+[^|;&]*--|restore|rm|mv)\b|\bln\b|\bdd\b|open\([^)]*['\"]w)"
)


def on_bash(payload: dict) -> None:
    command = payload.get("tool_input", {}).get("command", "")
    for regex, why in BASH_RULES:
        if re.search(regex, command):
            if UNLOCKED and "human decision" in why:
                continue
            decide("deny", f"Command blocked by the guardrails: {why}.")

    if UNLOCKED:
        return
    has_verb = bool(WRITE_VERBS.search(command))
    for prefix in PROTECTED:
        path = re.escape(prefix.rstrip("/")) + r"(/|\b)"
        redirect = re.search(r">>?\s*['\"]?(\./)?" + path, command)
        mention = has_verb and re.search(r"(^|[\s'\"/=])" + path, command)
        if redirect or mention:
            decide("deny", (
                f"The command seems to write to {prefix}, which is part of the guardrails. "
                "Do not change checks to make something pass: fix the code or ask the person."
            ))


# ---------------------------------------------------------------- stop


def on_stop(payload: dict) -> None:
    if payload.get("stop_hook_active"):
        sys.exit(0)  # already blocked once in this sequence; avoids a loop
    failures = []

    policy = subprocess.run(
        [sys.executable, str(ROOT / "scripts/guardrails/policy_check.py"), "--mode", "local"],
        cwd=ROOT, capture_output=True, text=True,
    )
    if policy.returncode != 0:
        failures.append("Policies:\n" + policy.stderr.strip())

    swiftlint = shutil.which("swiftlint")
    if swiftlint and (ROOT / ".swiftlint.yml").exists():
        lint = subprocess.run([swiftlint, "lint", "--strict", "--quiet"], cwd=ROOT, capture_output=True, text=True)
        if lint.returncode != 0:
            errors = [line for line in lint.stdout.splitlines() if ": error:" in line]
            failures.append("SwiftLint:\n" + "\n".join(errors[:30]))

    if failures:
        print(json.dumps({
            "decision": "block",
            "reason": "The local checks failed. Fix them before stopping "
                      "(without turning rules off):\n\n" + "\n\n".join(failures),
        }))
    sys.exit(0)


def main() -> None:
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    payload = json.load(sys.stdin)
    {"edit": on_edit, "bash": on_bash, "stop": on_stop}.get(mode, lambda _: None)(payload)


if __name__ == "__main__":
    main()
