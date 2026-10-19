import XCTest

/// Testes de UI: auditoria de acessibilidade de cada aba e a validação do formulário.
/// O app abre com `-ui-testing`: banco em memória e sem rede, então cada teste começa
/// do zero e não depende de internet.
///
/// As jornadas (criar tarefa, anotar, check-in) ficam no Maestro (`.maestro/`). Aqui
/// fica o que o Maestro não faz: a auditoria da Apple confere a tela aberta (contraste,
/// área de toque, elementos sem rótulo, texto cortado, Dynamic Type).
///
/// Contra flakiness: localizar elementos por `accessibilityIdentifier` (não por
/// texto que muda) e usar `waitForExistence` em vez de `sleep`.
///
/// A auditoria registra cada problema como uma falha; `auditAccessibility` liga
/// `continueAfterFailure` para o relatório trazer todos de uma vez, não só o primeiro.
///
/// `XCUIApplication` é isolado no main actor: cada teste é `@MainActor` e abre o
/// próprio app (o padrão do template do Xcode), em vez de guardar o app no `setUp`.
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

    // MARK: Auditoria de acessibilidade

    @MainActor
    func testTodayPassesAccessibilityAudit() throws {
        let app = launchApp()
        XCTAssertTrue(app.buttons["today.addFirstTask"].waitForExistence(timeout: 2))
        try auditAccessibility(app)
    }

    /// Com um registro salvo, para a auditoria também cobrir a célula da linha do tempo.
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

    // MARK: Validação do formulário

    @MainActor
    func testEmptyCheckInAsksForContent() {
        let app = launchApp()
        app.tabBars.buttons["Registros"].tap()
        app.buttons["records.checkIn"].tap()
        app.buttons["momentForm.save"].tap()

        XCTAssertTrue(app.staticTexts["momentForm.message"].waitForExistence(timeout: 2))
    }
}
