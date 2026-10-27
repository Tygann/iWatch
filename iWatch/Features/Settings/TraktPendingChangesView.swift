import SwiftUI

struct TraktPendingChangesView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        Form {
            Section {
                let health = session.traktSyncPresentation
                TraktStatusRow()
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
                            Text(change.title)
                            Text(change.action).font(.caption).foregroundStyle(.secondary)
                            Label(stateTitle(change), systemImage: symbol(change))
                                .font(.subheadline).foregroundStyle(.secondary)
                            if !change.isOnThisDevice {
                                Text("From another device").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("Saved Changes")
                } footer: {
                    if session.syncDiagnostics.changes.contains(where: { $0.state == .confirming }) {
                        Text("Unconfirmed watched plays are checked on Trakt without uploading them again.")
                    }
                    if session.syncDiagnostics.changes.contains(where: { !$0.isOnThisDevice }) {
                        Text("Open iWatch on the device where a change was made to upload it.")
                    }
                }
            }
            if session.traktSyncPresentation.needsAttention {
                Section {
                    NavigationLink("Help with These Changes") { TraktTroubleshootingView() }
                }
            } else if session.syncDiagnostics.changes.contains(where: { !$0.isOnThisDevice }) {
                Section {
                    NavigationLink("Continue on This Device") { TraktRecoveryView() }
                }
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
