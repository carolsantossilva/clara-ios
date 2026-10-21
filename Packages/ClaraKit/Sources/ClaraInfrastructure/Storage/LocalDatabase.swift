import ClaraCore
import Foundation

/// The app's local database: a single JSON file protected by iOS.
///
/// Why an `actor`? Several screens read and write at the same time. The actor serializes
/// access to `snapshot` without manual locks: the compiler forbids outside access
/// without `await`, which rules out data races in this part of the app.
///
/// Trade-off: for a personal-use MVP the volume is small and JSON is enough.
/// With thousands of records, the next step would be SQLite (GRDB/SwiftData)
/// behind the same repository protocols; the features would not change.
public actor LocalDatabase {
    // MARK: - Snapshot

    /// A value snapshot of all persisted records, encoded as the database JSON file.
    public struct Snapshot: Codable, Equatable, Sendable {
        public var tasks: [FocusTask]
        public var distractions: [Distraction]
        public var moments: [Moment]
        public var focusID: UUID?

        public init(
            tasks: [FocusTask] = [],
            distractions: [Distraction] = [],
            moments: [Moment] = [],
            focusID: UUID? = nil
        ) {
            self.tasks = tasks
            self.distractions = distractions
            self.moments = moments
            self.focusID = focusID
        }
    }

    // MARK: - State

    private var snapshot: Snapshot
    private let fileURL: URL?

    // MARK: - Initialization

    /// - Parameter fileURL: `nil` keeps everything in memory (tests, previews, UI tests).
    public init(fileURL: URL?) throws {
        self.fileURL = fileURL
        if let fileURL, FileManager.default.fileExists(atPath: fileURL.path) {
            try Self.excludeFromBackup(fileURL)
            let data = try Data(contentsOf: fileURL)
            snapshot = try Self.makeDecoder().decode(Snapshot.self, from: data)
        } else {
            snapshot = Snapshot()
        }
    }

    public init(inMemory snapshot: Snapshot = Snapshot()) {
        self.fileURL = nil
        self.snapshot = snapshot
    }

    // MARK: - Reading and writing

    public static func defaultFileURL() throws -> URL {
        let directory = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Clara", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("clara.json")
    }

    public func read<T: Sendable>(_ body: @Sendable (Snapshot) throws -> T) rethrows -> T {
        try body(snapshot)
    }

    /// Changes a copy and only publishes the change if writing to disk succeeds.
    /// That way a write failure never leaves memory and disk out of sync.
    public func write<T: Sendable>(_ body: @Sendable (inout Snapshot) throws -> T) throws -> T {
        var copy = snapshot
        let result = try body(&copy)
        try persist(copy)
        snapshot = copy
        return result
    }

    // MARK: - Persistence

    private func persist(_ snapshot: Snapshot) throws {
        guard let fileURL else { return }
        let data = try Self.makeEncoder().encode(snapshot)
        // .completeFileProtection: the file stays encrypted while the device is locked.
        // Records may contain health information (sensitive data under Brazil's LGPD).
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        // Atomic replacement may reset this attribute, so restore it after every write.
        try Self.excludeFromBackup(fileURL)
    }

    private static func excludeFromBackup(_ fileURL: URL) throws {
        var fileURL = fileURL
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try fileURL.setResourceValues(resourceValues)
    }

    // MARK: - JSON coding

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
