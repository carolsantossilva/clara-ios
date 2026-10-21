import Foundation

public enum APIError: Error, Equatable {
    case invalidURL
    case invalidResponse
    case offline
    case transport(URLError.Code)
    case status(Int)
    case decoding(String)

    /// Retrying only makes sense when the problem may be transient.
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
