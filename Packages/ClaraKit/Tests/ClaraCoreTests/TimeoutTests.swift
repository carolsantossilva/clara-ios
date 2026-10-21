import Foundation
import Testing
@testable import ClaraCore
import ClaraTestSupport

@Suite("Timeout")
struct TimeoutTests {
    @Test("returns the result when the operation finishes in time")
    func returnsResult() async throws {
        let value = try await withTimeout(.seconds(1), clock: OperationWinsClock()) { 42 }
        #expect(value == 42)
    }

    @Test("throws TimeoutError when the operation takes too long")
    func throwsOnTimeout() async {
        await #expect(throws: TimeoutError.self) {
            try await withTimeout(.milliseconds(10), clock: ImmediateClock()) {
                while true {
                    try Task.checkCancellation()
                    await Task.yield()
                }
            }
        }
    }
}

private struct OperationWinsClock: Clock {
    typealias Instant = ImmediateClock.Instant

    private let waiter = SleepWaiter()

    var now: Instant { ImmediateClock().now }
    var minimumResolution: Duration { .zero }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        try await withTaskCancellationHandler {
            await waiter.wait()
            try Task.checkCancellation()
        } onCancel: {
            Task { await waiter.resume() }
        }
    }
}

private actor SleepWaiter {
    private var continuation: CheckedContinuation<Void, Never>?
    private var didResume = false

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if didResume {
                continuation.resume()
            } else {
                self.continuation = continuation
            }
        }
    }

    func resume() {
        didResume = true
        continuation?.resume()
        continuation = nil
    }
}
