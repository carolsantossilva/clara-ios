import Foundation
import os

/// Crash reporting abstraction. In production, an adapter for Crashlytics,
/// Sentry or Bugsnag would implement this protocol; the rest of the app does not change.
public protocol CrashReporter: Sendable {
    /// Non-fatal error with a short context (never user text).
    func record(_ error: any Error, context: String)
    func breadcrumb(_ message: String)
}

public struct OSLogCrashReporter: CrashReporter {
    private let logger = Logger(subsystem: "app.clara", category: "errors")

    public init() {}

    public func record(_ error: any Error, context: String) {
        logger.error("[\(context, privacy: .public)] \(String(describing: error), privacy: .private)")
    }

    public func breadcrumb(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }
}
