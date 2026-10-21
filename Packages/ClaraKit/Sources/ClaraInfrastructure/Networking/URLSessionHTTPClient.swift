import Foundation

public struct URLSessionHTTPClient: HTTPClient {
    // MARK: - Configuration

    private let baseURL: URL
    private let session: any URLSessionProtocol
    private let retryPolicy: RetryPolicy
    private let sleep: @Sendable (Duration) async throws -> Void

    // MARK: - Initialization

    public init<C: Clock>(
        baseURL: URL,
        session: any URLSessionProtocol = URLSession.shared,
        retryPolicy: RetryPolicy = RetryPolicy(),
        clock: C = ContinuousClock()
    ) where C.Duration == Duration {
        self.baseURL = baseURL
        self.session = session
        self.retryPolicy = retryPolicy
        self.sleep = { try await clock.sleep(for: $0) }
    }

    // MARK: - Request execution

    public func send<E: Endpoint>(_ endpoint: E) async throws -> E.Response {
        let request = try makeRequest(for: endpoint)
        var attempt = 1
        while true {
            do {
                return try await perform(request, decoding: E.Response.self)
            } catch let error as APIError where endpoint.method == .get && error.isRetryable && attempt < retryPolicy.maxAttempts {
                // Clock.sleep honors cancellation: if the screen goes away, the retry stops.
                try await sleep(retryPolicy.delay(afterAttempt: attempt))
                attempt += 1
            }
        }
    }

    private func makeRequest<E: Endpoint>(for endpoint: E) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.path += endpoint.path
        components.queryItems = endpoint.queryItems.isEmpty ? nil : endpoint.queryItems
        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url, timeoutInterval: endpoint.timeout)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = endpoint.body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (field, value) in endpoint.headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        return request
    }

    private func perform<Response: Decodable>(_ request: URLRequest, decoding: Response.Type) async throws -> Response {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .cancelled: throw CancellationError()
            case .notConnectedToInternet: throw APIError.offline
            default: throw APIError.transport(error.code)
            }
        }

        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw APIError.status(http.statusCode) }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }
}
