import Foundation
import os

// Doubles shared across suites. They live in their own (non-test) target
// so several suites can import them without duplication.

// MARK: - Immediate clock

/// A clock that does not wait: `sleep` only yields. Timer tests run in
/// milliseconds without depending on real time (a classic source of flakiness).
public struct ImmediateClock: Clock {
    public struct Instant: InstantProtocol {
        public var offset: Duration

        public func advanced(by duration: Duration) -> Instant {
            Instant(offset: offset + duration)
        }

        public func duration(to other: Instant) -> Duration {
            other.offset - offset
        }

        public static func < (lhs: Instant, rhs: Instant) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    public init() {}

    public var now: Instant { Instant(offset: .zero) }
    public var minimumResolution: Duration { .zero }

    public func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        try Task.checkCancellation()
        await Task.yield()
    }
}

/// A "now" that moves one second forward on every read. Guarantees a stable order for
/// records created in sequence: with a real `Date()`, two records can get the
/// same instant and the test's ordering would come down to luck.
public final class SteppingNow: Sendable {
    private let current: OSAllocatedUnfairLock<Date>

    public init(start: Date = Date(timeIntervalSince1970: 1_790_000_000)) {
        current = OSAllocatedUnfairLock(initialState: start)
    }

    public var read: @Sendable () -> Date {
        { [current] in
            current.withLock { date in
                date = date.addingTimeInterval(1)
                return date
            }
        }
    }
}
