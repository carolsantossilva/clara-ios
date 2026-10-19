#!/usr/bin/env bash
# Installs CI tools at a pinned version with a verified checksum.
# Usage: scripts/ci/install-tools.sh xcodegen swiftlint gitleaks maestro
# Updating a version = changing version and checksum together, in a PR with the guardrails-change label.
set -euo pipefail

BIN="${RUNNER_TEMP:-/tmp}/tools/bin"
mkdir -p "$BIN"
WORK="$(mktemp -d)"
os="$(uname -s)"
EXTRA_PATHS=()

fetch() { # url sha256 file
  curl -fsSL --retry 3 -o "$WORK/$3" "$1"
  echo "$2  $WORK/$3" | shasum -a 256 -c - >/dev/null
  echo "✓ checksum ok: $3"
}

for tool in "$@"; do
  case "$tool:$os" in
    xcodegen:Darwin)
      fetch https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip \
        4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806 xcodegen.zip
      unzip -q "$WORK/xcodegen.zip" -d "$WORK/xcodegen-dist"
      # No symlink: XcodeGen finds its presets (share/) from the executable's path;
      # through a link, it generates targets without PRODUCT_NAME.
      mv "$WORK/xcodegen-dist/xcodegen" "${RUNNER_TEMP:-/tmp}/tools/xcodegen"
      EXTRA_PATHS+=("${RUNNER_TEMP:-/tmp}/tools/xcodegen/bin") ;;
    swiftlint:Darwin)
      fetch https://github.com/realm/SwiftLint/releases/download/0.65.1/portable_swiftlint.zip \
        c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0 swiftlint.zip
      unzip -qo "$WORK/swiftlint.zip" swiftlint -d "$BIN" ;;
    gitleaks:Linux)
      fetch https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz \
        551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb gitleaks.tar.gz
      tar -xzf "$WORK/gitleaks.tar.gz" -C "$BIN" gitleaks ;;
    maestro:Darwin)
      fetch https://github.com/mobile-dev-inc/Maestro/releases/download/cli-2.10.0/maestro.zip \
        29b675e10cc12080e445e9bfb2e2b4e4dfb9c0f2e30d5884120d258b5e1cd991 maestro.zip
      unzip -q "$WORK/maestro.zip" -d "${RUNNER_TEMP:-/tmp}/tools"
      EXTRA_PATHS+=("${RUNNER_TEMP:-/tmp}/tools/maestro/bin") ;;
    *) echo "No pinned version of $tool for $os" >&2; exit 1 ;;
  esac
done

if [[ -n "${GITHUB_PATH:-}" ]]; then
  echo "$BIN" >> "$GITHUB_PATH"
  # Form compatible with macOS bash 3.2, which treats an empty array as unset.
  for dir in ${EXTRA_PATHS[@]+"${EXTRA_PATHS[@]}"}; do echo "$dir" >> "$GITHUB_PATH"; done
fi
echo "Tools in $BIN"
