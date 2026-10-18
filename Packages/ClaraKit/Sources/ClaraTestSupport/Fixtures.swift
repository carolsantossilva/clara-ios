import ClaraCore
import Foundation

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
