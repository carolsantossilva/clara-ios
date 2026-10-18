import ClaraCore
import ClaraServices
import ClaraStorage
import ClaraTestSupport
import Foundation
import Testing
@testable import ConsultationFeature

@Suite("Consulta")
@MainActor
struct ConsultationViewModelTests {
    let exporter = SpyExporter()
    let analytics = SpyAnalyticsTracker()

    func makeViewModel(moments: [Moment]) -> ConsultationViewModel {
        let database = LocalDatabase(inMemory: .init(moments: moments))
        return ConsultationViewModel(dependencies: ConsultationDependencies(
            repository: LocalMomentRepository(database: database),
            exporter: exporter,
            analytics: analytics,
            crashReporter: SpyCrashReporter(),
            now: { Fixtures.date("2026-09-20T15:00:00-03:00") }
        ))
    }

    @Test("começa com a última semana e tudo selecionado")
    func initialState() async {
        let inside = Fixtures.moment(at: "2026-09-18T10:00:00-03:00")
        let outside = Fixtures.moment(at: "2026-09-01T10:00:00-03:00")
        let viewModel = makeViewModel(moments: [inside, outside])

        await viewModel.load()

        #expect(viewModel.eligible.map(\.id) == [inside.id])
        #expect(viewModel.selectedIDs == [inside.id, outside.id])
    }

    @Test("desmarcar remove do resumo")
    func toggleRemovesFromReport() async {
        let first = Fixtures.moment(at: "2026-09-18T10:00:00-03:00")
        let second = Fixtures.moment(at: "2026-09-19T10:00:00-03:00")
        let viewModel = makeViewModel(moments: [first, second])
        await viewModel.load()

        viewModel.toggle(first.id)

        #expect(viewModel.report.entries.map(\.id) == [second.id])
    }

    @Test("\"Este mês\" começa no dia 1")
    func thisMonth() async {
        let early = Fixtures.moment(at: "2026-09-02T10:00:00-03:00")
        let viewModel = makeViewModel(moments: [early])
        await viewModel.load()
        #expect(viewModel.eligible.isEmpty)

        viewModel.chooseThisMonth()

        #expect(viewModel.eligible.map(\.id) == [early.id])
    }

    @Test("exportar gera o HTML com as perguntas e registra só a contagem")
    func exportsPDF() async {
        let viewModel = makeViewModel(moments: [Fixtures.moment(at: "2026-09-19T10:00:00-03:00", note: "dia cheio")])
        await viewModel.load()
        viewModel.questions = "Rotina de sono"

        viewModel.exportPDF()

        #expect(viewModel.exportedFileURL != nil)
        #expect(exporter.lastHTML?.contains("dia cheio") == true)
        #expect(exporter.lastHTML?.contains("Rotina de sono") == true)
        #expect(analytics.events.last == AnalyticsEvent(name: "report_exported", properties: ["entries": "1"]))
    }
}

@MainActor
final class SpyExporter: ReportExporting {
    private(set) var lastHTML: String?

    func exportPDF(html: String, fileName: String) throws -> URL {
        lastHTML = html
        return URL(fileURLWithPath: "/tmp/\(fileName)")
    }
}
