# ADR 0002 — One presentation architecture per feature, chosen by the problem

**Status:** accepted

## Context

Choosing the right architecture is a matter of trade-offs. In large apps, different patterns commonly live side by side (older code in MVC/VIP, newer code in SwiftUI). Clara's three screens have different needs.

## Decision

| Feature | Pattern | Why |
|---|---|---|
| Today | SwiftUI + **MVVM-C** | Several sheets and flows (create, pause, AI suggestions, privacy). The Coordinator takes navigation out of the ViewModel, which stays testable with a spy router. |
| Records | UIKit View Code + **VIP** | A list with editing and deletion, concurrency rules (revision conflicts) and formatting. VIP separates rules (Interactor), formatting (Presenter) and UI (ViewController), and each part is tested in isolation. It also stands for the "legacy" UIKit part that lives alongside SwiftUI. |
| Consultation | SwiftUI + **MVVM** without a coordinator | A single screen with no navigation. A coordinator here would be ceremony with no gain. |

## Trade-offs

- **VIP:** more files and protocols per screen (boilerplate), but very clear boundaries; good for large teams and rule-heavy screens.
- **MVVM-C:** less ceremony than VIP/VIPER; the risk is the ViewModel growing too much, mitigated with smaller ViewModels per sheet (`StepSuggestionsViewModel`).
- **VIPER:** would add Entity and a more formal Router; for these screens, the gain over VIP would not pay off.
- **MVC:** fine for small screens, but tends to pile everything into the ViewController (the "Massive View Controller").

## Consequences

Newcomers need to know more than one pattern. The rule: the pattern lives inside the feature, and every feature has the same public boundary (a *builder* that takes dependencies and returns a screen).
