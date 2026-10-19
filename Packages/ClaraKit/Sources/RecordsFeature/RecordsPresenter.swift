import ClaraCore
import Foundation

@MainActor
protocol RecordsPresentationLogic: AnyObject {
    func presentMoments(_ response: Records.Load.Response)
    func presentFailure(title: String, message: String)
}

/// Turns domain data into text ready for the screen.
/// It is pure, synchronous code, so tests check the formatting without UIKit.
@MainActor
final class RecordsPresenter: RecordsPresentationLogic {
    // `weak`: the View owns the Interactor, which owns the Presenter. Without `weak`,
    // Presenter → View would close a retain cycle and the screen would never be freed.
    weak var viewController: (any RecordsDisplayLogic)?

    func presentMoments(_ response: Records.Load.Response) {
        let rows = response.moments.map(Self.makeRow)
        viewController?.displayMoments(Records.Load.ViewModel(rows: rows))
    }

    func presentFailure(title: String, message: String) {
        viewController?.displayFailure(Records.Failure.ViewModel(title: title, message: message))
    }

    nonisolated static func makeRow(_ moment: Moment) -> Records.Row {
        let kindLabel = moment.kind == .daily ? "Check-in" : "Momento"
        let dateLine = "\(kindLabel) · \(ClaraFormat.dateTime(moment.occurredAt, in: moment.timeZone))"
        let moodTag = moment.mood?.label ?? "sem descrição"
        let note = moment.note.isEmpty ? nil : moment.note
        let context = moment.context.isEmpty ? nil : "Contexto: \(moment.context)"
        let helped = moment.helpedOrHindered.isEmpty ? nil : "Ajudou ou atrapalhou: \(moment.helpedOrHindered)"
        let emptyNote = moment.hasWrittenDetails ? nil : "Só a palavra escolhida — e tudo bem."

        let spoken = [moodTag, dateLine, note, context, helped]
            .compactMap { $0 }
            .joined(separator: ". ")

        return Records.Row(
            id: moment.id,
            symbol: symbol(for: moment.mood),
            moodTag: moodTag,
            dateLine: dateLine,
            note: note,
            context: context,
            helpedOrHindered: helped,
            emptyNote: emptyNote,
            accessibilityLabel: spoken
        )
    }

    private nonisolated static func symbol(for mood: Mood?) -> String {
        switch mood {
        case .good: "☀"
        case .difficult: "☁"
        case .okay, nil: "♡"
        }
    }
}
