import SwiftUI

struct LibrarySettingsView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        Form {
            LibraryIncludedSection()
            Section {
                LabeledContent("iCloud Sync") {
                    SettingsCapsule(title: capsuleTitle, tint: needsAttention ? .orange : .accentColor)
                }
                if let date = session.lastCloudActivityAt {
                    SyncDateRow(title: "Last Activity", date: date)
                } else {
                    LabeledContent("Last Activity", value: "Not recorded yet")
                }
                if isWorking || needsAttention {
                    HStack {
                        Text(detail).font(.subheadline).foregroundStyle(.secondary)
                        if isWorking { ProgressView().accessibilityLabel(session.cloudSyncStatus.title) }
                    }
                }
                if needsAttention {
                    Link("Get Help with iCloud", destination: URL(string: "https://support.apple.com/guide/icloud/set-up-icloud-on-your-devices-mmfc0f1e2a/icloud")!)
                }
            } header: {
                Text("iCloud")
            } footer: {
                Text("Your library syncs automatically across devices using the same Apple Account.")
            }
            TraktSettingsSection()
            Section {
                NavigationLink { AdvancedSettingsView() } label: {
                    SettingsNavigationLabel(title: "Manage Data", systemImage: "externaldrive")
                }
            }
        }
        .navigationTitle("Your Library")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var capsuleTitle: String {
        switch session.cloudSyncStatus {
        case .importing, .exporting: "Syncing"
        case .failed, .unavailable, .timedOut: "Needs Attention"
        default: "Automatic"
        }
    }

    private var detail: String {
        switch session.cloudSyncStatus {
        case .idle, .completed, .imported:
            session.lastCloudActivityAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "No completed transfers recorded on this device."
        case .importing: "Downloading library changes."
        case .exporting: "Uploading library changes."
        case let .failed(message), let .unavailable(message): message
        case .timedOut: "An upload hasn’t been confirmed yet."
        }
    }

    private var needsAttention: Bool {
        switch session.cloudSyncStatus {
        case .failed, .unavailable, .timedOut: true
        default: false
        }
    }

    private var isWorking: Bool {
        switch session.cloudSyncStatus {
        case .importing, .exporting: true
        default: false
        }
    }
}

#if DEBUG
struct ICloudSyncDetailsView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        Form {
            Section {
                if let date = session.lastCloudImportAt {
                    SyncDateRow(title: "Last Download", date: date)
                }
                if let date = session.lastCloudExportAt {
                    SyncDateRow(title: "Last Upload", date: date)
                }
                if session.lastCloudImportAt == nil && session.lastCloudExportAt == nil {
                    Text("No completed transfers recorded on this device.").foregroundStyle(.secondary)
                }
            } header: {
                Text("Recent Activity")
            } footer: {
                Text("Completed transfers are recorded on this device. An upload doesn’t confirm that another device has downloaded your changes.")
            }
            if let message = errorDetail {
                Section("Connection Details") {
                    Text(message).font(.subheadline).textSelection(.enabled)
                }
            }
            Section {
                Link("iCloud Help", destination: URL(string: "https://support.apple.com/guide/icloud/set-up-icloud-on-your-devices-mmfc0f1e2a/icloud")!)
            } footer: {
                Text("If changes haven’t appeared, check your connection and that iCloud is available for iWatch on each device.")
            }
        }
        .navigationTitle("iCloud Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var errorDetail: String? {
        switch session.cloudSyncStatus {
        case let .failed(message), let .unavailable(message): message
        case .timedOut: "Keep iWatch installed and connected while iCloud continues in the background."
        default: nil
        }
    }
}

#endif

struct LibraryIncludedSection: View {
    @Environment(AppSession.self) private var session
    @Environment(AppContainer.self) private var container
    @State private var counts: LibraryCounts?
    @State private var countsFailed = false

    var body: some View {
        Section("Library") {
            includedRow("Watchlist", symbol: "bookmark", detail: counts?.watchlistDescription)
            includedRow("Watched History", symbol: "clock", detail: counts?.historyDescription)
            includedRow("Show Progress", symbol: "play.rectangle", detail: counts?.progressDescription)
            if countsFailed {
                Button("Try Again") { Task { await loadCounts() } }
            }
        }
        .task(id: session.libraryRevision) { await loadCounts() }
    }

    private func includedRow(_ title: String, symbol: String, detail: String?) -> some View {
        Label {
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text(title)
                Text(detail ?? (countsFailed ? "Count unavailable" : "Loading…"))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: symbol)
        }
        .accessibilityElement(children: .combine)
    }

    private func loadCounts() async {
        do {
            let updated = try await container.libraryRepository.libraryCounts()
            try Task.checkCancellation()
            counts = updated
            countsFailed = false
        } catch is CancellationError {
        } catch {
            if !Task.isCancelled { countsFailed = true }
        }
    }

}
