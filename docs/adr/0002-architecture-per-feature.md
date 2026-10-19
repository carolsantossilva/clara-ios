# ADR 0002 — SwiftUI and MVVM for every feature

**Status:** accepted (replaces the original mixed presentation architectures)

## Context

The original app combined MVVM-C, UIKit with VIP and plain MVVM. Three presentation patterns made a small application harder to follow and required routing protocols and wiring tests without corresponding product complexity.

## Decision

All screens use SwiftUI and MVVM:

- Views own presentation state: sheets, confirmation dialogs, input drafts and focus duration preferences.
- Observable view models isolated to MainActor own loaded data and asynchronous operations.
- Repositories and platform services are injected, so behavior is tested without rendering screens.
- Operations return success when a form should close. The view decides how to dismiss it.

The focus duration is selected locally, rather than assigned through an experiment. Remote config, installation bucketing and simulated Objective-C legacy integrations have been removed.

## Consequences

There are no feature coordinators, routers, VIP cycles or UIKit view controllers. UIKit remains an implementation detail of the system PDF renderer and dynamic color resolution; it is not a presentation architecture.

Tests exercise observable behavior, persistence and failure handling. SwiftUI snapshots replace the former UIKit screen snapshots, retaining light, dark and accessibility text coverage.
