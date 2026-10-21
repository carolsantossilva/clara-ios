public struct RetryPolicy: Sendable {
    public var maxAttempts: Int
    public var baseDelay: Duration

    public init(maxAttempts: Int = 3, baseDelay: Duration = .milliseconds(300)) {
        self.maxAttempts = max(1, maxAttempts)
        self.baseDelay = baseDelay
    }

    public static let none = RetryPolicy(maxAttempts: 1, baseDelay: .zero)

    /// Exponential backoff: 300ms, 600ms, 1.2s...
    func delay(afterAttempt attempt: Int) -> Duration {
        baseDelay * (1 << (attempt - 1))
    }
}
