#!/usr/bin/env bash
# Run local checks from any working directory. Requires Xcode for iOS code.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

for tests in scripts/guardrails/tests scripts/ci/tests; do
  if [[ -d "$tests" ]]; then
    python3 -B -m unittest discover -s "$tests" -v
  fi
done
python3 scripts/guardrails/policy_check.py --mode local

# The main branch may contain only the repository scaffolding.
if [[ ! -f project.yml && ! -f Packages/ClaraKit/Package.swift ]]; then
  echo "Repository checks passed; no app or Swift package exists to lint or test."
  exit 0
fi

for tool in swiftlint xcodebuild xcrun; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing required tool: $tool. Run iOS validation on a Mac with Xcode and SwiftLint installed." >&2
    exit 1
  fi
done

swiftlint lint --strict
destination="${DESTINATION:-id=$(scripts/ci/simulator.sh)}"

if [[ -f project.yml ]]; then
  if ! command -v xcodegen >/dev/null 2>&1; then
    echo "Missing required tool: xcodegen. Install it with brew install xcodegen." >&2
    exit 1
  fi
  xcodegen generate
  xcodebuild test -project Clara.xcodeproj -scheme Clara \
    -destination "$destination" -skipMacroValidation CODE_SIGNING_ALLOWED=NO
else
  cd Packages/ClaraKit
  xcodebuild test -scheme ClaraKit-Package \
    -destination "$destination" -skipMacroValidation CODE_SIGNING_ALLOWED=NO
fi
