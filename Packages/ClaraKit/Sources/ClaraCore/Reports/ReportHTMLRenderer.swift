import Foundation

/// Builds the printable summary HTML (turned into a PDF by the Consultation feature).
/// Direct port of the React Native app's `renderReportHtml`.
public enum ReportHTMLRenderer {
    public enum Error: Swift.Error {
        case templateNotFound
    }

    // MARK: - Rendering

    public static func render(_ document: ReportDocument, preparedAt: Date = .now) throws -> String {
        let entries = document.entries.map(renderEntry).joined()
        let questions = document.questionsAndNotes.isEmpty
            ? ""
            : """
            <section class="questions"><h2>Quero conversar sobre</h2><p>\(escape(document.questionsAndNotes))</p></section>
            """
        guard let templateURL = Bundle.module.url(
            forResource: "report",
            withExtension: "html",
            subdirectory: "Reports/Resources"
        ) else {
            throw Error.templateNotFound
        }
        let template = try String(contentsOf: templateURL, encoding: .utf8)
        return renderTemplate(template, values: [
            "start": document.start.description,
            "end": document.end.description,
            "prepared": escape(ClaraFormat.shortDate(preparedAt)),
            "emptyMessage": entries.isEmpty ? "<p>Nenhum registro selecionado para este período.</p>" : "",
            "entries": entries,
            "questions": questions
        ])
    }

    // MARK: - Entry rendering

    private static func renderEntry(_ moment: Moment) -> String {
        var html = """
        <article class="entry">
          <time>\(escape(ClaraFormat.dateTime(moment.occurredAt, in: moment.timeZone)))</time>
          <strong>\(escape(moment.displayLabel))</strong>
        """
        if !moment.note.isEmpty {
            html += "<p>\(escape(moment.note))</p>"
        }
        if !moment.context.isEmpty {
            html += "<p><small>Contexto que percebi:</small> \(escape(moment.context))</p>"
        }
        if !moment.helpedOrHindered.isEmpty {
            html += "<p><small>Algo que ajudou ou atrapalhou:</small> \(escape(moment.helpedOrHindered))</p>"
        }
        return html + "</article>"
    }

    private static func renderTemplate(_ template: String, values: [String: String]) -> String {
        var output = ""
        var cursor = template.startIndex

        while let opening = template.range(of: "{{", range: cursor..<template.endIndex) {
            output.append(contentsOf: template[cursor..<opening.lowerBound])
            guard let closing = template.range(of: "}}", range: opening.upperBound..<template.endIndex) else {
                output.append(contentsOf: template[opening.lowerBound...])
                return output
            }

            let key = String(template[opening.upperBound..<closing.lowerBound])
            if let value = values[key] {
                output.append(contentsOf: value)
            } else {
                output.append(contentsOf: template[opening.lowerBound..<closing.upperBound])
            }
            cursor = closing.upperBound
        }

        output.append(contentsOf: template[cursor...])
        return output
    }

    // MARK: - HTML escaping

    /// User text never goes into the HTML unescaped.
    static func escape(_ value: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(value.count)
        for character in value {
            switch character {
            case "&": escaped += "&amp;"
            case "<": escaped += "&lt;"
            case ">": escaped += "&gt;"
            case "\"": escaped += "&quot;"
            case "'": escaped += "&#39;"
            default: escaped.append(character)
            }
        }
        return escaped
    }
}
