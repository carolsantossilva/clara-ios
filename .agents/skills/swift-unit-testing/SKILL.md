---
name: swift-unit-testing
description: Use when writing, reviewing, or debugging unit and component tests for this Swift/iOS project with Swift Testing. Not for UI or snapshot test design.
---

# Swift Unit Testing

Use the existing ClaraKit testing patterns to make behavior failures deterministic and easy to diagnose.

## Before writing tests

- Inspect the package targets and nearby tests. Put tests in the target that owns the behavior, and follow that target's existing conventions.
- Prefer tests of observable results, thrown errors, state changes, and relevant side effects over checks of private implementation details.

## ClaraKit patterns

- Use Swift Testing (`@Suite`, `@Test`, `#expect`, `#require`, and `#expect(throws:)`) for new tests. Keep each test focused on one behavior and give it a descriptive name.
- Reuse suitable doubles from `ClaraTestSupport`. Keep a helper in its suite while it is local; extract it when multiple suites need it.
- Make mutable state in async test doubles actor-isolated. Inject the dependency being replaced, such as `URLSessionProtocol`; avoid global stubs that require serializing otherwise independent tests.
- Keep time deterministic: use fixed dates for static values and inject `Clock` or the project's time provider when behavior depends on time. Use `ImmediateClock` for retries and `SteppingNow` for advancing timestamps. Do not use `.now`, `Date()`, `Task.sleep`, or real-time waits in deterministic tests.
- For timeout tests, make the operation respond to cancellation and coordinate completion through a test double. Do not leave a spinning child task behind after the timeout.
- Do not make live network requests. Use the session protocol and a fake response. Use an in-memory `LocalDatabase` for repository behavior; use a unique temporary file only when testing persistence across close and reopen.
- For failure paths, use an existing failing repository when it expresses the intended failure. Assert user-visible state and meaningful side effects—for example, that a failed save keeps its draft available and does not record a success event.

## Scope

This skill covers Swift unit and component tests in ClaraKit. Follow the feature's established test target and patterns for feature behavior. Use a separate workflow for UI automation, view rendering, or snapshot tests.
