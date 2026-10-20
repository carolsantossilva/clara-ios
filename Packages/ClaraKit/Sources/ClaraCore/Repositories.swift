import Foundation

// Persistence contracts. Features depend on these protocols, not on the
// implementation (Dependency Inversion): production uses the local database,
// tests use an in-memory database or a double that fails on purpose.

public protocol TaskRepository: Sendable {
    func create(title: String, nextAction: String) async throws -> FocusTask
    func listOpen() async throws -> [FocusTask]
    func focusID() async throws -> UUID?
    func setFocus(_ id: UUID) async throws
    @discardableResult
    func savePause(id: UUID, whereStopped: String, nextAction: String) async throws -> FocusTask?
    @discardableResult
    func updateNextAction(id: UUID, nextAction: String) async throws -> FocusTask?
    @discardableResult
    func setState(id: UUID, _ state: FocusTask.State) async throws -> FocusTask?
}

public protocol ParkingRepository: Sendable {
    @discardableResult
    func create(text: String) async throws -> ParkingNote
    func listOpen() async throws -> [ParkingNote]
    func complete(id: UUID) async throws
}

public protocol MomentRepository: Sendable {
    func list() async throws -> [Moment]
    @discardableResult
    func create(_ draft: MomentDraft) async throws -> Moment
    /// Fails with `StorageError.conflict` if the record changed since it was read.
    @discardableResult
    func update(_ moment: Moment) async throws -> Moment
    func delete(_ moment: Moment) async throws
}

public enum StorageError: Error, Equatable {
    case notFound
    /// Optimistic concurrency control: the saved revision is not the one that was edited.
    case conflict
}
