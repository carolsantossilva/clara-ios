import Foundation

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
}

/// Descreve uma chamada REST e o tipo que ela devolve.
///
/// O `associatedtype Response` liga a requisição à resposta em tempo de compilação:
/// `client.send(HolidaysEndpoint(year: 2026))` já devolve `[Holiday]`, sem cast.
public protocol Endpoint: Sendable {
    associatedtype Response: Decodable & Sendable

    var path: String { get }
    var method: HTTPMethod { get }
    var queryItems: [URLQueryItem] { get }
    var headers: [String: String] { get }
    var body: Data? { get }
    var timeout: TimeInterval { get }
}

extension Endpoint {
    public var method: HTTPMethod { .get }
    public var queryItems: [URLQueryItem] { [] }
    public var headers: [String: String] { [:] }
    public var body: Data? { nil }
    public var timeout: TimeInterval { 10 }
}

public enum APIError: Error, Equatable {
    case invalidURL
    case invalidResponse
    case offline
    case transport(URLError.Code)
    case status(Int)
    case decoding(String)

    /// Só vale tentar de novo quando o problema pode ser passageiro.
    var isRetryable: Bool {
        switch self {
        case .transport(let code):
            [URLError.Code.timedOut, .networkConnectionLost, .cannotConnectToHost].contains(code)
        case .status(let code):
            code >= 500 || code == 429
        default:
            false
        }
    }
}

public protocol HTTPClient: Sendable {
    func send<E: Endpoint>(_ endpoint: E) async throws -> E.Response
}

public struct RetryPolicy: Sendable {
    public var maxAttempts: Int
    public var baseDelay: Duration

    public init(maxAttempts: Int = 3, baseDelay: Duration = .milliseconds(300)) {
        self.maxAttempts = max(1, maxAttempts)
        self.baseDelay = baseDelay
    }

    public static let none = RetryPolicy(maxAttempts: 1, baseDelay: .zero)

    /// Backoff exponencial: 300ms, 600ms, 1.2s...
    func delay(afterAttempt attempt: Int) -> Duration {
        baseDelay * (1 << (attempt - 1))
    }
}

public struct URLSessionHTTPClient: HTTPClient {
    private let baseURL: URL
    private let session: URLSession
    private let retryPolicy: RetryPolicy

    public init(baseURL: URL, session: URLSession = .shared, retryPolicy: RetryPolicy = RetryPolicy()) {
        self.baseURL = baseURL
        self.session = session
        self.retryPolicy = retryPolicy
    }

    public func send<E: Endpoint>(_ endpoint: E) async throws -> E.Response {
        let request = try makeRequest(for: endpoint)
        var attempt = 1
        while true {
            do {
                return try await perform(request, decoding: E.Response.self)
            } catch let error as APIError where error.isRetryable && attempt < retryPolicy.maxAttempts {
                // Task.sleep respeita cancelamento: se a tela sumir, o retry para.
                try await Task.sleep(for: retryPolicy.delay(afterAttempt: attempt))
                attempt += 1
            }
        }
    }

    func makeRequest<E: Endpoint>(for endpoint: E) throws -> URLRequest {
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
