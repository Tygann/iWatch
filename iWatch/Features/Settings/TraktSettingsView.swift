import SwiftUI

struct TraktSettingsSection: View {
    @Environment(AppSession.self) private var session
    @State private var showDisconnect = false

    private var health: TraktSyncPresentation { session.traktSyncPresentation }

    var body: some View {
        Section {
            TraktConnectionRow()
            if health.action != .setup && (health.needsAttention || health.isWorking || health.title == "Changes Pending") {
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
                TraktLastSyncRow()
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

struct TraktLastSyncRow: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading) {
                    copy
                    if showsSyncAction { action }
                }
            } else {
                HStack {
                    copy
                    Spacer()
                    if showsSyncAction { action }
                }
            }
        }
    }

    private var showsSyncAction: Bool {
        let health = session.traktSyncPresentation
        return !health.needsAttention && !health.isWorking && !session.syncDiagnostics.hasPendingWork
    }

    private var copy: some View {
        VStack(alignment: .leading) {
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
            SettingsCapsule(title: title)
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

#if DEBUG
#Preview {
    let container = AppContainer.preview()
    NavigationStack { LibrarySettingsView() }
        .environment(container.session)
        .environment(container)
        .environment(container.router)
}
#endif
