import Foundation
import ClaraTestSupport
import Testing
@testable import ClaraInfrastructure

private struct Greeting: Decodable, Equatable, Sendable {
    let message: String
}

private struct GreetingEndpoint: Endpoint {
    typealias Response = Greeting
    var path: String { "/greeting" }
    var queryItems: [URLQueryItem] { [URLQueryItem(name: "lang", value: "pt")] }
}

private struct CreateGreetingEndpoint: Endpoint {
    typealias Response = Greeting
    var path: String { "/greeting" }
    var method: HTTPMethod { .post }
}

@Suite("HTTP client")
struct URLSessionHTTPClientTests {
    private func makeClient(
        responses: [StubResponse],
        retry: RetryPolicy = .none,
        clock: ImmediateClock = ImmediateClock()
    ) throws -> (URLSessionHTTPClient, FakeURLSession) {
        let baseURL = try #require(URL(string: "https://api.example.com"))
        let session = FakeURLSession(responses: responses)
        let client = URLSessionHTTPClient(
            baseURL: baseURL,
            session: session,
            retryPolicy: retry,
            clock: clock
        )
        return (client, session)
    }

    @Test("builds the URL with path and query and decodes the response")
    func decodesSuccess() async throws {
        let (client, session) = try makeClient(responses: [.init(status: 200, body: #"{"message":"olá"}"#)])

        let greeting = try await client.send(GreetingEndpoint())
        let requestedURLs = await session.requestedURLs

        #expect(greeting == Greeting(message: "olá"))
        #expect(requestedURLs.last?.absoluteString == "https://api.example.com/greeting?lang=pt")
    }

    @Test("a non-2xx status becomes APIError.status")
    func mapsHTTPStatus() async throws {
        let (client, _) = try makeClient(responses: [.init(status: 404, body: "{}")])

        await #expect(throws: APIError.status(404)) {
            try await client.send(GreetingEndpoint())
        }
    }

    @Test("retries on 5xx and returns the next success")
    func retriesServerErrors() async throws {
        let (client, session) = try makeClient(
            responses: [
                .init(status: 503, body: "{}"),
                .init(status: 200, body: #"{"message":"de novo"}"#),
            ],
            retry: RetryPolicy(maxAttempts: 2, baseDelay: .milliseconds(1))
        )

        let greeting = try await client.send(GreetingEndpoint())
        let requestedURLs = await session.requestedURLs

        #expect(greeting.message == "de novo")
        #expect(requestedURLs.count == 2)
    }

    @Test("does not retry POST on 5xx")
    func doesNotRetryPostRequests() async throws {
        let (client, session) = try makeClient(
            responses: [
                .init(status: 503, body: "{}"),
                .init(status: 200, body: #"{"message":"duplicate"}"#),
            ],
            retry: RetryPolicy(maxAttempts: 3, baseDelay: .milliseconds(1))
        )

        await #expect(throws: APIError.status(503)) {
            try await client.send(CreateGreetingEndpoint())
        }
        let requestedURLs = await session.requestedURLs

        #expect(requestedURLs.count == 1)
    }

    @Test("does not retry on 4xx")
    func doesNotRetryClientErrors() async throws {
        let (client, session) = try makeClient(
            responses: [
                .init(status: 400, body: "{}"),
                .init(status: 200, body: #"{"message":"x"}"#),
            ],
            retry: RetryPolicy(maxAttempts: 3, baseDelay: .milliseconds(1))
        )

        await #expect(throws: APIError.status(400)) {
            try await client.send(GreetingEndpoint())
        }
        let requestedURLs = await session.requestedURLs

        #expect(requestedURLs.count == 1)
    }

    @Test("unexpected JSON becomes APIError.decoding")
    func mapsDecodingErrors() async throws {
        let (client, _) = try makeClient(responses: [.init(status: 200, body: #"{"other":1}"#)])

        do {
            _ = try await client.send(GreetingEndpoint())
            Issue.record("Deveria ter falhado")
        } catch let APIError.decoding(description) {
            #expect(!description.isEmpty)
        }
    }
}

private struct StubResponse: Sendable {
    let status: Int
    let body: String
}

private actor FakeURLSession: URLSessionProtocol {
    private var responses: [StubResponse]
    private(set) var requestedURLs: [URL] = []

    init(responses: [StubResponse]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard let url = request.url,
              !responses.isEmpty,
              let response = HTTPURLResponse(url: url, statusCode: responses[0].status, httpVersion: nil, headerFields: nil)
        else {
            throw URLError(.badServerResponse)
        }
        requestedURLs.append(url)
        let body = responses.removeFirst().body
        return (Data(body.utf8), response)
    }
}
