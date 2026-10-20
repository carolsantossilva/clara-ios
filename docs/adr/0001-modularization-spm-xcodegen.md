# ADR 0001 — Three modules in a local SPM package

**Status:** accepted (revised after reviewing the portfolio scope)

## Context

Clara has three tabs maintained by one person. The original target-per-feature and target-per-service structure imposed public APIs and build configuration for small pieces of code.

## Decision

Use three production targets in `Packages/ClaraKit`:

- `ClaraCore`: models, repository contracts and pure report rules. No dependencies.
- `ClaraInfrastructure`: persistence, networking, local analytics and on-device suggestions. Depends on Core.
- `ClaraUI`: SwiftUI screens, their view models and shared visual components. Depends on Core and Infrastructure.

The app assembles concrete dependencies. `ClaraTestSupport` shares fixtures and doubles between test suites. Existing suite names remain stable so the project scheme and CI continue to run them.

XcodeGen still generates the project from `project.yml`.

## Consequences

The module graph expresses domain, platform implementation and presentation boundaries. Feature folders organize the UI without requiring a separate library for every screen. A feature does not reach into another feature's view model.

The compiler no longer enforces feature isolation. That is a deliberate trade-off for this project's size, reviewed through normal code review. More targets can be introduced if a concrete ownership or build-time need develops.
