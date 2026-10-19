import ClaraCore
import ClaraTestSupport
import Foundation
import Testing
@testable import ClaraServices

@Suite("Feature flags and A/B")
@MainActor
struct FeatureFlagsTests {
    @Test("A/B assignment is stable for the same installation")
    func bucketingIsDeterministic() {
        let variants = ["15", "25"]
        let first = Bucketing.variant(for: "focus_duration", installationID: "abc", variants: variants)
        for _ in 0..<100 {
            #expect(Bucketing.variant(for: "focus_duration", installationID: "abc", variants: variants) == first)
        }
    }

    @Test("assignment spreads installations across variants")
    func bucketingSpreadsUsers() {
        let counts = (0..<1_000).reduce(into: [String: Int]()) { counts, index in
            let variant = Bucketing.variant(for: "focus_duration", installationID: "install-\(index)", variants: ["15", "25"])
            counts[variant ?? "nil", default: 0] += 1
        }
        // Wide tolerance on purpose: the test checks distribution, not luck.
        #expect((350...650).contains(counts["15", default: 0]))
    }

    @Test("local override beats remote, which beats the default")
    func overridePrecedence() {
        let flags = FeatureFlags(config: RemoteConfig(flags: ["holiday_banner": false], experiments: [:]))
        #expect(!flags.isEnabled(.holidayBanner))
        #expect(flags.isEnabled(.aiStepSuggestions), "missing remotely → uses the bundled default")

        flags.overrides[.holidayBanner] = true
        #expect(flags.isEnabled(.holidayBanner))
    }

    @Test("without an installation ID, uses the first variant (control)")
    func controlWithoutInstallationID() {
        let flags = FeatureFlags(config: RemoteConfig(flags: [:], experiments: ["focus_duration": ["15", "25"]]))
        #expect(flags.variant(.focusDuration) == "15")
    }
}

@Suite("Remote config")
struct RemoteConfigLoaderTests {
    @Test("network failed and no cache: uses the default values")
    func fallsBackToDefaults() async {
        let client = FakeHTTPClient { _ in throw TestError() }
        let loader = RemoteConfigLoader(client: client, path: "/config.json", cacheSuiteName: "test-\(UUID().uuidString)")

        let (config, source) = await loader.load()

        #expect(config == .defaults)
        #expect(source == .defaults)
    }

    @Test("network failed after a success: uses the last saved value")
    func fallsBackToCache() async {
        let suite = "test-\(UUID().uuidString)"
        let remote = RemoteConfig(flags: ["holiday_banner": false], experiments: [:])
        _ = await RemoteConfigLoader(client: FakeHTTPClient { _ in remote }, path: "/c", cacheSuiteName: suite).load()

        let (config, source) = await RemoteConfigLoader(client: FakeHTTPClient { _ in throw TestError() }, path: "/c", cacheSuiteName: suite).load()

        #expect(config == remote)
        #expect(source == .cache)
    }
}

@Suite("Holidays (BrasilAPI)")
struct HolidayServiceTests {
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
        let service = AnalyticsService(destinations: [AnyAnalyticsDestination(BufferAnalyticsDestination(buffer: buffer))], hasConsent: false)

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
