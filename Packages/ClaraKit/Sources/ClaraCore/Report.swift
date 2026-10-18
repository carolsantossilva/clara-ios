import Foundation

public struct ReportSelection: Sendable {
    public var start: LocalDay
    public var end: LocalDay
    public var momentIDs: Set<UUID>
    public var questionsAndNotes: String

    public init(start: LocalDay, end: LocalDay, momentIDs: Set<UUID>, questionsAndNotes: String) {
        self.start = start
        self.end = end
        self.momentIDs = momentIDs
        self.questionsAndNotes = questionsAndNotes
    }
}

public struct ReportDocument: Equatable, Sendable {
    public let start: LocalDay
    public let end: LocalDay
    public let entries: [Moment]
    public let questionsAndNotes: String
}

/// Monta o resumo para consulta. Função pura: mesma entrada, mesma saída —
/// por isso é a parte mais fácil (e mais importante) de testar.
public enum ReportBuilder {
    public static func build(_ selection: ReportSelection, from moments: [Moment]) -> ReportDocument {
        let entries = moments
            .filter { $0.deletedAt == nil && selection.momentIDs.contains($0.id) }
            .filter { moment in
                let day = LocalDay(moment.occurredAt, in: moment.timeZone)
                return day >= selection.start && day <= selection.end
            }
            .sorted { $0.occurredAt < $1.occurredAt }

        return ReportDocument(
            start: selection.start,
            end: selection.end,
            entries: entries,
            questionsAndNotes: selection.questionsAndNotes
        )
    }

    /// Todos os registros dentro do período, independentemente da seleção.
    public static func eligible(start: LocalDay, end: LocalDay, in moments: [Moment]) -> [Moment] {
        let everything = ReportSelection(
            start: start,
            end: end,
            momentIDs: Set(moments.map(\.id)),
            questionsAndNotes: ""
        )
        return build(everything, from: moments).entries
    }
}

public enum ClaraFormat {
    public static let locale = Locale(identifier: "pt_BR")

    /// `Date.FormatStyle` é um tipo de valor barato e com cache interno. Criar um
    /// `DateFormatter` por célula/linha é um clássico problema de performance.
    public static func dateTime(_ date: Date, in timeZone: TimeZone) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale, timeZone: timeZone))
    }

    public static func shortDate(_ date: Date, in timeZone: TimeZone = .current) -> String {
        date.formatted(Date.FormatStyle(date: .numeric, time: .omitted, locale: locale, timeZone: timeZone))
    }
}
