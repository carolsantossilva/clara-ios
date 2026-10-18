import ClaraAI
import ClaraCore
import ClaraServices
import Foundation

/// Tudo o que a feature precisa do mundo de fora, num só lugar.
/// O app monta com implementações reais; os testes, com dublês.
public struct TodayDependencies: Sendable {
    public var tasks: any TaskRepository
    public var parking: any ParkingRepository
    public var suggester: any StepSuggesting
    public var holidays: any HolidayProviding
    public var flags: FeatureFlags
    public var analytics: any AnalyticsTracker
    public var crashReporter: any CrashReporter
    /// `any Clock<Duration>`: em produção `ContinuousClock`; nos testes um relógio
    /// que não espera de verdade, para o timer não deixar o teste lento nem instável.
    public var clock: any Clock<Duration>
    public var now: @Sendable () -> Date

    public init(
        tasks: any TaskRepository,
        parking: any ParkingRepository,
        suggester: any StepSuggesting,
        holidays: any HolidayProviding,
        flags: FeatureFlags,
        analytics: any AnalyticsTracker,
        crashReporter: any CrashReporter,
        clock: any Clock<Duration> = ContinuousClock(),
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.tasks = tasks
        self.parking = parking
        self.suggester = suggester
        self.holidays = holidays
        self.flags = flags
        self.analytics = analytics
        self.crashReporter = crashReporter
        self.clock = clock
        self.now = now
    }
}
