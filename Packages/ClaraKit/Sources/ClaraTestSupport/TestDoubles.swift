import ClaraAI
import ClaraCore
import ClaraNetworking
import ClaraServices
import Foundation

// Dublês compartilhados entre as suítes. Ficam num target próprio (não de teste)
// para que várias suítes os importem sem duplicação.

// MARK: - Relógio imediato

/// Relógio que não espera: `sleep` só cede a vez. Testes de timer rodam em
/// milissegundos e sem depender do tempo real (uma fonte clássica de flakiness).
public struct ImmediateClock: Clock {
    public struct Instant: InstantProtocol {
        public var offset: Duration

        public func advanced(by duration: Duration) -> Instant {
            Instant(offset: offset + duration)
        }

        public func duration(to other: Instant) -> Duration {
            other.offset - offset
        }

        public static func < (lhs: Instant, rhs: Instant) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    public init() {}

    public var now: Instant { Instant(offset: .zero) }
    public var minimumResolution: Duration { .zero }

    public func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        try Task.checkCancellation()
        await Task.yield()
    }
}

/// "Agora" que avança um segundo a cada leitura. Garante ordem estável entre
/// registros criados em sequência — com `Date()` real, dois registros podem
/// ganhar o mesmo instante e a ordenação do teste viraria sorte.
public final class SteppingNow: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    public init(start: Date = Date(timeIntervalSince1970: 1_790_000_000)) {
        current = start
    }

    public var read: @Sendable () -> Date {
        { [self] in
            lock.withLock {
                current = current.addingTimeInterval(1)
                return current
            }
        }
    }
}

// MARK: - HTTP

public struct FakeHTTPClientError: Error, Equatable {
    public init() {}
}

public final class FakeHTTPClient: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var paths: [String] = []
    private let responder: @Sendable (String) async throws -> any Sendable

    /// - Parameter responder: recebe o `path` pedido e devolve a resposta já decodificada.
    public init(responder: @escaping @Sendable (String) async throws -> any Sendable) {
        self.responder = responder
    }

    public var requestedPaths: [String] {
        lock.withLock { paths }
    }

    public func send<E: Endpoint>(_ endpoint: E) async throws -> E.Response {
        lock.withLock { paths.append(endpoint.path) }
        let value = try await responder(endpoint.path)
        guard let typed = value as? E.Response else { throw FakeHTTPClientError() }
        return typed
    }
}

// MARK: - Analytics e crash

public final class SpyAnalyticsTracker: AnalyticsTracker, @unchecked Sendable {
    private let lock = NSLock()
    private var tracked: [AnalyticsEvent] = []

    public init() {}

    public var events: [AnalyticsEvent] { lock.withLock { tracked } }
    public var names: [String] { events.map(\.name) }

    public func track(_ event: AnalyticsEvent) {
        lock.withLock { tracked.append(event) }
    }
}

public final class SpyCrashReporter: CrashReporter, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []

    public init() {}

    public var contexts: [String] { lock.withLock { recorded } }

    public func record(_ error: any Error, context: String) {
        lock.withLock { recorded.append(context) }
    }

    public func breadcrumb(_ message: String) {}
}

// MARK: - IA

public struct StubStepSuggester: StepSuggesting {
    public enum Behavior: Sendable {
        case succeed([String])
        case fail
        case hang
        case unavailable
    }

    private let behavior: Behavior
    private let source: StepSuggestion.Source

    public init(_ behavior: Behavior, source: StepSuggestion.Source = .onDevice) {
        self.behavior = behavior
        self.source = source
    }

    public var isAvailable: Bool {
        get async {
            if case .unavailable = behavior { return false }
            return true
        }
    }

    public func suggestSteps(for taskTitle: String) async throws -> StepSuggestion {
        switch behavior {
        case .succeed(let steps):
            return StepSuggestion(steps: steps, source: source)
        case .fail, .unavailable:
            throw StepSuggestionError.unavailable
        case .hang:
            try await Task.sleep(for: .seconds(3600))
            throw StepSuggestionError.unavailable
        }
    }
}

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

// MARK: - Fixtures

public enum Fixtures {
    public static let saoPaulo = "America/Sao_Paulo"

    public static func date(_ iso: String) -> Date {
        guard let date = ISO8601DateFormatter().date(from: iso) else {
            preconditionFailure("Data ISO inválida no teste: \(iso)")
        }
        return date
    }

    public static func moment(
        id: UUID = UUID(),
        kind: Moment.Kind = .event,
        at iso: String,
        timeZone: String = saoPaulo,
        mood: Mood? = nil,
        note: String = "",
        context: String = "",
        helpedOrHindered: String = "",
        revision: Int = 1,
        deletedAt: Date? = nil
    ) -> Moment {
        Moment(
            id: id,
            kind: kind,
            occurredAt: date(iso),
            timeZoneIdentifier: timeZone,
            mood: mood,
            note: note,
            context: context,
            helpedOrHindered: helpedOrHindered,
            revision: revision,
            updatedAt: date(iso),
            deletedAt: deletedAt
        )
    }
}
