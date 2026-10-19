import ClaraCore
import ClaraInfrastructure
import ClaraUI
import Foundation
import SwiftUI

@MainActor
final class AppEnvironment {
    let analytics: AnalyticsService
    let todayViewModel: TodayViewModel
    let recordsViewModel: RecordsViewModel
    let consultationViewModel: ConsultationViewModel
    let storageWarning: AlertContent?

    private static let consentKey = "analytics.consent"

    private init(database: LocalDatabase, holidays: any HolidayProviding, storageWarning: AlertContent? = nil) {
        let crashReporter = OSLogCrashReporter()
        let buffer = AnalyticsEventBuffer()
        let analytics = AnalyticsService(buffer: buffer, hasConsent: UserDefaults.standard.bool(forKey: Self.consentKey))
        let suggester = StepSuggesterFactory.makeDefault()
        let moments = LocalMomentRepository(database: database)
        self.analytics = analytics
        self.storageWarning = storageWarning
        self.todayViewModel = TodayViewModel(dependencies: TodayDependencies(
            tasks: LocalTaskRepository(database: database),
            parking: LocalParkingRepository(database: database),
            suggester: suggester,
            holidays: holidays,
            analytics: analytics,
            crashReporter: crashReporter
        ))
        self.recordsViewModel = RecordsViewModel(repository: moments, analytics: analytics, crashReporter: crashReporter)
        self.consultationViewModel = ConsultationViewModel(dependencies: ConsultationDependencies(
            repository: moments,
            analytics: analytics,
            crashReporter: crashReporter
        ))
    }

    static func make(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppEnvironment {
        if arguments.contains("-ui-testing") {
            return AppEnvironment(database: LocalDatabase(inMemory: .init()), holidays: StaticHolidayProvider())
        }
        let holidays = BrasilAPIHolidayService(client: URLSessionHTTPClient(baseURL: URL(string: "https://brasilapi.com.br")!))
        do {
            return AppEnvironment(database: try LocalDatabase(fileURL: LocalDatabase.defaultFileURL()), holidays: holidays)
        } catch {
            OSLogCrashReporter().record(error, context: "app.openDatabase")
            return AppEnvironment(
                database: LocalDatabase(inMemory: .init()),
                holidays: holidays,
                storageWarning: AlertContent(
                    title: "Não foi possível abrir o armazenamento",
                    message: "O arquivo existente não foi alterado. O que você adicionar agora ficará apenas nesta sessão e será perdido ao fechar o app."
                )
            )
        }
    }

    var hasAnalyticsConsent: Bool {
        get { analytics.hasConsent }
        set {
            analytics.hasConsent = newValue
            UserDefaults.standard.set(newValue, forKey: Self.consentKey)
        }
    }
}
