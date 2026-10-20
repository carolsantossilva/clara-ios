#!/usr/bin/env python3
"""Choose whether Maestro is needed and which flow tags to include."""
import argparse
import subprocess
import sys

DOC_EXTENSIONS = {".md", ".rst", ".txt", ".png", ".jpg", ".jpeg", ".gif", ".webp"}


def is_documentation(path):
    from pathlib import PurePosixPath

    parsed = PurePosixPath(path)
    parts = parsed.parts
    if parts[0] in (".github", ".maestro", "App", "Packages", "Resources", "scripts"):
        return False
    if len(parts) == 1:
        return parsed.suffix.lower() == ".md"
    return parts[0] == "docs" and parsed.suffix.lower() in DOC_EXTENSIONS


def mode_for(event, paths):
    if event in ("schedule", "workflow_dispatch"):
        return "full"
    if event == "pull_request" and paths and all(is_documentation(path) for path in paths):
        return "skip"
    return "smoke"


def changed_paths(base, head):
    try:
        result = subprocess.run(
            ["git", "diff", "--name-only", "-z", "--no-renames", base, head, "--"],
            check=True, capture_output=True, text=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return []
    return result.stdout.split("\0")[:-1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--event", required=True)
    parser.add_argument("--base", default="")
    parser.add_argument("--head", default="")
    args = parser.parse_args()
    paths = changed_paths(args.base, args.head) if args.base and args.head else []
    print(mode_for(args.event, paths))


if __name__ == "__main__":
    sys.exit(main())
