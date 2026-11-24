import SwiftUI

struct TraktSettingsSection: View {
    @Environment(AppSession.self) private var session
    @State private var showDisconnect = false

    private var health: TraktSyncPresentation { session.traktSyncPresentation }

    var body: some View {
        Section {
            TraktConnectionRow()
            if !session.traktConnected && (health.needsAttention || health.isWorking) {
                TraktStatusRow()
            }
            if session.pendingTraktAccountKey != nil {
                NavigationLink {
                    TraktSetupView()
                } label: {
                    SettingsNavigationLabel(title: "Finish Setup", systemImage: "person.crop.circle.badge.checkmark")
                }
                .accessibilityIdentifier("trakt-setup")
            } else if session.traktConnected {
                TraktLastCheckRow()
                if health.needsAttention || health.isWorking || health.title == "Changes Pending" {
                    TraktStatusRow(showsAction: false)
                }
                TraktSyncActionButton(fullWidth: true)
                if !session.syncDiagnostics.changes.isEmpty || health.needsAttention {
                    NavigationLink {
                        TraktPendingChangesView()
                    } label: {
                        SettingsNavigationLabel(title: "Pending Changes", systemImage: "clock",
                            detail: session.syncDiagnostics.changes.isEmpty ? "Review" : session.syncDiagnostics.changes.count.formatted())
                    }
                }
                NavigationLink("Help with Sync") { TraktTroubleshootingView() }
            }
            if session.traktConnected {
                Button("Disconnect Trakt", role: .destructive) { showDisconnect = true }
                    .disabled(session.syncActionsUnavailable)
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
        .confirmationDialog("Disconnect Trakt?", isPresented: $showDisconnect, titleVisibility: .visible) {
            Button("Disconnect Trakt", role: .destructive) { session.logoutTrakt() }
        } message: {
            Text("Your iWatch library will remain. Future changes won’t sync with Trakt until you reconnect.")
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
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if session.traktConnected {
                LabeledContent("Trakt Sync") { SettingsCapsule(title: "Connected") }
                    .accessibilityElement(children: .combine)
            } else if typeSize.isAccessibilitySize {
                VStack(alignment: .leading) {
                    Text("Trakt Sync")
                    if !session.traktSyncPresentation.needsAttention { connectButton }
                }
            } else {
                HStack {
                    Text("Trakt Sync")
                    Spacer()
                    if !session.traktSyncPresentation.needsAttention { connectButton }
                }
            }
        }
        .accessibilityIdentifier("trakt-connection")
    }

    @ViewBuilder
    private var connectButton: some View {
        if session.traktIsConnecting {
            ProgressView().accessibilityLabel("Connecting…")
        } else {
            Button { session.startTraktOAuth() } label: {
                SettingsCapsule(title: "Connect")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Connect Trakt")
            .disabled(session.syncActionsUnavailable)
        }
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
    var showsAction = true

    var body: some View {
        let health = session.traktSyncPresentation
        SettingsStatusRow(title: health.rowTitle, detail: detail, symbol: health.symbol, needsAttention: health.needsAttention) {
            if showsAction { TraktSyncActionButton() }
        }
    }

    private var detail: String {
        let health = session.traktSyncPresentation
        if health.title == "Sync Complete", let date = session.lastSyncAt {
            return "Last synced " + date.formatted(date: .abbreviated, time: .shortened)
        }
        return health.detail
    }
}

struct TraktSyncActionButton: View {
    @Environment(AppSession.self) private var session

    @State private var retryOffer: SyncEngine.HistoryRetry?
    @State private var showsRetryConfirmation = false
    var fullWidth = false

    var body: some View {
        let health = session.traktSyncPresentation
        Group {
            if health.isWorking {
                ProgressView().accessibilityLabel(health.title)
            } else if health.action != .setup {
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
                    if fullWidth {
                        Text(title)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    } else {
                        SettingsCapsule(title: title)
                    }
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(title)
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
        case .check: "Try Again"
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
