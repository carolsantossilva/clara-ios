import ClaraCore
import ClaraInfrastructure
import ClaraTestSupport
import Foundation
import Testing
@testable import ClaraUI

@Suite("Records screen")
@MainActor
struct RecordsViewModelTests {
    let database = LocalDatabase(inMemory: .init())
    let analytics = SpyAnalyticsTracker()
    let crashReporter = SpyCrashReporter()
    let now = Fixtures.date("2026-10-10T12:00:00-03:00")

    func makeViewModel(repository: (any MomentRepository)? = nil) -> RecordsViewModel {
        RecordsViewModel(
            repository: repository ?? LocalMomentRepository(database: database, now: { now }),
            analytics: analytics,
            crashReporter: crashReporter,
            now: { now },
            timeZone: { TimeZone(identifier: Fixtures.saoPaulo)! }
        )
    }

    @Test("an empty draft is not saved")
    func rejectsEmptyDraft() async throws {
        let viewModel = makeViewModel()
        let result = await viewModel.save(MomentDraft(kind: .daily, occurredAt: now), editing: nil)
        #expect(result == .needsContent)
        #expect(try await LocalMomentRepository(database: database).list().isEmpty)
        #expect(analytics.events.isEmpty)
    }

    @Test("saving reloads the timeline and tracks only metadata")
    func createsMoment() async {
        let viewModel = makeViewModel()
        let result = await viewModel.save(MomentDraft(kind: .daily, occurredAt: now, mood: .good, note: "private"), editing: nil)
        #expect(result == .saved)
        #expect(viewModel.moments.first?.note == "private")
        #expect(analytics.events == [ClaraEvent.momentSaved(kind: "daily", isEdit: false).analyticsEvent])
    }

    @Test("editing updates the original instead of creating another record")
    func editsMoment() async throws {
        let viewModel = makeViewModel()
        _ = await viewModel.save(MomentDraft(kind: .event, occurredAt: now, note: "antes"), editing: nil)
        let original = try #require(viewModel.moments.first)
        var draft = MomentDraft(editing: original)
        draft.note = "depois"
        #expect(await viewModel.save(draft, editing: original) == .saved)
        #expect(viewModel.moments.map(\.note) == ["depois"])
        #expect(viewModel.moments.first?.id == original.id)
    }

    @Test("a stale edit reloads the latest record without overwriting it")
    func reportsConflict() async throws {
        let viewModel = makeViewModel()
        _ = await viewModel.save(MomentDraft(kind: .event, occurredAt: now, note: "original"), editing: nil)
        let original = try #require(viewModel.moments.first)
        var latest = original
        latest.note = "latest"
        _ = try await LocalMomentRepository(database: database).update(latest)
        var draft = MomentDraft(editing: original)
        draft.note = "stale"
        #expect(await viewModel.save(draft, editing: original) == .failed)
        #expect(viewModel.moments.first?.note == "latest")
        #expect(viewModel.alert?.title == "Este registro mudou")
    }

    @Test("deletion removes the record from the timeline")
    func deletesMoment() async throws {
        let viewModel = makeViewModel()
        _ = await viewModel.save(MomentDraft(kind: .daily, occurredAt: now, mood: .okay), editing: nil)
        await viewModel.delete(try #require(viewModel.moments.first))
        #expect(viewModel.moments.isEmpty)
        #expect(analytics.names.last == "moment_deleted")
    }

    @Test("load failure shows an error and ends the loading state")
    func reportsLoadFailure() async {
        let viewModel = makeViewModel(repository: FailingMomentRepository())
        await viewModel.load()
        #expect(!viewModel.isLoading)
        #expect(viewModel.alert?.title == "Não foi possível abrir os registros")
        #expect(crashReporter.contexts == ["records.load"])
    }

    @Test("new drafts use the injected date")
    func createsDraft() {
        let draft = makeViewModel().newDraft(kind: .event)
        #expect(draft.kind == .event)
        #expect(draft.occurredAt == now)
        #expect(!draft.hasContent)
    }

    @Test("save failure keeps the form open and does not track a successful save")
    func reportsSaveFailure() async {
        let viewModel = makeViewModel(repository: FailingMomentRepository())
        let result = await viewModel.save(MomentDraft(kind: .daily, occurredAt: now, mood: .good), editing: nil)
        #expect(result == .failed)
        #expect(crashReporter.contexts == ["records.save"])
        #expect(analytics.events.isEmpty)
    }

    @Test("delete failure reports an error instead of a successful deletion")
    func reportsDeleteFailure() async {
        let viewModel = makeViewModel(repository: FailingMomentRepository())
        await viewModel.delete(Fixtures.moment(at: "2026-10-10T12:00:00-03:00"))
        #expect(viewModel.alert?.title == "Não foi possível excluir")
        #expect(crashReporter.contexts == ["records.delete"])
        #expect(analytics.events.isEmpty)
    }

    @Test("saving a deleted original does not recreate it")
    func doesNotRecreateDeletedRecord() async throws {
        let repository = LocalMomentRepository(database: database)
        let original = try await repository.create(MomentDraft(kind: .daily, occurredAt: now, mood: .good))
        try await repository.delete(original)
        let viewModel = makeViewModel()
        #expect(await viewModel.save(MomentDraft(editing: original), editing: original) == .failed)
        #expect(try await repository.list().isEmpty)
    }

    @Test("returning to the screen refreshes records saved by another caller")
    func reloadsExternalChanges() async throws {
        let viewModel = makeViewModel()
        await viewModel.load()
        #expect(viewModel.moments.isEmpty)
        let moment = try await LocalMomentRepository(database: database).create(MomentDraft(kind: .daily, occurredAt: now, mood: .okay))
        await viewModel.load()
        #expect(viewModel.moments.map(\.id) == [moment.id])
    }

    @Test("deleting a stale version leaves the latest version saved")
    func staleDeleteKeepsLatest() async throws {
        let repository = LocalMomentRepository(database: database)
        let original = try await repository.create(MomentDraft(kind: .daily, occurredAt: now, mood: .good))
        var updated = original
        updated.note = "latest"
        _ = try await repository.update(updated)
        let viewModel = makeViewModel()
        await viewModel.delete(original)
        #expect(viewModel.alert != nil)
        #expect(try await repository.list().map(\.note) == ["latest"])
    }

    @Test("editing only text preserves the record time and original time zone")
    func editingPreservesDate() async throws {
        let original = Fixtures.moment(at: "2026-09-20T10:00:00-03:00", note: "original")
        let viewModel = makeViewModel(repository: LocalMomentRepository(database: LocalDatabase(inMemory: .init(moments: [original]))))
        var draft = MomentDraft(editing: original)
        draft.note = "edited"
        #expect(await viewModel.save(draft, editing: original) == .saved)
        #expect(viewModel.moments.first?.occurredAt == original.occurredAt)
        #expect(viewModel.moments.first?.timeZoneIdentifier == original.timeZoneIdentifier)
    }
}
