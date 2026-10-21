import Foundation
import Testing
@testable import ClaraInfrastructure

private struct Greeting: Decodable, Equatable, Sendable {
    let message: String
}

private struct GreetingEndpoint: Endpoint {
    typealias Response = Greeting
    var path: String { "/greeting" }
}

@Suite("URL session abstraction")
struct URLSessionProtocolTests {
    @Test("HTTP client accepts a lightweight session double")
    func usesInjectedSession() async throws {
        let baseURL = try #require(URL(string: "https://api.example.com"))
        let session = FakeURLSession()
        let client = URLSessionHTTPClient(
            baseURL: baseURL,
            session: session,
            retryPolicy: .none
        )

        let greeting = try await client.send(GreetingEndpoint())
        let requestedURLs = await session.requestedURLs

        #expect(greeting == Greeting(message: "from stub"))
        #expect(requestedURLs.map(\.absoluteString) == ["https://api.example.com/greeting"])
    }
}

private actor FakeURLSession: URLSessionProtocol {
    private(set) var requestedURLs: [URL] = []

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        else {
            throw URLError(.badURL)
        }
        requestedURLs.append(url)
        return (Data(#"{"message":"from stub"}"#.utf8), response)
    }
}
