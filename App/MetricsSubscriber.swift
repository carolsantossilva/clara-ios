import ClaraServices
import Foundation
import MetricKit

/// MetricKit delivers, within 24 hours, real metrics of the app in production (launch
/// time, hangs, memory use) and crash/hang diagnostics, with no third-party SDK.
/// It complements Instruments, which only measures on the tester's machine.
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
