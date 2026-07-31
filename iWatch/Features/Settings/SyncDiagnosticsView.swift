import SwiftUI

struct SyncDiagnosticsView: View {
    @Environment(AppSession.self) private var session

    @State private var showResetConfirmation = false

    var body: some View {
        Form {
            overviewSection
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
            Text("This removes Trakt-derived watchlist and history data plus pending Trakt operations from this device, then rebuilds from Trakt. Unsynced local Trakt changes will be lost.")
        }
        .task {
            await session.refreshSyncDiagnostics()
        }
    }

    private var overviewSection: some View {
        Section {
            LabeledContent("Initial Import") {
                Text(session.syncDiagnostics.initialBaselineComplete ? "Complete" : "Pending")
                    .foregroundStyle(.secondary)
            }

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

            if let lastRemoteActivityAt = session.syncDiagnostics.lastSeenRemoteActivityAt {
                LabeledContent("Last Trakt Change") {
                    Text(lastRemoteActivityAt.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Current Status")
        } footer: {
            Text("These values describe iWatch’s local Trakt sync queue and are mainly useful when troubleshooting.")
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
