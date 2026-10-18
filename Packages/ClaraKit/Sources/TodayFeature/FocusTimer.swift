import ClaraLegacy
import Foundation
import Observation

/// Contagem regressiva da sessão de foco.
///
/// `@Observable` (Observation, iOS 17): a SwiftUI rastreia quais propriedades cada
/// view leu no `body` e redesenha só essas views quando elas mudam. Diferente do
/// antigo `ObservableObject`, não precisa de `@Published` e evita redesenhos extras.
@MainActor
@Observable
public final class FocusTimer {
    public private(set) var remainingSeconds: Int
    public private(set) var isRunning = false
    public private(set) var didFinish = false

    private var tickTask: Task<Void, Never>?
    private let clock: any Clock<Duration>

    public init(durationSeconds: Int, clock: any Clock<Duration>) {
        self.remainingSeconds = durationSeconds
        self.clock = clock
    }

    public func start(durationSeconds: Int) {
        stop()
        remainingSeconds = durationSeconds
        didFinish = false
        isRunning = true
        // A Task herda o isolamento do MainActor: o loop roda no main actor, mas
        // `clock.sleep` suspende sem bloquear a thread principal.
        tickTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    public func stop() {
        tickTask?.cancel()
        tickTask = nil
        isRunning = false
    }

    /// Espera o loop terminar. Usado nos testes.
    func waitUntilFinished() async {
        await tickTask?.value
    }

    private func runLoop() async {
        while remainingSeconds > 0 {
            do {
                try await clock.sleep(for: .seconds(1))
            } catch {
                return // cancelado
            }
            remainingSeconds -= 1
        }
        isRunning = false
        didFinish = true
    }

    // Código Objective-C legado chamado do Swift.
    public var clockLabel: String { CLADurationFormatter.clockString(seconds: remainingSeconds) }
    public var spokenLabel: String { CLADurationFormatter.spokenString(seconds: remainingSeconds) }
}
