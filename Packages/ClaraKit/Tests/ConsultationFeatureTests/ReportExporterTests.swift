import CoreGraphics
import Foundation
import Testing
@testable import ConsultationFeature

/// Gera um PDF de verdade com o motor de impressão do UIKit e confere o arquivo.
@Suite("Consulta — exportar PDF")
@MainActor
struct ReportExporterTests {
    @Test("o resumo vira um PDF A4 no diretório temporário")
    func exportsA4PDF() throws {
        let fileName = "resumo-\(UUID().uuidString).pdf"

        let url = try PrintRendererReportExporter().exportPDF(html: "<h1>Resumo</h1><p>Dormi bem.</p>", fileName: fileName)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(url.lastPathComponent == fileName)
        let document = try #require(CGPDFDocument(url as CFURL))
        #expect(document.numberOfPages == 1)
        let page = try #require(document.page(at: 1))
        let box = page.getBoxRect(.mediaBox)
        #expect(abs(box.width - 595.2) < 0.5)
        #expect(abs(box.height - 841.8) < 0.5)
    }
}
