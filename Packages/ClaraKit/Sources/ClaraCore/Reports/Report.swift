import Foundation

// MARK: - Report input

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

// MARK: - Report output

public struct ReportDocument: Equatable, Sendable {
    public let start: LocalDay
    public let end: LocalDay
    public let entries: [Moment]
    public let questionsAndNotes: String
}

// MARK: - Report building

/// Builds the summary for an appointment. A pure function: same input, same output,
/// which makes it the easiest (and most important) part to test.
public enum ReportBuilder {
    public static func build(_ selection: ReportSelection, from moments: [Moment]) -> ReportDocument {
        let entries = moments
            .filter { $0.deletedAt == nil && selection.momentIDs.contains($0.id) }
            .filter { moment in
                guard let day = LocalDay(moment.occurredAt, in: moment.timeZone) else { return false }
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

    /// Every record within the period, regardless of the selection.
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

// MARK: - Date formatting

public enum ClaraFormat {
    public static let locale = Locale(identifier: "pt_BR")

    /// `Date.FormatStyle` is a cheap value type with an internal cache. Creating a
    /// `DateFormatter` per cell/row is a classic performance problem.
    public static func dateTime(_ date: Date, in timeZone: TimeZone) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale, timeZone: timeZone))
    }

    public static func shortDate(_ date: Date, in timeZone: TimeZone = .current) -> String {
        date.formatted(Date.FormatStyle(date: .numeric, time: .omitted, locale: locale, timeZone: timeZone))
    }
}
