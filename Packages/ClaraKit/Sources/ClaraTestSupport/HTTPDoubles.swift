import ClaraNetworking
import os

// MARK: - HTTP

public struct FakeHTTPClientError: Error, Equatable {
    public init() {}
}

public final class FakeHTTPClient: HTTPClient, Sendable {
    private let paths = OSAllocatedUnfairLock(initialState: [String]())
    private let responder: @Sendable (String) async throws -> any Sendable

    /// - Parameter responder: receives the requested `path` and returns the already decoded response.
    public init(responder: @escaping @Sendable (String) async throws -> any Sendable) {
        self.responder = responder
    }

    public var requestedPaths: [String] {
        paths.withLock { $0 }
    }

    public func send<E: Endpoint>(_ endpoint: E) async throws -> E.Response {
        paths.withLock { $0.append(endpoint.path) }
        let value = try await responder(endpoint.path)
        guard let typed = value as? E.Response else { throw FakeHTTPClientError() }
        return typed
    }
}
