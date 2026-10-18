import Foundation

/// Um dia do calendário (sem hora), como "2026-09-20".
///
/// O resumo filtra por dia *local do momento*: um registro feito às 23h em São Paulo
/// pertence àquele dia, mesmo que em UTC já seja o dia seguinte.
public struct LocalDay: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, in timeZone: TimeZone) {
        let components = Self.calendar(in: timeZone).dateComponents([.year, .month, .day], from: date)
        self.init(year: components.year ?? 0, month: components.month ?? 0, day: components.day ?? 0)
    }

    /// Lê "AAAA-MM-DD" e rejeita datas impossíveis, como 2026-02-31.
    public init?(isoString: String) {
        let parts = isoString.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let candidate = LocalDay(year: parts[0], month: parts[1], day: parts[2])
        guard let date = candidate.startOfDay(in: .gmt),
              LocalDay(date, in: .gmt) == candidate
        else { return nil }
        self = candidate
    }

    public func startOfDay(in timeZone: TimeZone) -> Date? {
        Self.calendar(in: timeZone).date(from: DateComponents(year: year, month: month, day: day))
    }

    public func adding(days: Int) -> LocalDay {
        guard let start = startOfDay(in: .gmt),
              let shifted = Self.calendar(in: .gmt).date(byAdding: .day, value: days, to: start)
        else { return self }
        return LocalDay(shifted, in: .gmt)
    }

    public static func < (lhs: LocalDay, rhs: LocalDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static func calendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}
