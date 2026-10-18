import ClaraCore
import Foundation

/// Banco local do app: um único arquivo JSON protegido pelo iOS.
///
/// Por que `actor`? Várias telas leem e gravam ao mesmo tempo. O actor serializa
/// o acesso ao `snapshot` sem locks manuais: o compilador impede acesso de fora
/// sem `await`, o que elimina data races nessa parte do app.
///
/// Trade-off: para um MVP de uso pessoal o volume é pequeno e JSON é suficiente.
/// Com milhares de registros, o próximo passo seria SQLite (GRDB/SwiftData)
/// atrás dos mesmos protocolos de repositório — as features não mudariam.
public actor LocalDatabase {
    public struct Snapshot: Codable, Equatable, Sendable {
        public var tasks: [FocusTask]
        public var parkingNotes: [ParkingNote]
        public var moments: [Moment]
        public var focusID: UUID?

        public init(
            tasks: [FocusTask] = [],
            parkingNotes: [ParkingNote] = [],
            moments: [Moment] = [],
            focusID: UUID? = nil
        ) {
            self.tasks = tasks
            self.parkingNotes = parkingNotes
            self.moments = moments
            self.focusID = focusID
        }
    }

    private var snapshot: Snapshot
    private let fileURL: URL?

    /// - Parameter fileURL: `nil` mantém tudo em memória (testes, previews, UI tests).
    public init(fileURL: URL?) throws {
        self.fileURL = fileURL
        if let fileURL, FileManager.default.fileExists(atPath: fileURL.path) {
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

    /// Altera uma cópia e só publica a mudança se a gravação em disco der certo.
    /// Assim, uma falha de escrita nunca deixa memória e disco divergentes.
    public func write<T: Sendable>(_ body: @Sendable (inout Snapshot) throws -> T) throws -> T {
        var copy = snapshot
        let result = try body(&copy)
        try persist(copy)
        snapshot = copy
        return result
    }

    private func persist(_ snapshot: Snapshot) throws {
        guard let fileURL else { return }
        let data = try Self.makeEncoder().encode(snapshot)
        // .completeFileProtection: o arquivo fica cifrado enquanto o aparelho está bloqueado.
        // Os registros podem conter informação de saúde (dado sensível pela LGPD).
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

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
