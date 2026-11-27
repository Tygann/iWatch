import SwiftUI

struct TraktPendingChangesView: View {
    @Environment(AppSession.self) private var session
    @State private var showMoveConfirmation = false
    @State private var moveResult: String?

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
            if changes.contains(where: { !$0.isOnThisDevice }) || moveResult != nil {
                Section {
                    if changes.contains(where: { !$0.isOnThisDevice }) {
                        Button("Move Uploads to This Device") { showMoveConfirmation = true }
                            .disabled(session.syncActionsUnavailable || !session.traktConnected || session.pendingTraktAccountKey != nil)
                    }
                    if let moveResult {
                        Text(moveResult).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Link("Trakt Service Status", destination: URL(string: "https://status.trakt.tv")!)
                Link("Contact Support", destination: SyncSupportView.contactURL)
            }
        }
        .navigationTitle("Pending Changes")
        .navigationBarTitleDisplayMode(.inline)
        .task { await session.refreshSyncDiagnostics() }
        .confirmationDialog("Move Uploads to This Device?", isPresented: $showMoveConfirmation, titleVisibility: .visible) {
            Button("Move Pending Uploads") {
                Task {
                    await session.recoverPendingUploads()
                    moveResult = session.syncMaintenanceMessage ?? "Uploads couldn’t be moved. Try again later."
                }
            }
        } message: {
            Text("Stop Trakt sync on your other devices first. This changes which device uploads unfinished changes for this account.")
        }
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
