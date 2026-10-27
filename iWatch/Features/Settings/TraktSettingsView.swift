import SwiftUI

struct TraktSettingsView: View {
    @Environment(AppSession.self) private var session
    @State private var showDisconnect = false
    @State private var showImport = false

    private var health: TraktSyncPresentation { session.traktSyncPresentation }

    var body: some View {
        Form {
            Section {
                TraktStatusRow()
            }

            if session.pendingTraktAccountKey != nil {
                setupSection
            } else if session.traktConnected {
                Section {
                    if !session.syncDiagnostics.changes.isEmpty || health.needsAttention {
                        NavigationLink {
                            TraktPendingChangesView()
                        } label: {
                            SettingsNavigationLabel(title: "Pending Changes", systemImage: "clock",
                                detail: session.syncDiagnostics.changes.isEmpty ? "Review" : session.syncDiagnostics.changes.count.formatted())
                        }
                    }
                    NavigationLink("Advanced") { TraktAdvancedSettingsView() }
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
            }
        } header: {
            Text("Choose How to Start")
        } footer: {
            Text("You can finish setup later.")
        }
        .disabled(session.syncActionsUnavailable)
    }
}

struct TraktStatusRow: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        let health = session.traktSyncPresentation
        SettingsStatusRow(title: title, detail: detail, symbol: health.symbol, needsAttention: health.needsAttention) {
            if health.isWorking {
                ProgressView().accessibilityLabel(health.title)
            } else if health.action != .setup {
                TraktSyncActionButton()
            }
        }
    }

    private var title: String {
        let health = session.traktSyncPresentation
        return health.title == "Sync Complete" ? "Trakt" : health.title
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
                Image(systemName: "arrow.triangle.2.circlepath")
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

#Preview {
    let container = AppContainer.preview()
    NavigationStack { TraktSettingsView() }.environment(container.session)
}
