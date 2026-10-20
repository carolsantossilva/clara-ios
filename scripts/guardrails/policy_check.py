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


def read_list(path: str, staged: bool = False) -> list[str]:
    text = git("show", f":{path}") if staged else (ROOT / path).read_text(encoding="utf-8")
    lines = text.splitlines()
    return [line for line in lines if line.strip() and not line.lstrip().startswith("#")]


# ---------------------------------------------------------------- diff


@dataclass
class Diff:
    touched: list[str]
    added_lines: list[tuple[str, int, str]]  # (file, line, content)
    sources: dict[str, str] = field(default_factory=dict)


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
    touched = []
    for row in status.splitlines():
        _, _, path = row.partition("\t")
        touched.append(path)

    added: list[tuple[str, int, str]] = []
    current, line_no = None, 0
    in_hunk = False
    for row in git("diff", "-U0", "--no-renames", *spec).splitlines():
        if row.startswith("diff --git "):
            current, in_hunk = None, False
        elif not in_hunk and row.startswith("+++ "):
            current = row[6:] if row.startswith("+++ b/") else None
        elif row.startswith("@@"):
            in_hunk = True
            match = re.search(r"\+(\d+)", row)
            line_no = int(match.group(1)) if match else 0
        elif row.startswith("+") and current:
            added.append((current, line_no, row[1:]))
            line_no += 1

    if local and not staged:
        for path in git("ls-files", "--others", "--exclude-standard").splitlines():
            touched.append(path)
            try:
                text = (ROOT / path).read_text(encoding="utf-8")
            except (UnicodeDecodeError, OSError):
                continue
            added += [(path, i, line) for i, line in enumerate(text.splitlines(), 1)]

    sources = {}
    for path in {path for path, _, _ in added if path.endswith((".swift", ".m", ".h"))}:
        try:
            if staged:
                sources[path] = git("show", f":{path}")
            elif local:
                sources[path] = (ROOT / path).read_text(encoding="utf-8")
            else:
                sources[path] = git("show", f"HEAD:{path}")
        except (UnicodeDecodeError, OSError, subprocess.CalledProcessError):
            continue

    return Diff(touched=touched, added_lines=added, sources=sources)


# ---------------------------------------------------------------- rule 1


SWIFT_LITERAL = r'"[^"\\\r\n]+"'
SWIFT_PACKAGE_CALL = re.compile(r"\.\s*package\s*\(")
SWIFT_DECLARATION = re.compile(
    r"\.\s*package\s*\(\s*(?:name\s*:\s*" + SWIFT_LITERAL + r"\s*,\s*)?"
    r"(?:path\s*:\s*" + SWIFT_LITERAL + r"|url\s*:\s*"
    r'"(?P<url>[^"\\\r\n]+)"\s*,\s*(?:exact|revision)\s*:\s*' + SWIFT_LITERAL + r")\s*\)"
)


def block_comment_end(text: str, start: int) -> int:
    position, depth = start + 2, 1
    while position < len(text) and depth:
        if text.startswith("/*", position):
            depth += 1
            position += 2
        elif text.startswith("*/", position):
            depth -= 1
            position += 2
        else:
            position += 1
    return position


def string_token(text: str, start: int, swift: bool = True) -> tuple[int, list[tuple[int, int]]] | None:
    """Return a string end and any executable Swift interpolation ranges."""
    position, hashes = start, 0
    if text[position] == "#":
        while position < len(text) and text[position] == "#":
            hashes += 1
            position += 1
        if position == len(text) or text[position] != '"':
            return None
    elif text[position] not in ('"', "'"):
        return None

    quote = text[position]
    marker = '"""' if quote == '"' and text.startswith('"""', position) else quote
    closing = marker + "#" * hashes
    position += len(marker)
    interpolations = []
    while position < len(text):
        interpolation = "\\" + "#" * hashes + "(" if swift and quote == '"' else ""
        if interpolation and text.startswith(interpolation, position):
            content_start = position + len(interpolation)
            end = interpolation_end(text, content_start)
            if end is not None:
                interpolations.append((content_start, end - 1))
                position = end
            else:
                position = content_start
        elif hashes and text.startswith("\\" + "#" * hashes, position):
            position += hashes + 2
        elif not hashes and text[position] == "\\":
            position += 2
        elif text.startswith(closing, position):
            return position + len(closing), interpolations
        else:
            position += 1
    return len(text), interpolations


