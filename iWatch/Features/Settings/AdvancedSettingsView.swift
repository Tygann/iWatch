import SwiftUI

enum AdvancedSettingsSection: String, CaseIterable {
    case storage = "Storage"
    case reset = "Reset"
}

struct AdvancedSettingsView: View {
    @Environment(AppSession.self) private var session
    @Environment(AppRouter.self) private var router

    @State private var showEraseConfirmation = false

    var body: some View {
        Form {
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
            } header: {
                Text(AdvancedSettingsSection.storage.rawValue)
            } footer: {
                Text("Removes downloaded artwork and cached network responses. Your library, preferences, iCloud data, and Trakt data are not affected.")
            }

            if let message = session.cacheMaintenanceMessage {
                Section("Latest Result") {
                    Text(message)
                }
            }

            Section {
                if canStartReset {
                    Button(role: .destructive) {
                        showEraseConfirmation = true
                    } label: {
                        Label("Erase All App Data", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                    .disabled(session.isErasingAllData || session.isSyncing)
                }
            } header: {
                Text(AdvancedSettingsSection.reset.rawValue)
            } footer: {
                Text("Permanently removes your iWatch library and preferences from this app and iCloud, then disconnects Trakt on this device. Trakt account data is not deleted.")
            }

            resetStatusSection
        }
        .navigationTitle("Storage & Data")
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

#Preview {
    let container = AppContainer.preview()
    NavigationStack {
        AdvancedSettingsView()
    }
    .environment(container.session)
    .environment(container.router)
}
