import ClaraTestSupport
import Foundation
import Testing
@testable import ClaraCore

// Portados de `report.test.ts` do app React Native.
@Suite("Resumo para consulta")
struct ReportBuilderTests {
    let day = LocalDay(year: 2026, month: 9, day: 20)

    @Test("mantém só os selecionados, ordena por horário e preserva o texto da usuária")
    func keepsSelectedSortedAndVerbatim() {
        let later = Fixtures.moment(at: "2026-09-20T19:00:00-03:00", mood: .difficult, note: "  Reunião longa  ")
        let earlier = Fixtures.moment(kind: .daily, at: "2026-09-20T10:00:00-03:00", mood: .good)
        let notSelected = Fixtures.moment(at: "2026-09-20T11:00:00-03:00", mood: .okay, note: "Não incluir")

        let report = ReportBuilder.build(
            ReportSelection(start: day, end: day, momentIDs: [later.id, earlier.id], questionsAndNotes: "Quero conversar sobre rotina."),
            from: [later, earlier, notSelected]
        )

        #expect(report.entries.map(\.id) == [earlier.id, later.id])
        #expect(report.entries[1].note == "  Reunião longa  ")
        #expect(report.entries[0].note.isEmpty)
        #expect(report.questionsAndNotes == "Quero conversar sobre rotina.")
    }

    @Test("usa o dia local do momento, não o dia em UTC")
    func filtersByLocalDayOfTheMoment() {
        // 23h em São Paulo = 02h do dia seguinte em UTC.
        let lateNight = Fixtures.moment(at: "2026-09-20T23:00:00-03:00")

        let report = ReportBuilder.build(
            ReportSelection(start: day, end: day, momentIDs: [lateNight.id], questionsAndNotes: ""),
            from: [lateNight]
        )

        #expect(report.entries.count == 1)
    }

    @Test("ignora registros excluídos")
    func ignoresDeleted() {
        let deleted = Fixtures.moment(at: "2026-09-20T10:00:00-03:00", deletedAt: Fixtures.date("2026-09-21T10:00:00Z"))
        #expect(ReportBuilder.eligible(start: day, end: day, in: [deleted]).isEmpty)
    }

    @Test("escapa o texto pessoal antes de colocá-lo no documento imprimível")
    func escapesPersonalText() {
        let entry = Fixtures.moment(at: "2026-09-20T10:00:00-03:00", note: "<script>alert('oi')</script>")
        let report = ReportBuilder.build(
            ReportSelection(start: day, end: day, momentIDs: [entry.id], questionsAndNotes: ""),
            from: [entry]
        )

        let html = ReportHTMLRenderer.render(report)

        #expect(html.contains("&lt;script&gt;"))
        #expect(!html.contains("<script>"))
    }
}

@Suite("LocalDay")
struct LocalDayTests {
    @Test("rejeita datas incompletas e impossíveis", arguments: ["2026-02-31", "2026-13-01", "2026-09", "abc"])
    func rejectsInvalid(_ text: String) {
        #expect(LocalDay(isoString: text) == nil)
    }

    @Test("soma dias atravessando o ano")
    func addsAcrossYears() {
        #expect(LocalDay(year: 2026, month: 12, day: 29).adding(days: 5) == LocalDay(year: 2027, month: 1, day: 3))
    }
}

@Suite("Rascunho de momento")
struct MomentDraftTests {
    @Test("precisa de uma palavra ou de algum texto")
    func requiresSomeContent() {
        var draft = MomentDraft(kind: .daily, occurredAt: .now)
        #expect(!draft.hasContent)

        draft.note = "   "
        #expect(!draft.hasContent, "Só espaços não contam")

        draft.mood = .okay
        #expect(draft.hasContent)
    }

    @Test("ao editar sem mudar a hora, preserva o fuso original")
    func preservesTimeZoneWhenTimeIsUnchanged() {
        let original = Fixtures.moment(at: "2026-09-20T10:00:00-03:00", note: "antes")
        var draft = MomentDraft(editing: original)
        draft.note = "depois"

        let updated = original.applying(draft, currentTimeZone: TimeZone(identifier: "Europe/Lisbon")!)

        #expect(updated.note == "depois")
        #expect(updated.timeZoneIdentifier == Fixtures.saoPaulo)
    }
}

@Suite("Timeout")
struct TimeoutTests {
    @Test("devolve o resultado quando a operação termina a tempo")
    func returnsResult() async throws {
        let value = try await withTimeout(.seconds(1)) { 42 }
        #expect(value == 42)
    }

    @Test("lança TimeoutError quando a operação demora demais")
    func throwsOnTimeout() async {
        await #expect(throws: TimeoutError.self) {
            try await withTimeout(.milliseconds(10)) {
                try await Task.sleep(for: .seconds(10))
                return 0
            }
        }
    }
}
