import Foundation

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
