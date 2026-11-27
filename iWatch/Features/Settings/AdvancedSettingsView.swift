import SwiftUI

struct LibraryMaintenanceSection: View {
    @Environment(AppSession.self) private var session
    @Environment(AppRouter.self) private var router

    @State private var showsTools = false
    @State private var showEraseConfirmation = false
    @State private var showRebuildConfirmation = false
    @State private var maintenanceResult: String?

    var body: some View {
        Section("Maintenance") {
            Button(showsTools ? "Hide Maintenance Tools" : "Show Maintenance Tools") {
                withAnimation { showsTools.toggle() }
            }
            .accessibilityAddTraits(showsTools ? .isSelected : [])

            if showsTools {
                Button {
                    Task {
                        await session.clearCache()
                        Haptics.notification(.success)
                    }
                } label: {
                    HStack {
                        Text("Clear Temporary Files")
                        Spacer()
                        if session.isClearingCache {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .disabled(session.isClearingCache || session.isErasingAllData)
                if let message = session.cacheMaintenanceMessage {
                    Text(message).font(.subheadline).foregroundStyle(.secondary)
                }
                libraryMaintenanceActions

                if canStartReset {
                    Button("Erase All App Data", role: .destructive) {
                        showEraseConfirmation = true
                    }
                    .disabled(session.syncActionsUnavailable)
                }
            }
        }
        .confirmationDialog(
            "Erase all iWatch data?",
            isPresented: $showEraseConfirmation,
            titleVisibility: .visible
        ) {
            Button("Erase All Data", role: .destructive) {
                Task {
                    await session.eraseAllAppData()
                    router.resetToDefaults()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes your library from iWatch and iCloud, resets your app preferences, and disconnects Trakt on this device. Your Trakt account data is kept.")
        }
        .alert("Rebuild Library from Trakt?", isPresented: $showRebuildConfirmation) {
            Button("Discard Changes and Rebuild", role: .destructive) {
                Task {
                    maintenanceResult = nil
                    await session.resetLocalTraktSyncCache()
                    maintenanceResult = session.lastSyncAt != nil && session.traktLastError == nil && session.syncMaintenanceMessage != nil
                        ? "Library rebuilt from Trakt."
                        : "The rebuild couldn’t finish. Check the Trakt status above."
                }
            }
            .disabled(session.syncActionsUnavailable || !session.traktConnected || session.pendingTraktAccountKey != nil)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This replaces your iWatch Watchlist, watched history, and show progress with data from Trakt. The changes can sync through iCloud. Unsynced changes will be lost.")
        }
        resetStatusSection
    }

    private var libraryMaintenanceActions: some View {
        Group {
            Button("Check Library Data") {
                Task {
                    maintenanceResult = nil
                    await session.repairLocalSyncData()
                    maintenanceResult = session.syncMaintenanceMessage ?? "The library check couldn’t finish."
                }
            }
            .disabled(session.syncActionsUnavailable)
            if session.traktConnected && session.pendingTraktAccountKey == nil {
                Button("Rebuild from Trakt", role: .destructive) { showRebuildConfirmation = true }
                    .disabled(session.syncActionsUnavailable)
            }
            if session.isMaintainingSync, let title = session.syncMaintenanceTitle {
                ProgressView(title)
            } else if let maintenanceResult {
                Text(maintenanceResult).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var resetStatusSection: some View {
        switch session.dataResetStatus {
        case .idle:
            EmptyView()
        case .deletingOnDevice:
            Section("Reset Progress") {
                LabeledContent("Deleting on this device") {
                    ProgressView()
                }
            }
        case .waitingForICloud:
            Section {
                LabeledContent("Waiting for iCloud") {
                    ProgressView()
                }
            } header: {
                Text("Reset Progress")
            } footer: {
                Text("Keep iWatch installed and online until the iCloud update completes.")
            }
        case let .completed(date):
            Section {
                Label("Removed from this device and iCloud", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                LabeledContent("iCloud Updated") {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Reset Complete")
            } footer: {
                Text("You can now uninstall iWatch or connect another Trakt account.")
            }
        case let .needsAttention(message):
            Section {
                Label(message, systemImage: "exclamationmark.icloud.fill")
                    .foregroundStyle(.orange)
                Button("Try Again") {
                    Task { await session.retryCloudResetConfirmation() }
                }
                .disabled(session.isErasingAllData)
            } header: {
                Text("iCloud Update Not Confirmed")
            } footer: {
                Text("Your data is already removed from this device. Keep iWatch installed while it retries the iCloud update.")
            }
        case let .failed(message):
            Section("Reset Failed") {
                Label(message, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    private var canStartReset: Bool {
        switch session.dataResetStatus {
        case .idle, .failed:
            return true
        case .deletingOnDevice, .waitingForICloud, .completed, .needsAttention:
            return false
        }
    }
}
