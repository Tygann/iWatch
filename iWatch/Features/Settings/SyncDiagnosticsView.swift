import SwiftUI

/// Read-only technical information. Normal status and actions live on the Trakt screen.
struct SyncDiagnosticsView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        Form {
            Section("Trakt Transfers") {
                Text(session.traktSyncPresentation.title)
                LabeledContent("Initial Import", value: session.syncDiagnostics.initialBaselineComplete ? "Complete" : "Not Complete")
                if let date = session.syncDiagnostics.lastSuccessfulPullAt {
                    SyncDateRow(title: "Last Download", date: date)
                }
                if let date = session.syncDiagnostics.lastSuccessfulPushAt {
                    SyncDateRow(title: "Last Upload Pass", date: date)
                }
                if let date = session.syncDiagnostics.lastSeenRemoteActivityAt {
                    SyncDateRow(title: "Last Trakt Activity", date: date)
                }
            }
            Section {
                LabeledContent("Watchlist Movies", value: session.syncDiagnostics.importedMovieCount.formatted())
                LabeledContent("Watchlist and Active Shows", value: session.syncDiagnostics.importedShowCount.formatted())
                LabeledContent("Watched Plays", value: session.syncDiagnostics.importedHistoryCount.formatted())
            } header: {
                Text("Local Library")
            } footer: {
                Text("Counts describe the library on this device. Shows include active progress retained by iWatch; these counts aren’t a live inventory of your Trakt account.")
            }
            Section("Upload Queue") {
                LabeledContent("Waiting", value: session.syncDiagnostics.pendingOperationCount.formatted())
                LabeledContent("Processing", value: session.syncDiagnostics.processingOperationCount.formatted())
                LabeledContent("Stopped", value: session.syncDiagnostics.deadletterOperationCount.formatted())
                LabeledContent("Possible Local Duplicates", value: session.syncDiagnostics.duplicateCandidateCount.formatted())
            }
            if let error = session.traktLastError ?? session.syncDiagnostics.lastErrorDescription {
                Section("Latest Error Details") {
                    Text(error).font(.subheadline).textSelection(.enabled)
                }
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .task { await session.refreshSyncDiagnostics() }
    }
}
