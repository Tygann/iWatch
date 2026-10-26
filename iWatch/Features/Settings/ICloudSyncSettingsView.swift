import SwiftUI

struct ICloudSyncSettingsView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        Form {
            Section {
                SyncStatusContent(title: title, detail: detail, symbol: "icloud",
                                  needsAttention: needsAttention, isWorking: isWorking)
            }
            Section {
                if let date = session.lastCloudImportAt {
                    SyncDateRow(title: "Last Download", date: date)
                }
                if let date = session.lastCloudExportAt {
                    SyncDateRow(title: "Last Upload", date: date)
                }
                if session.lastCloudImportAt == nil && session.lastCloudExportAt == nil {
                    Text("No upload or download has been observed during this session.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Recent Activity")
            } footer: {
                Text("Activity shows transfers observed on this device. An upload doesn’t confirm that another device has downloaded your changes.")
            }
            if needsAttention, let message = session.cloudSyncStatus.detail {
                Section {
                    DisclosureGroup("Technical Details") {
                        Text(message).font(.subheadline).textSelection(.enabled)
                    }
                }
            }
            Section("How iCloud Sync Works") {
                Text("iCloud automatically syncs your iWatch library across devices using the same Apple Account. Trakt is optional and syncs separately.")
                Text("If changes haven’t appeared, check your internet connection and that iCloud is available for iWatch in Settings on each device. Syncing may continue in the background.")
                    .foregroundStyle(.secondary)
                Link("iCloud Help", destination: URL(string: "https://support.apple.com/guide/icloud/set-up-icloud-on-your-devices-mmfc0f1e2a/icloud")!)
            }
        }
        .navigationTitle("iCloud Sync")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var title: String {
        session.cloudSyncStatus == .idle ? "Syncs Automatically" : session.cloudSyncStatus.title
    }

    private var detail: String {
        switch session.cloudSyncStatus {
        case .idle: return "iCloud transfers library changes automatically when available."
        case .importing: return "Receiving library changes from iCloud."
        case .exporting: return "Sending library changes to iCloud."
        case .imported: return "Library changes were received on this device."
        case .completed: return "Library changes were sent from this device."
        case .failed, .unavailable: return "iCloud couldn’t complete a transfer. Check your connection and iCloud settings. Your local library remains available."
        case .timedOut: return "An upload hasn’t been confirmed yet. Keep iWatch installed and connected while iCloud continues."
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
