import ClaraCore
import ClaraTestSupport
import Foundation
import Testing
@testable import ClaraInfrastructure

@Suite("Holidays (BrasilAPI)")
struct HolidayServiceTests {
    @Test("calendar errors propagate without requesting holidays")
    func rejectsUnrepresentableWindow() async {
        let client = FakeHTTPClient { _ in [Holiday]() }
        let service = BrasilAPIHolidayService(client: client)
        let day = LocalDay(year: 2026, month: 9, day: 20)

        await #expect(throws: LocalDay.AdditionError.calendarCalculationFailed) {
            try await service.upcomingHoliday(from: day, within: Int.max)
        }
        #expect(client.requestedPaths.isEmpty)
    }

    @Test("concurrent calls for the same year make a single request")
    func deduplicatesInFlightRequests() async throws {
        let client = FakeHTTPClient { _ in
            try await Task.sleep(for: .milliseconds(50))
            return [Holiday(date: "2026-10-12", name: "Nossa Senhora Aparecida")]
        }
        let service = BrasilAPIHolidayService(client: client)
        let day = LocalDay(year: 2026, month: 10, day: 10)

        async let first = service.upcomingHoliday(from: day, within: 7)
        async let second = service.upcomingHoliday(from: day, within: 7)
        let results = try await [first, second]

        #expect(results.allSatisfy { $0?.name == "Nossa Senhora Aparecida" })
        #expect(client.requestedPaths == ["/api/feriados/v1/2026"])
    }

    @Test("a window crossing New Year fetches both years")
    func crossesYearBoundary() async throws {
        let client = FakeHTTPClient { path in
            path.hasSuffix("2027") ? [Holiday(date: "2027-01-01", name: "Confraternização mundial")] : [Holiday]()
        }
        let service = BrasilAPIHolidayService(client: client)

        let holiday = try await service.upcomingHoliday(from: LocalDay(year: 2026, month: 12, day: 28), within: 7)

        #expect(holiday?.name == "Confraternização mundial")
        #expect(Set(client.requestedPaths) == ["/api/feriados/v1/2026", "/api/feriados/v1/2027"])
    }
}

@Suite("Analytics")
struct AnalyticsTests {
    @Test("without consent, nothing is sent")
    func respectsConsent() {
        let buffer = AnalyticsEventBuffer()
        let service = AnalyticsService(buffer: buffer, hasConsent: false)

        service.track(.taskCompleted)
        #expect(buffer.events.isEmpty)

        service.hasConsent = true
        service.track(.taskCompleted)
        #expect(buffer.events.map(\.name) == ["task_completed"])
    }

    @Test("the buffer keeps only the most recent events")
    func bufferCapacity() {
        let buffer = AnalyticsEventBuffer(capacity: 2)
        ["a", "b", "c"].forEach { buffer.append(AnalyticsEvent(name: $0)) }
        #expect(buffer.events.map(\.name) == ["b", "c"])
    }

    @Test("concurrent writes lose no events")
    func concurrentWrites() async {
        let buffer = AnalyticsEventBuffer(capacity: 1_000)
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<500 {
                group.addTask { buffer.append(AnalyticsEvent(name: "e\(index)")) }
            }
        }
        #expect(buffer.events.count == 500)
    }
}
