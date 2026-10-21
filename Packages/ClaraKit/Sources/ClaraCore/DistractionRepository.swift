import Foundation

public protocol DistractionRepository: Sendable {
    @discardableResult
    func create(text: String) async throws -> Distraction
    func listOpen() async throws -> [Distraction]
    func complete(id: UUID) async throws
}
