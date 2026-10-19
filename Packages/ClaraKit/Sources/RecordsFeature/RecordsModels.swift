import ClaraCore
import Foundation

/// VIP cycle (Clean Swift) models, grouped by use case:
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

    /// A list row, already formatted. The View only assigns text: no rules live in it.
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
