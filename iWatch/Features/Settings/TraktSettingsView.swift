import SwiftUI

struct TraktSettingsSections: View {
    @Environment(AppSession.self) private var session
    @State private var showImport = false

    private var health: TraktSyncPresentation { session.traktSyncPresentation }

    var body: some View {
        Group {
            Section {
                TraktConnectionRow()
                if session.traktConnected && session.pendingTraktAccountKey == nil {
                    TraktLastSyncRow()
                }
            } header: {
                Text("Trakt")
            } footer: {
                if session.pendingTraktAccountKey != nil {
                    Text("Finish setup to start syncing this Trakt account.")
                } else {
                    Text(session.traktConnected ? "Syncs your Watchlist and watched history automatically." : "Sync your Watchlist and watched history with Trakt.")
                }
            }
            .task { await session.refreshSyncDiagnostics() }

            if health.needsAttention || (health.isWorking && !session.isSyncing && session.traktConnected) || health.title == "Changes Pending" {
                Section(health.needsAttention ? "Needs Attention" : "Activity") {
                    TraktStatusRow(showsPrimaryAction: false)
                }
            }

            if session.pendingTraktAccountKey != nil {
                setupSection
            } else if session.traktConnected && (!session.syncDiagnostics.changes.isEmpty || health.needsAttention) {
                Section {
                    if !session.syncDiagnostics.changes.isEmpty || health.needsAttention {
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
    }

    private var setupSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Button("Use Trakt Library") { showImport = true }
                Text("Replace your iWatch library and discard pending uploads.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Button("Upload Pending Changes") { Task { await session.uploadLocalLibrary() } }
                Text("Send pending changes from this device, then download Trakt.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
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
                    action
                }
            } else {
                HStack {
                    Text("Trakt Sync")
                    Spacer(minLength: AppSpacing.small)
                    action
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
                    action
                }
            } else {
                HStack(spacing: AppSpacing.medium) {
                    copy
                    Spacer(minLength: 8)
                    action
                }
            }
        }
        .padding(.vertical, 4)
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

    @ViewBuilder
    private var action: some View {
        if session.isSyncing {
            ProgressView("Syncing…")
        } else {
            Button {
                Task { await session.runSync(reason: .userInitiated) }
            } label: {
                SettingsCapsule(title: "Sync Now")
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(session.syncActionsUnavailable || session.traktSyncPresentation.action != .sync)
        }
    }
}

struct TraktStatusRow: View {
    @Environment(AppSession.self) private var session
    var showsPrimaryAction = true

    var body: some View {
        let health = session.traktSyncPresentation
        SettingsStatusRow(title: health.rowTitle, detail: detail, symbol: health.symbol, needsAttention: health.needsAttention) {
            if health.isWorking {
                ProgressView().accessibilityLabel(health.title)
            } else if health.action != .setup && (showsPrimaryAction || health.action == .check || health.action == .retry) {
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
            if session.traktSyncPresentation.action == .sync {
                SettingsCapsule(title: "Sync Now")
                    .frame(minWidth: 44, minHeight: 44)
            } else if session.traktSyncPresentation.action == .connect {
                SettingsCapsule(title: "Connect")
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            } else {
                Text(title).frame(minHeight: 44)
            }
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
struct TraktSettingsView: View {
    var body: some View {
        Form { TraktSettingsSections() }
            .navigationTitle("Trakt")
            .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    let container = AppContainer.preview()
    NavigationStack { TraktSettingsView() }.environment(container.session).environment(container)
}

#endif
