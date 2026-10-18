import ClaraAI
import ClaraCore
import ClaraNetworking
import ClaraServices
import ClaraStorage
import ConsultationFeature
import Foundation
import RecordsFeature
import SwiftUI
import TodayFeature

/// Composition root: o único lugar que conhece as implementações concretas.
/// As features recebem só protocolos — trocar o banco, o analytics ou a IA
/// muda este arquivo e nenhum outro.
@MainActor
final class AppEnvironment {
    let flags: FeatureFlags
    let analytics: AnalyticsService
    let analyticsBuffer: AnalyticsEventBuffer
    let crashReporter: any CrashReporter
    let suggester: any StepSuggesting
    let isUITesting: Bool

    private let database: LocalDatabase
    private let holidays: any HolidayProviding
    private let remoteConfigLoader: RemoteConfigLoader?
    private let installationIDProvider: InstallationIDProvider
    private let metrics: MetricsSubscriber
    private var didBootstrap = false

    private static let consentKey = "analytics.consent"

    private init(
        database: LocalDatabase,
        holidays: any HolidayProviding,
        remoteConfigLoader: RemoteConfigLoader?,
        suggester: any StepSuggesting,
        isUITesting: Bool
    ) {
        let crashReporter = OSLogCrashReporter()
        let buffer = AnalyticsEventBuffer()
        self.database = database
        self.holidays = holidays
        self.remoteConfigLoader = remoteConfigLoader
        self.suggester = suggester
        self.isUITesting = isUITesting
        self.crashReporter = crashReporter
        self.analyticsBuffer = buffer
        self.flags = FeatureFlags()
        self.installationIDProvider = InstallationIDProvider()
        self.metrics = MetricsSubscriber(crashReporter: crashReporter)
        self.analytics = AnalyticsService(
            destinations: [
                AnyAnalyticsDestination(ConsoleAnalyticsDestination(), name: "Console"),
                AnyAnalyticsDestination(BufferAnalyticsDestination(buffer: buffer), name: "Painel local"),
                // Em produção: AnyAnalyticsDestination(FirebaseDestination(), name: "Firebase")
            ],
            hasConsent: isUITesting || UserDefaults.standard.bool(forKey: Self.consentKey)
        )
    }

    static func make(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppEnvironment {
        // UI tests rodam com banco em memória e sem rede: resultados determinísticos.
        if arguments.contains("-ui-testing") {
            return AppEnvironment(
                database: LocalDatabase(inMemory: .init()),
                holidays: StaticHolidayProvider(),
                remoteConfigLoader: nil,
                suggester: HeuristicStepSuggester(),
                isUITesting: true
            )
        }

        let crashReporter = OSLogCrashReporter()
        let database: LocalDatabase
        do {
            database = try LocalDatabase(fileURL: LocalDatabase.defaultFileURL())
        } catch {
            // Não perder a sessão por causa do disco: segue em memória e registra.
            crashReporter.record(error, context: "app.openDatabase")
            database = LocalDatabase(inMemory: .init())
        }

        let brasilAPI = URLSessionHTTPClient(baseURL: URL(string: "https://brasilapi.com.br")!)
        return AppEnvironment(
            database: database,
            holidays: BrasilAPIHolidayService(client: brasilAPI),
            remoteConfigLoader: makeRemoteConfigLoader(),
            suggester: StepSuggesterFactory.makeDefault(),
            isUITesting: false
        )
    }

    /// A URL do JSON de configuração vem do Info.plist (build setting REMOTE_CONFIG_URL).
    private static func makeRemoteConfigLoader() -> RemoteConfigLoader? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "ClaraRemoteConfigURL") as? String,
              let url = URL(string: raw),
              let scheme = url.scheme,
              let host = url.host(),
              let baseURL = URL(string: "\(scheme)://\(host)")
        else { return nil }
        let client = URLSessionHTTPClient(baseURL: baseURL, retryPolicy: RetryPolicy(maxAttempts: 2))
        return RemoteConfigLoader(client: client, path: url.path())
    }

    // MARK: Inicialização assíncrona

    private enum BootstrapStep: Sendable {
        case remoteConfig(RemoteConfig, RemoteConfigSource)
        case holidaysWarmed
        case aiPrewarmed
    }

    /// Tarefas independentes em paralelo com `TaskGroup`; cada resultado é aplicado
    /// assim que chega, de volta no MainActor (o corpo do grupo roda no main actor).
    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true

        // 1) ID de instalação (Objective-C com completion handler, importado como async).
        let installationID = await installationIDProvider.installationID()
        flags.setInstallationID(installationID)

        // 2) O resto em paralelo.
        let loader = remoteConfigLoader
        let holidays = self.holidays
        let suggester = self.suggester
        let today = LocalDay(.now, in: .current)

        await withTaskGroup(of: BootstrapStep?.self) { group in
            if let loader {
                group.addTask {
                    let (config, source) = await loader.load()
                    return .remoteConfig(config, source)
                }
            }
            group.addTask {
                // Pré-carrega o cache do actor; a tela Hoje lê dele depois.
                _ = try? await holidays.upcomingHoliday(from: today, within: 7)
                return .holidaysWarmed
            }
            group.addTask {
                await suggester.prewarm()
                return .aiPrewarmed
            }

            for await step in group {
                switch step {
                case .remoteConfig(let config, let source):
                    flags.apply(config, source: source)
                    crashReporter.breadcrumb("remote config: \(source.rawValue)")
                case .holidaysWarmed, .aiPrewarmed, nil:
                    break
                }
            }
        }
    }

    // MARK: Consentimento

    var hasAnalyticsConsent: Bool {
        get { analytics.hasConsent }
        set {
            analytics.hasConsent = newValue
            UserDefaults.standard.set(newValue, forKey: Self.consentKey)
        }
    }

    // MARK: Dependências das features

    private(set) lazy var todayCoordinator = TodayCoordinator(
        dependencies: TodayDependencies(
            tasks: LocalTaskRepository(database: database),
            parking: LocalParkingRepository(database: database),
            suggester: suggester,
            holidays: holidays,
            flags: flags,
            analytics: analytics,
            crashReporter: crashReporter
        ),
        makePrivacyView: { [unowned self] in AnyView(PrivacyView(environment: self)) }
    )

    var recordsDependencies: RecordsDependencies {
        RecordsDependencies(
            repository: LocalMomentRepository(database: database),
            analytics: analytics,
            crashReporter: crashReporter
        )
    }

    private(set) lazy var consultationViewModel = ConsultationViewModel(
        dependencies: ConsultationDependencies(
            repository: LocalMomentRepository(database: database),
            analytics: analytics,
            crashReporter: crashReporter
        )
    )
}
