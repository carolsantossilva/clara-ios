import ClaraCore
import ClaraDesignSystem
import ClaraTestSupport
import SnapshotTesting
import SwiftUI
import Testing
import UIKit
@testable import RecordsFeature

/// Snapshot tests compare the rendered screen with a reference image.
///
/// To keep them from being brittle:
/// - always run on the same simulator/version (CI pins the destination);
/// - fixed data (dates with an explicit time zone, no `Date()`);
/// - the first run records the references in `__Snapshots__` and fails on
///   purpose; later runs compare.
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

    /// Dynamic Type at an accessibility size: the layout must not clip text.
    /// Taller than the iPhone screen so the image includes the cells, not only the header.
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
        // No interactor: the View is fed the Presenter's ViewModel directly.
        let viewController = RecordsViewController()
        viewController.loadViewIfNeeded()
        viewController.displayMoments(Records.Load.ViewModel(rows: rows))
        return viewController
    }
}
