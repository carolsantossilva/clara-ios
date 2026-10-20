#!/usr/bin/env python3
"""Policy checks for AI-generated code (and code written by people).

Runs in CI (the "policy" job) and locally (Claude Code Stop hook).

Rules:
  1. Dependencies: every external dependency must be in
     guardrails/allowed-dependencies.txt, and remote Swift packages need an
     exact version (`exact:` or `revision:`). No label exception.
  2. Guardrails: changing a path from guardrails/protected-paths.txt requires
     the "guardrails-change" label.
  3. Suppressions: adding a pattern from guardrails/suppression-patterns.txt
     requires the "guardrail-exception" label.
  4. Tests: lowering the number of tests requires the "guardrail-exception" label.

Usage:
  policy_check.py --mode pr --base <sha>     # PR: rules 1 to 4
  policy_check.py --mode push --base <sha>   # push to main: rule 1 only
  policy_check.py --mode local               # working tree against origin/main (or HEAD)
  policy_check.py --mode staged              # only what is staged (pre-commit hook)

PR labels come from the PR_LABELS variable (a JSON list of names).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EMPTY_TREE = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"
LABEL_GUARDRAILS = "guardrails-change"
LABEL_EXCEPTION = "guardrail-exception"
IN_CI = os.environ.get("GITHUB_ACTIONS") == "true"


@dataclass
class Report:
    errors: list[str] = field(default_factory=list)
    notices: list[str] = field(default_factory=list)

    def error(self, message: str, file: str | None = None, line: int | None = None) -> None:
        self.errors.append(message)
        annotate("error", message, file, line)

    def notice(self, message: str, file: str | None = None, line: int | None = None) -> None:
        self.notices.append(message)
        annotate("warning", message, file, line)


def annotate(level: str, message: str, file: str | None, line: int | None) -> None:
    if not IN_CI:
        return
    location = ""
    if file:
        location = f" file={file}" + (f",line={line}" if line else "")
    print(f"::{level}{location}::{message}")


def git(*args: str) -> str:
    return subprocess.run(
        ["git", *args], cwd=ROOT, check=True, capture_output=True, text=True
    ).stdout


def ref_exists(ref: str) -> bool:
    return subprocess.run(
        ["git", "rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}"],
        cwd=ROOT, capture_output=True,
    ).returncode == 0


def read_list(path: str) -> list[str]:
    lines = (ROOT / path).read_text(encoding="utf-8").splitlines()
    return [line for line in lines if line.strip() and not line.lstrip().startswith("#")]


# ---------------------------------------------------------------- diff


@dataclass
class Diff:
    changed: list[str]
    deleted: list[str]
    added_lines: list[tuple[str, int, str]]  # (file, line, content)


def collect_diff(base: str, local: bool, staged: bool = False) -> Diff:
    # PR/push: base...HEAD. Local: base against the working tree. Staged: base against the index.
    if staged:
        spec = ["--cached", base]
    elif local:
        spec = [base]
    elif base == EMPTY_TREE:
        spec = [EMPTY_TREE, "HEAD"]
    else:
        spec = [f"{base}...HEAD"]

    status = git("diff", "--name-status", "--no-renames", *spec)
    changed, deleted = [], []
    for row in status.splitlines():
        kind, _, path = row.partition("\t")
        (deleted if kind == "D" else changed).append(path)

    added: list[tuple[str, int, str]] = []
    current, line_no = None, 0
    for row in git("diff", "-U0", "--no-renames", *spec).splitlines():
        if row.startswith("+++ "):
            current = row[6:] if row.startswith("+++ b/") else None
        elif row.startswith("@@"):
            match = re.search(r"\+(\d+)", row)
            line_no = int(match.group(1)) if match else 0
        elif row.startswith("+") and current:
            added.append((current, line_no, row[1:]))
            line_no += 1

    if local and not staged:
        for path in git("ls-files", "--others", "--exclude-standard").splitlines():
            changed.append(path)
            try:
                text = (ROOT / path).read_text(encoding="utf-8")
            except (UnicodeDecodeError, OSError):
                continue
            added += [(path, i, line) for i, line in enumerate(text.splitlines(), 1)]

    return Diff(changed=changed, deleted=deleted, added_lines=added)


# ---------------------------------------------------------------- rule 1


SWIFT_PACKAGE = re.compile(r"\.package\(\s*url:\s*\"([^\"]+)\"\s*,\s*(\w+)\s*:")
GEM = re.compile(r"^\s*gem\s+[\"']([^\"']+)[\"']", re.MULTILINE)


def check_dependencies(report: Report) -> None:
    allowed = {tuple(line.split(None, 1)) for line in read_list("guardrails/allowed-dependencies.txt")}
    tracked = git("ls-files", "--cached", "--others", "--exclude-standard").splitlines()

    for path in tracked:
        name = Path(path).name
        if name == "Package.swift":
            text = (ROOT / path).read_text(encoding="utf-8")
            for match in SWIFT_PACKAGE.finditer(text):
                url, requirement = match.group(1).removesuffix(".git"), match.group(2)
                line = text.count("\n", 0, match.start()) + 1
                if ("swift", url) not in allowed:
                    report.error(
                        f"Swift dependency not in the allow-list: {url}. "
                        "Check that the package exists and is the right one, then ask a person "
                        "to add it to guardrails/allowed-dependencies.txt.",
                        path, line,
                    )
                if requirement not in ("exact", "revision"):
                    report.error(
                        f"Use an exact version for {url} (`exact:`), not `{requirement}:`. "
                        "That way no new version gets in without a PR (Dependabot opens them).",
                        path, line,
                    )
        elif name == "Gemfile":
            text = (ROOT / path).read_text(encoding="utf-8")
            for match in GEM.finditer(text):
                if ("gem", match.group(1)) not in allowed:
                    line = text.count("\n", 0, match.start()) + 1
                    report.error(f"Gem not in the allow-list: {match.group(1)}.", path, line)


# ---------------------------------------------------------------- rule 2


def is_protected(path: str, prefixes: list[str]) -> bool:
    return any(path == p or (p.endswith("/") and path.startswith(p)) for p in prefixes)


def check_protected(report: Report, diff: Diff, labels: set[str] | None) -> None:
    prefixes = [line.strip() for line in read_list("guardrails/protected-paths.txt")]
    touched = sorted(p for p in diff.changed + diff.deleted if is_protected(p, prefixes))
    if not touched:
        return
    listing = ", ".join(touched)
    if labels is None:
        report.notice(f"Guardrail files changed (the PR will need the {LABEL_GUARDRAILS} label): {listing}")
    elif LABEL_GUARDRAILS not in labels:
        report.error(
            f"This PR changes guardrail files ({listing}). "
            f"A person needs to review it and add the '{LABEL_GUARDRAILS}' label."
        )


# ---------------------------------------------------------------- rule 3


def suppression_scan_text(text: str) -> str:
    """Ignore leading comment prose while preserving directives and active code."""
    if re.search(r"\b(swiftlint|swiftformat):", text):
        return text
    remaining = text.strip()
    while remaining.startswith("/*"):
        depth, position = 1, 2
        while position < len(remaining) and depth:
            token = remaining[position:position + 2]
            if token == "/*":
                depth += 1
                position += 2
            elif token == "*/":
                depth -= 1
                position += 2
            else:
                position += 1
        if depth:
            return ""
        remaining = remaining[position:].lstrip()
    if remaining.startswith(("//", "*")):
        return ""
    return remaining


def check_suppressions(report: Report, diff: Diff, labels: set[str] | None) -> None:
    patterns = []
    for line in read_list("guardrails/suppression-patterns.txt"):
        regex, _, why = line.partition("\t")
        patterns.append((re.compile(regex), why.strip()))

    prefixes = [line.strip() for line in read_list("guardrails/protected-paths.txt")]
    hits = []
    for path, line_no, text in diff.added_lines:
        if not path.endswith((".swift", ".m", ".h")) or is_protected(path, prefixes):
            continue
        # A comment only counts if it is a directive (e.g. swiftlint:disable); mentioning
        # `@unchecked Sendable` in an explanation turns nothing off.
        scan_text = suppression_scan_text(text)
        for regex, why in patterns:
            if regex.search(scan_text):
                hits.append((path, line_no, why, text.strip()))

    for path, line_no, why, text in hits:
        message = f"Suppression added ({why}): {text}"
        if labels is None:
            report.notice(message, path, line_no)
        elif LABEL_EXCEPTION not in labels:
            report.error(
                f"{message}. Fix the code instead of turning the check off; if the exception is "
                f"really needed, justify it in the PR and a person adds the '{LABEL_EXCEPTION}' label.",
                path, line_no,
            )
        else:
            report.notice(f"{message} (accepted by the {LABEL_EXCEPTION} label)", path, line_no)


# ---------------------------------------------------------------- rule 4


TEST_DECL = re.compile(r"^\s*(@Test\b|func\s+test\w*\s*\()", re.MULTILINE)


def count_tests(tree: str | None) -> int:
    """Counts tests in a commit (tree) or in the working tree (None)."""
    total = 0
    if tree is None:
        files = git("ls-files", "--cached", "--others", "--exclude-standard").splitlines()
        for path in files:
            if path.endswith(".swift") and (ROOT / path).exists():
                total += len(TEST_DECL.findall((ROOT / path).read_text(encoding="utf-8")))
        return total
    if tree == EMPTY_TREE:
        return 0
    for path in git("ls-tree", "-r", "--name-only", tree).splitlines():
        if path.endswith(".swift"):
            total += len(TEST_DECL.findall(git("show", f"{tree}:{path}")))
    return total


def check_test_count(report: Report, base: str, local: bool, labels: set[str] | None) -> None:
    merge_base = base if local or base == EMPTY_TREE else git("merge-base", base, "HEAD").strip()
    before, after = count_tests(merge_base), count_tests(None if local else "HEAD")
    if after >= before:
        return
    message = f"The number of tests went down from {before} to {after}."
    if labels is None:
        report.notice(message)
    elif LABEL_EXCEPTION not in labels:
        report.error(f"{message} Removing tests requires human review and the '{LABEL_EXCEPTION}' label.")


# ---------------------------------------------------------------- main


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=["pr", "push", "local", "staged"], required=True)
    parser.add_argument("--base", default="")
    args = parser.parse_args()

    base = args.base
    if not base or set(base) == {"0"} or not ref_exists(base):
        if args.mode == "staged":
            base = "HEAD" if ref_exists("HEAD") else EMPTY_TREE
        elif args.mode == "local":
            base = "origin/main" if ref_exists("origin/main") else ("HEAD" if ref_exists("HEAD") else EMPTY_TREE)
        else:
            base = EMPTY_TREE

    labels: set[str] | None = None
    if args.mode == "pr":
        labels = set(json.loads(os.environ.get("PR_LABELS") or "[]"))

    report = Report()
    check_dependencies(report)
    if args.mode != "push":
        local = args.mode in ("local", "staged")
        diff = collect_diff(base, local=local, staged=args.mode == "staged")
        check_protected(report, diff, labels)
        check_suppressions(report, diff, labels)
        if args.mode != "staged":
            check_test_count(report, base, local, labels)

    for message in report.notices:
        print(f"warning: {message}", file=sys.stderr)
    for message in report.errors:
        print(f"error: {message}", file=sys.stderr)
    if report.errors:
        print(f"\n{len(report.errors)} policy violation(s).", file=sys.stderr)
        return 1
    print("Policies OK.", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
