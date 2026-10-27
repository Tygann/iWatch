import SwiftUI

struct TraktTroubleshootingView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        Form {
            Section {
                Text("Start by checking your library. Review the result before trying another recovery option.")
                NavigationLink("Check Library Data") { TraktLibraryCheckView() }
            }
            if session.syncDiagnostics.changes.contains(where: { !$0.isOnThisDevice }) {
                Section {
                    NavigationLink("Continue on This Device") { TraktRecoveryView() }
                } footer: {
                    Text("Use this only after stopping sync on the device where these changes were made.")
                }
            }
            Section {
                NavigationLink("Contact Support") { SyncSupportView() }
            }
            Section {
                NavigationLink("Rebuild from Trakt") { TraktRebuildView() }
            } header: {
                Text("If the Problem Continues")
            } footer: {
                Text("Rebuilding replaces your iWatch library and discards unsynced changes. Contact support first if you’re unsure.")
            }
        }
        .navigationTitle("Help with Changes")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TraktLibraryCheckView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        Form {
            Section {
                Text("Checks local records for duplicates and inconsistent links, and repairs issues it can resolve.")
                    .font(.subheadline).foregroundStyle(.secondary)
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
                Text("This doesn’t compare every library item with Trakt.")
            }
            if let result = session.syncMaintenanceMessage {
                Section("Latest Result") { Text(result) }
            }
        }
        .navigationTitle("Check Library Data")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TraktRecoveryView: View {
    @Environment(AppSession.self) private var session
    @State private var showConfirmation = false

    var body: some View {
        Form {
            Section {
                Text("Move this account’s unfinished uploads from another device to this one.")
                Text("First stop Trakt sync on your other devices.")
            }
            Section {
                Button("Move Pending Uploads Here") { showConfirmation = true }
                    .disabled(session.syncActionsUnavailable || !session.traktConnected || session.pendingTraktAccountKey != nil)
            } footer: {
                Text("Unconfirmed watched plays are checked without being uploaded again.")
            }
            if let result = session.syncMaintenanceMessage {
                Section("Latest Result") { Text(result) }
            }
        }
        .navigationTitle("Continue on This Device")
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
