import ClaraServices
import Foundation
import MetricKit

/// MetricKit entrega, em até 24h, métricas reais do app em produção (tempo de
/// abertura, travamentos, uso de memória) e diagnósticos de crash/hang — sem SDK
/// de terceiros. Complementa o Instruments, que mede só na máquina de quem testa.
final class MetricsSubscriber: NSObject, MXMetricManagerSubscriber {
    private let crashReporter: any CrashReporter

    init(crashReporter: any CrashReporter) {
        self.crashReporter = crashReporter
        super.init()
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            let launch = payload.applicationLaunchMetrics?.histogrammedTimeToFirstDraw.totalBucketCount ?? 0
            crashReporter.breadcrumb("metrics: \(payload.timeStampBegin)–\(payload.timeStampEnd), launches=\(launch)")
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let crashes = payload.crashDiagnostics?.count ?? 0
            let hangs = payload.hangDiagnostics?.count ?? 0
            crashReporter.breadcrumb("diagnostics: crashes=\(crashes) hangs=\(hangs)")
        }
    }
}
