import Foundation

public protocol MomentRepository: Sendable {
    func list() async throws -> [Moment]
    @discardableResult
    func create(_ draft: MomentDraft) async throws -> Moment
    /// Fails with `StorageError.conflict` if the record changed since it was read.
    @discardableResult
    func update(_ moment: Moment) async throws -> Moment
    func delete(_ moment: Moment) async throws
}
