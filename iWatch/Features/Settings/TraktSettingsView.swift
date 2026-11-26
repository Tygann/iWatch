import SwiftUI

struct TraktSettingsSection: View {
    @Environment(AppSession.self) private var session
    @State private var showDisconnect = false

    private var health: TraktSyncPresentation { session.traktSyncPresentation }

    var body: some View {
        Section {
            TraktConnectionRow()
            if !session.traktConnected && health.needsAttention {
                TraktStatusRow()
                TraktSyncActionButton()
            }
            if session.pendingTraktAccountKey != nil {
                NavigationLink {
                    TraktSetupView()
                } label: {
                    SettingsNavigationLabel(title: "Finish Setup", systemImage: "person.crop.circle.badge.checkmark")
                }
                .accessibilityIdentifier("trakt-setup")
            } else if session.traktConnected {
                if health.needsAttention || health.isWorking || health.title == "Changes Pending" {
                    TraktStatusRow()
                }
                TraktSyncActionButton()
                if !session.syncDiagnostics.changes.isEmpty || health.needsAttention {
                    NavigationLink {
                        TraktPendingChangesView()
                    } label: {
                        SettingsNavigationLabel(title: "Pending Changes", systemImage: "clock",
                            detail: session.syncDiagnostics.changes.isEmpty ? "Review" : session.syncDiagnostics.changes.count.formatted())
                    }
                }
                TraktLastCheckRow()
                NavigationLink("Help with Sync") { TraktTroubleshootingView() }
            }
        } header: {
            Text("Trakt")
        } footer: {
            Text(session.pendingTraktAccountKey != nil
                ? "Finish setup to start syncing this Trakt account."
                : session.traktConnected
                    ? "Syncs your Watchlist and watched history automatically."
                    : "Optionally sync your Watchlist and watched history with Trakt.")
        }
        .task { await session.refreshSyncDiagnostics() }

        if session.traktConnected {
            Section {
                Button("Disconnect Trakt", role: .destructive) { showDisconnect = true }
                    .disabled(session.syncActionsUnavailable)
            }
            .confirmationDialog("Disconnect Trakt?", isPresented: $showDisconnect, titleVisibility: .visible) {
                Button("Disconnect Trakt", role: .destructive) { session.logoutTrakt() }
            } message: {
                Text("Your iWatch library will remain. Future changes won’t sync with Trakt until you reconnect.")
            }
        }
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
                LabeledContent("Account", value: "Connected")
                    .accessibilityElement(children: .combine)
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

private struct TraktLastCheckRow: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        LabeledContent("Last Trakt Check") {
            if let date = session.syncDiagnostics.lastSuccessfulPullAt {
                Text(date, format: .relative(presentation: .named))
                    .accessibilityLabel(Text(date.formatted(date: .abbreviated, time: .shortened)))
            } else {
                Text("Not checked yet")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct TraktStatusRow: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        let health = session.traktSyncPresentation
        if health.isWorking {
            ProgressView {
                statusCopy(health)
            }
        } else {
            statusCopy(health)
        }
    }

    private func statusCopy(_ health: TraktSyncPresentation) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            Text(health.rowTitle)
            Text(health.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

}

struct TraktSyncActionButton: View {
    @Environment(AppSession.self) private var session

    @State private var retryOffer: SyncEngine.HistoryRetry?
    @State private var showsRetryConfirmation = false

    var body: some View {
        let health = session.traktSyncPresentation
        Group {
            if !health.isWorking && health.action != .setup {
                Button {
                    Task {
                        switch health.action {
                        case .check:
                            retryOffer = await session.checkWatchedUploadConfirmations()
                            showsRetryConfirmation = retryOffer != nil
                        case .retry: await session.retryFailedSyncOperations()
                        case .sync: await session.runSync(reason: .userInitiated)
                        case .connect: session.startTraktOAuth()
                        case .setup: break
                        }
                    }
                } label: {
                    Text(title)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .disabled(session.syncActionsUnavailable || session.pendingTraktAccountKey != nil)
            }
        }
        .alert("Retry Missing Plays?", isPresented: $showsRetryConfirmation, presenting: retryOffer) { offer in
            Button("Retry Upload") {
                Task { _ = await session.checkWatchedUploadConfirmations(historyRetry: offer) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { offer in
            let count = offer.ids.count
            Text("iWatch couldn’t find ^[\(count) watched play](inflect: true) in Trakt history. It will check again before retrying with the original watched times. A play could be duplicated if Trakt hasn’t made it visible yet.")
        }
    }

    private var title: String {
        switch session.traktSyncPresentation.action {
        case .check: "Check Trakt History"
        case .retry: "Retry Failed Changes"
        case .sync: "Sync Now"
        case .connect: "Connect Trakt"
        case .setup: "Finish Setup"
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