def regex_token(text: str, start: int) -> tuple[int, list[tuple[int, int]]] | None:
    """Return a raw Swift regex end and any executable interpolation ranges."""
    if text[start] != "#":
        return None
    position = start
    while position < len(text) and text[position] == "#":
        position += 1
    hashes = position - start
    if position == len(text) or text[position] != "/":
        return None

    position += 1
    closing = "/" + "#" * hashes
    interpolation = "\\" + "#" * hashes + "("
    interpolations = []
    while position < len(text):
        if text.startswith(interpolation, position):
            content_start = position + len(interpolation)
            end = interpolation_end(text, content_start)
            if end is not None:
                interpolations.append((content_start, end - 1))
                position = end
            else:
                position = content_start
        elif text[position] == "\\":
            position += 2
        elif text.startswith(closing, position):
            return position + len(closing), interpolations
        else:
            position += 1
    return len(text), interpolations


def interpolation_end(text: str, start: int) -> int | None:
    position, depth = start, 1
    while position < len(text):
        if text.startswith("//", position):
            end = text.find("\n", position)
            position = len(text) if end < 0 else end
        elif text.startswith("/*", position):
            position = block_comment_end(text, position)
        else:
            token = regex_token(text, position) or string_token(text, position)
            if token:
                position = token[0]
            elif text[position] == "(":
                depth += 1
                position += 1
            elif text[position] == ")":
                depth -= 1
                position += 1
                if not depth:
                    return position
            else:
                position += 1
    return None


def blank(text: str) -> list[str]:
    return ["\n" if char == "\n" else " " for char in text]


def source_views(text: str, swift: bool = True) -> tuple[str, str, str]:
    """Return manifest text, executable code, and comments with offsets preserved."""
    manifest, code = list(text), list(text)
    comments = ["\n" if char == "\n" else " " for char in text]
    position = 0
    while position < len(text):
        if text.startswith("//", position):
            end = text.find("\n", position)
            end = len(text) if end < 0 else end
            comments[position:end] = text[position:end]
            code[position:end] = ["\n" if char == "\n" else " " for char in text[position:end]]
            manifest[position:end] = code[position:end]
            position = end
        elif text.startswith("/*", position):
            start = position
            position = block_comment_end(text, position)
            comments[start:position] = text[start:position]
            masked = blank(text[start:position])
            code[start:position] = masked
            manifest[start:position] = masked
        else:
            token = (regex_token(text, position) if swift else None) or string_token(text, position, swift)
            if token is None:
                position += 1
            else:
                end, interpolations = token
                code[position:end] = blank(text[position:end])
                for start, stop in interpolations:
                    _, inner_code, inner_comments = source_views(text[start:stop], swift)
                    code[start:stop] = list(inner_code)
                    comments[start:stop] = list(inner_comments)
                position = end
    return "".join(manifest), "".join(code), "".join(comments)


GEM_CALL = re.compile(r"^[ \t]*gem\b", re.MULTILINE)
GEM = re.compile(r"^[ \t]*gem[ \t]+(['\"])(?P<name>[^'\"]+)\1(?P<options>[^\n]*)$", re.MULTILINE)
GEM_SOURCE_CALL = re.compile(r"^[ \t]*source\b", re.MULTILINE)
GEM_SOURCE = re.compile(r"^[ \t]*source[ \t]+(['\"])(?P<url>[^'\"]+)\1[^\n]*$", re.MULTILINE)
GEM_IMPORT = re.compile(r"^[ \t]*(?:gemspec|eval_gemfile)\b", re.MULTILINE)
GEM_SOURCE_OVERRIDE = re.compile(r":?(?:git|github|path|source|branch|ref|tag)\s*(?::|=>)")


