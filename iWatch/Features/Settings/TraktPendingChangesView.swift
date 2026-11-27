import SwiftUI

struct TraktPendingChangesView: View {
    @Environment(AppSession.self) private var session

    private let states: [SyncPendingChange.State] = [.failed, .confirming, .uploading, .waiting]

    var body: some View {
        let changes = session.syncDiagnostics.changes
        Form {
            if changes.isEmpty {
                ContentUnavailableView("No Pending Changes", systemImage: "checkmark.circle",
                    description: Text("New changes will appear here while they sync to Trakt."))
            } else {
                Section {
                    ForEach(states.indices, id: \.self) { index in
                        let state = states[index]
                        let group = changes.filter { $0.state == state }
                        if !group.isEmpty {
                            DisclosureGroup(stateTitle(state, count: group.count)) {
                                ForEach(group) { change in
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
                            }
                        }
                    }
                } footer: {
                    if changes.contains(where: { !$0.isOnThisDevice }) {
                        Text("Changes from another device sync when you open iWatch on that device.")
                    }
                    if session.traktSyncPresentation.needsAttention {
                        Text("Use Sync Now to retry failed changes and check for watched plays on Trakt.")
                    }
                }
            }
            Section {
                NavigationLink("Get Help") { TraktTroubleshootingView() }
            }
        }
        .navigationTitle("Pending Changes")
        .navigationBarTitleDisplayMode(.inline)
        .task { await session.refreshSyncDiagnostics() }
    }

    private func stateTitle(_ state: SyncPendingChange.State, count: Int) -> String {
        switch state {
        case .waiting: "Waiting to Upload (\(count))"
        case .uploading: "Uploading (\(count))"
        case .failed: "Needs Attention (\(count))"
        case .confirming: "Waiting for Confirmation (\(count))"
        }
    }
}
