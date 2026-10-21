import ClaraTestSupport
import Foundation
import Testing
@testable import ClaraCore

// Ported from the React Native app's `report.test.ts`.
@Suite("Appointment summary")
struct ReportBuilderTests {
    let day = LocalDay(year: 2026, month: 9, day: 20)

    @Test("keeps only the selected ones, sorts by time and preserves the user's text")
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

    @Test("uses the moment's local day, not the UTC day")
    func filtersByLocalDayOfTheMoment() {
        // 11 p.m. in São Paulo = 2 a.m. the next day in UTC.
        let lateNight = Fixtures.moment(at: "2026-09-20T23:00:00-03:00")

        let report = ReportBuilder.build(
            ReportSelection(start: day, end: day, momentIDs: [lateNight.id], questionsAndNotes: ""),
            from: [lateNight]
        )

        #expect(report.entries.count == 1)
    }

    @Test("ignores deleted records")
    func ignoresDeleted() {
        let deleted = Fixtures.moment(at: "2026-09-20T10:00:00-03:00", deletedAt: Fixtures.date("2026-09-21T10:00:00Z"))
        #expect(ReportBuilder.eligible(start: day, end: day, in: [deleted]).isEmpty)
    }

    @Test("escapes personal text before putting it in the printable document")
    func escapesPersonalText() throws {
        let entry = Fixtures.moment(at: "2026-09-20T10:00:00-03:00", note: "{{questions}} <script>alert('oi')</script>")
        let report = ReportBuilder.build(
            ReportSelection(start: day, end: day, momentIDs: [entry.id], questionsAndNotes: ""),
            from: [entry]
        )

        let html = try ReportHTMLRenderer.render(report)

        #expect(html.contains("{{questions}}"))
        #expect(html.contains("&lt;script&gt;"))
        #expect(!html.contains("<script>"))
    }
}
