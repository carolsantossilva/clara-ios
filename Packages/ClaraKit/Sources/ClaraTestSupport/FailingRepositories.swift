import ClaraCore
import Foundation

// MARK: - Repositórios que falham

public struct TestError: Error, Equatable {
    public init() {}
}

public struct FailingTaskRepository: TaskRepository {
    public init() {}
    public func create(title: String, nextAction: String) async throws -> FocusTask { throw TestError() }
    public func listOpen() async throws -> [FocusTask] { throw TestError() }
    public func focusID() async throws -> UUID? { throw TestError() }
    public func setFocus(_ id: UUID) async throws { throw TestError() }
    public func savePause(id: UUID, whereStopped: String, nextAction: String) async throws -> FocusTask? { throw TestError() }
    public func updateNextAction(id: UUID, nextAction: String) async throws -> FocusTask? { throw TestError() }
    public func setState(id: UUID, _ state: FocusTask.State) async throws -> FocusTask? { throw TestError() }
}

public struct FailingMomentRepository: MomentRepository {
    public init() {}
    public func list() async throws -> [Moment] { throw TestError() }
    public func create(_ draft: MomentDraft) async throws -> Moment { throw TestError() }
    public func update(_ moment: Moment) async throws -> Moment { throw TestError() }
    public func delete(_ moment: Moment) async throws { throw TestError() }
}
