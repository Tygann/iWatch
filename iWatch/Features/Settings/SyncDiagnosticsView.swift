import SwiftUI

// MARK: - Sync Diagnostics Screen

struct SyncDiagnosticsView: View {
    @Environment(AppSession.self) private var session

    @State private var showResetConfirmation = false
    @State private var showRecoveryConfirmation = false

    var body: some View {
        Form {
            statusSection
            librarySection
            uploadQueueSection
            maintenanceSection
            resetSection

            if let message = session.syncMaintenanceMessage {
                Section("Latest Result") {
                    Text(message)
                }
            }

            if let error = session.traktLastError ?? session.syncDiagnostics.lastErrorDescription {
                Section("Last Error") {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Sync Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Reset Trakt library data?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Trakt Library Data", role: .destructive) {
                Task { await session.resetLocalTraktSyncCache() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes Trakt-derived Watchlist and history data plus pending uploads, then imports Trakt again. These deletions can sync to your other devices through iCloud. Unsynced changes will be lost.")
        }
        .confirmationDialog("Recover uploads on this device?", isPresented: $showRecoveryConfirmation, titleVisibility: .visible) {
            Button("Recover Pending Uploads") { Task { await session.recoverPendingUploads() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("First stop Trakt syncing on your other devices. This transfers unfinished uploads for this account to this device. A request that reached Trakt before its response was lost may be repeated, including a watched play.")
        }
        .task {
            await session.refreshSyncDiagnostics()
        }
    }

    private var statusSection: some View {
        Section {
            LabeledContent("Trakt Sync") {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(session.syncProgress.title)
                    if let detail = session.syncProgress.detail {
                        Text(detail)
                            .font(.caption)
                    }
                }
                .foregroundStyle(.secondary)
            }

            LabeledContent("iCloud") {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(session.cloudSyncStatus.title)
                    if let detail = session.cloudSyncStatus.detail {
                        Text(detail)
                            .font(.caption)
                    }
                }
                .foregroundStyle(.secondary)
            }

            if let date = session.lastCloudImportAt {
                LabeledContent("Last iCloud Download", value: date.formatted(date: .abbreviated, time: .shortened))
            }
            if let date = session.lastCloudExportAt {
                LabeledContent("Last iCloud Upload", value: date.formatted(date: .abbreviated, time: .shortened))
            }

            LabeledContent("Library Import") {
                Text(session.syncDiagnostics.initialBaselineComplete ? "Complete" : "Pending")
                    .foregroundStyle(.secondary)
            }

            if let lastRemoteActivityAt = session.syncDiagnostics.lastSeenRemoteActivityAt {
                LabeledContent("Last Trakt Change") {
                    Text(lastRemoteActivityAt.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Status")
        }
    }

    private var librarySection: some View {
        Section {
            LabeledContent("Watchlist Movies") {
                Text("\(session.syncDiagnostics.importedMovieCount)")
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Watchlist Shows") {
                Text("\(session.syncDiagnostics.importedShowCount)")
                    .foregroundStyle(.secondary)
            }

            LabeledContent("History Entries") {
                Text("\(session.syncDiagnostics.importedHistoryCount)")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Trakt Library")
        } footer: {
            Text("Watchlist includes Trakt Watchlist items and active show progress retained by iWatch.")
        }
    }

    private var uploadQueueSection: some View {
        Section {
            LabeledContent("Pending Changes") {
                Text("\(session.syncDiagnostics.pendingOperationCount)")
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Processing Changes") {
                Text("\(session.syncDiagnostics.processingOperationCount)")
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Failed Changes") {
                Text("\(session.syncDiagnostics.deadletterOperationCount)")
                    .foregroundStyle(failedChangesColor)
            }

            LabeledContent("Possible Duplicates") {
                Text("\(session.syncDiagnostics.duplicateCandidateCount)")
                    .foregroundStyle(duplicateColor)
            }

        } header: {
            Text("Pending Uploads")
        } footer: {
            Text("Uploads are sent by the device that created them. Recover pending uploads here only after stopping sync on the other device.")
        }
    }

    private var maintenanceSection: some View {
        Section("Repair") {
            Button("Recover Pending Uploads on This Device") { showRecoveryConfirmation = true }
                .disabled(!session.traktConnected || session.isSyncing || session.isErasingAllData)

            if session.syncDiagnostics.deadletterOperationCount > 0 {
                Button {
                    Task { await session.retryFailedSyncOperations() }
                } label: {
                    Label("Retry Failed Changes", systemImage: "arrow.clockwise")
                }
                .disabled(session.isSyncing || session.isErasingAllData)
            }

            Button {
                Task { await session.repairLocalSyncData() }
            } label: {
                Label("Check and Repair Sync Data", systemImage: "cross.case")
            }
            .disabled(session.isSyncing || session.isErasingAllData)
        }
    }

    private var resetSection: some View {
        Section {
            Button("Reset Trakt Library Data", role: .destructive) {
                showResetConfirmation = true
            }
            .disabled(!session.traktConnected || session.isSyncing || session.isErasingAllData)
        } footer: {
            Text("Use this only when Trakt data remains incorrect after checking and repairing local data.")
        }
    }

    private var failedChangesColor: Color {
        session.syncDiagnostics.deadletterOperationCount > 0 ? .red : .secondary
    }

    private var duplicateColor: Color {
        session.syncDiagnostics.duplicateCandidateCount > 0 ? .orange : .secondary
    }
}

// MARK: - Previews

#Preview {
    let container = AppContainer.preview()
    NavigationStack {
        SyncDiagnosticsView()
    }
    .environment(container.session)
}
