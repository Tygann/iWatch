import SwiftUI

struct SyncDiagnosticsView: View {
    @Environment(AppSession.self) private var session

    @State private var showResetConfirmation = false

    var body: some View {
        Form {
            statusSection
            importedLibrarySection
            outboundQueueSection
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
            "Reset local Trakt sync data?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Local Sync Data", role: .destructive) {
                Task { await session.resetLocalTraktSyncCache() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes Trakt-derived Following and history data plus pending Trakt operations from this device, then rebuilds from Trakt. Unsynced local Trakt changes will be lost.")
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

            LabeledContent("Initial Import") {
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
            Text("Current Status")
        }
    }

    private var importedLibrarySection: some View {
        Section {
            LabeledContent("Following Movies") {
                Text("\(session.syncDiagnostics.importedMovieCount)")
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Following Shows") {
                Text("\(session.syncDiagnostics.importedShowCount)")
                    .foregroundStyle(.secondary)
            }

            LabeledContent("History Entries") {
                Text("\(session.syncDiagnostics.importedHistoryCount)")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Imported Library")
        } footer: {
            Text("Following includes Trakt Watchlist items and active show progress retained by iWatch.")
        }
    }

    private var outboundQueueSection: some View {
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
            Text("Changes to Upload")
        } footer: {
            Text("Zero means iWatch has no local changes waiting to be sent to Trakt.")
        }
    }

    private var maintenanceSection: some View {
        Section("Maintenance") {
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
                Label("Check and Repair Local Data", systemImage: "cross.case")
            }
            .disabled(session.isSyncing || session.isErasingAllData)
        }
    }

    private var resetSection: some View {
        Section {
            Button("Reset Local Trakt Sync Data", role: .destructive) {
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

#Preview {
    let container = AppContainer.preview()
    NavigationStack {
        SyncDiagnosticsView()
    }
    .environment(container.session)
}
