# Clara — native iOS

Clara helps you pick a next step, park distractions and gather personal records to bring to an appointment. This is the **native Swift** version of the app I started in React Native (`daily-focus`), rewritten as if it were part of a large app: modular, tested and with CI.

> Privacy is a product requirement: tasks and records stay **on the device only** (a file with iOS data protection). The AI runs on the device. Analytics is opt-in and never sends text written by the user.

The app's interface is in Brazilian Portuguese; code and docs are in English.

## Features

| Tab | What it does | Architecture |
|---|---|---|
| **Hoje** (Today) | Task in focus, focus timer (A/B test 15/25 min), "pause and leave a hint", "this can wait", **small-step suggestions with AI** and holiday notice (BrasilAPI) | SwiftUI + **MVVM-C** |
| **Registros** (Records) | Daily check-in and one-off moments, edit/delete, timeline | UIKit **View Code** + **VIP** |
| **Consulta** (Consultation) | Pick a period and records, faithful preview and **PDF** export | SwiftUI + **MVVM** |

## Running it (Mac)

```bash
brew install xcodegen swiftlint
cd clara-ios
xcodegen generate        # generates Clara.xcodeproj from project.yml
open Clara.xcodeproj
```

Pick an iPhone simulator and run (⌘R). Tests: ⌘U.

- **Snapshot tests:** the first run records the reference images in `Packages/ClaraKit/Tests/SnapshotTests/__Snapshots__` and **fails on purpose**. Run again and they pass. Commit the images.
- **On-device AI:** needs iOS 26 + a device with Apple Intelligence (an Apple Silicon Mac with Apple Intelligence on, or iPhone 15 Pro or newer). On an Intel Mac/VM, the app automatically uses the simple suggestions (NaturalLanguage) and says so on screen.
- **Remote config:** the app reads `config/remote-config.json` straight from this GitHub repository. Offline, it uses the last cached value or the bundled defaults.
- If your XcodeGen version does not accept the package tests in the scheme, run them directly: `cd Packages/ClaraKit && xcodebuild test -scheme ClaraKit-Package -destination 'platform=iOS Simulator,name=iPhone 17'`.

Fastlane: `bundle install`, then `bundle exec fastlane lint` or `bundle exec fastlane test`.

End-to-end flows with [Maestro](https://maestro.dev), with the app installed on a simulator: `maestro test .maestro`.

## Guardrails for AI-generated code

This project was written with AI assistance. Before any app code, the repository got automated
checks the AI cannot turn off: Claude Code hooks, a pre-commit hook, CI with policies, secrets,
lint, tests, coverage, Maestro and CodeQL, and rules on the `main` branch.
Details in [docs/GUARDRAILS.md](docs/GUARDRAILS.md).

```bash
scripts/install-git-hooks.sh   # once per clone
```

## Structure

```
App/                      App target: composition root, tabs, privacy panel, MetricKit
AppUITests/               UI tests (XCUITest)
Packages/ClaraKit/        Local SPM package with every module
  Sources/
    ClaraCore/            Models (structs), repository protocols, summary and HTML (pure)
    ClaraStorage/         Local database (actor) + repositories
    ClaraNetworking/      Generic REST client (Endpoint with associatedtype, retry, errors)
    ClaraServices/        Feature flags/A-B, remote config, analytics, crash reporting, holidays
    ClaraAI/              Foundation Models (on-device) + NaturalLanguage fallback
    ClaraLegacy/          "Legacy" Objective-C (formatter and a store with completion handlers)
    ClaraDesignSystem/    Tokens (light/dark), typography with Dynamic Type, components
    TodayFeature/         SwiftUI + MVVM-C
    RecordsFeature/       UIKit View Code + VIP
    ConsultationFeature/  SwiftUI + MVVM, PDF export
    ClaraTestSupport/     Test doubles shared across suites
  Tests/                  Swift Testing + snapshot tests
config/remote-config.json Remote config served by GitHub
docs/                     Guardrails and ADRs
```

Dependency graph (features do not know each other; everything points to `ClaraCore`):

```
                 App (composition root)
        ┌───────────┼──────────────┬──────────────┐
  TodayFeature  RecordsFeature  ConsultationFeature  ClaraStorage
     │  │  │         │               │                 │
     │  │  └──── ClaraDesignSystem ──┘                 │
     │  └── ClaraAI                                    │
     └──────── ClaraServices ── ClaraNetworking        │
                 │      └── ClaraLegacy (ObjC)         │
                 └──────────── ClaraCore ◀─────────────┘
```

## Documentation

- [Guardrails for AI-generated code](docs/GUARDRAILS.md)
- Architecture decisions: [modularization](docs/adr/0001-modularization-spm-xcodegen.md) · [one architecture per feature](docs/adr/0002-architecture-per-feature.md) · [on-device AI](docs/adr/0003-on-device-ai.md) · [guardrails for AI](docs/adr/0004-guardrails-for-ai-generated-code.md)
