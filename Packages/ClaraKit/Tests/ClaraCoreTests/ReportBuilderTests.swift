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
    @Test("rejects incomplete and impossible dates", arguments: ["2026-02-31", "2026-13-01", "2026-09", "abc"])
    func rejectsInvalid(_ text: String) {
        #expect(LocalDay(isoString: text) == nil)
    }

    @Test("adds days across the year boundary")
    func addsAcrossYears() {
        #expect(LocalDay(year: 2026, month: 12, day: 29).adding(days: 5) == LocalDay(year: 2027, month: 1, day: 3))
    }
}

@Suite("Moment draft")
struct MomentDraftTests {
    @Test("needs a word or some text")
    func requiresSomeContent() {
        var draft = MomentDraft(kind: .daily, occurredAt: .now)
        #expect(!draft.hasContent)

        draft.note = "   "
        #expect(!draft.hasContent, "Whitespace alone does not count")

        draft.mood = .okay
        #expect(draft.hasContent)
    }

    @Test("editing without changing the time keeps the original time zone")
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
    @Test("returns the result when the operation finishes in time")
    func returnsResult() async throws {
        let value = try await withTimeout(.seconds(1)) { 42 }
        #expect(value == 42)
    }

    @Test("throws TimeoutError when the operation takes too long")
    func throwsOnTimeout() async {
        await #expect(throws: TimeoutError.self) {
            try await withTimeout(.milliseconds(10)) {
                try await Task.sleep(for: .seconds(10))
                return 0
            }
        }
    }
}
