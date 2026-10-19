import ClaraCore
import ClaraTestSupport
import Foundation
import os
import Testing
@testable import ClaraStorage

@Suite("Local repositories")
struct LocalRepositoriesTests {
    let t0 = Fixtures.date("2026-09-20T10:00:00Z")

    @Test("creates a trimmed task and lists open ones from newest to oldest")
    func createsAndListsTasks() async throws {
        let database = LocalDatabase(inMemory: .init())
        let clock = TestNow(t0)
        let repository = LocalTaskRepository(database: database, now: clock.read)

        _ = try await repository.create(title: "  Primeira  ", nextAction: "")
        clock.advance(seconds: 60)
        let second = try await repository.create(title: "Segunda", nextAction: " abrir ")

        let open = try await repository.listOpen()
        #expect(open.map(\.title) == ["Segunda", "Primeira"])
        #expect(second.nextAction == "abrir")
    }

    @Test("pausing bumps the revision and completed tasks leave the list")
    func pauseAndComplete() async throws {
        let repository = LocalTaskRepository(database: LocalDatabase(inMemory: .init()))
        let task = try await repository.create(title: "Exames", nextAction: "")

        let paused = try await repository.savePause(id: task.id, whereStopped: "documentos", nextAction: "abrir pasta")
        #expect(paused?.revision == 2)
        #expect(paused?.whereStopped == "documentos")

        let done = try await repository.setState(id: task.id, .done)
        #expect(done?.state == .done)
        #expect(try await repository.listOpen().isEmpty)
    }

    @Test("editing a stale version fails with a conflict instead of overwriting")
    func optimisticConcurrency() async throws {
        let repository = LocalMomentRepository(database: LocalDatabase(inMemory: .init()))
        let created = try await repository.create(MomentDraft(kind: .event, occurredAt: t0, note: "original"))

        var firstEdit = created
        firstEdit.note = "primeira edição"
        _ = try await repository.update(firstEdit)

        var staleEdit = created // still on revision 1
        staleEdit.note = "edição atrasada"
        await #expect(throws: StorageError.conflict) {
            try await repository.update(staleEdit)
        }
        #expect(try await repository.list().first?.note == "primeira edição")
    }

    @Test("deletion is soft: the record leaves the list")
    func softDelete() async throws {
        let database = LocalDatabase(inMemory: .init())
        let repository = LocalMomentRepository(database: database)
        let moment = try await repository.create(MomentDraft(kind: .daily, occurredAt: t0, mood: .good))

        try await repository.delete(moment)

        #expect(try await repository.list().isEmpty)
        let stored = await database.read { $0.moments }
        #expect(stored.first?.deletedAt != nil)
    }

    @Test("persists to disk and reloads")
    func persistsToDisk() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("clara-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let first = try LocalDatabase(fileURL: url)
        _ = try await LocalParkingRepository(database: first).create(text: "ligar para a clínica")

        let reopened = try LocalDatabase(fileURL: url)
        let notes = try await LocalParkingRepository(database: reopened).listOpen()
        #expect(notes.map(\.text) == ["ligar para a clínica"])
    }
}

/// Controllable clock for tests (thread-safe because it is read from inside the actor).
final class TestNow: Sendable {
    private let current: OSAllocatedUnfairLock<Date>

    init(_ date: Date) {
        current = OSAllocatedUnfairLock(initialState: date)
    }

    var read: @Sendable () -> Date {
        { [current] in current.withLock { $0 } }
    }

    func advance(seconds: TimeInterval) {
        current.withLock { $0 = $0.addingTimeInterval(seconds) }
    }
}
