import SwiftUI

struct TraktSettingsSection: View {
    @Environment(AppSession.self) private var session

    private var health: TraktSyncPresentation { session.traktSyncPresentation }

    var body: some View {
        Section("Trakt") {
            TraktConnectionStatus()
            if session.pendingTraktAccountKey != nil {
                TraktSetupOptions()
            } else if session.traktConnected {
                let hasPendingChanges = !session.syncDiagnostics.changes.isEmpty
                if hasPendingChanges {
                    TraktPendingChangesSection()
                }
                TraktSyncActionButton()
                if !hasPendingChanges && health.needsAttention {
                    Link("Trakt Service Status", destination: URL(string: "https://status.trakt.tv")!)
                }
            }
            if !session.traktIsConnecting {
                TraktConnectionAction()
            }
        }
        .task { await session.refreshSyncDiagnostics() }
    }
}

private struct TraktSetupOptions: View {
    @Environment(AppSession.self) private var session
    @State private var showImport = false

    var body: some View {
        DisclosureGroup {
            Text(session.traktSyncPresentation.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
            if session.isMaintainingSync, let title = session.syncMaintenanceTitle {
                ProgressView(title)
            }
            if let error = session.traktLastError {
                DisclosureGroup("Error Details") {
                    Text(error).font(.subheadline).textSelection(.enabled)
                }
                Link("Contact Support", destination: SyncSupportView.contactURL)
            }
        } label: {
            Text("Finish Setup")
        }
        .disabled(session.syncActionsUnavailable || session.pendingTraktAccountKey == nil)
        .alert("Replace Library from Trakt?", isPresented: $showImport) {
            Button("Replace and Import", role: .destructive) { Task { await session.importTraktLibrary() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("After Trakt finishes downloading, iWatch replaces your Watchlist, watched history, and show progress and discards pending uploads. The replacement can sync through iCloud.")
        }
    }
}

private struct TraktConnectionStatus: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        let health = session.traktSyncPresentation

        if session.traktIsConnecting {
            ProgressView("Connecting to Trakt…")
        } else if !health.isWorking || session.pendingTraktAccountKey != nil {
            let status = summary(for: health)
            VStack(alignment: .leading, spacing: 4) {
                Text(status.title)
                Text(status.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("trakt-connection")
        }
    }

    private func summary(for health: TraktSyncPresentation) -> (title: String, detail: String) {
        if session.pendingTraktAccountKey != nil {
            return ("Connected", "Finish setup to start syncing.")
        }
        if health.needsAttention || health.title == "Changes Pending" || !session.traktConnected {
            return (health.title, health.detail)
        }
        return ("Connected", "Your Watchlist and watched history sync automatically.")
    }
}

private struct TraktConnectionAction: View {
    @Environment(AppSession.self) private var session
    @State private var showDisconnect = false

    var body: some View {
        Group {
            if session.traktConnected {
                Button("Disconnect Trakt") { showDisconnect = true }
            } else {
                Button("Connect Trakt") { session.startTraktOAuth() }
            }
        }
        .disabled(session.syncActionsUnavailable)
        .confirmationDialog("Disconnect Trakt?", isPresented: $showDisconnect, titleVisibility: .visible) {
            Button("Disconnect Trakt", role: .destructive) { session.logoutTrakt() }
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
                let health = session.traktSyncPresentation
                ProgressView {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(health.title)
                        if !health.detail.isEmpty {
                            Text(health.detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
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
