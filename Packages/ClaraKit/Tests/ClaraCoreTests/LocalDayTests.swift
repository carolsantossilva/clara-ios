import ClaraTestSupport
import Foundation
import Testing
@testable import ClaraCore

@Suite("LocalDay")
struct LocalDayTests {
    @Test("rejects dates outside the calendar's representable range", arguments: [1e300, -1e300, .infinity, -.infinity, .nan])
    func rejectsUnrepresentableDate(_ timeInterval: TimeInterval) {
        let date = Date(timeIntervalSince1970: timeInterval)
        #expect(LocalDay(date, in: .gmt) == nil)
    }

    @Test("converts a valid leap day in the moment's time zone")
    func convertsValidLeapDay() throws {
        let date = Fixtures.date("2024-03-01T01:30:00Z")
        let timeZone = try #require(TimeZone(secondsFromGMT: -3 * 60 * 60))

        #expect(LocalDay(date, in: timeZone) == LocalDay(year: 2024, month: 2, day: 29))
        #expect(LocalDay(date, in: .gmt) == LocalDay(year: 2024, month: 3, day: 1))
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
