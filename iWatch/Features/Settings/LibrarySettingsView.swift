import SwiftUI

struct LibrarySettingsView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Form {
            iCloudSection
            TraktSettingsSection()
            LibraryMaintenanceSection()
        }
        .navigationTitle("Library Sync")
        .navigationBarTitleDisplayMode(.large)
    }

    private var iCloudSection: some View {
        Section {
            VStack(alignment: typeSize.isAccessibilitySize ? .leading : .center, spacing: 12) {
                if !typeSize.isAccessibilitySize {
                    Image(systemName: needsAttention ? "exclamationmark.icloud" : "icloud.fill")
                        .font(.largeTitle)
                        .imageScale(.large)
                        .foregroundStyle(needsAttention ? Color.orange : Color.accentColor)
                        .accessibilityHidden(true)
                }

                Text("iCloud")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)

                VStack(alignment: typeSize.isAccessibilitySize ? .leading : .center, spacing: 4) {
                    if isWorking {
                        ProgressView()
                            .accessibilityHidden(true)
                    }
                    Text(statusTitle)
                        .font(.subheadline.weight(.semibold))
                    if let statusDetail {
                        Text(statusDetail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("icloud-sync-status")
                Text("Sync your library across devices using the same Apple Account.")
                    .foregroundStyle(.secondary)

                if needsAttention {
                    Link("Get Help with iCloud", destination: URL(string: "https://support.apple.com/guide/icloud/set-up-icloud-on-your-devices-mmfc0f1e2a/icloud")!)
                        .buttonStyle(.borderless)
                        .frame(minHeight: 44)
                }
            }
            .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .center)
            .frame(maxWidth: 440, alignment: typeSize.isAccessibilitySize ? .leading : .center)
            .frame(maxWidth: .infinity, alignment: typeSize.isAccessibilitySize ? .leading : .center)
            .padding(.vertical, 16)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private var statusTitle: String {
        switch session.cloudSyncStatus {
        case .idle, .completed, .imported:
            "Syncs Automatically"
        case .importing: "Downloading Changes…"
        case .exporting: "Uploading Changes…"
        case .failed, .unavailable: "iCloud Needs Attention"
        case .timedOut: "Upload Not Confirmed"
        }
    }

    private var statusDetail: String? {
        switch session.cloudSyncStatus {
        case .idle, .completed, .imported:
            session.lastCloudActivityAt.map { date in
                "Last activity: \(date.formatted(date: .abbreviated, time: .shortened))"
            }
        case .importing, .exporting: nil
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
