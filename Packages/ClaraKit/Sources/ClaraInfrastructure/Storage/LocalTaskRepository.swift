import ClaraCore
import Foundation

// Repository implementations on top of LocalDatabase.
// `now` is injected so tests control time (without depending on the real clock).

public struct LocalTaskRepository: TaskRepository {
    // MARK: - Dependencies

    private let database: LocalDatabase
    private let now: @Sendable () -> Date

    // MARK: - Initialization

    public init(database: LocalDatabase, now: @escaping @Sendable () -> Date = { .now }) {
        self.database = database
        self.now = now
    }

    // MARK: - Repository operations

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

    // MARK: - Mutation helper

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
