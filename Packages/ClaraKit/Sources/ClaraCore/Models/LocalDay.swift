import Foundation

/// A Gregorian calendar day without a time or time zone.
///
/// Use `LocalDay` to compare or group records by their calendar day. Convert a `Date` using
/// the time zone where the event happened so that a late-night record stays on its local day.
///
/// ## Example
///
/// ```swift
/// let day = LocalDay(year: 2026, month: 9, day: 20)
/// let nextDay = try day.adding(days: 1)
/// ```
public struct LocalDay: Comparable, Hashable, Sendable, CustomStringConvertible {
    /// Errors produced by calendar arithmetic.
    public enum AdditionError: Error, Equatable {
        /// The calendar could not represent the starting date or the calculated result.
        case calendarCalculationFailed
    }

    // MARK: - Components

    /// The Gregorian calendar year.
    public let year: Int

    /// The Gregorian calendar month, from 1 through 12 for valid dates.
    public let month: Int

    /// The day of the month for the given year and month.
    public let day: Int

    // MARK: - Initialization

    /// Creates a day from Gregorian calendar components.
    ///
    /// The values are stored as provided. Use `startOfDay(in:)` to check whether they form a
    /// date recognized by the calendar.
    ///
    /// - Parameters:
    ///   - year: The Gregorian calendar year.
    ///   - month: The calendar month.
    ///   - day: The day of the month.
    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Creates a day from a moment in a time zone.
    ///
    /// - Parameters:
    ///   - date: The absolute date to convert.
    ///   - timeZone: The time zone used to determine the calendar day.
    /// - Returns: `nil` if the calendar cannot represent the date or extract its year, month, and day.
    public init?(_ date: Date, in timeZone: TimeZone) {
        let calendar = Self.calendar(in: timeZone)
        guard date.timeIntervalSinceReferenceDate.isFinite,
              let interval = calendar.dateInterval(of: .day, for: date),
              interval.contains(date)
        else { return nil }
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// Creates a day from a hyphen-separated year, month, and day string.
    ///
    /// Rejects incomplete values and impossible dates, such as `2026-02-31`.
    ///
    /// - Parameter isoString: A date written as `YYYY-MM-DD`.
    /// - Returns: `nil` if the string cannot be parsed as a real Gregorian calendar day.
    public init?(isoString: String) {
        let parts = isoString.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let candidate = LocalDay(year: parts[0], month: parts[1], day: parts[2])
        guard let date = candidate.startOfDay(in: .gmt),
              let roundTrip = LocalDay(date, in: .gmt),
              roundTrip == candidate
        else { return nil }
        self = candidate
    }

    // MARK: - Calendar operations

    /// Returns the first representable instant of this day in the given time zone.
    ///
    /// - Parameter timeZone: The time zone in which to construct the date.
    /// - Returns: `nil` if these components do not form a date the calendar can represent.
    public func startOfDay(in timeZone: TimeZone) -> Date? {
        Self.calendar(in: timeZone).date(from: DateComponents(year: year, month: month, day: day))
    }

    /// Returns the day that many calendar days before or after this one.
    ///
    /// - Throws: `AdditionError.calendarCalculationFailed` if the calendar cannot represent the
    ///   starting day or calculate the result.
    ///
    /// - Parameter days: The number of calendar days to add; negative values go backward.
    public func adding(days: Int) throws -> LocalDay {
        // Some Foundation versions return the input date when an out-of-range addition fails.
        guard let start = startOfDay(in: .gmt),
              let shifted = Self.calendar(in: .gmt).date(byAdding: .day, value: days, to: start),
              days == 0 || shifted != start,
              let result = LocalDay(shifted, in: .gmt)
        else { throw AdditionError.calendarCalculationFailed }
        return result
    }

    // MARK: - Comparison and display

    /// Compares days in chronological order.
    public static func < (lhs: LocalDay, rhs: LocalDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// A zero-padded representation in `YYYY-MM-DD` form.
    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    // MARK: - Calendar construction

    private static func calendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}
