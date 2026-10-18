import Foundation

// Contratos de persistência. As features dependem destes protocolos, não da
// implementação (Dependency Inversion): em produção entra o banco local, nos
// testes entra um banco em memória ou um dublê que falha de propósito.

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
    /// Falha com `StorageError.conflict` se o registro mudou desde que foi lido.
    @discardableResult
    func update(_ moment: Moment) async throws -> Moment
    func delete(_ moment: Moment) async throws
}

public enum StorageError: Error, Equatable {
    case notFound
    /// Controle de concorrência otimista: a revisão salva não é a que foi editada.
    case conflict
}
