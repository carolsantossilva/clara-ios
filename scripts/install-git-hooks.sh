#!/usr/bin/env bash
# Enables the versioned hooks in scripts/git-hooks.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
git config core.hooksPath scripts/git-hooks
chmod +x scripts/git-hooks/*
echo "Git hooks enabled (scripts/git-hooks)."
