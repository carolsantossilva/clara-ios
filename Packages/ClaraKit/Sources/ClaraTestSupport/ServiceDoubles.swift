import ClaraInfrastructure
import os

// MARK: - Analytics and crashes

public final class SpyAnalyticsTracker: AnalyticsTracker, Sendable {
    private let tracked = OSAllocatedUnfairLock(initialState: [AnalyticsEvent]())

    public init() {}

    public var events: [AnalyticsEvent] { tracked.withLock { $0 } }
    public var names: [String] { events.map(\.name) }

    public func track(_ event: AnalyticsEvent) {
        tracked.withLock { $0.append(event) }
    }
}

public final class SpyCrashReporter: CrashReporter, Sendable {
    private let recorded = OSAllocatedUnfairLock(initialState: [String]())

    public init() {}

    public var contexts: [String] { recorded.withLock { $0 } }

    public func record(_ error: any Error, context: String) {
        recorded.withLock { $0.append(context) }
    }

    public func breadcrumb(_ message: String) {}
}
