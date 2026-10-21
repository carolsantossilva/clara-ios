import ClaraCore
import Foundation

public struct LocalMomentRepository: MomentRepository {
    // MARK: - Dependencies

    private let database: LocalDatabase
    private let now: @Sendable () -> Date
    private let timeZone: @Sendable () -> TimeZone

    // MARK: - Initialization

    public init(
        database: LocalDatabase,
        now: @escaping @Sendable () -> Date = { .now },
        timeZone: @escaping @Sendable () -> TimeZone = { .current }
    ) {
        self.database = database
        self.now = now
        self.timeZone = timeZone
    }

    // MARK: - Repository operations

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
