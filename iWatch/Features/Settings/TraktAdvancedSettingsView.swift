import SwiftUI

struct TraktAdvancedSettingsView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        Form {
            Section {
                Button {
                    Task { await session.repairLocalSyncData() }
                } label: {
                    if session.isMaintainingSync {
                        ProgressView(session.syncMaintenanceTitle ?? "Working…")
                    } else {
                        Text("Check Library Data")
                    }
                }
                .disabled(session.syncActionsUnavailable)
            } footer: {
                Text("Checks local records for duplicates and inconsistent links, and repairs issues it can resolve. This doesn’t verify every item against Trakt.")
            }
            if let result = session.syncMaintenanceMessage {
                Section("Latest Result") { Text(result) }
            }
            Section {
                NavigationLink("Diagnostics") { SyncDiagnosticsView() }
                NavigationLink("Move Pending Uploads") { TraktRecoveryView() }
            }
            Section {
                NavigationLink("Rebuild from Trakt") { TraktRebuildView() }
            } footer: {
                Text("Rebuilding replaces your iWatch Watchlist, watched history, and show progress, and discards pending uploads. Review the consequences before continuing.")
            }
        }
        .navigationTitle("Advanced")
        .navigationBarTitleDisplayMode(.inline)
        .task { await session.refreshSyncDiagnostics() }
    }
}

struct TraktRecoveryView: View {
    @Environment(AppSession.self) private var session
    @State private var showConfirmation = false

    var body: some View {
        Form {
            Section {
                Text("Continue Uploads on This Device").font(.headline)
                Text("Use this if changes are stuck on a device you no longer use. Pending uploads for this Trakt account will be assigned to this device.")
                Text("First stop Trakt sync on your other devices to prevent both devices trying to upload the same changes.")
            }
            Section {
                Button("Move Pending Uploads Here") { showConfirmation = true }
                    .disabled(session.syncActionsUnavailable || !session.traktConnected || session.pendingTraktAccountKey != nil)
            } footer: {
                Text("Unconfirmed watched uploads will be checked without sending another play. Moving them doesn’t guarantee they can be confirmed.")
            }
            if let result = session.syncMaintenanceMessage {
                Section("Latest Result") { Text(result) }
            }
        }
        .navigationTitle("Move Pending Uploads")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Move Uploads to This Device?", isPresented: $showConfirmation, titleVisibility: .visible) {
            Button("Move Pending Uploads") { Task { await session.recoverPendingUploads() } }
        } message: {
            Text("Continue only after stopping Trakt sync on your other devices. This changes which device owns unfinished uploads for this account.")
        }
    }
}

struct TraktRebuildView: View {
    @Environment(AppSession.self) private var session
    @State private var showConfirmation = false

    var body: some View {
        Form {
            Section {
                Text("Replace Your iWatch Library").font(.headline)
                Text("Rebuilding removes your iWatch Watchlist, watched history, and show progress, discards pending uploads, then imports your Trakt library again.")
                Label("Unsynced changes will be lost.", systemImage: "exclamationmark.triangle")
                Text("These removals can sync to your other devices through iCloud. Your Trakt account’s library isn’t deleted.")
            }
            Section {
                Button("Rebuild from Trakt", role: .destructive) { showConfirmation = true }
                    .disabled(session.syncActionsUnavailable || !session.traktConnected || session.pendingTraktAccountKey != nil)
            } footer: {
                Text("Use this only if your library remains incorrect after checking local data and reviewing pending changes.")
            }
            if let result = session.syncMaintenanceMessage {
                Section("Latest Result") { Text(result) }
            }
        }
        .navigationTitle("Rebuild from Trakt")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Rebuild Library from Trakt?", isPresented: $showConfirmation) {
            Button("Discard Changes and Rebuild", role: .destructive) { Task { await session.resetLocalTraktSyncCache() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your iWatch library will be replaced from Trakt, including through iCloud. Unsynced changes will be lost. This can’t be undone.")
        }
    }
}
