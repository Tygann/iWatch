import SwiftUI

struct TraktSettingsView: View {
    @Environment(AppSession.self) private var session
    @State private var showDisconnect = false
    @State private var showImport = false

    private var health: TraktSyncPresentation { session.traktSyncPresentation }

    var body: some View {
        Form {
            Section {
                SyncStatusContent(title: health.title, detail: health.detail, symbol: health.symbol,
                                  needsAttention: health.needsAttention, isWorking: health.isWorking)
                if !session.traktConnected {
                    Button("Connect Trakt") { session.startTraktOAuth() }
                        .disabled(session.syncActionsUnavailable)
                } else if session.pendingTraktAccountKey == nil {
                    TraktSyncActionButton()
                }
                if session.traktConnected, session.pendingTraktAccountKey == nil, let date = session.lastSyncAt {
                    SyncDateRow(title: "Last Successful Sync", date: date)
                }
            }

            if session.pendingTraktAccountKey != nil {
                setupSection
            } else if session.traktConnected {
                if !session.syncDiagnostics.changes.isEmpty || health.needsAttention {
                    Section {
                        NavigationLink {
                            TraktPendingChangesView()
                        } label: {
                            SettingsNavigationLabel(title: "Pending Changes", systemImage: "clock",
                                detail: session.syncDiagnostics.changes.isEmpty ? "Review" : session.syncDiagnostics.changes.count.formatted())
                        }
                    }
                }
                Section {
                    NavigationLink("Advanced") { TraktAdvancedSettingsView() }
                } footer: {
                    Text("Library checks, diagnostics, and recovery options.")
                }
            }

            if session.traktConnected {
                Section {
                    Label("Signed In to Trakt", systemImage: "person.crop.circle")
                    Button("Disconnect Trakt", role: .destructive) { showDisconnect = true }
                        .disabled(session.syncActionsUnavailable)
                } header: {
                    Text("Account")
                } footer: {
                    Text("Disconnecting stops Trakt sync. Your iWatch library stays on this device and in iCloud.")
                }
            }
        }
        .navigationTitle("Trakt")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Disconnect Trakt?", isPresented: $showDisconnect, titleVisibility: .visible) {
            Button("Disconnect Trakt", role: .destructive) { session.logoutTrakt() }
        } message: {
            Text("Your iWatch library will remain. Future changes won’t sync with Trakt until you reconnect.")
        }
        .alert("Replace Library from Trakt?", isPresented: $showImport) {
            Button("Replace and Import", role: .destructive) { Task { await session.importTraktLibrary() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes your iWatch Watchlist, watched history, show progress, and pending uploads before importing this account. Removals can sync through iCloud. Unsynced changes will be lost.")
        }
        .task { await session.refreshSyncDiagnostics() }
    }

    private var setupSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Button("Use Trakt Library") { showImport = true }
                Text("Start from this account’s Watchlist and watched history. This replaces your iWatch Watchlist, watched history, show progress, and pending uploads.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Button("Upload Pending Changes") { Task { await session.uploadLocalLibrary() } }
                Text("Send pending changes made on this device before connecting to Trakt, then download this account’s library.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if let error = session.traktLastError {
                DisclosureGroup("Error Details") {
                    Text(error).font(.subheadline).textSelection(.enabled)
                }
            }
        } header: {
            Text("Choose How to Start")
        } footer: {
            Text("Sync won’t start until you choose. You can leave this screen and finish setup later.")
        }
        .disabled(session.syncActionsUnavailable)
    }
}

struct TraktSyncActionButton: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        Button(title) {
            Task {
                switch session.traktSyncPresentation.action {
                case .check: await session.checkWatchedUploadConfirmations()
                case .retry: await session.retryFailedSyncOperations()
                case .sync: await session.runSync(reason: .userInitiated)
                case .connect: session.startTraktOAuth()
                case .setup: break
                }
            }
        }
        .disabled(session.syncActionsUnavailable || session.pendingTraktAccountKey != nil)
    }

    private var title: String {
        if session.isSyncing { return "Syncing…" }
        switch session.traktSyncPresentation.action {
        case .check: return "Check Again"
        case .retry: return "Retry Failed Changes"
        case .sync: return "Sync Now"
        case .connect: return "Connect Trakt"
        case .setup: return "Finish Setup"
        }
    }
}

#Preview {
    let container = AppContainer.preview()
    NavigationStack { TraktSettingsView() }.environment(container.session)
}
