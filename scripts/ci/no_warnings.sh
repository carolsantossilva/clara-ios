#!/usr/bin/env bash
# Fails if the xcodebuild log has compiler warnings in the project's code.
#
# Replaces SWIFT_TREAT_WARNINGS_AS_ERRORS on the command line: that setting applies
# to every target, remote dependencies included, which Xcode builds with
# -suppress-warnings (the two together are an error). Here only our code counts.
# Usage: no_warnings.sh <xcodebuild-log>
set -euo pipefail

log=$1
root=${GITHUB_WORKSPACE:-$(pwd)}
pattern="^${root}/(App|AppUITests|Packages/ClaraKit/(Sources|Tests))/[^:]+:[0-9]+:[0-9]+: warning: "

warnings=$(grep -E "$pattern" "$log" | sort -u || true)
if [[ -z "$warnings" ]]; then
  echo "No compiler warnings in the project code."
  exit 0
fi

while IFS= read -r line; do
  file=${line%%:*}
  rest=${line#*:}
  lineno=${rest%%:*}
  message=${line#*warning: }
  echo "::error file=${file#"$root"/},line=${lineno}::${message}"
done <<< "$warnings"
echo "$(wc -l <<< "$warnings" | tr -d ' ') compiler warning(s). AI-generated code does not get in with warnings."
exit 1
