import XCTest

/// UI tests: an accessibility audit of each tab and the form validation.
/// The app launches with `-ui-testing`: an in-memory database and no network, so each
/// test starts from scratch and needs no internet.
///
/// The journeys (create a task, park a note, check in) live in Maestro (`.maestro/`).
/// This file covers what Maestro cannot: Apple's audit checks the open screen (contrast,
/// hit regions, missing labels, clipped text, Dynamic Type).
///
/// Against flakiness: find elements by `accessibilityIdentifier` (not by text that
/// changes) and use `waitForExistence` instead of `sleep`.
///
/// The audit records each issue as a failure; `auditAccessibility` turns on
/// `continueAfterFailure` so the report lists all of them at once, not only the first.
///
/// `XCUIApplication` is isolated to the main actor: each test is `@MainActor` and launches
/// its own app (the Xcode template pattern) instead of keeping the app from `setUp`.
final class ClaraUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        return app
    }

    @MainActor
    private func auditAccessibility(_ app: XCUIApplication) throws {
        continueAfterFailure = true
        try app.performAccessibilityAudit()
    }

    // MARK: Accessibility audit

    @MainActor
    func testTodayPassesAccessibilityAudit() throws {
        let app = launchApp()
        XCTAssertTrue(app.buttons["today.addFirstTask"].waitForExistence(timeout: 2))
        try auditAccessibility(app)
    }

    /// With a saved record, so the audit also covers the timeline cell.
    @MainActor
    func testRecordsPassesAccessibilityAudit() throws {
        let app = launchApp()
        app.tabBars.buttons["Registros"].tap()
        app.buttons["records.checkIn"].tap()
        let good = app.buttons["mood.good"]
        XCTAssertTrue(good.waitForExistence(timeout: 2))
        good.tap()
        app.buttons["momentForm.save"].tap()
        XCTAssertTrue(app.cells["records.row"].firstMatch.waitForExistence(timeout: 2))

        try auditAccessibility(app)
    }

    @MainActor
    func testConsultationPassesAccessibilityAudit() throws {
        let app = launchApp()
        app.tabBars.buttons["Consulta"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["consultation.preview"].waitForExistence(timeout: 2))
        try auditAccessibility(app)
    }

    // MARK: Form validation

    @MainActor
    func testEmptyCheckInAsksForContent() {
        let app = launchApp()
        app.tabBars.buttons["Registros"].tap()
        app.buttons["records.checkIn"].tap()
        app.buttons["momentForm.save"].tap()

        XCTAssertTrue(app.staticTexts["momentForm.message"].waitForExistence(timeout: 2))
    }
}
