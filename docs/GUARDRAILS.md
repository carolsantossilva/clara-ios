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
| 4 | CI | `.github/workflows/` | Conventional Commits PR title, policies, secrets in history, dependency review, lint, build with no compiler warnings, unit/snapshot/UI tests, minimum coverage, Maestro flows, CodeQL | Blocks the merge |
| 5 | GitHub | `main` rules, settings | Only PRs with a green "CI OK", no high CodeQL alert, no force push; secret scanning with push protection; Dependabot | Nobody bypasses by accident |
| 6 | Monitoring | Scorecard, Mutation | Public best-practices score; weekly mutation testing on `ClaraCore` | Measures |

### Policies (`scripts/guardrails/policy_check.py`)

| Rule | Without a label | To allow it |
|---|---|---|
| Dependency missing from `guardrails/allowed-dependencies.txt`, or Swift package without an exact version | ❌ fails | A person checks it and edits the list (which is protected) |
| Change to a file in `guardrails/protected-paths.txt` | ❌ fails | Label `guardrails-change` |
| New suppression (`swiftlint:disable`, `@unchecked Sendable`, `try!`, disabled test, re-recorded snapshot...) | ❌ fails | Label `guardrail-exception` + justification in the PR |
| Number of tests went down | ❌ fails | Label `guardrail-exception` |

In CI, only root-level Markdown changes or prose and raster images under `docs/` may skip
Maestro. Any other unknown path keeps the flows enabled. PRs run every flow except those
tagged `full`; untagged flows remain in the smoke suite. The weekly run and
`workflow_dispatch` run the full suite. New flows therefore enter the smoke suite
automatically and leave it only when someone explicitly marks them `full`.
`full` flows can fail without blocking a PR, so a failure may only appear in the manual
release validation; run `workflow_dispatch` before a release to validate the full suite.

Labels are a human decision: the hooks stop the AI from adding them.

When labels are added or removed, CI reevaluates policies with the current labels without
rerunning macOS jobs. "CI OK" requires code validation from the same workflow, PR and
merge commit; failed, cancelled or pending results do not count. Label changes do not
cancel code validation in progress. If no valid validation exists, rerun the code event
(`opened`/`synchronize`/`reopened`), or wait for it to finish and rerun the label event.
Before approving a result, each run checks the current labels again so it cannot accept
an exception removed during testing.

### Trusted policy source

CI runs the Python checker and reads rule lists from the base revision, never from the
proposal. It reads proposed manifests and diffs as Git data without checking out,
building or importing proposed files during policy evaluation. Clearing the protection
list or replacing the checker in a PR does not change that evaluation.

The same applies to the dependency list: a human must first approve and merge a PR that
updates the list; only then can a PR use the new library. The `guardrails-change` label
allows a protected-file change but does not allow dependencies missing from the base list.

The `trusted-policy.yml` workflow, triggered by `pull_request_target`, uses only base
code and a read-only token. It fetches proposed Git objects without checking out the
proposal and checks current labels before evaluating policy. Builds and tests remain in
the `pull_request` event, outside that context. See [GitHub's security guidance](https://docs.github.com/en/actions/reference/security/securely-using-pull_request_target).

**Limit:** the regular workflow and the `CI OK` check name can still be changed in a PR.
To make independent evaluation a required barrier against hostile workflows, a person
must configure an external rule requiring the trusted workflow. A required check by
name alone does not prove its origin. This change does not alter rulesets, labels or
GitHub settings.

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
