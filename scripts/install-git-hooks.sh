#!/usr/bin/env bash
# Ativa os hooks versionados em scripts/git-hooks.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
git config core.hooksPath scripts/git-hooks
chmod +x scripts/git-hooks/*
echo "Hooks do git ativados (scripts/git-hooks)."
