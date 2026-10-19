import ClaraLegacy
import Foundation
import Observation

/// Focus session countdown.
///
/// `@Observable` (Observation, iOS 17): SwiftUI tracks which properties each
/// view read in `body` and redraws only those views when they change. Unlike the
/// old `ObservableObject`, it needs no `@Published` and avoids extra redraws.
@MainActor
@Observable
public final class FocusTimer {
    public private(set) var remainingSeconds: Int
    public private(set) var isRunning = false
    public private(set) var didFinish = false

    private var tickTask: Task<Void, Never>?
    private let clock: any Clock<Duration>

    public init(durationSeconds: Int, clock: any Clock<Duration>) {
        self.remainingSeconds = durationSeconds
        self.clock = clock
    }

    public func start(durationSeconds: Int) {
        stop()
        remainingSeconds = durationSeconds
        didFinish = false
        isRunning = true
        // The Task inherits MainActor isolation: the loop runs on the main actor, but
        // `clock.sleep` suspends without blocking the main thread.
        tickTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    public func stop() {
        tickTask?.cancel()
        tickTask = nil
        isRunning = false
    }

    /// Waits for the loop to finish. Used in tests.
    func waitUntilFinished() async {
        await tickTask?.value
    }

    private func runLoop() async {
        while remainingSeconds > 0 {
            do {
                try await clock.sleep(for: .seconds(1))
            } catch {
                return // cancelled
            }
            remainingSeconds -= 1
        }
        isRunning = false
        didFinish = true
    }

    // Legacy Objective-C code called from Swift.
    public var clockLabel: String { CLADurationFormatter.clockString(seconds: remainingSeconds) }
    public var spokenLabel: String { CLADurationFormatter.spokenString(seconds: remainingSeconds) }
}
