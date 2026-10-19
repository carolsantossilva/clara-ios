# Review instructions

Instructions for reviewing pull requests in this repository, read by Claude Code Review
and meant as the checklist for human reviewers too. Project context and rules live in
`AGENTS.md`; this file only says what to flag, how severely, and what to skip.

## What Important means here

Reserve Important for findings that would:

- send user data off the device: network calls with task or record content, user text in
  analytics properties, logs (`privacy: .public`) or crash reports;
- interpret the user clinically: mood or sentiment analysis, diagnoses, advice;
- break behavior or lose data: wrong logic, a write that ignores the revision check
  (`StorageError.conflict`), a missing `await` on actor state, UI state updated off the
  main actor;
- weaken a check without saying so: a test that asserts nothing, a test changed to match
  new behavior without explaining why, a snapshot reference re-recorded, a threshold or
  guardrail loosened;
- hide information from VoiceOver or Dynamic Type users on a new or changed screen.

Style, naming and refactoring suggestions are Nit at most.

## Cap the nits

Report at most five Nits per review.

## Always check

- Every behavior change has a test, and the test would fail without the change.
- A feature does not import another feature; concrete types are only wired in
  `App/AppEnvironment.swift`.
- The change follows the pattern of the feature it touches: Today is MVVM-C, Records is
  VIP, Consultation is MVVM (`docs/adr/0002-architecture-per-feature.md`).
- AI suggestions keep a fallback and show where they came from.
- New user-facing text is in Brazilian Portuguese; code, comments and docs are in English.
- New interactive elements have an accessibility label, and text uses Dynamic Type styles.
- Tests use the doubles in `ClaraTestSupport`: no `sleep`, real network or real date/time.

## Do not report

- What CI already enforces: SwiftLint, compiler warnings, coverage threshold, secrets,
  dependency allow-list, suppressions and test count (`scripts/guardrails/policy_check.py`).
- Snapshot reference images under `__Snapshots__/`.
- The generated `Clara.xcodeproj` and `App/Info.plist` (not in git; `project.yml` is).
- Portuguese strings in tests that mirror the UI or are test data.

## Evidence

Claims about behavior need a `file:line` citation in the source, not an inference from a
name. For a concurrency finding, name the actor or isolation domain involved.
