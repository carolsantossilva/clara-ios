import ClaraCore
import Foundation

// Repository implementations on top of LocalDatabase.
// `now` is injected so tests control time (without depending on the real clock).

public struct LocalTaskRepository: TaskRepository {
    private let database: LocalDatabase
    private let now: @Sendable () -> Date

    public init(database: LocalDatabase, now: @escaping @Sendable () -> Date = { .now }) {
        self.database = database
        self.now = now
    }

    public func create(title: String, nextAction: String) async throws -> FocusTask {
        let task = FocusTask(title: title.trimmed, nextAction: nextAction.trimmed, updatedAt: now())
        try await database.write { $0.tasks.append(task) }
        return task
    }

    public func listOpen() async throws -> [FocusTask] {
        await database.read { snapshot in
            snapshot.tasks
                .filter { $0.state == .open && $0.deletedAt == nil }
                .sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    public func focusID() async throws -> UUID? {
        await database.read { $0.focusID }
    }

    public func setFocus(_ id: UUID) async throws {
        try await database.write { $0.focusID = id }
    }

    public func savePause(id: UUID, whereStopped: String, nextAction: String) async throws -> FocusTask? {
        try await mutateTask(id: id) { task in
            task.whereStopped = whereStopped.trimmed
            task.nextAction = nextAction.trimmed
        }
    }

    public func updateNextAction(id: UUID, nextAction: String) async throws -> FocusTask? {
        try await mutateTask(id: id) { $0.nextAction = nextAction.trimmed }
    }

    public func setState(id: UUID, _ state: FocusTask.State) async throws -> FocusTask? {
        try await mutateTask(id: id) { $0.state = state }
    }

    private func mutateTask(
        id: UUID,
        _ change: @escaping @Sendable (inout FocusTask) -> Void
    ) async throws -> FocusTask? {
        let date = now()
        return try await database.write { snapshot in
            guard let index = snapshot.tasks.firstIndex(where: { $0.id == id && $0.deletedAt == nil }) else {
                return nil
            }
            change(&snapshot.tasks[index])
            snapshot.tasks[index].revision += 1
            snapshot.tasks[index].updatedAt = date
            return snapshot.tasks[index]
        }
    }
}

public struct LocalParkingRepository: ParkingRepository {
    private let database: LocalDatabase
    private let now: @Sendable () -> Date

    public init(database: LocalDatabase, now: @escaping @Sendable () -> Date = { .now }) {
        self.database = database
        self.now = now
    }

    public func create(text: String) async throws -> ParkingNote {
        let note = ParkingNote(text: text.trimmed, updatedAt: now())
        try await database.write { $0.parkingNotes.append(note) }
        return note
    }

    public func listOpen() async throws -> [ParkingNote] {
        await database.read { snapshot in
            snapshot.parkingNotes
                .filter { !$0.completed && $0.deletedAt == nil }
                .sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    public func complete(id: UUID) async throws {
        let date = now()
        try await database.write { snapshot in
            guard let index = snapshot.parkingNotes.firstIndex(where: { $0.id == id }) else { return }
            snapshot.parkingNotes[index].completed = true
            snapshot.parkingNotes[index].revision += 1
            snapshot.parkingNotes[index].updatedAt = date
        }
    }
}

public struct LocalMomentRepository: MomentRepository {
    private let database: LocalDatabase
    private let now: @Sendable () -> Date
    private let timeZone: @Sendable () -> TimeZone

    public init(
        database: LocalDatabase,
        now: @escaping @Sendable () -> Date = { .now },
        timeZone: @escaping @Sendable () -> TimeZone = { .current }
    ) {
        self.database = database
        self.now = now
        self.timeZone = timeZone
    }

    public func list() async throws -> [Moment] {
        await database.read { snapshot in
            snapshot.moments
                .filter { $0.deletedAt == nil }
                .sorted { $0.occurredAt > $1.occurredAt }
        }
    }

    public func create(_ draft: MomentDraft) async throws -> Moment {
        let date = now()
        let moment = Moment(
            kind: draft.kind,
            // A daily check-in is for "now"; a one-off moment uses the chosen time.
            occurredAt: draft.kind == .daily ? date : draft.occurredAt,
            timeZoneIdentifier: timeZone().identifier,
            mood: draft.mood,
            note: draft.note,
            context: draft.context,
            helpedOrHindered: draft.helpedOrHindered,
            updatedAt: date
        )
        try await database.write { $0.moments.append(moment) }
        return moment
    }

    public func update(_ moment: Moment) async throws -> Moment {
        let date = now()
        return try await database.write { snapshot in
            guard let index = snapshot.moments.firstIndex(where: { $0.id == moment.id && $0.deletedAt == nil }) else {
                throw StorageError.notFound
            }
            // Equivalent to the original app's `UPDATE ... WHERE revision = ?`.
            guard snapshot.moments[index].revision == moment.revision else {
                throw StorageError.conflict
            }
            var updated = moment
            updated.revision += 1
            updated.updatedAt = date
            snapshot.moments[index] = updated
            return updated
        }
    }

    public func delete(_ moment: Moment) async throws {
        let date = now()
        try await database.write { snapshot in
            guard let index = snapshot.moments.firstIndex(where: { $0.id == moment.id }) else {
                throw StorageError.notFound
            }
            guard snapshot.moments[index].revision == moment.revision else {
                throw StorageError.conflict
            }
            // Soft delete: keeps the history for a future sync.
            snapshot.moments[index].deletedAt = date
            snapshot.moments[index].revision += 1
            snapshot.moments[index].updatedAt = date
        }
    }
}
