import ClaraCore
import Foundation

/// Modelos do ciclo VIP (Clean Swift), agrupados por caso de uso:
/// View → Interactor (Request) → Presenter (Response) → View (ViewModel).
enum Records {
    enum Load {
        struct Response {
            let moments: [Moment]
        }

        struct ViewModel: Equatable {
            let rows: [Row]
        }
    }

    /// Uma linha da lista, já formatada. A View só atribui textos: nenhuma regra mora nela.
    struct Row: Hashable {
        let id: UUID
        let symbol: String
        let moodTag: String
        let dateLine: String
        let note: String?
        let context: String?
        let helpedOrHindered: String?
        let emptyNote: String?
        let accessibilityLabel: String
    }

    enum Failure {
        struct ViewModel: Equatable {
            let title: String
            let message: String
        }
    }
}

public enum MomentSaveResult: Equatable, Sendable {
    case saved
    case needsContent
    case failed
}
