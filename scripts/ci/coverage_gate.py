#!/usr/bin/env python3
"""Fails if the modules' line coverage drops below the minimum.

Usage: coverage_gate.py <Result.xcresult>
Reads the minimum, the ignored targets and the ignored files from guardrails/thresholds.json.
"""
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
config = json.loads((ROOT / "guardrails/thresholds.json").read_text())
minimum = config["min_line_coverage"]
excluded = set(config.get("coverage_excluded_targets", []))
excluded_files = set(config.get("coverage_excluded_files", []))

report = json.loads(subprocess.run(
    ["xcrun", "xccov", "view", "--report", "--json", sys.argv[1]],
    check=True, capture_output=True, text=True,
).stdout)

# Static package code can be attributed to a test bundle instead of its library.
# Classify our production files by path, independently of the binary that holds them.
sources = ROOT / "Packages/ClaraKit/Sources"
production = {}
for target in report.get("targets", []):
    for file in target.get("files", []):
        path = Path(file["path"]).resolve()
        if path.is_relative_to(ROOT / "App"):
            module = "Clara"
        elif path.is_relative_to(sources):
            module = path.relative_to(sources).parts[0]
        else:
            continue  # Tests, generated code and external dependencies do not count.
        if module in excluded or file["name"] in excluded_files:
            continue
        previous = production.get(path, (module, 0, 0))
        # A static library may appear in several bundles. Count each source once;
        # maxima retain a conservative coverage estimate without adding copies.
        production[path] = (module, max(previous[1], file["coveredLines"]),
                            max(previous[2], file["executableLines"]))

modules = {}
for module, file_covered, file_executable in production.values():
    counts = modules.setdefault(module, [0, 0])
    counts[0] += file_covered
    counts[1] += file_executable
covered = sum(counts[0] for counts in modules.values())
executable = sum(counts[1] for counts in modules.values())
rows = [(module, counts[0] / counts[1] if counts[1] else 0.0)
        for module, counts in modules.items()]

if excluded_files:
    print(f"Files left out: {', '.join(sorted(excluded_files))}")
for name, value in sorted(rows):
    print(f"  {name:<28} {value:6.1%}")
if executable == 0:
    sys.exit("No covered code lines found in the report.")
total = covered / executable
print(f"Total coverage: {total:.1%} (minimum {minimum:.0%})")
if total < minimum:
    print(f"::error::Coverage {total:.1%} is below the {minimum:.0%} minimum. Write tests; do not lower the threshold.")
    sys.exit(1)
