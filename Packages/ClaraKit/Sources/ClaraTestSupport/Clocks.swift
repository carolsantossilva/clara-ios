import Foundation
import os

// Dublês compartilhados entre as suítes. Ficam num target próprio (não de teste)
// para que várias suítes os importem sem duplicação.

// MARK: - Relógio imediato

/// Relógio que não espera: `sleep` só cede a vez. Testes de timer rodam em
/// milissegundos e sem depender do tempo real (uma fonte clássica de flakiness).
public struct ImmediateClock: Clock {
    public struct Instant: InstantProtocol {
        public var offset: Duration

        public func advanced(by duration: Duration) -> Instant {
            Instant(offset: offset + duration)
        }

        public func duration(to other: Instant) -> Duration {
            other.offset - offset
        }

        public static func < (lhs: Instant, rhs: Instant) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    public init() {}

    public var now: Instant { Instant(offset: .zero) }
    public var minimumResolution: Duration { .zero }

    public func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        try Task.checkCancellation()
        await Task.yield()
    }
}

/// "Agora" que avança um segundo a cada leitura. Garante ordem estável entre
/// registros criados em sequência — com `Date()` real, dois registros podem
/// ganhar o mesmo instante e a ordenação do teste viraria sorte.
public final class SteppingNow: Sendable {
    private let current: OSAllocatedUnfairLock<Date>

    public init(start: Date = Date(timeIntervalSince1970: 1_790_000_000)) {
        current = OSAllocatedUnfairLock(initialState: start)
    }

    public var read: @Sendable () -> Date {
        { [current] in
            current.withLock { date in
                date = date.addingTimeInterval(1)
                return date
            }
        }
    }
}
