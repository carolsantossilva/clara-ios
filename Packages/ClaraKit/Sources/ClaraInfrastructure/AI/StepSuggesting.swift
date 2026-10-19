import ClaraCore
import Foundation

/// Small steps suggested to start a task.
public struct StepSuggestion: Equatable, Sendable {
    public enum Source: String, Sendable {
        /// Apple's language model running on the device (Foundation Models).
        case onDevice = "on_device"
        /// Simple rules with NaturalLanguage, when no model is available.
        case heuristic
    }

    public let steps: [String]
    public let source: Source

    public init(steps: [String], source: Source) {
        self.steps = steps
        self.source = source
    }
}

/// Product decision: the AI only *suggests*, and only when the user asks. She picks
/// a step (or none). The text never leaves the device and there is no clinical interpretation.
public protocol StepSuggesting: Sendable {
    var isAvailable: Bool { get async }
    func suggestSteps(for taskTitle: String) async throws -> StepSuggestion
    /// Loads the model before first use, so the answer arrives faster.
    func prewarm() async
}

extension StepSuggesting {
    public func prewarm() async {}
}

public enum StepSuggestionError: Error, Equatable {
    case emptyTitle
    case unavailable
    case noSteps
}

/// Tries the main provider (on-device AI) and, if it is unavailable, fails
/// or takes too long, uses the fallback. Decorator + Open/Closed: providers can be
/// swapped or stacked without touching the caller.
public struct FallbackStepSuggester: StepSuggesting {
    private let primary: any StepSuggesting
    private let fallback: any StepSuggesting
    private let timeout: Duration

    public init(primary: any StepSuggesting, fallback: any StepSuggesting, timeout: Duration = .seconds(8)) {
        self.primary = primary
        self.fallback = fallback
        self.timeout = timeout
    }

    public var isAvailable: Bool {
        get async {
            let primaryAvailable = await primary.isAvailable
            if primaryAvailable { return true }
            return await fallback.isAvailable
        }
    }

    public func suggestSteps(for taskTitle: String) async throws -> StepSuggestion {
        guard !taskTitle.trimmed.isEmpty else { throw StepSuggestionError.emptyTitle }
        if await primary.isAvailable {
            do {
                let primary = self.primary
                return try await withTimeout(timeout) {
                    try await primary.suggestSteps(for: taskTitle)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Falls back: the user always gets some help.
            }
        }
        return try await fallback.suggestSteps(for: taskTitle)
    }

    public func prewarm() async {
        await primary.prewarm()
    }
}

public enum StepSuggesterFactory {
    /// Picks the best provider for this device at runtime.
    public static func makeDefault() -> any StepSuggesting {
        let heuristic = HeuristicStepSuggester()
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return FallbackStepSuggester(primary: FoundationModelsStepSuggester(), fallback: heuristic)
        }
        #endif
        return heuristic
    }
}
