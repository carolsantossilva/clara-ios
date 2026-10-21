import ClaraCore
import Foundation

/// National holiday from BrasilAPI (https://brasilapi.com.br/docs#tag/Feriados-Nacionais).
public struct Holiday: Decodable, Equatable, Sendable {
    public let date: String
    public let name: String
    public let type: String

    public init(date: String, name: String, type: String = "national") {
        self.date = date
        self.name = name
        self.type = type
    }

    public var day: LocalDay? { LocalDay(isoString: date) }
}

struct HolidaysEndpoint: Endpoint {
    typealias Response = [Holiday]
    let year: Int
    var path: String { "/api/feriados/v1/\(year)" }
}

public protocol HolidayProviding: Sendable {
    /// The next holiday between `day` and `day + days`, if any.
    func upcomingHoliday(from day: LocalDay, within days: Int) async throws -> Holiday?
}

/// Privacy: the request only carries the year. No user data leaves the device.
public actor BrasilAPIHolidayService: HolidayProviding {
    private let client: any HTTPClient
    private var cache: [Int: [Holiday]] = [:]
    private var inFlight: [Int: Task<[Holiday], any Error>] = [:]

    public init(client: any HTTPClient) {
        self.client = client
    }

    public func upcomingHoliday(from day: LocalDay, within days: Int) async throws -> Holiday? {
        let end = try day.adding(days: days)
        let holidays: [Holiday]
        if end.year == day.year {
            holidays = try await self.holidays(year: day.year)
        } else {
            // The window crosses New Year: fetch both years in parallel.
            async let current = self.holidays(year: day.year)
            async let next = self.holidays(year: end.year)
            holidays = try await current + next
        }
        let candidates = holidays.compactMap { holiday -> (holiday: Holiday, day: LocalDay)? in
            guard let holidayDay = holiday.day, holidayDay >= day, holidayDay <= end else { return nil }
            return (holiday, holidayDay)
        }
        return candidates.min { $0.day < $1.day }?.holiday
    }

    /// Actor reentrancy: while we wait for the network (`await`), another call can
    /// enter the actor. Without the `inFlight` dictionary, two screens asking for 2026 at
    /// the same time would make two requests. With it, the second awaits the same Task.
    func holidays(year: Int) async throws -> [Holiday] {
        if let cached = cache[year] {
            return cached
        }
        if let running = inFlight[year] {
            return try await running.value
        }

        let client = self.client
        let task = Task { try await client.send(HolidaysEndpoint(year: year)) }
        inFlight[year] = task
        defer { inFlight[year] = nil }

        let result = try await task.value
        cache[year] = result
        return result
    }
}

/// Used in previews, UI tests and when the flag is off.
public struct StaticHolidayProvider: HolidayProviding {
    private let holiday: Holiday?

    public init(holiday: Holiday? = nil) {
        self.holiday = holiday
    }

    public func upcomingHoliday(from day: LocalDay, within days: Int) async throws -> Holiday? {
        holiday
    }
}
