import SwiftUI

struct SyncSupportView: View {
    @Environment(AppSession.self) private var session

    private var report: String {
        SyncSupportReport.make(
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—",
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—",
            connected: session.traktConnected, cloudStatus: session.cloudSyncStatus,
            lastCloudActivity: session.lastCloudActivityAt, diagnostics: session.syncDiagnostics)
    }

    var body: some View {
        Form {
            Section {
                Link("Contact Support", destination: URL(string: "https://tylerkeegan.com/iwatch/support/")!)
            } footer: {
                Text("Describe what happened and what you expected. A screenshot can help explain the problem.")
            }
            Section {
                DisclosureGroup("Review Diagnostic Report") {
                    Text(report).font(.footnote.monospaced()).textSelection(.enabled)
                }
                ShareLink(item: report) {
                    Label("Share Diagnostic Report", systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text("Includes app version, sync status, transfer dates, and queue counts. Excludes account identifiers, credentials, library titles, and error messages. Nothing is sent automatically.")
            }
        }
        .navigationTitle("Contact Support")
        .navigationBarTitleDisplayMode(.inline)
        .task { await session.refreshSyncDiagnostics() }
    }
}

/// An allowlist: never export provider errors, pending-change payloads, or account identity.
enum SyncSupportReport {
    static func make(version: String, build: String, connected: Bool,
                     cloudStatus: AppSession.CloudSyncStatus, lastCloudActivity: Date?,
                     diagnostics: SyncDiagnostics) -> String {
        func date(_ value: Date?) -> String { value?.ISO8601Format() ?? "Not recorded" }
        return """
        iWatch Support Report
        Version: \(version) (\(build))
        Trakt connected: \(connected ? "Yes" : "No")
        iCloud status: \(cloudStatus.title)
        Last iCloud activity: \(date(lastCloudActivity))
        Initial Trakt import complete: \(diagnostics.initialBaselineComplete ? "Yes" : "No")
        Last Trakt download: \(date(diagnostics.lastSuccessfulPullAt))
        Last Trakt upload pass: \(date(diagnostics.lastSuccessfulPushAt))
        Waiting uploads: \(diagnostics.pendingOperationCount)
        Processing uploads: \(diagnostics.processingOperationCount)
        Stopped uploads: \(diagnostics.deadletterOperationCount)
        Unconfirmed changes: \(diagnostics.changes.filter { $0.state == .confirming }.count)
        Possible duplicates: \(diagnostics.duplicateCandidateCount)
        """
    }
}