def check_dependencies(report: Report, staged: bool = False) -> None:
    allowed = {tuple(line.split(None, 1)) for line in read_list("guardrails/allowed-dependencies.txt", staged)}
    tracked = git("ls-files", "--cached", *([] if staged else ["--others", "--exclude-standard"])).splitlines()

    for path in tracked:
        name = Path(path).name
        if name not in ("Package.swift", "Gemfile"):
            continue
        text = git("show", f":{path}") if staged else (ROOT / path).read_text(encoding="utf-8")
        if name == "Package.swift":
            manifest, code, _ = source_views(text)
            for match in SWIFT_PACKAGE_CALL.finditer(code):
                line = text.count("\n", 0, match.start()) + 1
                declaration = SWIFT_DECLARATION.match(manifest, match.start())
                if not declaration:
                    report.error(
                        "Unrecognized Swift declaration: use `.package(path: \"...\")` "
                        "or a literal URL with a literal `exact:`/`revision:` version.", path, line,
                    )
                    continue
                if not declaration.group("url"):
                    continue
                url = declaration.group("url").removesuffix(".git")
                if ("swift", url) not in allowed:
                    report.error(
                        f"Swift dependency not in the allow-list: {url}. "
                        "Check that the package exists and is the right one, then ask a person "
                        "to add it to guardrails/allowed-dependencies.txt.",
                        path, line,
                    )
        else:
            for call in GEM_SOURCE_CALL.finditer(text):
                source = GEM_SOURCE.match(text, call.start())
                line = text.count("\n", 0, call.start()) + 1
                if not source:
                    report.error("Unrecognized Ruby source; use https://rubygems.org.", path, line)
                elif source.group("url") != "https://rubygems.org":
                    report.error(f"Ruby source not allowed: {source.group('url')}.", path, line)

            for match in GEM_IMPORT.finditer(text):
                line = text.count("\n", 0, match.start()) + 1
                report.error("`gemspec` and `eval_gemfile` are not allowed; declare gems directly in the Gemfile.", path, line)

            for call in GEM_CALL.finditer(text):
                match = GEM.match(text, call.start())
                line = text.count("\n", 0, call.start()) + 1
                if not match:
                    report.error("Unrecognized Ruby declaration; declare the gem name literally.", path, line)
                    continue
                name, options = match.group("name"), match.group("options")
                if GEM_SOURCE_OVERRIDE.search(options) or options.rstrip().endswith(","):
                    report.error(f"Source override or continuation is not allowed for gem {name}.", path, line)
                if ("gem", name) not in allowed:
                    report.error(f"Gem not in the allow-list: {name}.", path, line)


# ---------------------------------------------------------------- rule 2


def is_protected(path: str, prefixes: list[str]) -> bool:
    return any(path == p or (p.endswith("/") and path.startswith(p)) for p in prefixes)


def check_protected(report: Report, diff: Diff, labels: set[str] | None) -> None:
    prefixes = [line.strip() for line in read_list("guardrails/protected-paths.txt")]
    touched = sorted(p for p in diff.touched if is_protected(p, prefixes))
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


def check_suppressions(report: Report, diff: Diff, labels: set[str] | None) -> None:
    patterns = []
    for line in read_list("guardrails/suppression-patterns.txt"):
        regex, _, why = line.partition("\t")
        patterns.append((re.compile(regex), why.strip()))

    prefixes = [line.strip() for line in read_list("guardrails/protected-paths.txt")]
    views = {}
    hits = []
    for path, line_no, text in diff.added_lines:
        if not path.endswith((".swift", ".m", ".h")) or is_protected(path, prefixes):
            continue
        # Classify each added line using the complete source for multiline literals.
        if path not in views:
            _, code, comments = source_views(diff.sources.get(path, text), swift=path.endswith(".swift"))
            views[path] = code.splitlines(), comments.splitlines()
        code_lines, comment_lines = views[path]
        index = line_no - 1
        code_line = code_lines[index] if 0 <= index < len(code_lines) else text
        comment_line = comment_lines[index] if 0 <= index < len(comment_lines) else ""
        for regex, why in patterns:
            candidate = comment_line if regex.pattern in {"swiftlint:disable", "swiftformat:disable"} else code_line
            if regex.search(candidate):
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


def is_test_source(path: str) -> bool:
    # shortcut: counts declarations in conventional test paths, not compiler discovery; revisit if targets change.
    parts = Path(path).parts
    return any(part == "Tests" or part.endswith("Tests") for part in parts[:-1]) or Path(path).stem.endswith("Tests")


def count_tests(tree: str | None) -> int:
    """Counts tests in a commit (tree) or in the working tree (None)."""
    total = 0
    if tree is None:
        files = git("ls-files", "--cached", "--others", "--exclude-standard").splitlines()
        for path in files:
            if path.endswith(".swift") and is_test_source(path) and (ROOT / path).exists():
                total += len(TEST_DECL.findall(source_views((ROOT / path).read_text(encoding="utf-8"))[1]))
        return total
    if tree == EMPTY_TREE:
        return 0
    for path in git("ls-tree", "-r", "--name-only", tree).splitlines():
        if path.endswith(".swift") and is_test_source(path):
            total += len(TEST_DECL.findall(source_views(git("show", f"{tree}:{path}"))[1]))
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
    check_dependencies(report, staged=args.mode == "staged")
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
