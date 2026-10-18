import Foundation
import os

/// Abstração de crash reporting. Em produção, um adaptador para Crashlytics,
/// Sentry ou Bugsnag implementaria este protocolo; o resto do app não muda.
public protocol CrashReporter: Sendable {
    /// Erro não fatal com um contexto curto (nunca texto da usuária).
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
