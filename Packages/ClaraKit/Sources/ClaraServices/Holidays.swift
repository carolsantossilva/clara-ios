import ClaraCore
import ClaraNetworking
import Foundation

/// Feriado nacional vindo da BrasilAPI (https://brasilapi.com.br/docs#tag/Feriados-Nacionais).
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
    /// O próximo feriado entre `day` e `day + days`, se houver.
    func upcomingHoliday(from day: LocalDay, within days: Int) async throws -> Holiday?
}

/// Privacidade: a requisição só leva o ano. Nenhum dado da usuária sai do aparelho.
public actor BrasilAPIHolidayService: HolidayProviding {
    private let client: any HTTPClient
    private var cache: [Int: [Holiday]] = [:]
    private var inFlight: [Int: Task<[Holiday], any Error>] = [:]

    public init(client: any HTTPClient) {
        self.client = client
    }

    public func upcomingHoliday(from day: LocalDay, within days: Int) async throws -> Holiday? {
        let end = day.adding(days: days)
        let holidays: [Holiday]
        if end.year == day.year {
            holidays = try await self.holidays(year: day.year)
        } else {
            // A janela cruza o ano novo: busca os dois anos em paralelo.
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

    /// Reentrância de actor: enquanto esperamos a rede (`await`), outra chamada pode
    /// entrar no actor. Sem o dicionário `inFlight`, duas telas pedindo 2026 ao mesmo
    /// tempo fariam duas requisições. Com ele, a segunda aguarda a mesma Task.
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

/// Usado em previews, UI tests e quando a flag está desligada.
public struct StaticHolidayProvider: HolidayProviding {
    private let holiday: Holiday?

    public init(holiday: Holiday? = nil) {
        self.holiday = holiday
    }

    public func upcomingHoliday(from day: LocalDay, within days: Int) async throws -> Holiday? {
        holiday
    }
}
