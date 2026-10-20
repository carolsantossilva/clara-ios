# Guardrails for AI-generated code

Much of this repository was written with AI assistance. Instead of trusting generated text, the
repository treats all code as **untrusted until it passes automated checks** that the AI cannot
turn off. The guardrails came **before** the app code: the first commit holds only them, and the
app came in through PRs, going through every barrier.

## Why

- Instructions to the AI ("run the tests", "write secure code") are requests, not guarantees.
- 2025–2026 surveys find more issues, and more security issues, in AI-generated PRs than in
  human ones.
- Typical failures of generated code: dependencies that do not exist (or with a name similar to
  the original, *slopsquatting*), tests that cover code without verifying anything, and "fixing"
  a check by turning the rule off.

## The layers

| # | Layer | Where | What it does | Strength |
|---|---|---|---|---|
| 1 | Instructions | `AGENTS.md`, `CLAUDE.md` | Architecture, product rules, how to work, what never to do | Guides |
| 2 | Claude Code hooks | `.claude/settings.json`, `.claude/hooks/guard.py` | Deny edits to guardrails and commands that bypass checks; ask for confirmation on suppressions; run policies + SwiftLint before stopping | Blocks the local AI |
| 3 | Git hooks | `scripts/git-hooks/pre-commit` | Secrets (gitleaks), policies, SwiftLint on committed files, no commits on `main` | Blocks any local commit |
| 4 | CI | `.github/workflows/` | Policies, secrets in history, dependency review, lint, build with no compiler warnings, unit/snapshot/UI tests, minimum coverage, Maestro flows, CodeQL | Blocks the merge |
| 5 | GitHub | `main` rules, settings | Only PRs with a green "CI OK", no high CodeQL alert, no force push; secret scanning with push protection; Dependabot | Nobody bypasses by accident |
| 6 | Monitoring | Scorecard, Mutation | Public best-practices score; weekly mutation testing on `ClaraCore` | Measures |

### Policies (`scripts/guardrails/policy_check.py`)

| Rule | Without a label | To allow it |
|---|---|---|
| Dependency missing from `guardrails/allowed-dependencies.txt`, or Swift package without an exact version | ❌ fails | A person checks it and edits the list (which is protected) |
| Change to a file in `guardrails/protected-paths.txt` | ❌ fails | Label `guardrails-change` |
| New suppression (`swiftlint:disable`, `@unchecked Sendable`, `try!`, disabled test, re-recorded snapshot...) | ❌ fails | Label `guardrail-exception` + justification in the PR |
| Number of tests went down | ❌ fails | Label `guardrail-exception` |

Labels are a human decision: the hooks stop the AI from adding them.

### Supply chain

- Actions pinned by commit SHA (a tag can be moved to malicious code).
- CI tools downloaded at a fixed version with a checksum (`scripts/ci/install-tools.sh`).
- Read-only `GITHUB_TOKEN`; checkout without stored credentials; `harden-runner` audits network
  traffic on Linux jobs.
- Dependabot waits 14 days before proposing a new version.
- Allow-list of dependencies + exact versions.

## Day to day

```bash
scripts/install-git-hooks.sh       # once per clone
brew install gitleaks swiftlint    # macOS
```

- Work on a branch and open a PR. The merge is always yours.
- To change a guardrail on purpose: edit it yourself, or start Claude Code with
  `CLARA_GUARDRAILS_UNLOCK=1 claude`. The PR will need the `guardrails-change` label.

## Known limits (honesty)

- The Claude Code hooks use heuristics (regular expressions). They catch the common case, not an
  agent determined to get around them. The definitive barrier is CI + the `main` rules.
- With a single person on the repository, approval from someone else cannot be required (GitHub
  does not let you approve your own PR). Safety rests on the required checks and on reading the
  diff, recorded in the PR template.
- Coverage and mutation measure tests, not correctness. The coverage threshold starts
  conservative and only goes up.
- Muter has had no release since 2023; the mutation job is experimental and does not block PRs.
- Snapshot images can differ between Intel (local VM) and Apple Silicon (CI); CI pins the same
  Xcode as the VM and the tests use a precision tolerance.
