import XCTest

/// Testes de UI dos fluxos principais. O app abre com `-ui-testing`: banco em
/// memória e sem rede, então cada teste começa do zero e não depende de internet.
///
/// Contra flakiness: localizar elementos por `accessibilityIdentifier` (não por
/// texto que muda) e usar `waitForExistence` em vez de `sleep`.
final class ClaraUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    func testCreateTaskBecomesFocusAndStartsTimer() {
        app.buttons["today.addFirstTask"].tap()

        let title = app.textFields["addTask.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 2))
        title.tap()
        title.typeText("Responder a clínica")
        app.buttons["addTask.save"].tap()

        XCTAssertTrue(app.staticTexts["today.focusTitle"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.staticTexts["today.focusTitle"].label, "Responder a clínica")

        app.buttons["today.startFocus"].tap()
        XCTAssertTrue(app.otherElements["today.timer"].waitForExistence(timeout: 2))
    }

    func testParkingNoteIsSaved() {
        let field = app.textFields["parking.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        field.tap()
        field.typeText("Comprar pilhas")
        app.buttons["parking.add"].tap()

        XCTAssertTrue(app.buttons["Concluir: Comprar pilhas"].waitForExistence(timeout: 2))
    }

    func testDailyCheckInAppearsInTimeline() {
        app.tabBars.buttons["Registros"].tap()
        app.buttons["records.checkIn"].tap()

        let good = app.buttons["mood.good"]
        XCTAssertTrue(good.waitForExistence(timeout: 2))
        good.tap()
        app.buttons["momentForm.save"].tap()

        XCTAssertTrue(app.cells["records.row"].firstMatch.waitForExistence(timeout: 2))
    }

    func testEmptyCheckInAsksForContent() {
        app.tabBars.buttons["Registros"].tap()
        app.buttons["records.checkIn"].tap()
        app.buttons["momentForm.save"].tap()

        XCTAssertTrue(app.staticTexts["momentForm.message"].waitForExistence(timeout: 2))
    }
}
