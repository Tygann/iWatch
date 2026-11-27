import SwiftUI

struct TraktSettingsSection: View {
    @Environment(AppSession.self) private var session

    private var health: TraktSyncPresentation { session.traktSyncPresentation }

    var body: some View {
        Section {
            TraktConnectionRow()
            if !session.traktConnected && health.needsAttention {
                Button("Connect Trakt") { session.startTraktOAuth() }
                    .disabled(session.syncActionsUnavailable)
            }
            if session.pendingTraktAccountKey != nil {
                NavigationLink {
                    TraktSetupView()
                } label: {
                    Text("Finish Setup")
                }
                .accessibilityIdentifier("trakt-setup")
            } else if session.traktConnected {
                TraktSyncActionButton()
                if !session.syncDiagnostics.changes.isEmpty || health.needsAttention {
                    NavigationLink {
                        TraktPendingChangesView()
                    } label: {
                        LabeledContent("Pending Changes", value: session.syncDiagnostics.changes.count.formatted())
                    }
                }
            }
        } header: {
            Text("Trakt")
        } footer: {
            Text(footer)
        }
        .task { await session.refreshSyncDiagnostics() }
    }

    private var footer: String {
        if session.pendingTraktAccountKey != nil { return "Finish setup to start syncing." }
        if health.needsAttention {
            if health.title == "Connection Interrupted" { return health.title }
            if !session.traktConnected { return health.detail }
            if !session.syncDiagnostics.changes.isEmpty {
                return "Some changes still need attention. See Pending Changes for details."
            }
            return health.detail
        }
        return session.traktConnected
            ? "Your Watchlist and watched history sync automatically."
            : "Sync your Watchlist and watched history with Trakt."
    }
}

struct TraktSetupView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var showImport = false

    var body: some View {
        Form {
            setupSection
        }
        .navigationTitle("Set Up Trakt")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: session.pendingTraktAccountKey) { _, accountKey in
            if accountKey == nil { dismiss() }
        }
    }

    private var setupSection: some View {
        Section {
            Button(role: .destructive) { showImport = true } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Replace iWatch Library from Trakt").foregroundStyle(.red)
                    Text("Replace your iWatch library and discard pending uploads.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button { Task { await session.uploadLocalLibrary() } } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Upload Pending Changes").foregroundStyle(Color.accentColor)
                    Text("Send pending changes from this device, then download Trakt.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let error = session.traktLastError {
                DisclosureGroup("Error Details") {
                    Text(error).font(.subheadline).textSelection(.enabled)
                }
                NavigationLink("Contact Support") { SyncSupportView() }
            }
        } header: {
            Text("Choose How to Start")
        } footer: {
            Text("You can finish setup later.")
        }
        .disabled(session.syncActionsUnavailable || session.pendingTraktAccountKey == nil)
        .alert("Replace Library from Trakt?", isPresented: $showImport) {
            Button("Replace and Import", role: .destructive) { Task { await session.importTraktLibrary() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes your iWatch Watchlist, watched history, show progress, and pending uploads before importing this account. Removals can sync through iCloud. Unsynced changes will be lost.")
        }
    }
}

struct TraktConnectionRow: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        Group {
            if session.traktConnected {
                NavigationLink {
                    TraktAccountSettingsView()
                } label: {
                    LabeledContent("Account", value: "Connected")
                }
            } else if session.traktIsConnecting {
                ProgressView("Connecting to Trakt…")
            } else if !session.traktSyncPresentation.needsAttention {
                Button("Connect Trakt") { session.startTraktOAuth() }
                    .disabled(session.syncActionsUnavailable)
            }
        }
        .accessibilityIdentifier("trakt-connection")
    }
}

private struct TraktAccountSettingsView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var showDisconnect = false

    var body: some View {
        Form {
            Section {
                if let date = session.syncDiagnostics.lastSuccessfulPullAt {
                    SyncDateRow(title: "Last Trakt Check", date: date)
                } else {
                    LabeledContent("Last Trakt Check", value: "Not checked yet")
                }
            }
            Section {
                NavigationLink("Help with Sync") { TraktTroubleshootingView() }
            }
            Section {
                Button("Disconnect Trakt", role: .destructive) { showDisconnect = true }
                    .disabled(session.syncActionsUnavailable)
            }
        }
        .navigationTitle("Trakt Account")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Disconnect Trakt?", isPresented: $showDisconnect, titleVisibility: .visible) {
            Button("Disconnect Trakt", role: .destructive) {
                session.logoutTrakt()
                dismiss()
            }
        } message: {
            Text("Your iWatch library will remain. Future changes won’t sync with Trakt until you reconnect.")
        }
    }
}

struct TraktSyncActionButton: View {
    @Environment(AppSession.self) private var session
    @State private var retryOffer: SyncEngine.HistoryRetry?
    @State private var showsRetryConfirmation = false

    var body: some View {
        Group {
            if session.traktSyncPresentation.isWorking {
                ProgressView("Syncing…")
                    .accessibilityIdentifier("trakt-sync-progress")
            } else {
                Button("Sync Now") {
                    Task {
                        retryOffer = await session.syncTraktNow()
                        showsRetryConfirmation = retryOffer != nil
                    }
                }
                .disabled(session.syncActionsUnavailable)
            }
        }
        .alert("Retry Missing Plays?", isPresented: $showsRetryConfirmation, presenting: retryOffer) { offer in
            Button("Retry Upload") {
                Task { _ = await session.syncTraktNow(historyRetry: offer) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { offer in
            let count = offer.ids.count
            Text("iWatch couldn’t find ^[\(count) watched play](inflect: true) in Trakt history. It will check again before retrying. A play could be duplicated if it hasn’t appeared on Trakt yet.")
        }
    }
}

#if DEBUG
#Preview {
    let container = AppContainer.preview()
    NavigationStack { LibrarySettingsView() }
        .environment(container.session)
        .environment(container)
        .environment(container.router)
}
#endif
