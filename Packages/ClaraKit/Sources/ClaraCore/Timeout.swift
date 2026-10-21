import Foundation

// MARK: - Timeout error

public struct TimeoutError: Error, Equatable {
    public init() {}
}

// MARK: - Timeout operations

/// Runs `operation` with a deadline. Two child tasks race in a TaskGroup:
/// the first to finish wins and the other is cancelled.
///
/// This only works because cancellation in Swift Concurrency is *cooperative*:
/// suspensions such as `Clock.sleep` and `URLSession` check for cancellation; a
/// CPU loop that does not call `Task.checkCancellation()` would keep running.
public func withTimeout<T: Sendable>(
    _ duration: Duration,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withTimeout(duration, clock: ContinuousClock(), operation: operation)
}

public func withTimeout<C: Clock, T: Sendable>(
    _ duration: Duration,
    clock: C,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await clock.sleep(for: duration)
            throw TimeoutError()
        }
        defer { group.cancelAll() }
        guard let first = try await group.next() else { throw TimeoutError() }
        return first
    }
}
