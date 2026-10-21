import Foundation
import Testing
@testable import ClaraCore

@Suite("LocalDay")
struct LocalDayTests {
    @Test("rejects dates whose calendar components cannot be extracted")
    func rejectsUnrepresentableDate() {
        let date = Date(timeIntervalSince1970: 1e300)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let components = calendar.dateComponents([.year, .month, .day], from: date)

        #expect(components.year == nil || components.month == nil || components.day == nil)
        #expect(LocalDay(date, in: .gmt) == nil)
    }

    @Test("rejects incomplete and impossible dates", arguments: ["2026-02-31", "2026-13-01", "2026-09", "abc"])
    func rejectsInvalid(_ text: String) {
        #expect(LocalDay(isoString: text) == nil)
    }

    @Test("adds days across the year boundary")
    func addsAcrossYears() throws {
        let result = try LocalDay(year: 2026, month: 12, day: 29).adding(days: 5)
        #expect(result == LocalDay(year: 2027, month: 1, day: 3))
    }

    @Test("throws when the calendar cannot add the amount")
    func throwsWhenCalendarCannotAddAmount() {
        let day = LocalDay(year: 2026, month: 9, day: 20)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        guard let start = day.startOfDay(in: .gmt) else {
            Issue.record("The fixed Gregorian day must be representable")
            return
        }

        let shifted = calendar.date(byAdding: .day, value: Int.max, to: start)
        #expect(shifted == nil || shifted == start)
        #expect(throws: LocalDay.AdditionError.calendarCalculationFailed) {
            try day.adding(days: Int.max)
        }
    }
}
