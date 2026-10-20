import Foundation
import os

public struct AnalyticsEvent: Equatable, Sendable {
    public let name: String
    public let properties: [String: String]

    public init(name: String, properties: [String: String] = [:]) {
        self.name = name
        self.properties = properties
    }
}

public protocol AnalyticsTracker: Sendable {
    func track(_ event: AnalyticsEvent)
}

// MARK: - Thread-safe buffer with a lock

/// Keeps the latest events, read and written from any thread.
///
/// Why not GCD (a concurrent queue with `sync` reads and `.barrier` writes)? That
/// was the previous version, and it hung on CI: `sync` blocks the calling thread.
/// Called from inside a Task, it blocks a thread of the Swift Concurrency
/// cooperative pool, which has one thread per core. With few cores, GCD did not
/// start a new thread to run the write and the reads waited forever.
///
/// The lock holds the thread only long enough to copy an array, and the compiler
/// checks thread safety (`OSAllocatedUnfairLock` is Sendable), without `@unchecked`.
/// With pure Swift Concurrency, the equivalent would be an `actor`, but then every
/// read would become `await`, which does not work for synchronous callers.
public final class AnalyticsEventBuffer: Sendable {
    private let storage = OSAllocatedUnfairLock(initialState: [AnalyticsEvent]())
    private let capacity: Int

    public init(capacity: Int = 50) {
        self.capacity = capacity
    }

    public func append(_ event: AnalyticsEvent) {
        storage.withLock { events in
            events.append(event)
            if events.count > capacity {
                events.removeFirst(events.count - capacity)
            }
        }
    }

    public var events: [AnalyticsEvent] {
        storage.withLock { $0 }
    }
}

// MARK: - Service with consent

/// Clara was born without analytics. Here tracking is opt-in, off by default,
/// and events never carry text written by the user (see `ClaraEvent`).
public final class AnalyticsService: AnalyticsTracker, Sendable {
    private let buffer: AnalyticsEventBuffer
    private let logger = Logger(subsystem: "app.clara", category: "analytics")
    // The lock holds the state and is Sendable: the compiler checks thread safety,
    // with no need for @unchecked (as in AnalyticsEventBuffer, above).
    private let consent: OSAllocatedUnfairLock<Bool>

    public init(buffer: AnalyticsEventBuffer, hasConsent: Bool) {
        self.buffer = buffer
        self.consent = OSAllocatedUnfairLock(initialState: hasConsent)
    }

    public var hasConsent: Bool {
        get { consent.withLock { $0 } }
        set { consent.withLock { $0 = newValue } }
    }

    public func track(_ event: AnalyticsEvent) {
        guard hasConsent else { return }
        buffer.append(event)
        logger.info("\(event.name, privacy: .public)")
    }
}

// MARK: - Event catalog

/// Every app event in one place. Properties are enums/numbers, never the
/// content of tasks or records.
public enum ClaraEvent: Equatable, Sendable {
    case taskCreated(hasFirstStep: Bool)
    case focusStarted(minutes: Int)
    case focusPaused(savedClue: Bool)
    case taskCompleted
    case parkingNoteSaved
    case momentSaved(kind: String, isEdit: Bool)
    case momentDeleted
    case reportExported(entries: Int)
    case stepSuggestionsShown(source: String)
    case stepSuggestionAccepted(source: String)
    case holidayBannerShown

    public var analyticsEvent: AnalyticsEvent {
        switch self {
        case .taskCreated(let hasFirstStep):
            AnalyticsEvent(name: "task_created", properties: ["has_first_step": String(hasFirstStep)])
        case .focusStarted(let minutes):
            AnalyticsEvent(name: "focus_started", properties: ["minutes": String(minutes)])
        case .focusPaused(let savedClue):
            AnalyticsEvent(name: "focus_paused", properties: ["saved_clue": String(savedClue)])
        case .taskCompleted:
            AnalyticsEvent(name: "task_completed")
        case .parkingNoteSaved:
            AnalyticsEvent(name: "parking_note_saved")
        case .momentSaved(let kind, let isEdit):
            AnalyticsEvent(name: "moment_saved", properties: ["kind": kind, "is_edit": String(isEdit)])
        case .momentDeleted:
            AnalyticsEvent(name: "moment_deleted")
        case .reportExported(let entries):
            AnalyticsEvent(name: "report_exported", properties: ["entries": String(entries)])
        case .stepSuggestionsShown(let source):
            AnalyticsEvent(name: "step_suggestions_shown", properties: ["source": source])
        case .stepSuggestionAccepted(let source):
            AnalyticsEvent(name: "step_suggestion_accepted", properties: ["source": source])
        case .holidayBannerShown:
            AnalyticsEvent(name: "holiday_banner_shown")
        }
    }
}

extension AnalyticsTracker {
    public func track(_ event: ClaraEvent) {
        track(event.analyticsEvent)
    }
}

public struct NoOpAnalyticsTracker: AnalyticsTracker {
    public init() {}
    public func track(_ event: AnalyticsEvent) {}
}
