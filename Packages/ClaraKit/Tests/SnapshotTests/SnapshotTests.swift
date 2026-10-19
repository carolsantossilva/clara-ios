import ClaraCore
import ClaraDesignSystem
import ClaraTestSupport
import SnapshotTesting
import SwiftUI
import Testing
import UIKit
@testable import RecordsFeature

/// Snapshot tests comparam a tela renderizada com uma imagem de referência.
///
/// Para não ficarem frágeis:
/// - rode sempre no mesmo simulador/versão (o CI fixa o destino);
/// - dados fixos (datas com fuso explícito, sem `Date()`);
/// - a primeira execução grava as referências em `__Snapshots__` e falha de
///   propósito; as seguintes comparam.
@Suite("Snapshots")
@MainActor
struct SnapshotTests {
    private let rows: [Records.Row] = [
        RecordsPresenter.makeRow(Fixtures.moment(
            kind: .daily,
            at: "2026-09-20T10:00:00-03:00",
            mood: .good,
            note: "Acordei com energia e fiz a caminhada.",
            context: "Dormi cedo"
        )),
        RecordsPresenter.makeRow(Fixtures.moment(
            at: "2026-09-19T18:30:00-03:00",
            mood: .difficult
        )),
    ]

    @Test func moodPicker() {
        let view = MoodPicker(selection: .constant(.okay))
            .padding()
            .background(ClaraColor.background)
        assertSnapshot(of: view, as: .image(layout: .fixed(width: 390, height: 100)))
    }

    @Test func emptyState() {
        let view = EmptyStateView()
            .padding()
            .background(ClaraColor.background)
        assertSnapshot(of: view, as: .image(layout: .fixed(width: 390, height: 280)))
    }

    @Test func recordsScreenLight() {
        assertSnapshot(of: makeRecordsScreen(), as: .image(on: .iPhone13))
    }

    @Test func recordsScreenDark() {
        assertSnapshot(
            of: makeRecordsScreen(),
            as: .image(on: .iPhone13, traits: UITraitCollection(userInterfaceStyle: .dark))
        )
    }

    /// Dynamic Type no tamanho de acessibilidade: o layout não pode cortar texto.
    /// Tela mais alta que o iPhone para a imagem incluir as células, não só o cabeçalho.
    @Test func recordsScreenAccessibilityText() {
        assertSnapshot(
            of: makeRecordsScreen(),
            as: .image(
                on: .iPhone13,
                size: CGSize(width: 390, height: 2_400),
                traits: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraLarge)
            )
        )
    }

    private func makeRecordsScreen() -> UIViewController {
        // Sem interactor: a View é alimentada direto com o ViewModel do Presenter.
        let viewController = RecordsViewController()
        viewController.loadViewIfNeeded()
        viewController.displayMoments(Records.Load.ViewModel(rows: rows))
        return viewController
    }
}
