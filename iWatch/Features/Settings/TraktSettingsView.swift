import SwiftUI

struct TraktSettingsView: View {
    @Environment(AppSession.self) private var session

    @State private var showDisconnectConfirmation = false
    @State private var showLinkDecision = false

    var body: some View {
        Form {
            statusSection

            if session.traktConnected {
                syncSection
                disconnectSection
            } else {
                connectSection
            }

            if let error = session.traktLastError {
                issueSection(error)
            }
        }
        .navigationTitle("Trakt")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Choose how to set up Trakt",
            isPresented: $showLinkDecision,
            titleVisibility: .visible
        ) {
            Button("Import Trakt Library") {
                Task { await session.importTraktLibrary() }
            }
            Button("Upload Local Library") {
                Task { await session.uploadLocalLibrary() }
            }
            Button("Decide Later", role: .cancel) {}
        } message: {
            Text("Import uses your Trakt Watchlist and active progress as the starting point. Upload sends existing Watchlist items and watched history to Trakt.")
        }
        .confirmationDialog(
            "Disconnect Trakt?",
            isPresented: $showDisconnectConfirmation,
            titleVisibility: .visible
        ) {
            Button("Disconnect Trakt", role: .destructive) {
                session.logoutTrakt()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your local iWatch library remains on this device and in iCloud. Future changes won’t sync with Trakt until you reconnect.")
        }
        .task {
            await session.refreshSyncDiagnostics()
            showLinkDecision = session.pendingTraktAccountKey != nil
        }
        .onChange(of: session.pendingTraktAccountKey) { _, accountKey in
            showLinkDecision = accountKey != nil
        }
    }

    private var statusSection: some View {
        Section {
            HStack {
                Text("Status")
                Spacer()
                Image(systemName: statusImage)
                Text(statusTitle)
            }
            .foregroundStyle(.secondary)

            if let lastSyncAt = session.lastSyncAt {
                LabeledContent("Last Synced") {
                    Text(lastSyncAt.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Account")
        } footer: {
            Text("Watchlist changes sync to Trakt Watchlist and watched activity syncs to Trakt history. iWatch keeps Watchlist items after playback.")
        }
    }

    private var connectSection: some View {
        Section {
            Button {
                session.startTraktOAuth()
            } label: {
                Label(
                    session.traktIsConnecting ? "Connecting…" : "Connect Trakt",
                    systemImage: "link"
                )
            }
            .disabled(session.traktIsConnecting || session.isErasingAllData)
        }
    }

    private var syncSection: some View {
        Section {
            Button {
                Task { await session.runSync(reason: .userInitiated) }
            } label: {
                Label(
                    session.isSyncing ? "Syncing…" : "Sync Now",
                    systemImage: "arrow.trianglehead.2.clockwise.rotate.90"
                )
            }
            .disabled(session.isSyncing || session.isErasingAllData)

            NavigationLink {
                SyncDiagnosticsView()
            } label: {
                SettingsNavigationLabel(
                    title: "Sync Diagnostics",
                    systemImage: "stethoscope",
                    detail: session.syncDiagnostics.deadletterOperationCount > 0 ? "Needs Attention" : nil
                )
            }
        } header: {
            Text("Sync")
        } footer: {
            if session.isSyncing {
                Text("Syncing your latest Trakt changes…")
            } else {
                Text("Changes normally sync automatically. Use Sync Now when you want to refresh immediately.")
            }
        }
    }

    private var disconnectSection: some View {
        Section {
            Button("Disconnect Trakt", role: .destructive) {
                showDisconnectConfirmation = true
            }
            .disabled(session.isSyncing || session.isErasingAllData)
        }
    }

    private func issueSection(_ error: String) -> some View {
        Section {
            Label {
                Text(error)
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            Button("Dismiss") {
                session.traktLastError = nil
            }
        } header: {
            Text("Needs Attention")
        }
    }

    private var statusTitle: String {
        if session.traktIsConnecting {
            return "Connecting"
        }
        return session.traktConnected ? "Connected" : "Not Connected"
    }

    private var statusImage: String {
        session.traktConnected ? "checkmark.circle.fill" : "circle"
    }
}

#Preview("Disconnected") {
    let container = AppContainer.preview()
    NavigationStack {
        TraktSettingsView()
    }
    .environment(container.session)
}
