import Foundation

/// A distraction the user set aside to return to later.
public struct Distraction: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var text: String
    public var completed: Bool
    public var revision: Int
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        text: String,
        completed: Bool = false,
        revision: Int = 1,
        updatedAt: Date,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.text = text
        self.completed = completed
        self.revision = revision
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}
