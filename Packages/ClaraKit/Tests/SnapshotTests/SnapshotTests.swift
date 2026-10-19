import ClaraCore
import ClaraInfrastructure
import ClaraTestSupport
import SnapshotTesting
import SwiftUI
import Testing
import UIKit
@testable import ClaraUI

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
    private let moments: [Moment] = [
        Fixtures.moment(
            kind: .daily,
            at: "2026-09-20T10:00:00-03:00",
            mood: .good,
            note: "Acordei com energia e fiz a caminhada.",
            context: "Dormi cedo"
        ),
        Fixtures.moment(at: "2026-09-19T18:30:00-03:00", mood: .difficult),
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

    @Test func swiftUIRecordsLight() async {
        let screen = await makeRecordsScreen()
        assertSnapshot(of: screen, as: .image(layout: .fixed(width: 390, height: 844)))
    }

    @Test func swiftUIRecordsDark() async {
        let screen = await makeRecordsScreen()
        assertSnapshot(
            of: screen,
            as: .image(layout: .fixed(width: 390, height: 844), traits: UITraitCollection(userInterfaceStyle: .dark))
        )
    }

    /// Dynamic Type at an accessibility size: the layout must not clip text.
    /// Taller than the iPhone screen so the image includes the cells, not only the header.
    @Test func swiftUIRecordsAccessibilityText() async {
        let screen = await makeRecordsScreen()
        assertSnapshot(
            of: screen,
            as: .image(
                layout: .fixed(width: 390, height: 2_400),
                traits: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraLarge)
            )
        )
    }

    private func makeRecordsScreen() async -> some View {
        let viewModel = RecordsViewModel(
            repository: LocalMomentRepository(database: LocalDatabase(inMemory: .init(moments: moments))),
            analytics: NoOpAnalyticsTracker(),
            crashReporter: SpyCrashReporter()
        )
        await viewModel.load()
        return RecordsView(viewModel: viewModel)
    }
}
