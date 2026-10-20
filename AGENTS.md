# Instructions for AI agents

Hooks and CI enforce these rules ([docs/GUARDRAILS.md](docs/GUARDRAILS.md)). Never weaken them.

## The project

Clara is a native iOS app (Swift, iOS 17+) that helps pick a next step, park distractions and
gather personal records for an appointment. The project is generated with XcodeGen
(`project.yml`); the code lives in the local SPM package `Packages/ClaraKit`.

- `ClaraCore` holds models and rules and depends on nothing. `ClaraInfrastructure` contains
  storage, networking, local analytics and on-device AI. `ClaraUI` holds the three features
  and their shared SwiftUI components. Features do not reference another feature's view model.
- Concrete dependencies are only wired in the app (`App/AppEnvironment.swift`, the composition root).
- Every feature uses SwiftUI + MVVM. Views own sheets and confirmation dialogs; view models
  own application state and operations (see `docs/adr/0002`).
- Swift 6 toolchain, language mode 5 with strict concurrency: ViewModels are `@MainActor`,
  shared mutable state lives in an `actor`.
- Code, comments, docs and commits are in English. **User-facing text is in Brazilian Portuguese.**

## Product rules (non-negotiable)

- User data stays **on the device only**. No backend, no cloud, no sending text she wrote.
- Analytics is opt-in and only uses events from the catalog (`ClaraEvent`), **no free text**.
- **No clinical interpretation** and no mood/sentiment analysis.
- AI only on device (Foundation Models), always with a fallback and showing where the suggestion came from.

## How to work

1. **Test first.** For a behavior change, write the failing test, then the code.
   Use Swift Testing and the doubles in `ClaraTestSupport` (`ImmediateClock`, `SteppingNow`...).
   No `sleep`, real network or real date/time in tests.
2. **Small changes.** One PR = one subject. If the change grew, split it.
3. **Run the checks before saying you are done** (the Stop hook runs some of them):
   ```bash
   python3 scripts/guardrails/policy_check.py --mode local
   swiftlint lint --strict
   xcodegen generate && xcodebuild test -project Clara.xcodeproj -scheme Clara \
     -destination 'platform=iOS Simulator,name=iPhone 17' -skipMacroValidation
   ```
4. **Never say something works without running it.** If you could not build or test, say so
   explicitly.

## When a check fails

Fix the code. Do **not** weaken the check. That includes:

- deleting, disabling (`.disabled`, `XCTSkip`) or loosening a test;
- re-recording a snapshot reference to "accept" the change;
- adding `swiftlint:disable`, `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency` or `try!`;
- lowering the coverage threshold or touching any file listed in
  `guardrails/protected-paths.txt`.

If you think the rule is wrong, **stop and explain it to the person**. She decides. The hooks block
these edits and CI rejects PRs with them unless a person adds an exception label.

## Dependencies

Do not add an external dependency on your own. If one is really needed, propose it: name, URL,
why the standard library is not enough, maintainer and latest release. Check that the package
exists and is the original (look-alike names are an attack vector). A person adds it to
`guardrails/allowed-dependencies.txt`. Versions are always exact (`exact:`).

## Git

- Never commit to `main`; create a branch (`feat/…`, `fix/…`, `chore/…`).
- Messages in the imperative mood, in English: `Add period filter to Consultation`.
- Never use `--no-verify` or force push, and never touch labels, rulesets or GitHub settings.
- Opening a PR is allowed; **merging is always human**.
