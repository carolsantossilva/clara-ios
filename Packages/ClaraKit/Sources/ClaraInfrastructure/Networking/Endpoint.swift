import Foundation

/// Describes a REST call and the type it returns.
///
/// The `associatedtype Response` ties the request to the response at compile time:
/// `client.send(HolidaysEndpoint(year: 2026))` returns `[Holiday]` directly, no cast.
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
