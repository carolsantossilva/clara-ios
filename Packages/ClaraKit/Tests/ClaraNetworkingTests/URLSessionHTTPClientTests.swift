import Foundation
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

/// `.serialized`: o stub de URLProtocol é estado global (estático). Rodando em
/// paralelo, um teste trocaria a resposta do outro — o exemplo clássico de teste
/// instável. Serializar a suíte elimina a corrida.
@Suite("Cliente HTTP", .serialized)
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

    @Test("monta a URL com path e query e decodifica a resposta")
    func decodesSuccess() async throws {
        StubURLProtocol.setResponses([.init(status: 200, body: #"{"message":"olá"}"#)])

        let greeting = try await makeClient().send(GreetingEndpoint())

        #expect(greeting == Greeting(message: "olá"))
        #expect(StubURLProtocol.requestedURLs.last?.absoluteString == "https://api.example.com/greeting?lang=pt")
    }

    @Test("status fora de 2xx vira APIError.status")
    func mapsHTTPStatus() async {
        StubURLProtocol.setResponses([.init(status: 404, body: "{}")])

        await #expect(throws: APIError.status(404)) {
            try await makeClient().send(GreetingEndpoint())
        }
    }

    @Test("tenta de novo em erro 5xx e devolve o sucesso seguinte")
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

    @Test("não tenta de novo em erro 4xx")
    func doesNotRetryClientErrors() async {
        StubURLProtocol.setResponses([.init(status: 400, body: "{}"), .init(status: 200, body: #"{"message":"x"}"#)])

        await #expect(throws: APIError.status(400)) {
            try await makeClient(retry: RetryPolicy(maxAttempts: 3, baseDelay: .milliseconds(1))).send(GreetingEndpoint())
        }
        #expect(StubURLProtocol.requestedURLs.count == 1)
    }

    @Test("JSON inesperado vira APIError.decoding")
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

/// Intercepta as requisições da URLSession e devolve respostas enfileiradas.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Response {
        let status: Int
        let body: String
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var queue: [Response] = []
    nonisolated(unsafe) private static var urls: [URL] = []

    static func setResponses(_ responses: [Response]) {
        lock.withLock {
            queue = responses
            urls = []
        }
    }

    static var requestedURLs: [URL] {
        lock.withLock { urls }
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let next: Response? = Self.lock.withLock {
            if let url = request.url { Self.urls.append(url) }
            return Self.queue.isEmpty ? nil : Self.queue.removeFirst()
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
