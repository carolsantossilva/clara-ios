import ClaraCore
import Foundation

public struct LocalDistractionRepository: DistractionRepository {
    // MARK: - Dependencies

    private let database: LocalDatabase
    private let now: @Sendable () -> Date

    // MARK: - Initialization

    public init(database: LocalDatabase, now: @escaping @Sendable () -> Date = { .now }) {
        self.database = database
        self.now = now
    }

    // MARK: - Repository operations

    public func create(text: String) async throws -> Distraction {
        let distraction = Distraction(text: text.trimmed, updatedAt: now())
        try await database.write { $0.distractions.append(distraction) }
        return distraction
    }

    public func listOpen() async throws -> [Distraction] {
        await database.read { snapshot in
            snapshot.distractions
                .filter { !$0.completed && $0.deletedAt == nil }
                .sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    public func complete(id: UUID) async throws {
        let date = now()
        try await database.write { snapshot in
            guard let index = snapshot.distractions.firstIndex(where: { $0.id == id }) else { return }
            snapshot.distractions[index].completed = true
            snapshot.distractions[index].revision += 1
            snapshot.distractions[index].updatedAt = date
        }
    }
}
