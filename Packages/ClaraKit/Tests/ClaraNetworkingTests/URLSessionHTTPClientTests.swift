import Foundation
import os
import Testing
@testable import ClaraNetworking

private struct Greeting: Decodable, Equatable, Sendable {
    let message: String
}

private struct GreetingEndpoint: Endpoint {
    typealias Response = Greeting
    var path: String { "/greeting" }
    var queryItems: [URLQueryItem] { [URLQueryItem(name: "lang", value: "pt")] }
}

/// `.serialized`: the URLProtocol stub is global (static) state. Running in
/// parallel, one test would swap the other's response, the classic flaky test.
/// Serializing the suite removes the race.
@Suite("HTTP client", .serialized)
struct URLSessionHTTPClientTests {
    private func makeClient(retry: RetryPolicy = .none) -> URLSessionHTTPClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSessionHTTPClient(
            baseURL: URL(string: "https://api.example.com")!,
            session: URLSession(configuration: configuration),
            retryPolicy: retry
        )
    }

    @Test("builds the URL with path and query and decodes the response")
    func decodesSuccess() async throws {
        StubURLProtocol.setResponses([.init(status: 200, body: #"{"message":"olá"}"#)])

        let greeting = try await makeClient().send(GreetingEndpoint())

        #expect(greeting == Greeting(message: "olá"))
        #expect(StubURLProtocol.requestedURLs.last?.absoluteString == "https://api.example.com/greeting?lang=pt")
    }

    @Test("a non-2xx status becomes APIError.status")
    func mapsHTTPStatus() async {
        StubURLProtocol.setResponses([.init(status: 404, body: "{}")])

        await #expect(throws: APIError.status(404)) {
            try await makeClient().send(GreetingEndpoint())
        }
    }

    @Test("retries on 5xx and returns the next success")
    func retriesServerErrors() async throws {
        StubURLProtocol.setResponses([
            .init(status: 503, body: "{}"),
            .init(status: 200, body: #"{"message":"de novo"}"#),
        ])

        let greeting = try await makeClient(retry: RetryPolicy(maxAttempts: 2, baseDelay: .milliseconds(1)))
            .send(GreetingEndpoint())

        #expect(greeting.message == "de novo")
        #expect(StubURLProtocol.requestedURLs.count == 2)
    }

    @Test("does not retry on 4xx")
    func doesNotRetryClientErrors() async {
        StubURLProtocol.setResponses([.init(status: 400, body: "{}"), .init(status: 200, body: #"{"message":"x"}"#)])

        await #expect(throws: APIError.status(400)) {
            try await makeClient(retry: RetryPolicy(maxAttempts: 3, baseDelay: .milliseconds(1))).send(GreetingEndpoint())
        }
        #expect(StubURLProtocol.requestedURLs.count == 1)
    }

    @Test("unexpected JSON becomes APIError.decoding")
    func mapsDecodingErrors() async throws {
        StubURLProtocol.setResponses([.init(status: 200, body: #"{"other":1}"#)])

        do {
            _ = try await makeClient().send(GreetingEndpoint())
            Issue.record("Deveria ter falhado")
        } catch let APIError.decoding(description) {
            #expect(!description.isEmpty)
        }
    }
}

/// Intercepts URLSession requests and returns queued responses.
final class StubURLProtocol: URLProtocol {
    struct Response: Sendable {
        let status: Int
        let body: String
    }

    private struct State: Sendable {
        var queue: [Response] = []
        var urls: [URL] = []
    }

    // Static state shared across URLSession threads, guarded by a
    // Sendable lock: no `nonisolated(unsafe)`.
    private static let state = OSAllocatedUnfairLock(initialState: State())

    static func setResponses(_ responses: [Response]) {
        state.withLock { $0 = State(queue: responses) }
    }

    static var requestedURLs: [URL] {
        state.withLock { $0.urls }
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url
        let next: Response? = Self.state.withLock { state in
            if let url { state.urls.append(url) }
            return state.queue.isEmpty ? nil : state.queue.removeFirst()
        }
        guard let next, let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: next.status, httpVersion: nil, headerFields: nil)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(next.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
