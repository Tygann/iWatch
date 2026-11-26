import SwiftUI

struct TraktPendingChangesView: View {
    @Environment(AppSession.self) private var session

    private let states: [SyncPendingChange.State] = [.failed, .confirming, .uploading, .waiting]

    var body: some View {
        let health = session.traktSyncPresentation
        Form {
            if health.isWorking || health.needsAttention {
                Section {
                    if health.isWorking || health.action != .check || session.syncDiagnostics.failure == .ambiguous
                        || session.syncDiagnostics.changes.isEmpty {
                        TraktStatusRow()
                    }
                    TraktSyncActionButton()
                }
            }
            if session.syncDiagnostics.changes.isEmpty {
                ContentUnavailableView("No Pending Changes", systemImage: "checkmark.circle",
                    description: Text("New changes will appear here while they sync to Trakt."))
            } else {
                ForEach(states.indices, id: \.self) { index in
                    let state = states[index]
                    let changes = session.syncDiagnostics.changes.filter { $0.state == state }
                    if !changes.isEmpty {
                        Section {
                            ForEach(changes) { change in
                                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                                    Text(change.title)
                                    Text(change.action).font(.subheadline).foregroundStyle(.secondary)
                                    Text(change.createdAt.formatted(.dateTime.month().day().hour().minute().second()))
                                        .font(.caption).foregroundStyle(.secondary)
                                    if !change.isOnThisDevice {
                                        Text("From another device").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .accessibilityElement(children: .combine)
                            }
                        } header: {
                            Text("\(stateTitle(state)) (\(changes.count))")
                        } footer: {
                            if state == .confirming {
                                Text("Check Trakt History looks for these plays and can offer to retry a missing upload.")
                            }
                            if changes.contains(where: { !$0.isOnThisDevice }) {
                                Text("Open iWatch on the device where a change was made to upload it.")
                            }
                        }
                    }
                }
            }
            if health.needsAttention {
                Section {
                    NavigationLink("Help with These Changes") { TraktTroubleshootingView(title: "Help with Changes") }
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

    private func stateTitle(_ state: SyncPendingChange.State) -> String {
        switch state {
        case .waiting: "Waiting to Upload"
        case .uploading: "Uploading"
        case .failed: "Needs Attention"
        case .confirming: "Waiting for Confirmation"
        }
    }
}
