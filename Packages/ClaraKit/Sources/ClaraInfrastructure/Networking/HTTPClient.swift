public protocol HTTPClient: Sendable {
    func send<E: Endpoint>(_ endpoint: E) async throws -> E.Response
}
