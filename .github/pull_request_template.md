## What changes and why

<!-- One or two sentences. Link to an issue/ADR if there is one. -->

## How it was verified

<!-- New/changed tests, manual steps, before/after screenshots for UI changes. -->

## Where the code came from

- [ ] Written by a person
- [ ] Generated or edited by AI (tool: ______ ) — and **I read the whole diff** before opening the PR

## Checklist

- [ ] Every behavior change has a test, and the test fails without the change
- [ ] No test was removed, disabled or had its snapshot reference re-recorded without an explanation here
- [ ] No new suppression (`swiftlint:disable`, `@unchecked Sendable`, `try!`...) — or it is justified below
- [ ] No new dependency — or it was checked (exists, is the right package, maintained) and added to `guardrails/allowed-dependencies.txt`
- [ ] Product rules kept: data on device only, analytics without user text, no clinical interpretation
- [ ] Accessibility: VoiceOver and Dynamic Type checked on new screens

## Exceptions

<!-- If the PR needs the guardrail-exception or guardrails-change labels, explain why here. -->
