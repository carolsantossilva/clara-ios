import Foundation
import UIKit

public protocol ReportExporting: Sendable {
    @MainActor
    func exportPDF(html: String, fileName: String) throws -> URL
}

/// Converts the summary HTML into an A4 PDF with UIKit's print engine.
/// Must run on the main actor: UIKit's print classes are UI classes.
public struct PrintRendererReportExporter: ReportExporting {
    public init() {}

    @MainActor
    public func exportPDF(html: String, fileName: String) throws -> URL {
        let renderer = A4PageRenderer()
        renderer.addPrintFormatter(UIMarkupTextPrintFormatter(markupText: html), startingAtPageAt: 0)

        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, renderer.paperRect, nil)
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
        for page in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: page, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try (data as Data).write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }
}

/// `paperRect` and `printableRect` are read-only: the supported way to set the
/// page size is to override them in a subclass.
private final class A4PageRenderer: UIPrintPageRenderer {
    override var paperRect: CGRect { CGRect(x: 0, y: 0, width: 595.2, height: 841.8) }
    override var printableRect: CGRect { paperRect.insetBy(dx: 48, dy: 54) }
}
