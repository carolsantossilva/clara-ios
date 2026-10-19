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

    @MainActor
    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 {
            if element.exists && element.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable)
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
        XCTAssertTrue(app.descendants(matching: .any)["records.row"].firstMatch.waitForExistence(timeout: 2))

        try auditAccessibility(app)
    }

    @MainActor
    func testConsultationPassesAccessibilityAudit() throws {
        let app = launchApp()
        app.tabBars.buttons["Consulta"].tap()
        XCTAssertTrue(app.staticTexts["Preparar uma consulta"].waitForExistence(timeout: 2))
        try auditAccessibility(app)
        scrollTo(app.buttons["consultation.preview"], in: app)
        try auditAccessibility(app)
    }

    @MainActor
    func testRecordCanBeEditedAndDeleted() {
        let app = launchApp()
        app.tabBars.buttons["Registros"].tap()
        app.buttons["records.newMoment"].tap()
        let note = app.textFields["momentForm.note"]
        let editor = app.textViews["momentForm.note"]
        if editor.waitForExistence(timeout: 2) {
            editor.tap()
            editor.typeText("Primeiro registro")
        } else {
            XCTAssertTrue(note.waitForExistence(timeout: 2))
            note.tap()
            note.typeText("Primeiro registro")
        }
        app.buttons["momentForm.save"].tap()
        let row = app.descendants(matching: .any)["records.row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 2))
        attachScreenshot(app, name: "records")
        app.tabBars.buttons["Consulta"].tap()
        scrollTo(app.buttons["consultation.preview"], in: app)
        app.buttons["consultation.preview"].tap()
        app.swipeUp()
        attachScreenshot(app, name: "consultation")
        app.tabBars.buttons["Registros"].tap()
        app.buttons["Editar"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Editar registro"].waitForExistence(timeout: 2))
        app.buttons["mood.good"].tap()
        app.buttons["momentForm.save"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 2))
        app.buttons["Excluir"].firstMatch.tap()
        app.alerts.buttons["Manter"].tap()
        XCTAssertTrue(row.exists)
        app.buttons["Excluir"].firstMatch.tap()
        app.alerts.buttons["Excluir"].tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 2))
    }

    @MainActor
    func testFocusDurationCanBeChosenLocally() {
        let app = launchApp()
        app.buttons["today.addFirstTask"].tap()
        let title = app.textFields["addTask.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 2))
        title.tap()
        title.typeText("Ler um livro")
        app.buttons["addTask.save"].tap()
        let duration = app.segmentedControls["today.focusDuration"]
        XCTAssertTrue(duration.waitForExistence(timeout: 2))
        duration.buttons["25 min"].tap()
        attachScreenshot(app, name: "today")
        XCTAssertTrue(app.buttons["today.startFocus"].label.contains("25"))
        app.terminate()
        app.launch()
        // The in-memory tasks reset; the local preference survives app restarts.
        app.buttons["today.addFirstTask"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 2))
        title.tap()
        title.typeText("Ler novamente")
        app.buttons["addTask.save"].tap()
        XCTAssertTrue(app.buttons["today.startFocus"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["today.startFocus"].label.contains("25"))
        duration.buttons["15 min"].tap()
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
