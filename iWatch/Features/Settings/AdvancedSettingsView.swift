import SwiftUI

// MARK: - Settings State

enum AdvancedSettingsSection: String, CaseIterable {
    case storage = "Storage"
    case reset = "Reset"
}

// MARK: - Advanced Settings Screen

struct AdvancedSettingsView: View {
    @Environment(AppSession.self) private var session
    @Environment(AppRouter.self) private var router

    @State private var showEraseConfirmation = false
    @State private var showRebuildConfirmation = false
    @State private var maintenanceResult: String?

    var body: some View {
        Form {
            LibraryIncludedSection()

            Section {
                Button {
                    Task {
                        await session.clearCache()
                        Haptics.notification(.success)
                    }
                } label: {
                    HStack {
                        Label("Clear Temporary Files", systemImage: "trash")
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
            } header: {
                Text(AdvancedSettingsSection.storage.rawValue)
            } footer: {
                Text("Removes downloaded artwork and cached network responses. Your library, preferences, iCloud data, and Trakt data are not affected.")
            }

            libraryMaintenanceSection

            if canStartReset {
                Section {
                    Button(role: .destructive) {
                        showEraseConfirmation = true
                    } label: {
                        Label("Erase All App Data", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                    .disabled(session.syncActionsUnavailable)
                } header: {
                    Text(AdvancedSettingsSection.reset.rawValue)
                } footer: {
                    Text("Permanently removes your iWatch library and preferences from this app and iCloud, then disconnects Trakt on this device. Trakt account data is not deleted.")
                }
            }

            resetStatusSection
        }
        .navigationTitle("Manage Data")
        .navigationBarTitleDisplayMode(.inline)
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
            Text("This action can’t be undone. Your iWatch library will be removed from this app and iCloud.")
        }
    }

    private var libraryMaintenanceSection: some View {
        Section {
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
        } header: {
            Text("Library Maintenance")
        } footer: {
            Text("Check for duplicate records and repair inconsistent links.")
        }
        .alert("Rebuild Library from Trakt?", isPresented: $showRebuildConfirmation) {
            Button("Discard Changes and Rebuild", role: .destructive) {
                Task {
                    maintenanceResult = nil
                    await session.resetLocalTraktSyncCache()
                    maintenanceResult = session.lastSyncAt != nil && session.traktLastError == nil && session.syncMaintenanceMessage != nil
                        ? "Library rebuilt from Trakt."
                        : "The rebuild couldn’t finish. Check Trakt in Sync."
                }
            }
            .disabled(session.syncActionsUnavailable || !session.traktConnected || session.pendingTraktAccountKey != nil)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This replaces your iWatch Watchlist, watched history, and show progress with data from Trakt. The changes can sync through iCloud. Unsynced changes will be lost.")
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

private struct LibraryIncludedSection: View {
    @Environment(AppSession.self) private var session
    @Environment(AppContainer.self) private var container
    @State private var counts: LibraryCounts?
    @State private var countsFailed = false

    var body: some View {
        Section("Library") {
            includedRow("Watchlist", symbol: "bookmark", detail: counts?.watchlistDescription)
            includedRow("Watched History", symbol: "clock", detail: counts?.historyDescription)
            includedRow("Show Progress", symbol: "play.rectangle", detail: counts?.progressDescription)
            if countsFailed {
                Button("Try Again") { Task { await loadCounts() } }
            }
        }
        .task(id: session.libraryRevision) { await loadCounts() }
    }

    private func includedRow(_ title: String, symbol: String, detail: String?) -> some View {
        Label {
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text(title)
                Text(detail ?? (countsFailed ? "Count unavailable" : "Loading…"))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: symbol)
        }
        .accessibilityElement(children: .combine)
    }

    private func loadCounts() async {
        do {
            let updated = try await container.libraryRepository.libraryCounts()
            try Task.checkCancellation()
            counts = updated
            countsFailed = false
        } catch is CancellationError {
        } catch {
            if !Task.isCancelled { countsFailed = true }
        }
    }

}

// MARK: - Previews

#Preview {
    let container = AppContainer.preview()
    NavigationStack {
        AdvancedSettingsView()
    }
    .environment(container.session)
    .environment(container.router)
    .environment(container)
}
