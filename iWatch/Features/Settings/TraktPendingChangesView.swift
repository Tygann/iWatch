import SwiftUI

struct TraktPendingChangesView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        Form {
            Section {
                let health = session.traktSyncPresentation
                SyncStatusContent(title: health.title, detail: health.detail, symbol: health.symbol,
                                  needsAttention: health.needsAttention, isWorking: health.isWorking)
                TraktSyncActionButton()
                if health.needsAttention {
                    Link("Open Trakt", destination: URL(string: "https://trakt.tv")!)
                }
            }
            if session.syncDiagnostics.changes.isEmpty {
                Section {
                    Text("No pending uploads for this Trakt account.").foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(session.syncDiagnostics.changes) { change in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(change.title).font(.headline)
                            Text(change.action).font(.subheadline)
                            Text(change.createdAt, format: .dateTime.month().day().hour().minute())
                                .font(.caption).foregroundStyle(.secondary)
                            Label(stateTitle(change), systemImage: symbol(change))
                                .font(.subheadline).foregroundStyle(.secondary)
                            if change.state == .confirming {
                                Text("iWatch will look for this play on Trakt without uploading it again.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            if !change.isOnThisDevice {
                                Text("Uploads from the device where this change was made. Open iWatch there to continue.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("Saved Changes")
                } footer: {
                    Text("Changes stay in iWatch while waiting for Trakt. A pending removal may already be hidden from your library.")
                }
            }
            Section {
                NavigationLink("Advanced") { TraktAdvancedSettingsView() }
            }
        }
        .navigationTitle("Pending Changes")
        .navigationBarTitleDisplayMode(.inline)
        .task { await session.refreshSyncDiagnostics() }
    }

    private func stateTitle(_ change: SyncPendingChange) -> String {
        switch change.state {
        case .waiting: "Waiting to Upload"
        case .uploading: "Uploading"
        case .failed: "Needs Attention"
        case .confirming: "Waiting for Confirmation"
        }
    }

    private func symbol(_ change: SyncPendingChange) -> String {
        switch change.state {
        case .waiting: "clock"
        case .uploading: "arrow.up.circle"
        case .failed: "exclamationmark.triangle"
        case .confirming: "clock.badge.exclamationmark"
        }
    }
}
