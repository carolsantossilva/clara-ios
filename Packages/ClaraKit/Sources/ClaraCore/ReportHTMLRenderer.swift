import Foundation

/// Builds the printable summary HTML (turned into a PDF by the Consultation feature).
/// Direct port of the React Native app's `renderReportHtml`.
public enum ReportHTMLRenderer {
    public static func render(_ document: ReportDocument, preparedAt: Date = .now) -> String {
        let entries = document.entries.map(renderEntry).joined()
        let questions = document.questionsAndNotes.isEmpty
            ? ""
            : """
            <section class="questions"><h2>Quero conversar sobre</h2><p>\(escape(document.questionsAndNotes))</p></section>
            """
        let prepared = ClaraFormat.shortDate(preparedAt)

        return """
        <!doctype html>
        <html lang="pt-BR">
        <head>
          <meta charset="utf-8" />
          <title>Resumo para consulta — Clara</title>
          <style>
            :root { color: #2b2733; font: 14px/1.55 -apple-system, sans-serif; }
            body { margin: 0; }
            .brand { color: #5b4b73; font-size: 19px; font-weight: 700; letter-spacing: -.05em; }
            h1 { margin: 32px 0 8px; font: 500 30px Georgia, serif; }
            .period, time, small, .footnote { color: #746e7b; }
            .entry { border-top: 1px solid #e9e5e9; padding: 14px 0; page-break-inside: avoid; }
            .entry time { display: block; font-size: 12px; }
            .entry strong { color: #5f4e76; }
            .entry p { margin: 4px 0 0; white-space: pre-wrap; overflow-wrap: anywhere; }
            .questions { margin-top: 25px; border-radius: 14px; padding: 16px; background: #f3eff8; page-break-inside: avoid; }
            .questions h2 { margin: 0 0 8px; color: #5b4b73; font-size: 14px; }
            .questions p { margin: 0; white-space: pre-wrap; }
            .footnote { margin-top: 30px; font-size: 11px; }
          </style>
        </head>
        <body>
          <div class="brand">clara<span style="color:#d69673">.</span> <small>RESUMO PESSOAL</small></div>
          <h1>Registros para consulta</h1>
          <p class="period">Período: \(document.start) a \(document.end) · Preparado em \(escape(prepared))</p>
          \(entries.isEmpty ? "<p>Nenhum registro selecionado para este período.</p>" : entries)
          \(questions)
          <p class="footnote">Este resumo reúne apenas o que escolhi registrar. Não explica causas nem substitui uma avaliação profissional.</p>
        </body>
        </html>
        """
    }

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
