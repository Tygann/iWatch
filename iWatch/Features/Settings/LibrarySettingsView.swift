import SwiftUI

struct LibrarySettingsView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        Form {
            iCloudSection
            TraktSettingsSection()
            Section {
                NavigationLink {
                    AdvancedSettingsView()
                } label: {
                    Text("Library Maintenance")
                }
                .accessibilityIdentifier("settings-library-maintenance")
            }
        }
        .navigationTitle("Library Sync")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var iCloudSection: some View {
        Section {
            SettingsStatusRow(title: statusTitle, detail: statusDetail, symbol: needsAttention ? "exclamationmark.icloud" : "icloud",
                              needsAttention: needsAttention) {
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityIdentifier("icloud-sync-status")

            if needsAttention {
                Link("Get Help with iCloud", destination: URL(string: "https://support.apple.com/guide/icloud/set-up-icloud-on-your-devices-mmfc0f1e2a/icloud")!)
            }
        } header: {
            Text("iCloud")
        } footer: {
            Text("Your Watchlist, watched history, and show progress sync automatically across devices using the same Apple Account.")
        }
    }

    private var statusTitle: String {
        switch session.cloudSyncStatus {
        case .idle, .completed, .imported:
            session.lastCloudActivityAt == nil ? "Automatic Sync" : "Last Activity"
        case .importing: "Downloading Changes…"
        case .exporting: "Uploading Changes…"
        case .failed, .unavailable: "iCloud Needs Attention"
        case .timedOut: "Upload Not Confirmed"
        }
    }

    private var statusDetail: String {
        switch session.cloudSyncStatus {
        case .idle, .completed, .imported:
            session.lastCloudActivityAt?.formatted(date: .abbreviated, time: .shortened)
                ?? "No recent activity on this device."
        case .importing, .exporting: ""
        case let .failed(message), let .unavailable(message): message
        case .timedOut: "iCloud can continue syncing in the background."
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
