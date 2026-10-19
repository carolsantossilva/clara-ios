# ADR 0003 — On-device generative AI, with a fallback and no clinical interpretation

**Status:** accepted

## Context

Starting a task is the hard part for Clara's users. The original product proposal left "AI to break down tasks" for later for two reasons: privacy (tasks may contain health information) and the risk of the app appearing to give clinical advice.

## Decision

- Suggest **2 to 4 small steps** for the task in focus, **only when the user asks**. She picks a step, which becomes the "next step", or closes without choosing.
- Main provider: **Foundation Models** (iOS 26), Apple's **on-device** model. It uses `@Generable` (guided generation) to get the answer as a struct, without parsing free text.
- Fallback: `HeuristicStepSuggester` with **NaturalLanguage** (also on device), used when the model is unavailable, fails or takes longer than 8 seconds (`FallbackStepSuggester` + `withTimeout`).
- The screen shows where the suggestion came from (transparency).
- We do **not** run sentiment analysis on records. It would be possible with NaturalLanguage, but it would be "automatic mood interpretation", explicitly out of the product's scope.

## Alternatives

- **Cloud LLM (API):** better answers and works on any device, but the text would leave the device, it would require explicit consent and a backend to avoid shipping the API key in the app. It remains possible in the future as one more provider behind the same `StepSuggesting` protocol.
- **Core ML with a custom model:** full control, but requires a dataset, training and model maintenance, with no clear gain for this task.

## Consequences

- On devices without Apple Intelligence the experience is simpler, but it never breaks.
- Swapping or adding providers does not change the feature (Open/Closed + Dependency Inversion).
