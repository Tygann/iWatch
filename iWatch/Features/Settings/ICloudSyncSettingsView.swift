import SwiftUI

struct ICloudSyncSettingsView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        Form {
            Section {
                LabeledContent("iCloud Sync") {
                    Text(capsuleTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(needsAttention ? Color.orange : Color.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background((needsAttention ? Color.orange : Color.accentColor).opacity(0.12), in: Capsule())
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    if isWorking {
                        Spacer(minLength: 8)
                        ProgressView().accessibilityLabel(title)
                    }
                }
                .padding(.vertical, 4)
                NavigationLink("Details") { ICloudSyncDetailsView() }
            } footer: {
                Text("Your library syncs automatically across devices using the same Apple Account.")
            }
            Section("Included") {
                Label("Watchlist", systemImage: "bookmark")
                Label("Watched History", systemImage: "clock")
                Label("Show Progress", systemImage: "play.rectangle")
            }
        }
        .navigationTitle("iCloud")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var capsuleTitle: String {
        switch session.cloudSyncStatus {
        case .importing, .exporting: "Syncing"
        case .failed, .unavailable, .timedOut: "Needs Attention"
        default: "Automatic"
        }
    }

    private var title: String {
        switch session.cloudSyncStatus {
        case .idle: "Recent Activity"
        case .completed, .imported: "Recent Activity"
        default: session.cloudSyncStatus.title
        }
    }

    private var detail: String {
        switch session.cloudSyncStatus {
        case .idle: "No transfers recorded this session."
        case .importing: "Downloading library changes."
        case .exporting: "Uploading library changes."
        case let .imported(date): "Downloaded " + date.formatted(date: .abbreviated, time: .shortened)
        case let .completed(date): "Uploaded " + date.formatted(date: .abbreviated, time: .shortened)
        case .failed, .unavailable: "Check your connection and iCloud settings."
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
                    Text("No transfers recorded this session.").foregroundStyle(.secondary)
                }
            } header: {
                Text("Recent Activity")
            } footer: {
                Text("Transfers are recorded on this device during this session. An upload doesn’t confirm that another device has downloaded your changes.")
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
        .navigationTitle("iCloud Details")
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
