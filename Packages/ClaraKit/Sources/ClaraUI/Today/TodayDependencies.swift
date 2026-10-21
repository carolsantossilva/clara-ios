import ClaraInfrastructure
import ClaraCore
import Foundation

/// Everything the feature needs from the outside world, in one place.
/// The app wires real implementations; the tests wire doubles.
public struct TodayDependencies: Sendable {
    public var tasks: any TaskRepository
    public var parking: any DistractionRepository
    public var suggester: any StepSuggesting
    public var holidays: any HolidayProviding
    public var analytics: any AnalyticsTracker
    public var crashReporter: any CrashReporter
    /// `any Clock<Duration>`: `ContinuousClock` in production; in tests a clock that
    /// does not really wait, so the timer does not make the test slow or flaky.
    public var clock: any Clock<Duration>
    public var now: @Sendable () -> Date

    public init(
        tasks: any TaskRepository,
        parking: any DistractionRepository,
        suggester: any StepSuggesting,
        holidays: any HolidayProviding,
        analytics: any AnalyticsTracker,
        crashReporter: any CrashReporter,
        clock: any Clock<Duration> = ContinuousClock(),
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.tasks = tasks
        self.parking = parking
        self.suggester = suggester
        self.holidays = holidays
        self.analytics = analytics
        self.crashReporter = crashReporter
        self.clock = clock
        self.now = now
    }
}
