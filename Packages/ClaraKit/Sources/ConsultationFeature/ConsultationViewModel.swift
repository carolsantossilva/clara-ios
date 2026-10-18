import ClaraCore
import ClaraDesignSystem
import ClaraServices
import Foundation
import Observation

public struct ConsultationDependencies: Sendable {
    public var repository: any MomentRepository
    public var exporter: any ReportExporting
    public var analytics: any AnalyticsTracker
    public var crashReporter: any CrashReporter
    public var now: @Sendable () -> Date

    public init(
        repository: any MomentRepository,
        exporter: any ReportExporting = PrintRendererReportExporter(),
        analytics: any AnalyticsTracker,
        crashReporter: any CrashReporter,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.repository = repository
        self.exporter = exporter
        self.analytics = analytics
        self.crashReporter = crashReporter
        self.now = now
    }
}

/// MVVM simples, sem Coordinator: a tela não navega para lugar nenhum.
/// Adicionar um Coordinator aqui seria cerimônia sem ganho — escolha consciente.
@MainActor
@Observable
public final class ConsultationViewModel {
    public private(set) var moments: [Moment] = []
    public var startDate: Date
    public var endDate: Date
    public var selectedIDs: Set<UUID> = []
    public var questions = ""
    public var isPreviewing = false
    public private(set) var exportedFileURL: URL?
    public var alert: AlertContent?

    @ObservationIgnored private let dependencies: ConsultationDependencies
    @ObservationIgnored private let calendar = Calendar.current

    public init(dependencies: ConsultationDependencies) {
        self.dependencies = dependencies
        let today = dependencies.now()
        self.endDate = today
        self.startDate = Calendar.current.date(byAdding: .day, value: -6, to: today) ?? today
    }

    // MARK: Estado derivado (recalculado a cada leitura; barato para dezenas de registros)

    var startDay: LocalDay { LocalDay(startDate, in: .current) }
    var endDay: LocalDay { LocalDay(endDate, in: .current) }

    public var eligible: [Moment] {
        ReportBuilder.eligible(start: startDay, end: endDay, in: moments)
    }

    public var report: ReportDocument {
        ReportBuilder.build(
            ReportSelection(start: startDay, end: endDay, momentIDs: selectedIDs, questionsAndNotes: questions),
            from: moments
        )
    }

    // MARK: Ações

    public func load() async {
        do {
            moments = try await dependencies.repository.list()
            // Como no app original: tudo começa selecionado; a usuária desmarca o que não quer levar.
            selectedIDs = Set(moments.map(\.id))
        } catch is CancellationError {
            return
        } catch {
            dependencies.crashReporter.record(error, context: "consultation.load")
            alert = AlertContent(title: "Não foi possível abrir seus registros", message: "Tente novamente antes de preparar o resumo.")
        }
    }

    public func toggle(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
        exportedFileURL = nil
    }

    public func selectAllEligible() {
        selectedIDs.formUnion(eligible.map(\.id))
        exportedFileURL = nil
    }

    public func chooseLastWeek() {
        let today = dependencies.now()
        endDate = today
        startDate = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        exportedFileURL = nil
    }

    public func chooseThisMonth() {
        let today = dependencies.now()
        endDate = today
        startDate = calendar.dateInterval(of: .month, for: today)?.start ?? today
        exportedFileURL = nil
    }

    public func exportPDF() {
        let document = report
        let html = ReportHTMLRenderer.render(document, preparedAt: dependencies.now())
        let fileName = "resumo-consulta-\(document.start)-a-\(document.end).pdf"
        do {
            exportedFileURL = try dependencies.exporter.exportPDF(html: html, fileName: fileName)
            dependencies.analytics.track(.reportExported(entries: document.entries.count))
        } catch {
            dependencies.crashReporter.record(error, context: "consultation.export")
            alert = AlertContent(title: "Não foi possível preparar o PDF", message: "Seus registros continuam salvos no aparelho.")
        }
    }
}
