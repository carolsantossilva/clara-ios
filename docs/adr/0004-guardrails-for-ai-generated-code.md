# ADR 0004 — Automated guardrails for AI-generated code

**Status:** accepted

## Context

The app was written with heavy AI assistance, by one person, on a short deadline. AI-generated
code tends to have more issues (security included), may suggest dependencies that do not exist
and, faced with a failing check, often "fixes" it by loosening the rule. Human review alone does
not scale to the volume of generated code.

## Decision

- **Guardrails before code:** the first commit holds only the checks; the app comes in through PRs.
- **Layered deterministic checks:** Claude Code hooks → git hooks → CI → GitHub rules on `main`.
  Instructions in `AGENTS.md` guide, but they are not the guarantee.
- **The guardrails protect themselves:** the AI does not edit guardrail files (hook), changes to
  them require a human label (CI) and go through the owner (CODEOWNERS).
- **Explicit exceptions:** suppressions and test removals are not forbidden, but they require a
  recorded human decision (label + justification in the PR).
- **Closed supply chain:** allow-list of dependencies, exact versions, actions pinned by SHA,
  tools verified by checksum.

## Alternatives

- **Human review only:** does not scale and fails exactly where review is tedious (lock files,
  workflows, tests).
- **Prompt/AGENTS.md instructions only:** the AI sometimes ignores them; there is no way to audit.
- **Commercial AI review tools as a gate:** useful as a second opinion, but probabilistic; they do
  not replace deterministic checks.

## Consequences

- More friction for guardrail changes (on purpose).
- Slower CI (macOS runners); mitigated by skipping jobs that do not apply and cancelling stale runs.
- Documents, verifiably, how AI was used responsibly in the project.
