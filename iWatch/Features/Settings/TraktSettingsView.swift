import SwiftUI

struct TraktSettingsSections: View {
    @Environment(AppSession.self) private var session
    @State private var showImport = false

    private var health: TraktSyncPresentation { session.traktSyncPresentation }

    var body: some View {
        Group {
            Section {
                TraktConnectionRow()
                if health.needsAttention || health.isWorking || health.title == "Changes Pending" {
                    TraktStatusRow()
                }
                if session.traktConnected && session.pendingTraktAccountKey == nil {
                    TraktLastSyncRow()
                }
            } header: {
                Text("Connection")
            } footer: {
                if session.pendingTraktAccountKey != nil {
                    Text("Finish setup to start syncing this Trakt account.")
                } else {
                    Text(session.traktConnected ? "Syncs your Watchlist and watched history automatically." : "Sync your Watchlist and watched history with Trakt.")
                }
            }
            .task { await session.refreshSyncDiagnostics() }

            if session.pendingTraktAccountKey != nil {
                setupSection
            } else if session.traktConnected && (!session.syncDiagnostics.changes.isEmpty || health.needsAttention) {
                Section {
                    NavigationLink {
                        TraktPendingChangesView()
                    } label: {
                        SettingsNavigationLabel(title: "Pending Changes", systemImage: "clock",
                            detail: session.syncDiagnostics.changes.isEmpty ? "Review" : session.syncDiagnostics.changes.count.formatted())
                    }
                }
            }
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
        .disabled(session.syncActionsUnavailable)
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
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    Text("Trakt Sync")
                    if !session.traktSyncPresentation.needsAttention { action }
                }
            } else {
                HStack {
                    Text("Trakt Sync")
                    Spacer(minLength: AppSpacing.small)
                    if !session.traktSyncPresentation.needsAttention { action }
                }
            }
        }
        .accessibilityIdentifier("trakt-connection")
    }

    @ViewBuilder
    private var action: some View {
        if session.traktIsConnecting {
            ProgressView().accessibilityLabel("Connecting…")
        } else {
            TraktSyncActionButton()
        }
    }
}

struct TraktLastSyncRow: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    copy
                    if showsSyncAction { action }
                }
            } else {
                HStack(spacing: AppSpacing.medium) {
                    copy
                    Spacer(minLength: 8)
                    if showsSyncAction { action }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var showsSyncAction: Bool {
        let health = session.traktSyncPresentation
        return !health.needsAttention && !health.isWorking && !session.syncDiagnostics.hasPendingWork
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            Text("Last Sync")
            Text(session.lastSyncAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Not synced yet")
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var action: some View {
        TraktSyncActionButton()
    }
}

struct TraktStatusRow: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        let health = session.traktSyncPresentation
        SettingsStatusRow(title: health.rowTitle, detail: detail, symbol: health.symbol, needsAttention: health.needsAttention) {
            if health.isWorking {
                ProgressView().accessibilityLabel(health.title)
            } else if health.action != .setup {
                TraktSyncActionButton()
            }
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

    var body: some View {
        Button {
            Task {
                switch session.traktSyncPresentation.action {
                case .check: await session.checkWatchedUploadConfirmations()
                case .retry: await session.retryFailedSyncOperations()
                case .sync: await session.runSync(reason: .userInitiated)
                case .connect: session.startTraktOAuth()
                case .setup: break
                }
            }
        } label: {
            Text(title).frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(title)
        .disabled(session.syncActionsUnavailable || session.pendingTraktAccountKey != nil)
    }

    private var title: String {
        switch session.traktSyncPresentation.action {
        case .check: "Check Again"
        case .retry: "Retry Failed Changes"
        case .sync: "Sync Now"
        case .connect: "Connect Trakt"
        case .setup: "Finish Setup"
        }
    }
}

struct TraktSettingsView: View {
    @Environment(AppSession.self) private var session
    @State private var showDisconnect = false

    var body: some View {
        Form {
            TraktSettingsSections()
            if session.traktConnected && session.pendingTraktAccountKey == nil {
                Section {
                    NavigationLink("Help with Sync") { TraktTroubleshootingView() }
                }
            }
            if session.traktConnected {
                Section {
                    Button("Disconnect Trakt", role: .destructive) { showDisconnect = true }
                        .disabled(session.syncActionsUnavailable)
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
    }
}

#if DEBUG
#Preview {
    let container = AppContainer.preview()
    NavigationStack { TraktSettingsView() }.environment(container.session).environment(container)
}

#endif
