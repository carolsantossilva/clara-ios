import ClaraCore
import ClaraInfrastructure
import Foundation
import Observation

public enum MomentSaveResult: Equatable, Sendable {
    case saved
    case needsContent
    case failed
}

@MainActor
@Observable
public final class RecordsViewModel {
    public private(set) var moments: [Moment] = []
    public private(set) var isLoading = true
    public var alert: AlertContent?

    @ObservationIgnored private let repository: any MomentRepository
    @ObservationIgnored private let analytics: any AnalyticsTracker
    @ObservationIgnored private let crashReporter: any CrashReporter
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let timeZone: @Sendable () -> TimeZone

    public init(
        repository: any MomentRepository,
        analytics: any AnalyticsTracker,
        crashReporter: any CrashReporter,
        now: @escaping @Sendable () -> Date = { .now },
        timeZone: @escaping @Sendable () -> TimeZone = { .current }
    ) {
        self.repository = repository
        self.analytics = analytics
        self.crashReporter = crashReporter
        self.now = now
        self.timeZone = timeZone
    }

    public func load() async {
        defer { isLoading = false }
        do {
            moments = try await repository.list()
        } catch is CancellationError {
            return
        } catch {
            crashReporter.record(error, context: "records.load")
            alert = AlertContent(title: "Não foi possível abrir os registros", message: "Seu histórico local continua no aparelho.")
        }
    }

    public func newDraft(kind: Moment.Kind) -> MomentDraft {
        MomentDraft(kind: kind, occurredAt: now())
    }

    public func save(_ draft: MomentDraft, editing original: Moment?) async -> MomentSaveResult {
        guard draft.hasContent else { return .needsContent }
        do {
            if let original {
                try await repository.update(original.applying(draft, currentTimeZone: timeZone()))
            } else {
                try await repository.create(draft)
            }
            analytics.track(.momentSaved(kind: draft.kind.rawValue, isEdit: original != nil))
            await load()
            return .saved
        } catch StorageError.conflict {
            await load()
            alert = AlertContent(title: "Este registro mudou", message: "Abrimos a versão mais recente. Confira e edite de novo, se quiser.")
            return .failed
        } catch {
            crashReporter.record(error, context: "records.save")
            return .failed
        }
    }

    public func delete(_ moment: Moment) async {
        do {
            try await repository.delete(moment)
            analytics.track(.momentDeleted)
            await load()
        } catch {
            crashReporter.record(error, context: "records.delete")
            alert = AlertContent(title: "Não foi possível excluir", message: "Tente novamente.")
        }
    }
}
