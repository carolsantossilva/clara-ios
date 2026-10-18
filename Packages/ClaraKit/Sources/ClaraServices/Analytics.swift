import Foundation
import os

public struct AnalyticsEvent: Equatable, Sendable {
    public let name: String
    public let properties: [String: String]

    public init(name: String, properties: [String: String] = [:]) {
        self.name = name
        self.properties = properties
    }
}

public protocol AnalyticsTracker: Sendable {
    func track(_ event: AnalyticsEvent)
}

// MARK: - Destinos com associatedtype + type erasure

/// Cada ferramenta (Firebase, Amplitude, Mixpanel, log local) quer o evento num
/// formato próprio: `Payload`. Por causa do associatedtype, não dá para guardar
/// `[any AnalyticsDestination]` e chamar `deliver` diretamente sem abrir o tipo —
/// por isso existe o `AnyAnalyticsDestination` logo abaixo.
public protocol AnalyticsDestination: Sendable {
    associatedtype Payload
    func makePayload(for event: AnalyticsEvent) -> Payload?
    func deliver(_ payload: Payload)
}

/// Type erasure: esconde o `Payload` concreto atrás de uma closure, permitindo
/// uma lista heterogênea de destinos.
public struct AnyAnalyticsDestination: AnalyticsTracker {
    public let name: String
    private let trackEvent: @Sendable (AnalyticsEvent) -> Void

    public init<Destination: AnalyticsDestination>(_ destination: Destination, name: String? = nil) {
        self.name = name ?? String(describing: Destination.self)
        self.trackEvent = { event in
            guard let payload = destination.makePayload(for: event) else { return }
            destination.deliver(payload)
        }
    }

    public func track(_ event: AnalyticsEvent) {
        trackEvent(event)
    }
}

/// Destino de desenvolvimento: escreve no Console/Xcode via os.Logger.
public struct ConsoleAnalyticsDestination: AnalyticsDestination {
    private let logger = Logger(subsystem: "app.clara", category: "analytics")

    public init() {}

    public func makePayload(for event: AnalyticsEvent) -> String? {
        let properties = event.properties
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        return "\(event.name) \(properties)"
    }

    public func deliver(_ payload: String) {
        logger.info("\(payload, privacy: .public)")
    }
}

/// Destino que guarda os últimos eventos na memória (painel de diagnóstico e testes).
public struct BufferAnalyticsDestination: AnalyticsDestination {
    private let buffer: AnalyticsEventBuffer

    public init(buffer: AnalyticsEventBuffer) {
        self.buffer = buffer
    }

    public func makePayload(for event: AnalyticsEvent) -> AnalyticsEvent? { event }

    public func deliver(_ payload: AnalyticsEvent) {
        buffer.append(payload)
    }
}

// MARK: - Buffer thread-safe com GCD

/// Exemplo clássico de leitores/escritor com GCD: fila concorrente, leituras com
/// `sync` em paralelo e escritas com `.barrier` (exclusivas).
///
/// `@unchecked Sendable` é uma promessa ao compilador de que a sincronização é
/// manual. Com Swift Concurrency, o equivalente seria um `actor` — mas aí toda
/// leitura viraria `await`, o que não serve para quem chama de código síncrono.
public final class AnalyticsEventBuffer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.clara.analytics.buffer", attributes: .concurrent)
    private var storage: [AnalyticsEvent] = []
    private let capacity: Int

    public init(capacity: Int = 50) {
        self.capacity = capacity
    }

    public func append(_ event: AnalyticsEvent) {
        queue.async(flags: .barrier) {
            self.storage.append(event)
            if self.storage.count > self.capacity {
                self.storage.removeFirst(self.storage.count - self.capacity)
            }
        }
    }

    public var events: [AnalyticsEvent] {
        queue.sync { storage }
    }
}

// MARK: - Serviço com consentimento

/// O Clara nasceu sem analytics. Aqui o rastreamento é opt-in, desligado por padrão,
/// e os eventos nunca carregam texto escrito pela usuária (veja `ClaraEvent`).
public final class AnalyticsService: AnalyticsTracker, Sendable {
    private let destinations: [AnyAnalyticsDestination]
    // O lock guarda o estado e é Sendable: o compilador confere a thread safety,
    // sem precisar de @unchecked (compare com AnalyticsEventBuffer, acima).
    private let consent: OSAllocatedUnfairLock<Bool>

    public init(destinations: [AnyAnalyticsDestination], hasConsent: Bool) {
        self.destinations = destinations
        self.consent = OSAllocatedUnfairLock(initialState: hasConsent)
    }

    public var hasConsent: Bool {
        get { consent.withLock { $0 } }
        set { consent.withLock { $0 = newValue } }
    }

    public func track(_ event: AnalyticsEvent) {
        guard hasConsent else { return }
        for destination in destinations {
            destination.track(event)
        }
    }
}

// MARK: - Catálogo de eventos

/// Todos os eventos do app num só lugar. Propriedades são enums/números, nunca o
/// conteúdo de tarefas ou registros.
public enum ClaraEvent: Equatable, Sendable {
    case taskCreated(hasFirstStep: Bool)
    case focusStarted(minutes: Int, variant: String?)
    case focusPaused(savedClue: Bool)
    case taskCompleted
    case parkingNoteSaved
    case momentSaved(kind: String, isEdit: Bool)
    case momentDeleted
    case reportExported(entries: Int)
    case stepSuggestionsShown(source: String)
    case stepSuggestionAccepted(source: String)
    case holidayBannerShown

    public var analyticsEvent: AnalyticsEvent {
        switch self {
        case .taskCreated(let hasFirstStep):
            AnalyticsEvent(name: "task_created", properties: ["has_first_step": String(hasFirstStep)])
        case .focusStarted(let minutes, let variant):
            AnalyticsEvent(name: "focus_started", properties: ["minutes": String(minutes), "variant": variant ?? "none"])
        case .focusPaused(let savedClue):
            AnalyticsEvent(name: "focus_paused", properties: ["saved_clue": String(savedClue)])
        case .taskCompleted:
            AnalyticsEvent(name: "task_completed")
        case .parkingNoteSaved:
            AnalyticsEvent(name: "parking_note_saved")
        case .momentSaved(let kind, let isEdit):
            AnalyticsEvent(name: "moment_saved", properties: ["kind": kind, "is_edit": String(isEdit)])
        case .momentDeleted:
            AnalyticsEvent(name: "moment_deleted")
        case .reportExported(let entries):
            AnalyticsEvent(name: "report_exported", properties: ["entries": String(entries)])
        case .stepSuggestionsShown(let source):
            AnalyticsEvent(name: "step_suggestions_shown", properties: ["source": source])
        case .stepSuggestionAccepted(let source):
            AnalyticsEvent(name: "step_suggestion_accepted", properties: ["source": source])
        case .holidayBannerShown:
            AnalyticsEvent(name: "holiday_banner_shown")
        }
    }
}

extension AnalyticsTracker {
    public func track(_ event: ClaraEvent) {
        track(event.analyticsEvent)
    }
}

public struct NoOpAnalyticsTracker: AnalyticsTracker {
    public init() {}
    public func track(_ event: AnalyticsEvent) {}
}
