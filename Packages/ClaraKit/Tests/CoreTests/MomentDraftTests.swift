import ClaraTestSupport
import Foundation
import Testing
@testable import ClaraCore

@Suite("Moment draft")
struct MomentDraftTests {
    @Test("needs a word or some text")
    func requiresSomeContent() {
        var draft = MomentDraft(kind: .daily, occurredAt: Date(timeIntervalSince1970: 1_790_000_000))
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

    @Test("changing a daily check-in to an event applies the event time")
    func appliesChangedKindAndEventTime() {
        let original = Fixtures.moment(kind: .daily, at: "2026-09-20T10:00:00-03:00")
        var draft = MomentDraft(editing: original)
        draft.kind = .event
        draft.occurredAt = Fixtures.date("2026-09-21T10:00:00-03:00")

        let updated = original.applying(draft, currentTimeZone: TimeZone(identifier: "Europe/Lisbon")!)

        #expect(updated.kind == .event)
        #expect(updated.occurredAt == draft.occurredAt)
        #expect(updated.timeZoneIdentifier == "Europe/Lisbon")
        #expect(updated.updatedAt == original.updatedAt)
        #expect(updated.revision == original.revision)
    }
}
