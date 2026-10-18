import Foundation

public struct TimeoutError: Error, Equatable {
    public init() {}
}

/// Executa `operation` com prazo. Duas tarefas filhas competem num TaskGroup:
/// a que terminar primeiro vence e a outra é cancelada.
///
/// Isso só funciona porque o cancelamento no Swift Concurrency é *cooperativo*:
/// `Task.sleep` e `URLSession` checam o cancelamento; um loop de CPU que não
/// chama `Task.checkCancellation()` continuaria rodando.
public func withTimeout<T: Sendable>(
    _ duration: Duration,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: duration)
            throw TimeoutError()
        }
        defer { group.cancelAll() }
        guard let first = try await group.next() else { throw TimeoutError() }
        return first
    }
}
